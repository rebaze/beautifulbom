import BOMCore
import SwiftUI

/// Where the selection sits: each ancestor is a button; the JSON Pointer
/// (with an explicit duplicate marker) can be selected and copied.
struct BreadcrumbBar: View {
    let model: DocumentModel

    var body: some View {
        HStack(spacing: 8) {
            if let tree = model.tree, let id = model.selection {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(tree.ancestors(id) + [id], id: \.self) { node in
                            if node != tree.root { Image(systemName: "chevron.compact.right").foregroundStyle(.tertiary) }
                            Button(label(tree, node)) { model.select(node, origin: .breadcrumb) }
                                .buttonStyle(.plain)
                                .foregroundStyle(node == id ? .primary : .secondary)
                                .fontWeight(node == id ? .semibold : .regular)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.never)
                .defaultScrollAnchor(.trailing)
                Spacer(minLength: 12)
                Text(tree.pointer(id).displayString.isEmpty ? "/" : tree.pointer(id).displayString)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .textSelection(.enabled)
                    .help("JSON Pointer (RFC 6901)")
            } else {
                Text("Select a value to see where it sits")
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(.bar)
    }

    private func label(_ tree: JSONTree, _ node: NodeID) -> String {
        if let key = tree.key(node) { return key }
        if let parent = tree.parent(node), tree.kind(parent) == .array { return "[\(tree.indexInParent(node))]" }
        return "root"
    }
}
