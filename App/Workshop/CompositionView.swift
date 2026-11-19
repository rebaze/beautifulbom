import BOMCore
import Charts
import SwiftUI

/// What the product is made of: who wrote it, under which licences, and how
/// deep the dependencies go. Every segment opens the matching components.
struct CompositionView: View {
    let model: DocumentModel
    let a: WorkshopAnalysis

    private var t: Typo { Typo(s: model.scale) }
    /// Packages only: files (Syft on an image) are counted apart.
    private var total: Int { a.composition.packageCount }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: t.pad(34)) {
                if let map = a.map {
                    section(title: L("How it hangs together"),
                            caption: L("The product in the middle. Each ring is one step further away: %d chosen directly, %d pulled in, up to %d steps deep.",
                                       a.composition.directCount ?? 0, a.composition.indirectCount ?? 0, map.deepest)) {
                        ProductMap(model: model, a: a, map: map, t: t)
                    }
                }
                vendors
                licences
                depth
            }
            .padding(t.pad(36))
            .frame(maxWidth: 1400 * t.s, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Vendors

    private var vendors: some View {
        let (named, others) = a.composition.top(a.composition.vendors, keep: 5)
        // The same colours as the map, so a vendor is one colour on the whole page.
        let top = VendorPalette.top(a)
        let segments = named.map { StackedBar.Segment(label: $0.unknown ? L("no vendor named") : $0.label, count: $0.count, filter: vendorFilter($0), isOthers: $0.unknown,
                                                      colour: top.firstIndex(of: $0.label).map { VendorPalette.colours[$0] }) }
            + (others.map { [StackedBar.Segment(label: Lp(a.composition.vendors.count - named.count, "1 other", "%d others"), count: $0.count, filter: nil, unknown: false, isOthers: true)] } ?? [])
        let ecosystems = a.composition.ecosystems.map { $0.unknown ? L("no package URL") : OverviewView.ecosystemName($0.label) + " " + "\($0.count)" }
        let vendorCount = a.composition.vendors.filter { !$0.unknown }.count
        let who = vendorCount == 0
            ? L("No component names a vendor (no group, no namespace in its package URL).")
            : vendorCount == 1 ? L("%d components from 1 vendor.", total) : L("%d components from %d vendors.", total, vendorCount)
        let files = a.composition.files.isEmpty ? "" : " " + L("%d files listed as components are not counted here.", a.composition.files.count)
        return section(title: L("Who wrote it"), caption: who + " " + L("Ecosystems: %@.", ecosystems.joined(separator: ", ")) + files) {
            StackedBar(segments: segments, total: total, t: t) { model.showComponents($0) }
        }
    }

    private func vendorFilter(_ s: Composition.Slice) -> ComponentFilter? {
        s.unknown ? nil : ComponentFilter(vendor: s.label)
    }

    /// Licence segments: the six largest, the rest as one "others" segment, so
    /// hundreds of free-text licence names cannot overflow the bar.
    @MainActor
    static func licenceSegments(_ a: WorkshopAnalysis) -> [StackedBar.Segment] {
        let (named, others) = a.composition.top(a.composition.licenses, keep: 6)
        // Coloured by family; within a family each further licence a little lighter.
        var seen: [LicenceFamily: Int] = [:]
        return named.map {
            let family = LicenceFamily.of($0.label)
            let k = seen[family, default: 0]; seen[family] = k + 1
            return StackedBar.Segment(label: $0.unknown ? L("no licence stated") : $0.label, count: $0.count,
                                      filter: ComponentFilter(licence: $0.unknown ? .unknown : .is($0.label)), unknown: $0.unknown,
                                      colour: FamilyStyle.colour(family).opacity(max(0.4, 1 - 0.22 * Double(k))))
        } + (others.map { [StackedBar.Segment(label: Lp(a.composition.licenses.count - named.count, "1 other", "%d others"), count: $0.count,
                                              filter: nil, isOthers: true)] } ?? [])
    }

    // MARK: Licences

    private var licences: some View {
        let slices = a.composition.licenses
        let segments = Self.licenceSegments(a)
        return section(title: L("Under which licences"), caption: licenceCaption(slices)) {
            StackedBar(segments: segments, total: segments.reduce(0) { $0 + $1.count }, t: t) { model.showComponents($0) }
            FamilyLegend(model: model, a: a, t: t)
        }
    }

    private func licenceCaption(_ slices: [Composition.Slice]) -> String {
        guard let major = slices.first(where: { !$0.unknown }) else { return L("No component states a licence.") }
        let rest = slices.filter { $0 != major }
        let restCount = Set(rest.flatMap(\.components)).subtracting(major.components).count
        if rest.isEmpty { return L("All %d components: %@.", total, major.label) }
        // Ten names at most: a Debian image states more than a hundred licence names.
        var list = rest.prefix(10).map { "\($0.unknown ? L("none stated") : $0.label) (\($0.count))" }.joined(separator: ", ")
        if rest.count > 10 { list += ", " + Lp(rest.count - 10, "1 more licence", "%d more licences") }
        return L("%d of %d under %@. The other %d: %@.", major.count, total, major.label, restCount, list)
    }

    // MARK: Depth

    @ViewBuilder
    private var depth: some View {
        if let histogram = a.composition.depthHistogram, let graph = a.graph, !histogram.isEmpty {
            let rows = histogram.sorted { $0.key < $1.key }
            let deepest = rows.last?.key ?? 0
            section(title: L("How deep it goes"),
                    caption: L("%d chosen directly, %d pulled in. The deepest is %d steps from the product.",
                               a.composition.directCount ?? 0, a.composition.indirectCount ?? 0, deepest)
                        + (graph.unreachable.isEmpty ? "" : " " + L("%d not reachable from the product.", graph.unreachable.count))) {
                Chart(rows, id: \.key) { row in
                    BarMark(x: .value(L("Steps from the product"), "\(row.key)"), y: .value(L("Components"), row.value))
                        .foregroundStyle(Color.accentColor.gradient)
                        .cornerRadius(4 * t.s)
                        .annotation(position: .top) {
                            Text("\(row.value)").font(t.font(13, .semibold)).monospacedDigit()
                        }
                }
                .chartXAxisLabel(L("steps from the product"), alignment: .center)
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks { _ in AxisValueLabel().font(t.font(13)) }
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onTapGesture { location in
                                let x = location.x - geo[proxy.plotFrame!].origin.x
                                if let label: String = proxy.value(atX: x), let d = Int(label) {
                                    model.showComponents(ComponentFilter(depth: d))
                                }
                            }
                    }
                }
                .frame(height: t.pad(220))
            }
        } else if case .notFromProduct(let linked) = a.composition.reach {
            section(title: L("How deep it goes"), caption: nil) {
                EvidenceButton(a.bom.tree.evidence(a.bom.root, "dependencies")) {
                    HStack(spacing: t.pad(10)) {
                        Image(systemName: "point.3.connected.trianglepath.dotted").foregroundStyle(.secondary)
                        Text(L("The dependency data links %d components among themselves, but no entry starts at the product, so it cannot say how deep anything is.", linked)).font(t.font(17))
                        Pill(text: L("no entry for the product"), kind: .gap, t: t)
                    }
                    .padding(.vertical, t.pad(4))
                }
            }
        } else if a.graph != nil, let subject = a.bom.subject {
            section(title: L("How deep it goes"), caption: nil) {
                EvidenceButton(a.bom.tree.evidence(subject.entry, "bom-ref")) {
                    HStack(spacing: t.pad(10)) {
                        Image(systemName: "point.3.connected.trianglepath.dotted").foregroundStyle(.secondary)
                        Text(L("The product has no bom-ref, so the dependency data cannot say how deep anything is.")).font(t.font(17))
                        Pill(text: L("no \"bom-ref\""), kind: .gap, t: t)
                    }
                    .padding(.vertical, t.pad(4))
                }
            }
        } else {
            section(title: L("How deep it goes"), caption: nil) {
                EvidenceButton(a.bom.tree.evidence(a.bom.root, "dependencies")) {
                    HStack(spacing: t.pad(10)) {
                        Image(systemName: "point.3.connected.trianglepath.dotted").foregroundStyle(.secondary)
                        Text(L("This SBOM has no dependency data.")).font(t.font(17))
                        Pill(text: L("no \"dependencies\""), kind: .gap, t: t)
                    }
                    .padding(.vertical, t.pad(4))
                }
            }
        }
    }

    // MARK: Layout

    private func section<C: View>(title: String, caption: String?, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: t.pad(10)) {
            Text(title).font(t.serif(26))
            if let caption {
                Text(caption).font(t.font(15)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
    }
}

/// One horizontal bar split into proportional segments, with a legend below.
/// The largest segment is the accent colour; the rest fade; unknown is hatched grey.
struct StackedBar: View {
    struct Segment: Identifiable {
        let label: String
        let count: Int
        let filter: ComponentFilter?
        var unknown = false
        var isOthers = false
        /// A fixed colour (vendors, as on the map); nil for the accent's fades.
        var colour: Color? = nil
        var id: String { label }
    }

    let segments: [Segment]
    let total: Int
    let t: Typo
    var height: CGFloat = 44
    var showLegend = true
    let open: (ComponentFilter) -> Void

    static let fades: [Double] = [1.0, 0.72, 0.52, 0.38, 0.27, 0.19, 0.14]

    private func colour(_ i: Int) -> Color {
        let s = segments[i]
        if s.unknown { return Color.red.opacity(0.35) }
        if s.isOthers { return Color.secondary.opacity(0.22) }
        if let c = s.colour { return c }
        return Color.accentColor.opacity(Self.fades[min(i, Self.fades.count - 1)])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: t.pad(12)) {
            GeometryReader { geo in
                let gap: CGFloat = 2
                let usable = geo.size.width - gap * CGFloat(max(0, segments.count - 1))
                HStack(spacing: gap) {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { i, s in
                        Button { if let f = s.filter { open(f) } } label: {
                            Rectangle()
                                .fill(colour(i))
                                .frame(width: max(3, usable * CGFloat(s.count) / CGFloat(max(1, total))))
                                .overlay(alignment: .leading) {
                                    if usable * CGFloat(s.count) / CGFloat(max(1, total)) > 90 * t.s, i == 0 {
                                        Text("\(s.label) \(s.count)")
                                            .font(t.font(13, .semibold))
                                            // Grey and pale red segments are light: dark text there.
                                            .foregroundStyle(s.unknown || s.isOthers ? AnyShapeStyle(.primary.opacity(0.8)) : AnyShapeStyle(.white))
                                            .padding(.leading, t.pad(10))
                                            .lineLimit(1)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .help("\(s.label): \(s.count)")
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8 * t.s, style: .continuous))
                .growIn()
            }
            .frame(height: height * t.s)
            if showLegend {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190 * t.s), alignment: .leading)], alignment: .leading, spacing: t.pad(6)) {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { i, s in
                        Button { if let f = s.filter { open(f) } } label: {
                            HStack(spacing: t.pad(8)) {
                                RoundedRectangle(cornerRadius: 3).fill(colour(i)).frame(width: t.pad(12), height: t.pad(12))
                                Text(s.label).font(t.font(14)).lineLimit(1)
                                Text("\(s.count)").font(t.font(14)).foregroundStyle(.secondary).monospacedDigit()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(s.filter == nil)
                    }
                }
            }
        }
    }
}

/// The licence families with their counts; each opens the matching components.
struct FamilyLegend: View {
    let model: DocumentModel
    let a: WorkshopAnalysis
    let t: Typo

    var body: some View {
        HStack(spacing: t.pad(8)) {
            Text(L("Families:")).font(t.font(13)).foregroundStyle(.secondary)
            ForEach(FamilyStyle.legend(a.composition), id: \.family) { f, n in
                Button { model.showComponents(ComponentFilter(family: f)) } label: {
                    Chip(text: "\(FamilyStyle.name(f)) \(n)", colour: FamilyStyle.colour(f), t: t)
                        .opacity(n == 0 ? 0.55 : 1)
                }
                .buttonStyle(.plain)
                .disabled(n == 0)
            }
        }
        .help(L("Families are derived from the SPDX identifiers; the SBOM does not state them."))
    }
}
