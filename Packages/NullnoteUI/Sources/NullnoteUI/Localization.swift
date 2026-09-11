import Foundation

extension LocalizedStringResource.BundleDescription {
    /// このパッケージのカタログ。`Text("…", bundle: .module)` と同じ書き方で引けるようにする。
    ///
    /// `LocalizedStringResource` だけは `Bundle` ではなく `BundleDescription` を受け取るので、
    /// そのままでは `.atURL(Bundle.module.bundleURL)` と書くことになる。
    /// 書き方が場所ごとに違うと、付け忘れの検査（`LocalizationSourceTests`）が
    /// 「`bundle: .module` があるか」だけで判定できなくなる。docs/12-make-multilingual.md
    static var module: Self { .atURL(Bundle.module.bundleURL) }
}
