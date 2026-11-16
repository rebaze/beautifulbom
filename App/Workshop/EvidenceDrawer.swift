import BOMCore
import SwiftUI

/// The drawer's header: where the evidence sits, Esc to close, the pin.
struct EvidenceHeader: View {
    @Bindable var model: DocumentModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.magnifyingglass").foregroundStyle(.secondary)
            Text(caption).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button {
                model.toggleDrawerPinned()
            } label: {
                Image(systemName: model.drawerPinned ? "pin.fill" : "pin")
            }
            .buttonStyle(.plain)
            .help(model.drawerPinned ? L("Let Esc close the evidence") : L("Keep the evidence open (⌥⌘E)"))
            Button(L("Esc to close")) { model.closeDrawer() }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .opacity(model.drawerPinned ? 0.4 : 1)
        }
        .font(.system(size: 12 * max(1, model.scale * 0.8)))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var caption: String {
        guard let tree = model.tree, let source = model.source, let e = model.evidence else { return L("Evidence") }
        switch e {
        case .located(let id):
            let line = source.lineColumn(of: tree.fullRange(id).lowerBound).line
            let pointer = tree.pointer(id).displayString
            return L("Evidence · line %d · %@", line, pointer.isEmpty ? "/" : pointer)
        case .absent(let a):
            let line = source.lineColumn(of: a.insertion).line
            let pointer = tree.pointer(a.parent).description
            return L("Evidence · line %d · %@ has no \"%@\"", line, pointer.isEmpty ? "/" : pointer, a.key)
        }
    }
}
