import BOMCore
import SwiftUI

/// One component: who it is, who made it, under which licence, how it can be
/// verified, what the TR misses, and why it is in the product at all.
struct ComponentPage: View {
    let model: DocumentModel
    let a: WorkshopAnalysis
    let index: Int

    private var t: Typo { Typo(s: model.scale) }
    private var c: Component { a.bom.components[index] }
    private var tree: JSONTree { a.bom.tree }
    private func ev(_ key: String) -> Evidence? { c.node.map { tree.evidence($0, a.bom.key(key)) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: t.pad(26)) {
                Button { model.show(tab: .components) } label: {
                    Label(L("All components"), systemImage: "chevron.left").font(t.font(13))
                }
                .buttonStyle(.link)
                header
                whyHere
                Grid(alignment: .topLeading, horizontalSpacing: t.pad(32), verticalSpacing: t.pad(26)) {
                    GridRow {
                        identity
                        people
                    }
                    GridRow {
                        licences
                        integrity
                    }
                    GridRow {
                        // SPDX is not checked against the TR (docs/design-spdx.md): no gaps card.
                        if a.profile != nil { gaps }
                        references
                    }
                }
                if !c.properties.isEmpty || !c.unknownKeys.isEmpty { more }
            }
            .padding(t.pad(36))
            .frame(maxWidth: 1400 * t.s, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: t.pad(6)) {
            Eyebrow(text: [c.type, c.packageURL.map { OverviewView.ecosystemName($0.type) }].compactMap { $0 }.joined(separator: " · "), t: t)
            HStack(alignment: .firstTextBaseline, spacing: t.pad(14)) {
                EvidenceButton(.located(c.entry)) {
                    Text(c.displayName).font(t.serif(36)).lineLimit(2)
                }
                if let v = c.version {
                    EvidenceButton(ev("version")) { Text(v).font(t.mono(22)).foregroundStyle(.secondary) }
                }
            }
            if let d = c.description {
                EvidenceButton(ev("description")) {
                    Text(d).font(t.font(15)).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
            }
        }
    }

    // MARK: Why is it here?

    private var whyHere: some View {
        VStack(alignment: .leading, spacing: t.pad(10)) {
            sectionTitle(L("Why is it here?"))
            if let graph = a.graph, let ref = c.bomRef, let path = graph.path(to: ref) {
                FlowLayout(spacing: t.pad(8)) {
                    ForEach(Array(path.enumerated()), id: \.offset) { step, r in
                        HStack(spacing: t.pad(8)) {
                            if step > 0 { Image(systemName: "arrow.right").foregroundStyle(.tertiary) }
                            pathNode(r, isLast: step == path.count - 1, graph: graph)
                        }
                    }
                }
                Text(path.count == 2 ? L("Chosen directly by the product.") : L("Pulled in, %d steps from the product.", path.count - 1))
                    .font(t.font(13)).foregroundStyle(.secondary)
                let users = graph.usedBy(ref)
                if !users.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: t.pad(8)) {
                        Text(L("Used by")).font(t.font(13)).foregroundStyle(.secondary)
                        FlowLayout(spacing: t.pad(6)) {
                            ForEach(users, id: \.self) { u in pathNode(u, isLast: false, graph: graph, compact: true) }
                        }
                    }
                }
            } else if a.graph == nil {
                EvidenceButton(tree.evidence(a.bom.root, a.bom.rootKey("dependencies"))) {
                    Text(L("This SBOM has no dependency data, so it cannot say why this component is here.")).font(t.font(15))
                }
            } else {
                Text(L("Not reachable from the product in the dependency data.")).font(t.font(15)).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(t)
    }

    private func pathNode(_ ref: String, isLast: Bool, graph: DependencyGraph, compact: Bool = false) -> some View {
        let target = ref == c.bomRef ? index : a.componentIndex(bomRef: ref)
        let comp = target.map { a.bom.components[$0] } ?? (a.bom.subject?.bomRef == ref ? a.bom.subject : nil)
        let label = comp.map { [$0.displayName, $0.version].compactMap { $0 }.joined(separator: " ") } ?? ref
        return Button {
            if let target, target != index { model.openComponent(target) } else if comp?.isSubject == true { model.show(tab: .overview) }
        } label: {
            Text(label)
                .font(t.font(compact ? 13 : 15, isLast ? .semibold : .regular))
                .padding(.horizontal, t.pad(compact ? 8 : 10))
                .padding(.vertical, t.pad(compact ? 3 : 5))
                .background(Capsule().fill(isLast ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .help(ref)
    }

    // MARK: Sections

    private var identity: some View {
        card(L("Identity")) {
            if let p = c.packageURL {
                fact(L("Package URL")) { EvidenceButton(ev("purl")) { Text(c.purl ?? "").font(t.mono(13)).textSelection(.enabled) } }
                fact(L("Ecosystem")) { Text(OverviewView.ecosystemName(p.type)) }
                if let ns = p.namespace { fact(L("Namespace")) { Text(ns) } }
                fact(L("Name")) { Text(p.name) }
                if let v = p.version { fact(L("Version")) { Text(v).font(t.mono(13)) } }
                ForEach(p.qualifiers.sorted { $0.key < $1.key }, id: \.key) { q in fact(q.key) { Text(q.value) } }
            } else {
                fact(L("Package URL")) { EvidenceButton(ev("purl")) { Pill(text: L("none"), kind: .gap, t: t) } }
            }
            if let r = c.bomRef { fact("bom-ref") { EvidenceButton(ev("bom-ref")) { Text(r).font(t.mono(12)).lineLimit(2) } } }
        }
    }

    private var people: some View {
        card(L("Who")) {
            fact(L("Author")) { EvidenceButton(ev(c.author != nil && tree.member(c.node!, "author") != nil ? "author" : "authors")) { value(c.author) } }
            fact(L("Supplier")) { EvidenceButton(ev("supplier")) { value(c.supplierName) } }
            fact(L("Manufacturer")) { EvidenceButton(ev("manufacturer")) { value(c.manufacturerName) } }
        }
    }

    private var licences: some View {
        card(L("Licence")) {
            if c.licenses.isEmpty {
                EvidenceButton(ev("licenses")) { Pill(text: L("none stated"), kind: .gap, t: t) }
            }
            ForEach(c.licenses, id: \.node) { l in
                EvidenceButton(.located(l.node)) {
                    HStack(spacing: t.pad(8)) {
                        Text(l.label).font(t.font(15, .medium))
                        Pill(text: l.acknowledgement ?? L("not marked declared or concluded"), kind: l.acknowledgement == "concluded" ? .ok : .neutral, t: t)
                    }
                }
            }
        }
    }

    private var integrity: some View {
        card(L("Integrity")) {
            let refHashes = c.externalReferences.flatMap { r in r.hashes.map { (r, $0) } }
            if c.hashes.isEmpty && refHashes.isEmpty {
                EvidenceButton(ev("hashes")) { Pill(text: L("no hash"), kind: .gap, t: t) }
            }
            ForEach(c.hashes, id: \.node) { h in hashRow(h, on: L("component")) }
            ForEach(refHashes, id: \.1.node) { r, h in hashRow(h, on: r.type ?? L("reference")) }
        }
    }

    private func hashRow(_ h: BOMCore.Hash, on: String) -> some View {
        EvidenceButton(.located(h.node)) {
            HStack(spacing: t.pad(8)) {
                Text(h.alg ?? "?").font(t.font(13, .semibold))
                Text(Self.shortHash(h.content)).font(t.mono(12)).foregroundStyle(.secondary)
                Text(L("on %@", on)).font(t.font(12)).foregroundStyle(.secondary)
            }
        }
    }

    static func shortHash(_ s: String?) -> String {
        guard let s, s.count > 20 else { return s ?? "" }
        return s.prefix(10) + "…" + s.suffix(8)
    }

    private var gaps: some View {
        let offenders = a.offenders(component: index)
        return card(L("TR-03183-2 gaps")) {
            if offenders.isEmpty {
                Pill(text: L("all fields present in the required form"), kind: .ok, t: t)
            }
            ForEach(offenders, id: \.self) { o in
                EvidenceButton(o.evidence) {
                    HStack(spacing: t.pad(8)) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        Text(CompletenessView.title(o.rule.requirement)).font(t.font(14))
                        if let d = o.detail { Text(d).font(t.font(12)).foregroundStyle(.secondary).lineLimit(1) }
                    }
                }
            }
        }
    }

    private var references: some View {
        card(L("External references")) {
            if c.externalReferences.isEmpty { Text(L("none")).foregroundStyle(.secondary).font(t.font(14)) }
            ForEach(c.externalReferences, id: \.node) { r in
                EvidenceButton(.located(r.node)) {
                    HStack(alignment: .firstTextBaseline, spacing: t.pad(8)) {
                        Text(r.type ?? "?").font(t.font(13, .semibold)).frame(width: t.pad(110), alignment: .leading)
                        Text(r.url ?? "").font(t.mono(12)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
            }
        }
    }

    private var more: some View {
        card(L("Properties and other fields")) {
            ForEach(c.properties, id: \.node) { p in
                EvidenceButton(.located(p.node)) {
                    HStack(spacing: t.pad(8)) {
                        Text(p.name ?? "?").font(t.mono(12, .semibold))
                        Text(p.value ?? "").font(t.mono(12)).foregroundStyle(.secondary)
                    }
                }
            }
            if !c.unknownKeys.isEmpty {
                fact(L("Not in CycloneDX 1.6")) {
                    Text(c.unknownKeys.joined(separator: ", ")).font(t.mono(12))
                }
            }
        }
    }

    // MARK: Building blocks

    private func sectionTitle(_ s: String) -> some View {
        Text(s).font(t.serif(20))
    }

    private func card<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: t.pad(8)) {
            Eyebrow(text: title, t: t)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func fact<V: View>(_ label: String, @ViewBuilder _ value: () -> V) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: t.pad(10)) {
            Text(label).font(t.font(13)).foregroundStyle(.secondary).frame(width: t.pad(110), alignment: .leading)
            value().font(t.font(14))
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func value(_ s: String?) -> some View {
        if let s { Text(s) } else { Text(L("not stated")).foregroundStyle(.secondary) }
    }
}

/// Lays children out left to right, wrapping to new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += line + spacing; line = 0 }
            x += s.width + spacing
            line = max(line, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            line = max(line, s.height)
        }
    }
}
