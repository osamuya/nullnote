import Foundation

/// `![]()` に書かれた場所を、実際に読める形に直したもの。
public enum ImageSource: Equatable {
    /// 手元のファイル。
    case local(URL)
    /// 網の向こう。読みに行くと、開いたことが相手に伝わる。
    case remote(URL)
}

/// 画像の場所の書き方を解釈する。
///
/// **書き方は全部認める。** 相対パス・`~/`・絶対パス・URL。
/// いま書いてある文書がそのまま表示されることを優先した。
///
/// 副作用を持たない。ファイルがあるかどうかも見ない。
/// **「読めるか」と「どこを指しているか」は別の話**で、
/// 読める・読めないはサンドボックスの許可の問題として別に扱う。
public enum ImageSourceResolver {

    /// - Parameters:
    ///   - source: `![代替テキスト](ここ)` の中身。
    ///   - document: 文書のファイル。相対パスの基準にする。新規で未保存なら `nil`。
    public static func resolve(_ source: String, relativeTo document: URL?) -> ImageSource? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 網の向こう。
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() {
            switch scheme {
            case "http", "https":
                return .remote(url)
            case "file":
                return .local(url.standardizedFileURL)
            default:
                // data: など、扱わない書き方。
                return nil
            }
        }

        let path = decoded(trimmed)

        // ホームからの指定。
        if path == "~" || path.hasPrefix("~/") {
            return .local(URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).standardizedFileURL)
        }
        // 絶対パス。
        if path.hasPrefix("/") {
            return .local(URL(fileURLWithPath: path).standardizedFileURL)
        }
        // 文書からの相対。基準が無ければ決めようがない。
        guard let document else { return nil }
        return .local(
            URL(fileURLWithPath: path, relativeTo: document.deletingLastPathComponent())
                .standardizedFileURL
        )
    }

    /// `%20` などを戻す。
    ///
    /// Markdown では空白を含む名前が符号化されて書かれることがある。
    /// **戻して名前が変わらないなら、そのまま使う。**
    /// ファイル名に `%` が入っている場合に、壊さないため。
    private static func decoded(_ path: String) -> String {
        guard path.contains("%"), let decoded = path.removingPercentEncoding else { return path }
        return decoded
    }
}
