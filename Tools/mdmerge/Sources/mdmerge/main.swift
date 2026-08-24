import Foundation
import MarkdownCore

// 開発用の道具。Claude Code のような「外から書く側」が、
// 相手の直しを踏み潰さずにファイルを更新するために使う。
//
//   mdmerge --base <読んだ時点の控え> --ours <直した結果> <書き込み先>
//
// 読んだときから相手が触っていなければ、そのまま書く。
// 違う行を触っていれば黙って合流する。**同じ行なら印を入れて 1 で終わる。**

let usage = """
使い方:
  mdmerge --base <控え> --ours <直した結果> [--dry-run] <書き込み先>

  --base     こちらがファイルを読んだ時点の内容（控え）。合流の基準。
  --ours     こちらが直した結果。
  --dry-run  書かずに、何が起きるかだけを出す。

終了コード:
  0  書けた（印なし）
  1  印を入れた。人が直すまで**そのまま**にしない
  2  引数かファイルの誤り
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("mdmerge: \(message)\n\(usage)\n".utf8))
    exit(2)
}

var basePath: String?
var oursPath: String?
var targetPath: String?
var dryRun = false

var arguments = Array(CommandLine.arguments.dropFirst())
while let argument = arguments.first {
    arguments.removeFirst()
    switch argument {
    case "--base":
        guard let value = arguments.first else { fail("--base の値がありません") }
        arguments.removeFirst()
        basePath = value
    case "--ours":
        guard let value = arguments.first else { fail("--ours の値がありません") }
        arguments.removeFirst()
        oursPath = value
    case "--dry-run":
        dryRun = true
    case "-h", "--help":
        print(usage)
        exit(0)
    default:
        guard targetPath == nil else { fail("書き込み先が2つ以上あります: \(argument)") }
        targetPath = argument
    }
}

guard let basePath, let oursPath, let targetPath else {
    fail("--base / --ours / 書き込み先 のすべてが要ります")
}

func read(_ path: String, label: String) -> String {
    guard let data = FileManager.default.contents(atPath: path),
          let text = String(data: data, encoding: .utf8)
    else { fail("\(label) が読めません: \(path)") }
    return text
}

let base = read(basePath, label: "--base")
let ours = read(oursPath, label: "--ours")
// **書く直前に読む。** ここが要点。控えを取ってから今までのあいだに
// 相手が保存しているかもしれない。
let theirs = read(targetPath, label: "書き込み先")

let plan = MergeWrite.plan(base: base, ours: ours, theirs: theirs)

if plan.conflictCount > 0 {
    FileHandle.standardError.write(
        Data("mdmerge: 同じ場所を直しています。印を \(plan.conflictCount) か所入れました\n".utf8)
    )
} else if base != theirs {
    FileHandle.standardError.write(Data("mdmerge: 外の直しと合流しました（印なし）\n".utf8))
}

if dryRun {
    print(plan.text)
    exit(plan.conflictCount > 0 ? 1 : 0)
}

if plan.needsWrite {
    // その場書き換え。実体番号を変えないので、相手の見張りを取り逃がさせない。
    do {
        try plan.text.write(toFile: targetPath, atomically: false, encoding: .utf8)
    } catch {
        fail("書けません: \(error.localizedDescription)")
    }
}

exit(plan.conflictCount > 0 ? 1 : 0)
