import SwiftUI

/// 文書に出てくる画像の一覧。拡大表示の前後送りに使う。
///
/// **段落をまたいで送りたい**ので、段落ごとのビューではなく上から配る。
/// 引数で持ち回すと、引用やリストの入れ子を通すたびに署名が増える。
private struct PreviewImageListKey: EnvironmentKey {
    static let defaultValue: [PreviewImageRef] = []
}

extension EnvironmentValues {
    var previewImageList: [PreviewImageRef] {
        get { self[PreviewImageListKey.self] }
        set { self[PreviewImageListKey.self] = newValue }
    }
}
