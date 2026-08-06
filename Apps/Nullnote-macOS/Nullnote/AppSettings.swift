import Foundation

enum AppSettings {
    /// `UserDefaults` のキー。`@AppStorage` の綴り間違いを1か所に閉じ込める。
    static let fontSizeKey = "editorFontSize"
    static let appearanceKey = "editorAppearance"

    /// 起動時に一度だけ呼ぶ。
    ///
    /// `register` は「ユーザーがまだ選んでいないときの既定値」を与えるだけなので、
    /// あとでユーザーが自分で変えれば、そちらが優先される。
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            // 保存パネルは既定で折りたたまれ、保存先が「場所」ポップアップだけになる。
            // 書類アプリでは保存先を選びたい場面が多いので、最初から
            // ファイルブラウザが開いた状態にする。
            "NSNavPanelExpandedStateForSaveMode": true,
            "NSNavPanelExpandedStateForSaveMode2": true,
        ])
    }
}
