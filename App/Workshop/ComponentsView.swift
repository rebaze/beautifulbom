import BOMCore
import SwiftUI

/// Every component, searchable and filterable: "everything not MIT",
/// "everything without a hash", "everything six steps away". A row opens the
/// component page.
struct ComponentsView: View {
    @Bindable var model: DocumentModel
    let a: WorkshopAnalysis

    private var t: Typo { Typo(s: model.scale) }

    var body: some View {
        if let i = model.componentPage, a.bom.components.indices.contains(i) {
            ComponentPage(model: model, a: a, index: i)
        } else {
            list
        }
    }

    private var matches: [Int] { model.componentFilter.apply(a) }

    private var list: some View {
        let rows = matches
        return VStack(alignment: .leading, spacing: 0) {
            filterBar(count: rows.count)
            header
            Hairline()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows, id: \.self) { i in row(i) }
                }
                .padding(.horizontal, t.pad(28))
                .padding(.bottom, t.pad(20))
            }
        }
    }

    // MARK: Filters

    private func filterBar(count: Int) -> some View {
        HStack(spacing: t.pad(10)) {
            HStack(spacing: t.pad(6)) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("Search name, group or package URL"), text: $model.componentFilter.text)
                    .textFieldStyle(.plain)
                    .font(t.font(15))
            }
            .padding(.horizontal, t.pad(10))
            .padding(.vertical, t.pad(6))
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            .frame(maxWidth: t.pad(360))

            licenceMenu
            gapMenu
            depthMenu
            if !model.componentFilter.isEmpty {
                Button(L("Clear")) { model.componentFilter = ComponentFilter() }
                    .buttonStyle(.link)
            }
            Spacer()
            Text(L("%d of %d", count, a.bom.components.count))
                .font(t.font(14)).foregroundStyle(.secondary).monospacedDigit()
        }
        .font(t.font(13))
        .padding(.horizontal, t.pad(28))
        .padding(.vertical, t.pad(14))
    }

    private var licenceMenu: some View {
        let labels = a.composition.licenses.filter { !$0.unknown }.map(\.label)
        return Menu {
            Button(L("Any licence")) { model.componentFilter.licence = nil }
            Section(L("Licence is")) {
                ForEach(labels, id: \.self) { l in Button(l) { model.componentFilter.licence = .is(l) } }
            }
            Section(L("Licence is not")) {
                ForEach(labels, id: \.self) { l in Button(L("not %@", l)) { model.componentFilter.licence = .isNot(l) } }
            }
            Button(L("No licence stated")) { model.componentFilter.licence = .unknown }
        } label: {
            Text(licenceLabel)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var licenceLabel: String {
        switch model.componentFilter.licence {
        case nil: L("Any licence")
        case .is(let l)?: l
        case .isNot(let l)?: L("not %@", l)
        case .unknown?: L("No licence stated")
        }
    }

    private var gapMenu: some View {
        let rules = a.report.sections.first { $0.scope == .components }?.rows.filter { !$0.offenders.isEmpty }.map(\.rule) ?? []
        return Menu {
            Button(L("Any fields")) { model.componentFilter.missing = nil }
            Section(L("Missing or malformed")) {
                ForEach(rules, id: \.self) { r in
                    Button(CompletenessView.title(r.requirement)) { model.componentFilter.missing = r }
                }
            }
        } label: {
            Text(model.componentFilter.missing.map { L("missing: %@", CompletenessView.title($0.requirement)) } ?? L("Any fields"))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(rules.isEmpty)
    }

    private var depthMenu: some View {
        let depths = a.composition.depthHistogram.map { $0.keys.sorted() } ?? []
        return Menu {
            Button(L("Any depth")) { model.componentFilter.depth = nil }
            ForEach(depths, id: \.self) { d in Button(L("%d steps from the product", d)) { model.componentFilter.depth = d } }
        } label: {
            Text(model.componentFilter.depth.map { L("%d steps away", $0) } ?? L("Any depth"))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(depths.isEmpty)
    }

    // MARK: Rows

    private var header: some View {
        HStack(spacing: t.pad(12)) {
            Text(L("Component")).frame(maxWidth: .infinity, alignment: .leading)
            Text(L("Version")).frame(width: t.pad(130), alignment: .leading)
            Text(L("Licence")).frame(width: t.pad(170), alignment: .leading)
            Text(L("Depth")).frame(width: t.pad(60), alignment: .trailing)
            Text(L("TR gaps")).frame(width: t.pad(80), alignment: .trailing)
        }
        .font(t.font(12, .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, t.pad(36))
        .padding(.bottom, t.pad(6))
    }

    private func row(_ i: Int) -> some View {
        let c = a.bom.components[i]
        let gaps = a.gapCount(component: i)
        return Button { model.openComponent(i) } label: {
            HStack(spacing: t.pad(12)) {
                (Text(c.group.flatMap { $0.isEmpty ? nil : $0 + "/" } ?? "").foregroundStyle(.secondary)
                    + Text(c.name ?? c.path).fontWeight(.medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(c.version ?? "–").font(t.mono(13)).lineLimit(1).frame(width: t.pad(130), alignment: .leading)
                Text(c.licenses.map(\.label).joined(separator: ", ").nonEmpty ?? "–")
                    .lineLimit(1)
                    .foregroundStyle(c.licenses.isEmpty ? .red : .primary)
                    .frame(width: t.pad(170), alignment: .leading)
                Text(c.bomRef.flatMap { a.graph?.depth($0) }.map(String.init) ?? "–")
                    .monospacedDigit().frame(width: t.pad(60), alignment: .trailing)
                Group {
                    if gaps == 0 { Image(systemName: "checkmark").foregroundStyle(.green) } else { Text("\(gaps)").foregroundStyle(.red).monospacedDigit() }
                }
                .frame(width: t.pad(80), alignment: .trailing)
            }
            .font(t.font(14))
            .padding(.vertical, t.pad(8))
            .padding(.horizontal, t.pad(8))
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Hairline().opacity(0.5) }
        }
        .buttonStyle(RowButtonStyle())
    }
}

/// A row that highlights while hovered or pressed.
struct RowButtonStyle: ButtonStyle {
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(configuration.isPressed ? 0.14 : hovering ? 0.06 : 0)))
            .onHover { hovering = $0 }
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
