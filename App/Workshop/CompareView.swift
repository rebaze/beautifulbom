import BOMCore
import SwiftUI

/// Two SBOMs side by side (File › Compare With…): release against release, or two tools on the
/// same source. A sentence answers the question, one bar shows the proportions, a table what each
/// file states, then the lists. Rows from this window's file (A) open its component page.
struct CompareView: View {
    let model: DocumentModel
    let c: BOMComparison

    private var t: Typo { Typo(s: model.scale) }
    private static let colourA = Color(red: 0.23, green: 0.44, blue: 0.77)
    private static let colourB = Color(red: 0.77, green: 0.44, blue: 0.16)
    private static let colourChanged = Color(red: 0.85, green: 0.64, blue: 0.0)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: t.pad(22)) {
                header
                files
                proportions
                factsTable
                changed
                HStack(alignment: .top, spacing: t.pad(36)) {
                    only(.onlyA).frame(maxWidth: .infinity, alignment: .leading)
                    only(.onlyB).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(t.pad(36))
            .frame(maxWidth: 1400 * t.s, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Names

    /// What to call each side: the tools when they differ, else the product versions, else A and B.
    private var names: (String, String) {
        let ta = c.docA.tools.first?.name, tb = c.docB.tools.first?.name
        if let ta, let tb, ta.lowercased() != tb.lowercased() { return (ta, tb) }
        let va = c.docA.subject?.version, vb = c.docB.subject?.version
        if let va, let vb, va != vb { return (va, vb) }
        return ("A", "B")
    }

    private var sameTool: Bool {
        let ta = c.docA.tools.first?.name?.lowercased(), tb = c.docB.tools.first?.name?.lowercased()
        return ta != nil && ta == tb
    }

    // MARK: Header

    private var header: some View {
        let n = c.counts
        let (a, b) = names
        let both = n.same + n.changed
        var first = Lp(both, "1 package in both.", "%d packages in both.")
        first += " " + (n.onlyA + n.onlyB == 0 ? L("None only on one side.") : L("%d only in %@, %d only in %@.", n.onlyA, a, n.onlyB, b))
        var second: [String] = []
        if n.changed == 0 {
            second.append(L("No package has a different version."))
        } else {
            let up = c.rows.filter { $0.kind == .changed && $0.direction == .up }.count
            let down = c.rows.filter { $0.kind == .changed && $0.direction == .down }.count
            second.append(Lp(n.changed, "1 has a different version", "%d have a different version")
                          + ": " + L("%d newer in %@, %d older.", up, b, down))
        }
        for (kind, side, doc) in [(BOMComparison.Kind.onlyA, a, c.docA), (.onlyB, b, c.docB)] {
            let rows = c.rows.filter { $0.kind == kind }
            let optional = rows.filter { r in
                let i = kind == .onlyA ? r.indexA : r.indexB
                return i.map { ["optional", "excluded"].contains(doc.components[$0].scope ?? "") } ?? false
            }.count
            if optional > 0 {
                second.append(L("Of the %d only in %@, %d are marked optional or excluded.", rows.count, side, optional))
            }
        }
        let licences = c.rows.filter(\.licenceDiffers).count
        if licences > 0 { second.append(Lp(licences, "1 package states other licences on each side.", "%d packages state other licences on each side.")) }
        return VStack(alignment: .leading, spacing: t.pad(8)) {
            Eyebrow(text: sameTool ? L("Two SBOMs side by side · one tool, two files") : L("Two SBOMs side by side"), t: t)
            Text(first).font(t.serif(34)).fixedSize(horizontal: false, vertical: true)
            Text(second.joined(separator: " ")).font(t.font(16)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: The two files

    private var files: some View {
        HStack(alignment: .top, spacing: t.pad(14)) {
            fileCard("A", Self.colourA, model.fileName, c.docA, c.a)
            fileCard("B", Self.colourB, model.comparedFileName, c.docB, c.b)
        }
    }

    private func fileCard(_ tag: String, _ colour: Color, _ name: String?, _ doc: BOMCore.BOMDocument, _ f: BOMComparison.Facts) -> some View {
        var parts: [String] = []
        if let tool = doc.tools.first { parts.append([tool.name, tool.version].compactMap { $0 }.joined(separator: " ")) }
        parts.append("\(doc.format == .spdx ? "SPDX" : "CycloneDX") \(doc.specVersion.value)")
        if let p = doc.subject, let title = ProductTitle(p.name).title { parts.append([title, p.version].compactMap { $0 }.joined(separator: " ")) }
        parts.append(Lp(f.packages, "1 package", "%d packages"))
        return HStack(alignment: .top, spacing: t.pad(10)) {
            Text(tag).font(t.font(12, .bold)).foregroundStyle(.white)
                .frame(width: t.pad(20), height: t.pad(20))
                .background(RoundedRectangle(cornerRadius: 5 * t.s).fill(colour))
            VStack(alignment: .leading, spacing: t.pad(4)) {
                Text(name ?? L("Unnamed file")).font(t.serif(20)).lineLimit(1)
                Text(parts.joined(separator: " · ")).font(t.font(13)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(t)
    }

    // MARK: Proportions

    private var proportions: some View {
        let n = c.counts
        let (a, b) = names
        let parts: [(String, Int, Color)] = [
            (L("only in %@", a), n.onlyA, Self.colourA),
            (L("in both, same version"), n.same, Color.secondary.opacity(0.55)),
            (L("different version"), n.changed, Self.colourChanged),
            (L("only in %@", b), n.onlyB, Self.colourB),
        ]
        let total = max(1, parts.reduce(0) { $0 + $1.1 })
        return VStack(alignment: .leading, spacing: t.pad(10)) {
            GeometryReader { geo in
                let shown = parts.filter { $0.1 > 0 }
                let gap: CGFloat = 2
                let usable = geo.size.width - gap * CGFloat(max(0, shown.count - 1))
                HStack(spacing: gap) {
                    ForEach(shown, id: \.0) { p in
                        let w = max(3, usable * CGFloat(p.1) / CGFloat(total))
                        Rectangle().fill(p.2).frame(width: w)
                            .overlay(alignment: .leading) {
                                if w > 110 * t.s {
                                    Text(verbatim: "\(p.0) \(p.1.formatted(.number.locale(L10n.locale)))")
                                        .font(t.font(13, .semibold)).foregroundStyle(.white).padding(.leading, t.pad(10)).lineLimit(1)
                                }
                            }
                            .help("\(p.0): \(p.1)")
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8 * t.s, style: .continuous))
                .growIn()
            }
            .frame(height: 44 * t.s)
            HStack(spacing: t.pad(22)) {
                ForEach(parts, id: \.0) { p in
                    HStack(spacing: t.pad(6)) {
                        RoundedRectangle(cornerRadius: 3).fill(p.2).frame(width: t.pad(11), height: t.pad(11))
                        Text(p.0).font(t.font(13))
                        Text("\(p.1)").font(t.font(13)).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
        }
    }

    // MARK: What each file states

    private var factsTable: some View {
        let (a, b) = names
        let rows: [(String, Int?, Int?)] = [
            (L("Package URL"), c.a.withPurl, c.b.withPurl),
            (L("Version"), c.a.withVersion, c.b.withVersion),
            (L("Licence"), c.a.withLicence, c.b.withLicence),
            (L("Hash"), c.a.withHash, c.b.withHash),
            (L("Supplier"), c.a.withSupplier, c.b.withSupplier),
        ]
        return VStack(alignment: .leading, spacing: t.pad(10)) {
            Text(L("What each file states")).font(t.serif(24))
            Grid(alignment: .leading, horizontalSpacing: t.pad(18), verticalSpacing: t.pad(9)) {
                GridRow {
                    Color.clear.frame(width: 1, height: 1)
                    Text(a == "A" ? "A" : L("A · %@", a)).font(t.font(12, .medium)).foregroundStyle(.secondary)
                    Text(b == "B" ? "B" : L("B · %@", b)).font(t.font(12, .medium)).foregroundStyle(.secondary)
                }
                GridRow {
                    Text(L("Packages")).font(t.font(15))
                    Text("\(c.a.packages)").font(t.font(15)).monospacedDigit()
                    Text("\(c.b.packages)").font(t.font(15)).monospacedDigit()
                }
                if c.a.files + c.b.files > 0 {
                    GridRow {
                        Text(L("Files listed as components")).font(t.font(15))
                        Text("\(c.a.files)").font(t.font(15)).monospacedDigit()
                        Text("\(c.b.files)").font(t.font(15)).monospacedDigit()
                    }
                }
                ForEach(rows, id: \.0) { r in
                    GridRow {
                        Text(r.0).font(t.font(15))
                        coverage(r.1 ?? 0, c.a.packages)
                        coverage(r.2 ?? 0, c.b.packages)
                    }
                }
                GridRow {
                    Text(L("Dependencies")).font(t.font(15))
                    Text(reach(c.docA)).font(t.font(15))
                    Text(reach(c.docB)).font(t.font(15))
                }
                GridRow {
                    Text(L("Ecosystems")).font(t.font(15))
                    ecosystems(c.a)
                    ecosystems(c.b)
                }
            }
        }
    }

    private func coverage(_ n: Int, _ total: Int) -> some View {
        HStack(spacing: t.pad(8)) {
            CoverageBar(covered: n, total: max(1, total), t: t, animated: false).frame(width: t.pad(150), height: t.pad(7))
            Text("\(n)").font(t.font(14)).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func reach(_ doc: BOMCore.BOMDocument) -> String {
        switch Composition(doc, graph: DependencyGraph(doc)).reach {
        case .reached(let d, let i):
            return "\(d.formatted(.number.locale(L10n.locale))) → \(i.formatted(.number.locale(L10n.locale)))"
        case .noData: return L("no dependency data")
        case .noProductRef: return L("product has no bom-ref")
        case .notFromProduct: return L("dependencies do not start at the product")
        }
    }

    private func ecosystems(_ f: BOMComparison.Facts) -> some View {
        HStack(spacing: t.pad(6)) {
            ForEach(f.ecosystems.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(3), id: \.key) {
                Chip(text: "\(OverviewView.ecosystemName($0.key)) \($0.value.formatted(.number.locale(L10n.locale)))", t: t)
            }
        }
    }

    // MARK: Lists

    private static let shown = 40

    @ViewBuilder
    private var changed: some View {
        let rows = c.rows.filter { $0.kind == .changed }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: t.pad(6)) {
                (Text(L("Different versions")).font(t.serif(24)) + Text("  \(rows.count)").font(t.font(16)).foregroundStyle(.secondary))
                ForEach(Array(rows.prefix(Self.shown).enumerated()), id: \.offset) { _, r in
                    rowView(r) {
                        HStack(spacing: t.pad(6)) {
                            Text(r.versionA ?? "–").font(t.mono(13))
                            Image(systemName: r.direction == .up ? "arrow.up.right" : r.direction == .down ? "arrow.down.right" : "arrow.right")
                                .foregroundStyle(r.direction == .down ? .orange : .secondary)
                            Text(r.versionB ?? "–").font(t.mono(13))
                        }
                    }
                }
                more(rows.count)
            }
        }
    }

    private func only(_ kind: BOMComparison.Kind) -> some View {
        let rows = c.rows.filter { $0.kind == kind }
        let (a, b) = names
        let doc = kind == .onlyA ? c.docA : c.docB
        return VStack(alignment: .leading, spacing: t.pad(6)) {
            (Text(L("Only in %@", kind == .onlyA ? a : b)).font(t.serif(24)) + Text("  \(rows.count)").font(t.font(16)).foregroundStyle(.secondary))
            if rows.isEmpty { Text(L("Nothing.")).font(t.font(14)).foregroundStyle(.secondary) }
            ForEach(Array(rows.prefix(Self.shown).enumerated()), id: \.offset) { _, r in
                rowView(r) {
                    HStack(spacing: t.pad(6)) {
                        Text((kind == .onlyA ? r.versionA : r.versionB) ?? "–").font(t.mono(13)).foregroundStyle(.secondary)
                        if let i = kind == .onlyA ? r.indexA : r.indexB, let scope = doc.components[i].scope, scope != "required" {
                            Pill(text: scope, kind: .neutral, t: t)
                        }
                    }
                }
            }
            more(rows.count)
        }
    }

    /// A row; from file A it opens the component page, from file B it only shows.
    private func rowView<Detail: View>(_ r: BOMComparison.Row, @ViewBuilder detail: () -> Detail) -> some View {
        let label = HStack(spacing: t.pad(10)) {
            Text(r.name).font(t.font(14, .medium)).lineLimit(1)
            Spacer(minLength: t.pad(8))
            detail()
            if let e = r.ecosystem { Chip(text: OverviewView.ecosystemName(e), t: t) }
            if r.licenceDiffers { Pill(text: L("other licences"), kind: .gap, t: t) }
        }
        .padding(.vertical, t.pad(3))
        return Group {
            if let i = r.indexA {
                Button { model.openComponent(i) } label: { label.contentShape(Rectangle()) }.buttonStyle(.plain)
            } else {
                label.help(L("In the other file"))
            }
        }
    }

    @ViewBuilder
    private func more(_ count: Int) -> some View {
        if count > Self.shown {
            Text(L("%d more", count - Self.shown)).font(t.font(13)).foregroundStyle(.secondary)
        }
    }
}
