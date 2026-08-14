import Foundation
import Testing
@testable import NullnoteUI

/// ファイルの見張り。
///
/// **実際にファイルを書いて確かめる。** 外部のエディタがどう保存するかは
/// 実装によって違い（その場で書く／別名で書いて置き換える）、
/// 模擬では取りこぼしに気づけない。
@Suite("ファイルの見張り", .serialized)
struct FileWatcherTests {

    /// 変更の知らせを待つ。
    ///
    /// 見張りは知らせをまとめるので、少し待つ必要がある。
    /// 待ちきる前に返ってきたら、そこで止める。
    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        func record() {
            lock.lock(); count += 1; lock.unlock()
        }

        var value: Int {
            lock.lock(); defer { lock.unlock() }
            return count
        }

        /// 最大 `timeout` 秒まで、知らせが来るのを待つ。
        func wait(seconds timeout: Double = 3) async -> Int {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if value > 0 {
                    // まとめられた続きが来ないか、少しだけ様子を見る。
                    try? await Task.sleep(for: .milliseconds(250))
                    return value
                }
                try? await Task.sleep(for: .milliseconds(30))
            }
            return value
        }
    }

    func makeFile(_ contents: String = "はじめの内容\n") throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FileWatcherTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("文書.md")
        try contents.write(to: url, atomically: false, encoding: .utf8)
        return url
    }

    @Test("その場で書き換えられたら知らせる")
    func detectsInPlaceWrite() async throws {
        let url = try makeFile()
        let recorder = Recorder()
        let watcher = FileWatcher(url: url) { recorder.record() }
        defer { watcher.stop() }

        // 見張りが開くまで待つ。
        try await Task.sleep(for: .milliseconds(200))
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("あとから足した行\n".utf8))
        try handle.close()

        #expect(await recorder.wait() >= 1)
    }

    @Test("別名で書いて置き換えられても知らせる")
    func detectsAtomicReplace() async throws {
        // Claude Code やエディタの多くはこの形で保存する。
        // 元の記述子は古い中身を指したままになるので、開き直せていないと取りこぼす。
        let url = try makeFile()
        let recorder = Recorder()
        let watcher = FileWatcher(url: url) { recorder.record() }
        defer { watcher.stop() }

        try await Task.sleep(for: .milliseconds(200))
        try "外から書き換えた内容\n".write(to: url, atomically: true, encoding: .utf8)

        #expect(await recorder.wait() >= 1)
    }

    @Test("置き換えられたあと、次の変更も拾える")
    func keepsWatchingAfterReplace() async throws {
        // ここが取りこぼしやすい。1回目で記述子が無効になり、開き直していないと
        // 2回目以降が永久に届かなくなる。
        let url = try makeFile()
        let recorder = Recorder()
        let watcher = FileWatcher(url: url) { recorder.record() }
        defer { watcher.stop() }

        try await Task.sleep(for: .milliseconds(200))
        try "1回目\n".write(to: url, atomically: true, encoding: .utf8)
        _ = await recorder.wait()

        let afterFirst = recorder.value
        // 開き直す猶予を与えてから、もう一度書く。
        try await Task.sleep(for: .milliseconds(300))
        try "2回目\n".write(to: url, atomically: true, encoding: .utf8)
        _ = await recorder.wait()

        #expect(recorder.value > afterFirst, "置き換えのあと、次の変更を拾えていない")
    }

    @Test("何も起きなければ知らせない")
    func silentWhenNothingHappens() async throws {
        let url = try makeFile()
        let recorder = Recorder()
        let watcher = FileWatcher(url: url) { recorder.record() }
        defer { watcher.stop() }

        try await Task.sleep(for: .milliseconds(600))
        #expect(recorder.value == 0)
    }

    @Test("止めたら、そのあとの変更は知らせない")
    func stopsWatching() async throws {
        let url = try makeFile()
        let recorder = Recorder()
        let watcher = FileWatcher(url: url) { recorder.record() }

        try await Task.sleep(for: .milliseconds(200))
        watcher.stop()
        try await Task.sleep(for: .milliseconds(150))
        try "止めたあとの変更\n".write(to: url, atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(500))

        #expect(recorder.value == 0)
    }

    @Test("1回の保存で何度も知らせない")
    func coalescesBurstsOfWrites() async throws {
        let url = try makeFile()
        let recorder = Recorder()
        let watcher = FileWatcher(url: url) { recorder.record() }
        defer { watcher.stop() }

        try await Task.sleep(for: .milliseconds(200))
        let handle = try FileHandle(forWritingTo: url)
        for index in 0..<10 {
            try handle.write(contentsOf: Data("行 \(index)\n".utf8))
        }
        try handle.close()

        let count = await recorder.wait()
        #expect(count >= 1)
        #expect(count <= 2, "まとめきれていない: \(count) 回")
    }

    @Test("無いファイルを指しても落ちない")
    func missingFileIsHarmless() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("存在しない-\(UUID().uuidString).md")
        let recorder = Recorder()
        let watcher = FileWatcher(url: url) { recorder.record() }
        defer { watcher.stop() }

        try await Task.sleep(for: .milliseconds(300))
        #expect(recorder.value == 0)
    }
}
