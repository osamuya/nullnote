import Foundation
import MarkdownCore

/// ファイルへの書き込みを「合流してから書く」形にまとめたもの。
///
/// **副作用のある部分と、判断の部分を分けてある。** 判断は `plan` に、
/// 実際の読み書きは `run` に置き、テストは `plan` を突く。
public enum MergeWrite {

    public struct Plan: Equatable {
        /// 書き込む内容。
        public let text: String
        /// 印を入れた箇所の数。
        public let conflictCount: Int
        /// 書く必要があるか。ディスクが既に同じなら false。
        public let needsWrite: Bool
    }

    /// - Parameters:
    ///   - base: **こちらが読んだ時点**のファイルの内容。合流の基準。
    ///   - ours: こちらが直した結果。
    ///   - theirs: **書く直前**のディスクの内容。
    public static func plan(base: String, ours: String, theirs: String) -> Plan {
        // 読んだときから誰も触っていない。普通に書けばよい。
        guard base != theirs else {
            return Plan(text: ours, conflictCount: 0, needsWrite: ours != theirs)
        }
        // こちらは何も直していない。相手の内容をそのまま残す。
        guard base != ours else {
            return Plan(text: theirs, conflictCount: 0, needsWrite: false)
        }
        let merged = ThreeWayMerge.merge(base: base, ours: ours, theirs: theirs)
        return Plan(
            text: merged.text,
            conflictCount: merged.conflictCount,
            needsWrite: merged.text != theirs
        )
    }
}
