import Foundation

/// 少し間を置いてから一度だけ呼ぶ。待っているあいだの呼び出しはまとめる。
///
/// 選択はマウスが動くたびに変わる。そのたびに相手側へ知らせると、塗り直しが追いつかない。
/// **ランループの共通モードに載せる。** ドラッグ中はイベント追跡のモードで回っており、
/// 既定のモードに載せたタイマーはマウスを離すまで動かない（#M0045）。
@MainActor
final class Coalescer {

    private let delay: TimeInterval
    private var timer: Timer?

    init(delay: TimeInterval) {
        self.delay = delay
    }

    /// 予定が無ければ入れる。あればそのまま（最初の予定の時刻に、そのときの状態で動く）。
    func schedule(_ action: @escaping @MainActor () -> Void) {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.timer = nil
                action()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
