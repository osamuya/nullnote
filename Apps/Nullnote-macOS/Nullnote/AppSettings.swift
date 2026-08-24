import Foundation

enum AppSettings {
    /// `UserDefaults` のキー。`@AppStorage` の綴り間違いを1か所に閉じ込める。
    static let fontSizeKey = "editorFontSize"
    static let appearanceKey = "editorAppearance"
    static let lineNumbersKey = "editorShowsLineNumbers"
    static let titleSyncKey = "syncsTitleWithFileName"
    static let breaksOnNewlineKey = "previewBreaksOnNewline"

    /// 保存パネルを最初から詳細表示（ファイルブラウザ）で開かせる AppKit のキー。
    ///
    /// 2つあるのは AppKit が世代の違う綴りを持っているため。
    /// **どちらが効いたかまでは切り分けていない**ので、両方書いている。
    private static let savePanelExpansionKeys = [
        "NSNavPanelExpandedStateForSaveMode",
        "NSNavPanelExpandedStateForSaveMode2",
    ]

    /// 上のキーをもう書いたか、という印。
    private static let savePanelExpansionSeededKey = "seededSavePanelExpansion"

    /// 起動時に一度だけ呼ぶ。
    ///
    /// `register` は「ユーザーがまだ選んでいないときの既定値」を与えるだけなので、
    /// あとでユーザーが自分で変えれば、そちらが優先される。
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            // 行番号は最初から出す。要らない人は設定画面で消せる。
            lineNumbersKey: true,

            // ファイル名と見出しの同期は**切ってある**。
            // 本文を黙って書き換える動きなので、選んだ人にだけ効かせる。
            titleSyncKey: false,

            // 普通の改行をプレビューでも改行にするのは**切ってある**。
            // Markdown の決まりから外れる見え方なので、選んだ人にだけ効かせる。
            breaksOnNewlineKey: false,
        ])

        seedSavePanelExpansion()
    }

    /// 保存パネルを、初回起動のときだけ詳細表示にしておく。
    ///
    /// 折りたたみ表示だと保存先が「場所」ポップアップだけになり、階層を辿れない。
    /// 書類アプリで保存先を選べないのは困るので、最初はブラウザを開いた状態にする。
    ///
    /// **`register(defaults:)` では効かない。** 登録ドメインはプロセスのメモリ上にしか無く、
    /// ディスクには書かれない。ところがサンドボックスアプリの保存パネルは別プロセス
    /// （`com.apple.appkit.xpc.openAndSavePanelService`）で動いていて、
    /// 読めるのは**永続化された設定だけ**。登録ドメインは見えない（実測。B-16）。
    ///
    /// だから実際の値を書く。ただし**書くのは一度きり**。
    /// パネルは閉じるときに自分でこのキーを上書きするので、毎回書くと
    /// 「折りたたんだままでいい」という利用者の選択を、起動のたびに踏み潰すことになる。
    private static func seedSavePanelExpansion() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: savePanelExpansionSeededKey) else { return }

        for key in savePanelExpansionKeys {
            defaults.set(true, forKey: key)
        }
        defaults.set(true, forKey: savePanelExpansionSeededKey)
    }
}
