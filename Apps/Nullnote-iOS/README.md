# Nullnote (iOS) （未着手 / 今期のゴールには含めない）

iOS アプリターゲットの置き場所。

## いまの状態

土台は揃っている。`Packages/MarkdownCore` と `Packages/NullnoteUI` は
**どちらも iOS 向けにビルドが通る状態**を保っている。

```sh
xcodebuild -scheme MarkdownCore -destination 'generic/platform=iOS' build
xcodebuild -scheme NullnoteUI   -destination 'generic/platform=iOS' build
```

`MarkdownEditorView` は `UIViewRepresentable`（`UITextView`）の実装まで書いてある。
`MarkdownPreview` は SwiftUI だけで組んであるのでそのまま動く。
残っているのはアプリの外枠だけ。

## 着手時にやること

1. iOS アプリターゲットを作成（Interface: SwiftUI、Bundle Identifier は `com.roughlang.Nullnote`）
2. `Packages/MarkdownCore` と `Packages/NullnoteUI` を依存に追加
3. `DocumentGroup` + Files アプリ連携。UTType の宣言は macOS 版と同じ
   （`Apps/Nullnote-macOS/Supporting/Info.plist` をそのまま持ってこられる）
4. iOS 固有の対応
   - ソフトキーボードの回避（`keyboardLayoutGuide`）
   - Markdown 記法の入力補助バー（`inputAccessoryView`）
   - 画面が狭いので、プレビューは左右分割ではなく全画面切り替えにする
     （`DocumentView` の `HSplitView` は macOS 専用。ここは書き分けが要る）

## 今のうちに守っておくこと

- `MarkdownCore` に AppKit を入れない
- `NullnoteUI` の AppKit 依存は `Platform.swift` と `MarkdownEditorView.swift` に閉じ込める。
  この2ファイル以外に `#if canImport(AppKit)` が増え始めたら黄信号
- CI で iOS ビルドを回す。壊れたことに気づけなくなるのが一番まずい
