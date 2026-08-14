import Foundation

/// ファイルが外で書き換わったことを知らせる見張り。
///
/// **ポーリングしない。** 変化があったときだけカーネルから起こされるので、
/// 何も起きていないあいだの費用はゼロ。書類1つにつきファイル記述子を2つ持つ。
///
/// ## ファイルだけ見張っても足りない
///
/// 多くのエディタ（Claude Code を含む）は、上書き保存を
/// 「別名で書いてから置き換える」形で行う。**このときファイル記述子には
/// イベントが1つも飛んでこない。** 置き換わったのはディレクトリの項目であって、
/// こちらが握っている中身ではないため。実測で確かめた。
///
/// そこで**親ディレクトリも見張る**。項目の増減や置き換えはこちらに届く。
///
/// ## 見張るだけでは多すぎる
///
/// ディレクトリのイベントは、同じ場所にある無関係なファイルでも飛ぶ。
/// 起こされるたびに `stat` を取り、**識別子・更新時刻・大きさのどれかが
/// 変わったときだけ**知らせる。`stat` は変化があったときにしか走らない。
public final class FileWatcher: @unchecked Sendable {

    /// 知らせをまとめる幅。1回の保存で飛ぶ複数の通知を1つにする。
    private static let coalescingInterval: DispatchTimeInterval = .milliseconds(120)

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
            inode = UInt64(info.st_ino)
            modified = Double(info.st_mtimespec.tv_sec)
                + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000
            size = Int64(info.st_size)
        }
    }

    private let url: URL
    private let onChange: @MainActor @Sendable () -> Void
    private let queue = DispatchQueue(label: "com.roughlang.Nullnote.FileWatcher")

    private var fileSource: DispatchSourceFileSystemObject?
    private var directorySource: DispatchSourceFileSystemObject?
    private var known: Fingerprint?
    private var pending: DispatchWorkItem?
    private var stopped = false

    /// - Parameter onChange: 変更を知らせる。**主スレッドで呼ぶ。**
    public init(url: URL, onChange: @escaping @MainActor @Sendable () -> Void) {
        self.url = url
        self.onChange = onChange
        queue.async { [weak self] in
            guard let self else { return }
            self.known = Fingerprint(path: self.url.path)
            self.watchDirectory()
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
            self.directorySource?.cancel()
            self.directorySource = nil
        }
    }

    // MARK: - 見張る

    /// 親ディレクトリ。置き換えによる保存はこちらにしか届かない。
    private func watchDirectory() {
        let parent = url.deletingLastPathComponent().path
        let descriptor = Darwin.open(parent, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .delete, .rename], queue: queue
        )
        source.setEventHandler { [weak self] in
            // 無関係なファイルの出入りでも飛ぶ。中身が変わったかは stat で確かめる。
            self?.checkAndNotify()
            self?.watchFile()
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        directorySource = source
        source.resume()
    }

    /// ファイル本体。その場で書き換える保存はこちらに届く。
    ///
    /// 置き換えられると、いま握っている記述子は誰からも見えない古い中身を指すので、
    /// 開き直す。開けないときは、ディレクトリ側の見張りに任せる。
    private func watchFile() {
        guard !stopped else { return }
        let current = Fingerprint(path: url.path)
        // 実体が変わっていないなら、いまの記述子のままでよい。
        if fileSource != nil, current == known { return }

        fileSource?.cancel()
        fileSource = nil

        let descriptor = Darwin.open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .rename, .delete, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.checkAndNotify()
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        fileSource = source
        source.resume()
    }

    // MARK: - 知らせる

    /// いまの中身が、最後に知っているものと違えば知らせる。
    private func checkAndNotify() {
        guard !stopped else { return }
        let current = Fingerprint(path: url.path)
        // どちらも無い（元から存在しない）ときは知らせない。
        guard current != known else { return }
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
