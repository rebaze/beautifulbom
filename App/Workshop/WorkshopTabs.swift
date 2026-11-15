import BOMCore
import SwiftUI

enum WorkshopTab: String, CaseIterable, Identifiable, Sendable {
    case overview, composition, completeness, components, source
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .composition: "Composition"
        case .completeness: "Completeness"
        case .components: "Components"
        case .source: "Source"
        }
    }
}

/// A place Back and Forward return to.
enum Place: Hashable, Sendable {
    case tab(WorkshopTab)
    case component(Int)
    case node(NodeID)
}

/// The workshop view for the current tab (never the Source tab).
struct WorkshopContent: View {
    let model: DocumentModel
    let analysis: WorkshopAnalysis

    var body: some View {
        switch model.tab {
        case .overview:
            OverviewView(model: model, a: analysis)
        case .composition:
            CompositionView(model: model, a: analysis)
        case .completeness:
            CompletenessView(model: model, a: analysis)
        case .components:
            ComponentsView(model: model, a: analysis)
        case .source:
            EmptyView()
        }
    }
}

/// The tabs of a CycloneDX document, as text with a dark pill on the current one.
struct TabBar: View {
    let model: DocumentModel

    var body: some View {
        HStack(spacing: 4 * model.scale) {
            ForEach(WorkshopTab.allCases) { tab in
                let selected = model.tab == tab
                Button { model.show(tab: tab) } label: {
                    Text(tab.title)
                        .font(.system(size: 13 * model.scale, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color(nsColor: .textBackgroundColor) : .primary)
                        .padding(.horizontal, 11 * model.scale)
                        .padding(.vertical, 4 * model.scale)
                        .background(Capsule().fill(selected ? Color.primary : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .keyboardShortcut(KeyEquivalent(Character(String(WorkshopTab.allCases.firstIndex(of: tab)! + 1))), modifiers: .command)
                if tab == .components { Divider().frame(height: 16 * model.scale).padding(.horizontal, 6) }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7 * model.scale)
    }
}
