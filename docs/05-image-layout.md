# 画像の配置とレイアウトのカスタマイズ

本来、Markdownのデフォルト機能にはないが、画像の配置をカスタマイズできる機能をつける。

## いまの状態

| 指定 | 状態 |
|---|---|
| `{.center}` | ✅ 実装済み |
| `{.thumbnail}` | ✅ 実装済み。押すと窓で拡大、前後送りつき |
| `{.left}` `{.right}` | ⬜ **見送り。** 文章の組み方を変える必要があり、土台の作り替えになる（`docs/02-decision-log.md` の D-27） |

書き方は空白に寛容。`{.center}` `{. center}` `{ .center }` のどれでも効く。
知らない名前は指定なし扱い。

## 中央寄せ（センタリング）

`{.center}`が付いた画像は、全幅でセンタリングにする

```markdown
![foo](./bar.png){.center}
```

レイアウト例
```text
texttexttexttexttexttexttexttexttexttexttexttext
texttexttexttexttexttexttexttexttexttexttexttext
texttexttexttexttexttexttexttexttexttexttexttext
┌──────────────────────────────────────────────┐
│                                              │
│                                              │
│                    image                     │
│                                              │
│                                              │
└──────────────────────────────────────────────┘
texttexttexttexttexttexttexttexttexttexttexttext
texttexttexttexttexttexttexttexttexttexttexttext
texttexttexttexttexttexttexttexttexttexttexttext
texttexttexttexttexttexttexttexttexttexttexttext
```

## 回り込み

### 左回りこみ

```markdown
![foo](./bar.png){.left}
```

レイアウト例
```text
texttexttexttexttexttexttexttexttexttexttexttext
texttexttexttexttexttexttexttexttexttexttexttext
texttexttexttexttexttexttexttexttexttexttexttext
┌───────────────────────┐texttexttexttexttexttex
│                       │texttexttexttexttexttex
│                       │texttexttexttexttexttex
│         image         │texttexttexttexttexttex
│                       │texttexttexttexttexttex
│                       │texttexttexttexttexttex
└───────────────────────┘texttexttexttexttexttex
texttexttexttexttexttexttexttexttexttexttexttext
texttexttexttexttexttexttexttexttexttexttexttext
texttexttexttexttexttexttexttexttexttexttexttext
texttexttexttexttexttexttexttexttexttexttexttext
```

### 右回りこみ

```markdown
![foo](./bar.png){.right}
```

レイアウト例

```text
texttexttexttexttexttexttexttexttexttexttexttext
texttexttexttexttexttexttexttexttexttexttexttext
texttexttexttexttexttexttexttexttexttexttexttext
texttexttexttexttexttex┌───────────────────────┐
texttexttexttexttexttex│                       │
texttexttexttexttexttex│                       │
texttexttexttexttexttex│         image         │
texttexttexttexttexttex│                       │
texttexttexttexttexttex│                       │
texttexttexttexttexttex└───────────────────────┘
texttexttexttexttexttexttexttexttexttexttexttext
texttexttexttexttexttexttexttexttexttexttexttext
texttexttexttexttexttexttexttexttexttexttexttext
texttexttexttexttexttexttexttexttexttexttexttext
```

## サムネイル

```markdown
![foo](./bar.png){.thumbnail}
![foo](./bar.png){.thumbnail}
![foo](./bar.png){.thumbnail}
![foo](./bar.png){.thumbnail}
![foo](./bar.png){.thumbnail}
```

レイアウト例

```text
texttexttexttexttexttexttexttexttexttexttexttext
texttexttexttexttexttexttexttexttexttexttexttext
texttexttexttexttexttexttexttexttexttexttexttext
texttexttexttexttexttexttexttexttexttexttexttext
┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐
│        │ │        │ │        │ │        │
│ image  │ │ image  │ │ image  │ │ image  │
│        │ │        │ │        │ │        │
└────────┘ └────────┘ └────────┘ └────────┘
texttexttexttexttexttexttexttexttexttexttexttext
texttexttexttexttexttexttexttexttexttexttexttext
texttexttexttexttexttexttexttexttexttexttexttext
texttexttexttexttexttexttexttexttexttexttexttext
```