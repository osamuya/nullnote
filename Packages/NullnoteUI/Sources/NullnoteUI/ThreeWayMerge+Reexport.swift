import MarkdownCore

/// 合流の判断そのものは `MarkdownCore` にある。
///
/// UI にも AppKit にも依存しない純粋な処理で、アプリの外（開発用の `mdmerge`）
/// からも同じ規則で呼びたいため、下の層へ移した。理由は `docs/02-decision-log.md` の D-34。
///
/// 書類側はこれまでどおり `NullnoteUI` の名前で使える。
public typealias ThreeWayMerge = MarkdownCore.ThreeWayMerge
