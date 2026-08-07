import SwiftUI

/// 見出しの目次。項目を選ぶと、その行が呼び出し側に伝わる。
///
/// 階層は開いた状態を既定にする。目次は全体を見渡すためのものなので、
/// 開く操作から始めさせない。畳んだものだけを覚えておく。
public struct OutlineView: View {

    private let source: String
    private let theme: MarkdownTheme
    private let onSelect: (Int) -> Void

    @State private var items: [OutlineItem] = []
    @State private var selection: OutlineItem.ID?
    /// **畳んだ**項目だけを覚える。既定はすべて開いた状態。
    @State private var collapsed: Set<OutlineItem.ID> = []

    /// - Parameter onSelect: 選ばれた見出しの行番号（1 始まり）が渡る。
    public init(source: String, theme: MarkdownTheme, onSelect: @escaping (Int) -> Void) {
        self.source = source
        self.theme = theme
        self.onSelect = onSelect
    }

    public var body: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                List(selection: $selection) {
                    ForEach(items) { node(for: $0).erased }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color(platform: theme.background))
        .preferredColorScheme(theme.appearance.colorScheme)
        .task(id: source) { await reload() }
        .onChange(of: selection) { _, id in
            guard let id, let item = items.flattened.first(where: { $0.id == id }) else { return }
            onSelect(item.line)
        }
    }

    @ViewBuilder
    private func node(for item: OutlineItem) -> some View {
        if let children = item.children {
            DisclosureGroup(isExpanded: expansion(of: item.id)) {
                ForEach(children) { node(for: $0).erased }
            } label: {
                row(for: item)
            }
        } else {
            row(for: item)
        }
    }

    private func expansion(of id: OutlineItem.ID) -> Binding<Bool> {
        Binding(
            get: { !collapsed.contains(id) },
            set: { isExpanded in
                if isExpanded { collapsed.remove(id) } else { collapsed.insert(id) }
            }
        )
    }

    private func row(for item: OutlineItem) -> some View {
        Text(item.title)
            .font(.system(size: theme.fontSize * 0.92, weight: item.level <= 2 ? .medium : .regular))
            .foregroundStyle(Color(platform: item.level <= 2 ? theme.heading : theme.text))
            .lineLimit(1)
            .truncationMode(.tail)
            .help(item.title)
            .tag(item.id)
    }

    private var emptyState: some View {
        Text("見出しがありません")
            .font(.system(size: theme.fontSize * 0.9))
            .foregroundStyle(Color(platform: theme.marker))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 入力が止まってから組み立てる。
    ///
    /// 見出しを拾うには文書全体をトークン化する必要がある（5万文字で 5.3 ms）。
    /// プレビューと同じく、打鍵のたびに走らせない。
    private func reload() async {
        if !items.isEmpty {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
        }
        items = DocumentOutline.build(from: source)
    }
}

private extension View {
    /// 再帰する箇所で型が無限に育つのを避ける。
    var erased: AnyView { AnyView(self) }
}
