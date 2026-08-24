# docs

Nullnote の開発ドキュメント。
Git repository: [nullnote](https://github.com/roughlang/nullnote)

## 起動方法

```bash
% cd <クローンした場所>/MarkdownEditor
% ./Apps/Nullnote-macOS/run.sh 
```

## この中にあるもの

| ファイル | 内容 | こんなとき |
|---|---|---|
| [01-native-app-anatomy.md](01-native-app-anatomy.md) | macOS ネイティブアプリの構造。ソースが `.app` になるまで、`.app` の中身、リンクの仕組み、DerivedData、署名とサンドボックス | 仕組みを知りたいとき。ビルド周りで詰まったとき |
| [02-decision-log.md](02-decision-log.md) | なぜこの作りになったか。捨てた案とその理由、実測値、見つけた不具合 | 「なぜこうしなかったのか」を思い出したいとき。設計を変えようとするとき |
| [03-release-plan.md](03-release-plan.md) | ローカル常用 → App Store 公開までの段取りとタスク。分担つき | 次に何をやるか思い出したいとき |
| [04-development-flow.md](04-development-flow.md) | コードを直してから常用アプリに反映するまでの手順。run.sh / install.sh の使い方 | 作業を再開するとき。「直したのに変わらない」とき |

## この外にあるもの

ドキュメントは重複させない。以下はそれぞれの場所が正。

| 知りたいこと | 場所 |
|---|---|
| 全体の構成、依存の向き、検証コマンド | [`../README.md`](../README.md) |
| パースの設計、対応記法、既知の制限 | [`../Packages/MarkdownCore/README.md`](../Packages/MarkdownCore/README.md) |
| ハイライトとプレビューの実装 | [`../Packages/NullnoteUI/README.md`](../Packages/NullnoteUI/README.md) |
| macOS ターゲットの設定、UTType、操作方法 | [`../Apps/Nullnote-macOS/README.md`](../Apps/Nullnote-macOS/README.md) |
| iOS 版に着手するときの手順 | [`../Apps/Nullnote-iOS/README.md`](../Apps/Nullnote-iOS/README.md) |

## 書き足すときの方針

- **`01-` は仕組みの話。** このプロジェクト固有でなくても、macOS 開発として知っておくべきことを書く
- **`02-` は判断の話。** 「何を選んだか」より **「何を捨てたか、なぜか」** を書く。
  後から読む人（未来の自分を含む）が困るのは、選ばれなかった道の理由が残っていないとき
- 構成や API の説明は書かない。それは README 側の仕事
- 数値は実測値を書く。「重い」「速い」ではなく「5万文字で 45.7 ms」
