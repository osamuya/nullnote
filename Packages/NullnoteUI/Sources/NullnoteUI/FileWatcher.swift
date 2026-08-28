import Foundation

/// ファイルが外で書き換わったことを知らせる見張り。
///
/// **ポーリングしない。** 変化があったときだけカーネルから起こされるので、
/// 何も起きていないあいだの費用はゼロ。
///
/// ## 置き換えによる保存が本題
///
/// 多くのエディタ（Claude Code を含む）は、上書き保存を
/// 「別名で書いてから置き換える」形で行う。`rename(2)` で被せると、
/// こちらが握っていた実体はリンクを失う。**記述子には `.delete` が1回飛ぶが、
/// その記述子はもう誰からも見えない古い中身を指している。**
/// 開き直さないかぎり、2回目以降の書き換えは永久に届かない（B-17。実測）。
///
/// そこで**イベントを受けるたびに開き直す**。実体番号が変わっていなければ
/// 何もしないので、その場書き換え（`.write`）が続くあいだの費用は増えない。
///
/// ## 親ディレクトリの見張りは「あれば助かる」程度
///
/// 項目の置き換えはディレクトリにも届くので、こちらも張る。
/// ただし**サンドボックスでは開けないことの方が多い**。書類を開いても、
/// その**フォルダ**を読む許可までは付いてこないため（`errno = EPERM`。実測）。
/// 頼りにはできないので、開けなくても動くようにしてある。
///
/// ディレクトリのイベントは無関係なファイルの出入りでも飛ぶ。
/// 起こされるたびに `stat` を取り、**識別子・更新時刻・大きさのどれかが
/// 変わったときだけ**知らせる。
public final class FileWatcher: @unchecked Sendable {

    /// 知らせをまとめる幅。1回の保存で飛ぶ複数の通知を1つにする。
    private static let coalescingInterval: DispatchTimeInterval = .milliseconds(120)

    /// 置き換えの途中でファイルが見えないことがある。開けなかったときの間隔と回数。
    private static let reopenRetryInterval: DispatchTimeInterval = .milliseconds(150)
    private static let reopenRetryLimit = 20

    /// ファイルの見分け方。この3つのどれかが変われば、中身が変わったとみなす。
    ///
    /// **`URLResourceValues` ではなく `stat` を使う。** 前者は
    /// `fileResourceIdentifier` の中身が不透明で、比べても差が出なかった
    /// （置き換えても「変わっていない」と判定されて、何も知らせなくなった）。
    private struct Fingerprint: Equatable {
        /// 実体の番号。置き換えられると変わる。
        let inode: UInt64
        let modified: TimeInterval
        let size: Int64

        init?(path: String) {
            var info = stat()
            guard stat(path, &info) == 0 else { return nil }
            self.init(info)
        }

        init(_ info: stat) {
            inode = UInt64(info.st_ino)
            modified = Double(info.st_mtimespec.tv_sec)
                + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000
            size = Int64(info.st_size)
        }
    }

    private let url: URL
    private let onChange: @MainActor @Sendable () -> Void
    private let queue = DispatchQueue(label: "com.sabanote.Nullnote.FileWatcher")

    private var fileSource: DispatchSourceFileSystemObject?
    private var directorySource: DispatchSourceFileSystemObject?
    private var known: Fingerprint?
    private var pending: DispatchWorkItem?
    private var stopped = false

    /// **いま握っている記述子が指している実体の番号。**
    ///
    /// `known` とは別に持つ。`known` は「最後に知らせた中身」で、
    /// 知らせた時点で更新されてしまうため、記述子が古いかどうかの判断には使えない。
    /// ここを混ぜていたのが B-17 の原因。
    private var watchedInode: UInt64?

    /// 開き直しの再試行が残っている回数。
    private var reopenAttemptsLeft = 0

    /// - Parameter onChange: 変更を知らせる。**主スレッドで呼ぶ。**
    public convenience init(url: URL, onChange: @escaping @MainActor @Sendable () -> Void) {
        self.init(url: url, watchesParentDirectory: true, onChange: onChange)
    }

    /// - Parameter watchesParentDirectory: 親ディレクトリも見張るか。
    ///
    ///   **テストで、サンドボックス下を再現するために切る。**
    ///   実機では親ディレクトリを開けないことの方が多いのに、テストは
    ///   非サンドボックスで走るので、切らないと必ず開けてしまう。
    ///   B-17 は、ディレクトリ側の見張りに助けられて素通りしていた。
    init(
        url: URL,
        watchesParentDirectory: Bool,
        onChange: @escaping @MainActor @Sendable () -> Void
    ) {
        self.url = url
        self.onChange = onChange
        queue.async { [weak self] in
            guard let self else { return }
            self.known = Fingerprint(path: self.url.path)
            if watchesParentDirectory { self.watchDirectory() }
            self.watchFile()
        }
    }

    deinit {
        fileSource?.cancel()
        directorySource?.cancel()
        pending?.cancel()
    }

    /// 見張りをやめる。書類を閉じるときに呼ぶ。
    public func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopped = true
            self.pending?.cancel()
            self.pending = nil
            self.fileSource?.cancel()
            self.fileSource = nil
            self.watchedInode = nil
            self.directorySource?.cancel()
            self.directorySource = nil
        }
    }

    /// いますぐ見比べる。**イベントを取りこぼしていても、ここで拾える。**
    ///
    /// 見張りはサンドボックスの都合で万全にはならない。
    /// アプリが前面に戻ったときなど、区切りの良い場面で呼んでもらう。
    public func checkNow() {
        queue.async { [weak self] in
            guard let self, !self.stopped else { return }
            self.checkAndNotify()
            self.watchFile()
        }
    }

    // MARK: - 見張る

    /// 親ディレクトリ。**開けたら儲けもの。** サンドボックスでは大抵開けない。
    private func watchDirectory() {
        let parent = url.deletingLastPathComponent().path
        let descriptor = Darwin.open(parent, O_EVTONLY)
        guard descriptor >= 0 else {
            Trace.log("watchDirectory: 開けない errno=\(errno) \(parent)")
            return
        }
        Trace.log("watchDirectory: 見張り開始 \(parent)")

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .delete, .rename], queue: queue
        )
        source.setEventHandler { [weak self] in
            Trace.log("watchDirectory: イベント")
            // 無関係なファイルの出入りでも飛ぶ。中身が変わったかは stat で確かめる。
            self?.checkAndNotify()
            self?.watchFile()
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        directorySource = source
        source.resume()
    }

    /// ファイル本体を見張る。すでに**いまの実体**を握っているなら何もしない。
    ///
    /// 置き換えられていたら開き直す。置き換えの途中で一瞬見えないことがあるので、
    /// 開けなかったときは間を置いて数回やり直す。
    private func watchFile() {
        guard !stopped else { return }

        // 記述子が生きていて、それがいまのファイル本体を指しているなら、そのままでよい。
        if fileSource != nil, let watchedInode,
            let current = Fingerprint(path: url.path), current.inode == watchedInode {
            return
        }

        fileSource?.cancel()
        fileSource = nil
        watchedInode = nil

        let descriptor = Darwin.open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            Trace.log("watchFile: 開けない errno=\(errno) 残り\(reopenAttemptsLeft)回")
            retryOpeningFile()
            return
        }

        // **`stat` ではなく `fstat`。** 開いたそばから置き換えられることがある。
        // いま開いた記述子そのものの番号を控えないと、ずれた値を握ることになる。
        var info = stat()
        watchedInode = fstat(descriptor, &info) == 0 ? UInt64(info.st_ino) : nil
        reopenAttemptsLeft = Self.reopenRetryLimit

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .rename, .delete, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            Trace.log("watchFile: イベント")
            self?.checkAndNotify()
            // **置き換えられていたら開き直す。** これを忘れると、
            // 1回目の置き換えのあと二度と気づかなくなる（B-17）。
            self?.watchFile()
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        fileSource = source
        source.resume()
        Trace.log("watchFile: 見張り開始 inode=\(watchedInode.map(String.init) ?? "?")")
    }

    /// 置き換えの隙間で開けなかったときに、間を置いてやり直す。
    ///
    /// 回数を切ってあるので、ファイルが本当に消えた場合でも回り続けない。
    private func retryOpeningFile() {
        guard reopenAttemptsLeft > 0 else { return }
        reopenAttemptsLeft -= 1
        queue.asyncAfter(deadline: .now() + Self.reopenRetryInterval) { [weak self] in
            guard let self, !self.stopped, self.fileSource == nil else { return }
            self.checkAndNotify()
            self.watchFile()
        }
    }

    // MARK: - 知らせる

    /// いまの中身が、最後に知っているものと違えば知らせる。
    private func checkAndNotify() {
        guard !stopped else { return }
        let current = Fingerprint(path: url.path)
        // どちらも無い（元から存在しない）ときは知らせない。
        guard current != known else { return }
        Trace.log("checkAndNotify: 変化あり size=\(current?.size.description ?? "nil")")
        known = current
        notify()
    }

    /// 短い間隔で来た知らせを1つにまとめてから伝える。
    private func notify() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.stopped else { return }
            let callback = self.onChange
            DispatchQueue.main.async { MainActor.assumeIsolated { callback() } }
        }
        pending = work
        queue.asyncAfter(deadline: .now() + Self.coalescingInterval, execute: work)
    }
}
