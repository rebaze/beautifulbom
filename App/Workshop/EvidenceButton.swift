import BOMCore
import SwiftUI

/// Any statement in a view: a click shows its evidence in the drawer.
struct EvidenceButton<Label: View>: View {
    @Environment(DocumentModel.self) private var model
    let evidence: Evidence?
    @ViewBuilder let label: () -> Label
    @State private var hovering = false

    init(_ evidence: Evidence?, @ViewBuilder label: @escaping () -> Label) {
        self.evidence = evidence
        self.label = label
    }

    private var isShown: Bool { evidence != nil && model.drawerOpen && model.evidence == evidence }

    var body: some View {
        if let evidence {
            Button { model.show(evidence) } label: {
                label()
                    .padding(.horizontal, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(hovering ? Color.accentColor.opacity(0.08) : .clear))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.accentColor, lineWidth: isShown ? 2 : 0))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(L("Show in the source"))
        } else {
            label()
        }
    }
}
