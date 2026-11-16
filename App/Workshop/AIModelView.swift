import BOMCore
import SwiftUI

/// An AI bill of materials: the model, its family tree (base models and training data) and what
/// the file leaves out. Every node and gap opens its source. Presence and form only.
struct AIModelView: View {
    let model: DocumentModel
    let a: WorkshopAnalysis
    let ai: AIBOMAnalysis

    private var t: Typo { Typo(s: model.scale) }
    private var m: AIBOMAnalysis.Model { ai.model }
    private var tree: JSONTree { a.bom.tree }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: t.pad(22)) {
                header
                facts
                // The list of gaps beside the tree when there is room, below it otherwise (presentation size).
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: t.pad(32)) {
                        FamilyTree(model: model, ai: ai, t: t)
                        Spacer(minLength: 0)
                        if !ai.gaps.isEmpty { gaps.frame(width: 380 * t.s) }
                    }
                    VStack(alignment: .leading, spacing: t.pad(22)) {
                        FamilyTree(model: model, ai: ai, t: t)
                        if !ai.gaps.isEmpty { gaps.frame(maxWidth: 900 * t.s, alignment: .leading) }
                    }
                }
                if !m.limitations.isEmpty || !m.useCases.isEmpty { considerations }
            }
            .padding(t.pad(36))
            .frame(maxWidth: 1500 * t.s, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: t.pad(6)) {
            EvidenceButton(.located(a.bom.specVersion.node)) {
                Eyebrow(text: ([L("AI bill of materials · CycloneDX %@", a.bom.specVersion.value)]
                               + a.bom.tools.prefix(1).compactMap { tool in tool.name.map { L("written by %@", [$0, tool.version].compactMap { $0 }.joined(separator: " ")) } })
                    .joined(separator: " · "), t: t)
            }
            EvidenceButton(.located(m.component.entry)) {
                Text(m.component.name ?? m.component.displayName).font(t.serif(42)).lineLimit(2)
            }
            Text(subtitle).font(t.font(17)).foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let task = m.task { parts.append(task) }
        if let arch = m.architecture { parts.append(L("%@ architecture", arch)) }
        if let base = m.ancestors.first { parts.append(L("fine-tuned from %@", base.component.displayName)) }
        if let group = m.component.group { parts.append(L("by %@", group)) }
        return parts.joined(separator: " · ")
    }

    // MARK: Facts

    private var facts: some View {
        HStack(spacing: t.pad(12)) {
            if let p = m.parameters { fact(Self.compact(Double(p)), L("parameters")) }
            if let c = m.contextLength { fact(c.formatted(.number.locale(L10n.locale)), L("tokens of context")) }
            let withLicence = m.datasets.filter { $0.component.map { !$0.licenses.isEmpty } ?? false }.count
            fact("\(m.datasets.count)", m.datasets.isEmpty ? L("training datasets stated")
                 : withLicence == m.datasets.count ? L("training datasets, each with a licence")
                 : L("training datasets, %d with a licence", withLicence))
            if let f = m.fileSize { fact(Self.bytes(Double(f)), L("model files")) }
        }
    }

    private func fact(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: t.pad(2)) {
            Text(value).font(t.serif(30)).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(t.font(13)).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(t)
    }

    /// File sizes in decimal units, in the app's language: 28967059598 → "29 GB".
    static func bytes(_ n: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = n, i = 0
        while v >= 1000, i < units.count - 1 { v /= 1000; i += 1 }
        return v.formatted(.number.precision(.fractionLength(v < 10 && i > 0 ? 1 : 0)).locale(L10n.locale)) + " " + units[i]
    }

    /// 7241732096 → "7.2 B" (billions and millions only; smaller numbers as they are).
    static func compact(_ n: Double) -> String {
        if n >= 1e9 { return (n / 1e9).formatted(.number.precision(.fractionLength(1)).locale(L10n.locale)) + " B" }
        if n >= 1e6 { return (n / 1e6).formatted(.number.precision(.fractionLength(0)).locale(L10n.locale)) + " M" }
        return Int(n).formatted(.number.locale(L10n.locale))
    }

    // MARK: Gaps

    private var gaps: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: L("Left out"), t: t).padding(.bottom, t.pad(6))
            ForEach(Array(ai.gaps.enumerated()), id: \.offset) { _, gap in
                EvidenceButton(gap.evidence) {
                    HStack(alignment: .firstTextBaseline, spacing: t.pad(10)) {
                        Image(systemName: "xmark").font(t.font(12, .bold)).foregroundStyle(.red)
                        Text(Self.text(gap.kind)).font(t.font(14)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, t.pad(8))
                }
                Hairline()
            }
            Text(L("Presence and form only, as in the SBOM views.")).font(t.font(12)).foregroundStyle(.secondary).padding(.top, t.pad(8))
        }
        .padding(.top, t.pad(8))
    }

    static func text(_ k: AIBOMAnalysis.Gap.Kind) -> String {
        switch k {
        case .subjectIsNotTheModel(let n): L("The BOM describes \"%@\", not the model", n)
        case .noLicence: L("No licence for the model")
        case .noAncestors: L("No base model (pedigree.ancestors)")
        case .noDatasets: L("No training data stated")
        case .datasetNamedOnly(let n): L("%@: named only, no licence or version", n)
        case .noHash: L("No hash of the model files")
        case .ancestorWithoutDatasets(let n): L("%@ states no training data", n)
        }
    }

    // MARK: Considerations

    private var considerations: some View {
        VStack(alignment: .leading, spacing: t.pad(10)) {
            Text(L("What the model card says")).font(t.serif(22))
            if !m.useCases.isEmpty {
                HStack(spacing: t.pad(8)) {
                    Text(L("Intended use:")).font(t.font(14)).foregroundStyle(.secondary)
                    ForEach(m.useCases, id: \.self) { Chip(text: $0, t: t) }
                }
            }
            ForEach(Array(m.limitations.enumerated()), id: \.offset) { _, text in
                HStack(alignment: .top, spacing: t.pad(10)) {
                    Rectangle().fill(Color.orange.opacity(0.6)).frame(width: 3)
                    Text(text).font(t.font(15)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: 1000 * t.s, alignment: .leading)
    }
}

/// Columns from the oldest base models on the left to the model on the right, datasets beside the
/// base models; arrows from each node to the one it went into.
private struct FamilyTree: View {
    let model: DocumentModel
    let ai: AIBOMAnalysis
    let t: Typo

    /// A node on the tree and the node it feeds into.
    struct Node: Identifiable {
        enum Kind: Equatable { case model, base, dataset, missingBase, moreDatasets(Int) }
        let id: String
        let kind: Kind
        let model: AIBOMAnalysis.Model?
        let dataset: AIBOMAnalysis.Dataset?
        let feeds: String?
    }

    static let maxDatasets = 6

    /// Columns, oldest generation first; the model is the last column.
    var columns: [[Node]] {
        var cols: [[Node]] = []
        func add(_ m: AIBOMAnalysis.Model, id: String, generation: Int, feeds: String?) {
            while cols.count <= generation { cols.append([]) }
            cols[generation].append(Node(id: id, kind: generation == 0 ? .model : .base, model: m, dataset: nil, feeds: feeds))
            for (i, a) in m.ancestors.enumerated() { add(a, id: "\(id).a\(i)", generation: generation + 1, feeds: id) }
        }
        add(ai.model, id: "m", generation: 0, feeds: nil)
        while cols.count < 2 { cols.append([]) }
        if ai.model.ancestors.isEmpty {
            cols[1].append(Node(id: "missing", kind: .missingBase, model: nil, dataset: nil, feeds: "m"))
        }
        let ds = ai.model.datasets
        let shown = ds.count > Self.maxDatasets ? Array(ds.prefix(Self.maxDatasets - 1)) : ds
        for (i, d) in shown.enumerated() { cols[1].append(Node(id: "d\(i)", kind: .dataset, model: nil, dataset: d, feeds: "m")) }
        if shown.count < ds.count { cols[1].append(Node(id: "dmore", kind: .moreDatasets(ds.count - shown.count), model: nil, dataset: nil, feeds: "m")) }
        return cols.reversed()
    }

    var body: some View {
        let cols = columns
        HStack(alignment: .center, spacing: t.pad(90)) {
            ForEach(Array(cols.enumerated()), id: \.offset) { _, col in
                VStack(alignment: .leading, spacing: t.pad(22)) {
                    ForEach(col) { node in
                        card(node).anchorPreference(key: NodeBounds.self, value: .bounds) { [node.id: $0] }
                    }
                }
            }
        }
        .padding(.vertical, t.pad(12))
        .overlayPreferenceValue(NodeBounds.self) { bounds in
            GeometryReader { geo in
                ForEach(cols.flatMap { $0 }.filter { $0.feeds != nil }) { node in
                    if let from = bounds[node.id], let to = bounds[node.feeds!] {
                        edge(from: geo[from], to: geo[to], node: node)
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .modifier(Bloom())
    }

    private func edge(from a: CGRect, to b: CGRect, node: Node) -> some View {
        let start = CGPoint(x: a.maxX + 4, y: a.midY)
        let end = CGPoint(x: b.minX - 6, y: b.midY)
        let dx = (end.x - start.x) * 0.5
        var p = Path()
        p.move(to: start)
        p.addCurve(to: end, control1: CGPoint(x: start.x + dx, y: start.y), control2: CGPoint(x: end.x - dx, y: end.y))
        var head = Path()
        head.move(to: end)
        head.addLine(to: CGPoint(x: end.x - 9, y: end.y - 5))
        head.addLine(to: CGPoint(x: end.x - 9, y: end.y + 5))
        head.closeSubpath()
        let missing = if case .missingBase = node.kind { true } else { false }
        let colour: Color = missing ? .red.opacity(0.7) : .secondary.opacity(0.7)
        return ZStack {
            p.stroke(colour, style: StrokeStyle(lineWidth: 1.6, dash: missing ? [6, 5] : []))
            head.fill(colour)
        }
    }

    // MARK: Cards

    @ViewBuilder
    private func card(_ node: Node) -> some View {
        switch node.kind {
        case .model, .base:
            let mm = node.model!
            EvidenceButton(.located(mm.component.entry)) {
                box(main: node.kind == .model) {
                    kind(node.kind == .model ? L("This model") : L("Base model"), "cube.fill", .blue)
                    name(mm.component.group, mm.component.name ?? mm.component.displayName, size: node.kind == .model ? 26 : 20)
                    chips(mm.component.licenses.map(\.label), extra: {
                        if let task = mm.task, node.kind == .model { Chip(text: task, t: t) }
                        if node.kind == .base, mm.datasets.isEmpty { Pill(text: L("no training data stated"), kind: .gap, t: t) }
                        if node.kind == .base, !mm.datasets.isEmpty { Chip(text: L("%d datasets", mm.datasets.count), t: t) }
                    })
                }
            }
        case .dataset:
            let d = node.dataset!
            EvidenceButton(.located(d.component?.entry ?? d.node)) {
                box(main: false) {
                    kind(d.component == nil ? L("Dataset, named only") : L("Dataset"), "tablecells.fill", .teal)
                    let parts = d.name.split(separator: "/", maxSplits: 1).map(String.init)
                    name(parts.count == 2 ? parts[0] : nil, parts.last ?? d.name, size: 19)
                    if let c = d.component {
                        chips(c.licenses.map(\.label), extra: { if c.licenses.isEmpty { Pill(text: L("no licence"), kind: .gap, t: t) } })
                    } else {
                        HStack(spacing: t.pad(6)) { Pill(text: L("no licence"), kind: .gap, t: t); Pill(text: L("not a component"), kind: .gap, t: t) }
                    }
                }
            }
        case .missingBase:
            let evidence = ai.gaps.first { $0.kind == .noAncestors }?.evidence
            EvidenceButton(evidence) {
                VStack(alignment: .leading, spacing: t.pad(4)) {
                    kind(L("Base model"), "cube", .red)
                    Text(L("not in this AIBOM")).font(t.serif(20)).foregroundStyle(.red)
                }
                .frame(width: 300 * t.s, alignment: .leading)
                .padding(t.pad(14))
                .background(RoundedRectangle(cornerRadius: 16 * t.s).fill(Color.red.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 16 * t.s).strokeBorder(Color.red.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
            }
        case .moreDatasets(let n):
            box(main: false) {
                Text(L("%d more datasets", n)).font(t.font(15)).foregroundStyle(.secondary)
            }
        }
    }

    /// The publisher small, the name large: "HuggingFaceH4" over "ultrafeedback_binarized".
    private func name(_ group: String?, _ name: String, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let group, !group.isEmpty { Text(group).font(t.font(12)).foregroundStyle(.secondary) }
            Text(name).font(t.serif(size)).lineLimit(2).minimumScaleFactor(0.8)
        }
    }

    private func kind(_ text: String, _ symbol: String, _ colour: Color) -> some View {
        HStack(spacing: t.pad(6)) {
            Image(systemName: symbol).foregroundStyle(colour)
            Text(text.uppercased()).tracking(0.8 * t.s)
        }
        .font(t.font(11, .medium))
        .foregroundStyle(.secondary)
    }

    private func chips<E: View>(_ licences: [String], @ViewBuilder extra: () -> E) -> some View {
        HStack(spacing: t.pad(6)) {
            ForEach(licences, id: \.self) { Chip(text: $0, colour: FamilyStyle.colour(LicenceFamily.of($0)), t: t) }
            extra()
        }
    }

    private func box<C: View>(main: Bool, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: t.pad(5)) { content() }
            .frame(width: (main ? 340 : 300) * t.s, alignment: .leading)
            .padding(t.pad(14))
            .background(RoundedRectangle(cornerRadius: 16 * t.s).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 16 * t.s).strokeBorder(main ? Color.primary : Color.primary.opacity(0.12), lineWidth: main ? 2 : 1))
            .shadow(color: .black.opacity(main ? 0.12 : 0.05), radius: main ? 14 : 6, y: main ? 6 : 2)
    }
}

private struct NodeBounds: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}
