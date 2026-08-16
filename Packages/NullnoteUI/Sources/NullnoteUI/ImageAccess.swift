import SwiftUI

/// 「このフォルダを読ませてください」と利用者に頼む手立て。
///
/// **頼み方はアプリ側が持つ。** 許可の求め方（パネルの出し方）も、
/// 覚え方（ブックマークの保存先）も AppKit と結び付いていて、
/// iOS では別の作りになる。こちらは受け口だけを用意する。
public struct ImageAccessRequester: Sendable {

    /// - Returns: 許可されたら `true`。断られたら `false`。
    public let request: @MainActor @Sendable (URL) async -> Bool

    public init(request: @escaping @MainActor @Sendable (URL) async -> Bool) {
        self.request = request
    }
}

private struct ImageAccessRequesterKey: EnvironmentKey {
    static let defaultValue: ImageAccessRequester? = nil
}

extension EnvironmentValues {
    /// 画像を読む許可を求める手立て。入っていなければ、頼む口を出さない。
    public var imageAccessRequester: ImageAccessRequester? {
        get { self[ImageAccessRequesterKey.self] }
        set { self[ImageAccessRequesterKey.self] = newValue }
    }
}

extension View {
    /// 画像を読む許可の求め方を渡す。
    public func imageAccessRequester(_ requester: ImageAccessRequester?) -> some View {
        environment(\.imageAccessRequester, requester)
    }
}
