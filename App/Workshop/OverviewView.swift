import BOMCore
import SwiftUI

/// The title page: what the product is, what it is made of in four numbers,
/// who made the SBOM and when, and one sentence about its completeness.
struct OverviewView: View {
    let model: DocumentModel
    let a: WorkshopAnalysis

    private var t: Typo { Typo(s: model.scale) }
    private var tree: JSONTree { a.bom.tree }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: t.pad(22)) {
                header
                stats
                madeOf
                HStack(alignment: .top, spacing: t.pad(28)) {
                    facts.frame(maxWidth: .infinity, alignment: .leading)
                    verdict.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(t.pad(36))
            .frame(maxWidth: 1400 * t.s, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Header

    private var subject: Component? { a.bom.subject }

    private var header: some View {
        VStack(alignment: .leading, spacing: t.pad(6)) {
            EvidenceButton(.located(a.bom.specVersion.node)) {
                Eyebrow(text: L("Software bill of materials · CycloneDX %@", a.bom.specVersion.value), t: t)
            }
            EvidenceButton(subject.map { tree.evidence($0.entry, "name") } ?? a.bom.metadata.map { tree.evidence($0, "component") }) {
                Text(ProductTitle(subject?.name).title ?? model.fileName ?? L("Unnamed product"))
                    .font(t.serif(42))
                    .tracking(-0.4 * t.s)
                    .lineLimit(2)
            }
            Text(subtitle)
                .font(t.font(17))
                .foregroundStyle(.secondary)
            if let d = subject?.description {
                Text(d).font(t.font(14)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        let title = ProductTitle(subject?.name)
        // A name that says nothing (".") is shown as the file says it, next to the file name.
        if title.title == nil, let name = subject?.name { parts.append(L("product named “%@” in the SBOM", name)) }
        if let digest = title.digest { parts.append(digest) }
        if let type = subject?.type { parts.append(type) }
        if let v = subject?.version { parts.append(v) }
        // "Built on" only when the product names exactly one direct dependency; with several,
        // the first in the file is an accident of order.
        if let direct = a.graph?.direct, direct.count == 1, let c = a.bom.component(bomRef: direct[0]) {
            parts.append(L("built on %@", [c.displayName, c.version].compactMap { $0 }.joined(separator: " ")))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Stats

    private var stats: some View {
        HStack(alignment: .top, spacing: t.pad(12)) {
            let files = a.composition.files.count
            stat(value: "\(a.composition.packageCount)", label: files == 0 ? L("components") : L("components · %d files", files),
                 target: .components) { componentsPicture }
            switch a.composition.reach {
            case .reached(let direct, let indirect):
                stat(value: "\(direct) → \(indirect)", label: L("chosen directly → pulled in"), target: .composition,
                     link: a.map == nil ? nil : L("See the map →")) {
                    if let map = a.map { MiniMap(a: a, map: map).frame(width: 96 * min(t.s, 1.4), height: 96 * min(t.s, 1.4)) }
                }
            case .noData:
                stat(value: "–", label: L("no dependency data"), target: .composition) { EmptyView() }
            case .noProductRef:
                stat(value: "–", label: L("product has no bom-ref"), target: .composition) { EmptyView() }
            case .notFromProduct:
                stat(value: "–", label: L("dependencies do not start at the product"), target: .composition) { EmptyView() }
            }
            let known = a.composition.ecosystems.filter { !$0.unknown }
            stat(value: "\(known.count)", label: known.count == 1 ? L("ecosystem") : L("ecosystems"), target: .composition) {
                chips(known.prefix(3).map { Chip(text: "\(Self.ecosystemName($0.label)) \($0.count)", t: t) })
            }
            let licences = a.composition.licenses.filter { !$0.unknown }
            let families = a.composition.families
            let label = licences.count == 1 ? L("licence") : L("licences")
            stat(value: "\(licences.count)",
                 label: families.count == 1 && families[0].label == LicenceFamily.permissive.rawValue ? L("%@, all permissive", label) : label,
                 target: .composition) {
                chips(licences.prefix(3).map { Chip(text: "\(Self.shortLicence($0.label)) \($0.count)", colour: FamilyStyle.colour(LicenceFamily.of($0.label)), t: t) })
            }
        }
    }

    /// One square per component in its vendor's colour; a bar instead for large SBOMs.
    @ViewBuilder
    private var componentsPicture: some View {
        let vendors = VendorPalette.top(a)
        if a.bom.components.count <= 120 {
            let colours = a.bom.components.map { VendorPalette.colour($0, vendors: vendors) }
            let sorted = colours.enumerated().sorted { (rank(colours[$0.offset], vendors), $0.offset) < (rank(colours[$1.offset], vendors), $1.offset) }.map(\.element)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(t.pad(8)), spacing: t.pad(3)), count: 16), alignment: .leading, spacing: t.pad(3)) {
                ForEach(sorted.indices, id: \.self) { RoundedRectangle(cornerRadius: 2 * t.s).fill(sorted[$0]).frame(width: t.pad(8), height: t.pad(8)) }
            }
            .frame(width: t.pad(16 * 11), alignment: .leading)
            .accessibilityHidden(true)
        } else {
            let (named, others) = a.composition.top(a.composition.vendors, keep: 5)
            HStack(spacing: 1) {
                ForEach(named.indices, id: \.self) { k in
                    Rectangle().fill(named[k].unknown ? VendorPalette.others : VendorPalette.colour(of: named[k].label, vendors: vendors))
                        .frame(width: t.pad(170) * CGFloat(named[k].count) / CGFloat(max(1, a.bom.components.count)))
                }
                if let others { Rectangle().fill(VendorPalette.others).frame(width: t.pad(170) * CGFloat(others.count) / CGFloat(max(1, a.bom.components.count))) }
            }
            .frame(height: t.pad(10))
            .clipShape(Capsule())
        }
    }

    private func rank(_ c: Color, _ vendors: [String]) -> Int { VendorPalette.colours.firstIndex(of: c) ?? VendorPalette.colours.count }

    /// As many chips as fit on one line, largest first.
    private func chips(_ items: [Chip]) -> some View {
        ViewThatFits(in: .horizontal) {
            ForEach((1...max(1, items.count)).reversed(), id: \.self) { n in
                HStack(spacing: t.pad(6)) { ForEach(0..<min(n, items.count), id: \.self) { items[$0] } }
                    .fixedSize()
            }
        }
    }

    private func stat<P: View>(value: String, label: String, target: WorkshopTab, link: String? = nil,
                               @ViewBuilder picture: () -> P) -> some View {
        Button { model.show(tab: target) } label: {
            HStack(alignment: .top, spacing: t.pad(8)) {
                VStack(alignment: .leading, spacing: t.pad(2)) {
                    Text(value)
                        .font(t.serif(38))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(label)
                        .font(t.font(13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: t.pad(10))
                    if link != nil, !beside { picture().padding(.bottom, t.pad(8)) }
                    if let link { Text(link).font(t.font(13)).foregroundStyle(Color.accentColor) }
                    else { picture() }
                }
                if link != nil, beside {
                    Spacer(minLength: 0)
                    picture()
                }
            }
            .frame(maxWidth: .infinity, minHeight: t.pad(118), alignment: .topLeading)
            .panel(t)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L("Open %@", target.title))
    }

    /// The picture of a card with a link stands beside the number at normal sizes, under it at presentation size.
    private var beside: Bool { t.s <= 1.25 }

    /// "BSD-3-Clause" fits a chip as "BSD-3"; other identifiers stay as they are.
    static func shortLicence(_ s: String) -> String {
        s.hasSuffix("-Clause") ? String(s.dropLast("-Clause".count)) : s
    }

    static func ecosystemName(_ purlType: String) -> String {
        let names = ["composer": "Composer", "npm": "npm", "maven": "Maven", "pypi": "PyPI", "golang": "Go",
                     "cargo": "Cargo", "nuget": "NuGet", "gem": "RubyGems", "deb": "Debian", "rpm": "RPM",
                     "apk": "Alpine", "oci": "OCI", "docker": "Docker", "generic": "generic", "github": "GitHub",
                     "swift": "Swift", "cocoapods": "CocoaPods", "hex": "Hex", "pub": "pub", "conan": "Conan"]
        return names[purlType] ?? purlType
    }

    // MARK: Made of

    private var madeOf: some View {
        let (vendors, others) = a.composition.top(a.composition.vendors, keep: 5)
        let top = VendorPalette.top(a)
        let vendorSegments = vendors.map { StackedBar.Segment(label: $0.unknown ? L("no vendor named") : $0.label, count: $0.count,
                                                            filter: $0.unknown ? nil : ComponentFilter(vendor: $0.label), isOthers: $0.unknown,
                                                            colour: top.contains($0.label) ? VendorPalette.colour(of: $0.label, vendors: top) : nil) }
            + (others.map { [StackedBar.Segment(label: L("others"), count: $0.count, filter: nil, isOthers: true)] } ?? [])
        let licenceSegments = CompositionView.licenceSegments(a)
        return Grid(alignment: .leading, horizontalSpacing: t.pad(16), verticalSpacing: t.pad(10)) {
            GridRow {
                Text(L("Vendors")).font(t.font(13)).foregroundStyle(.secondary)
                StackedBar(segments: vendorSegments, total: a.composition.packageCount, t: t, height: 26, showLegend: false) { model.showComponents($0) }
            }
            GridRow {
                Text(L("Licences")).font(t.font(13)).foregroundStyle(.secondary)
                StackedBar(segments: licenceSegments, total: licenceSegments.reduce(0) { $0 + $1.count }, t: t, height: 26, showLegend: false) { model.showComponents($0) }
            }
            GridRow {
                Color.clear.frame(width: 1, height: 1)
                FamilyLegend(model: model, a: a, t: t)
            }
        }
    }

    // MARK: Facts

    private var facts: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: L("About this SBOM"), t: t).padding(.bottom, t.pad(6))
            field(L("Made by")) {
                if a.bom.tools.isEmpty {
                    EvidenceButton(a.bom.metadata.map { tree.evidence($0, "tools") }) { Pill(text: L("no tool named"), kind: .gap, t: t) }
                } else {
                    VStack(alignment: .leading, spacing: t.pad(2)) {
                        ForEach(a.bom.tools, id: \.node) { tool in
                            EvidenceButton(.located(tool.node)) {
                                (Text(tool.name ?? L("unnamed tool"))
                                    + Text(tool.version.map { "  " + L("version %@", $0) } ?? "").foregroundStyle(.secondary))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            field(L("Made when")) {
                if let ts = a.bom.timestamp {
                    EvidenceButton(.located(ts.node)) {
                        Text(Self.formatTimestamp(ts.value))
                    }
                } else {
                    EvidenceButton(a.bom.metadata.map { tree.evidence($0, "timestamp") } ?? tree.evidence(a.bom.root, "metadata")) {
                        Pill(text: L("no timestamp"), kind: .gap, t: t)
                    }
                }
            }
            field(L("Manufacturer")) {
                let evidence = a.bom.metadata.map { tree.evidence($0, "manufacturer") } ?? tree.evidence(a.bom.root, "metadata")
                EvidenceButton(evidence) {
                    if let name = a.bom.manufacturerLabel { Text(name) } else { Pill(text: L("none named"), kind: .gap, t: t) }
                }
            }
            if let supplier = a.bom.supplierName {
                field(L("Supplier")) {
                    EvidenceButton(a.bom.metadata.map { tree.evidence($0, "supplier") }) { Text(supplier) }
                }
            }
            field(L("Format")) {
                EvidenceButton(.located(a.bom.specVersion.node)) { Text("CycloneDX \(a.bom.specVersion.value)") }
            }
        }
    }

    private func field<V: View>(_ label: String, @ViewBuilder _ value: () -> V) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: t.pad(12)) {
            Text(label)
                .font(t.font(13))
                .foregroundStyle(.secondary)
                .frame(width: t.pad(120), alignment: .leading)
            value().font(t.font(15))
            Spacer(minLength: 0)
        }
        .padding(.vertical, t.pad(8))
        .overlay(alignment: .bottom) { Hairline() }
    }

    static func formatTimestamp(_ s: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let g = ISO8601DateFormatter()
        guard let date = f.date(from: s) ?? g.date(from: s) else { return s }
        return date.formatted(Date.FormatStyle(date: .long, time: .shortened, locale: L10n.locale, timeZone: TimeZone(identifier: "UTC")!)) + " UTC"
    }

    // MARK: Verdict

    private var verdict: some View {
        let v = a.verdict
        return Button { model.show(tab: .completeness) } label: {
            VStack(alignment: .leading, spacing: t.pad(8)) {
                Eyebrow(text: L("BSI TR-03183-2 2.1.0"), t: t)
                Text(v.headline)
                    .font(t.serif(22))
                    .fixedSize(horizontal: false, vertical: true)
                if let gaps = v.gapList {
                    Text(gaps)
                        .font(t.font(14))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Grid(alignment: .leading, horizontalSpacing: t.pad(12), verticalSpacing: t.pad(6)) {
                    ForEach(a.report.sections.filter { $0.evaluated > 0 }) { section in
                        GridRow {
                            Text(CompletenessView.sectionTitle(section.scope)).font(t.font(14))
                            CoverageBar(covered: section.present, total: section.evaluated, t: t).frame(height: t.pad(8))
                            Text(L("%d of %d", section.present, section.evaluated)).font(t.font(13)).foregroundStyle(.secondary).monospacedDigit()
                                .gridColumnAlignment(.trailing)
                        }
                    }
                }
                .padding(.top, t.pad(4))
                HStack {
                    Text(L("Fields present in the required form, per part. Presence and form only."))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(L("Completeness →")).foregroundStyle(Color.accentColor)
                }
                .font(t.font(12))
                .padding(.top, t.pad(4))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel(t, tint: v.ready ? .green : .orange)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
