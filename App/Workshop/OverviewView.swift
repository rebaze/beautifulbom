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
                Text(subject?.name ?? model.fileName ?? L("Unnamed product"))
                    .font(t.font(40, .semibold))
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
        if let type = subject?.type { parts.append(type) }
        if let v = subject?.version { parts.append(v) }
        if let first = a.graph?.direct.first, let c = a.bom.component(bomRef: first) {
            parts.append(L("built on %@", [c.displayName, c.version].compactMap { $0 }.joined(separator: " ")))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Stats

    private var stats: some View {
        HStack(spacing: t.pad(12)) {
            stat(value: "\(a.bom.components.count)", label: L("components"), target: .components)
            if let direct = a.composition.directCount, let indirect = a.composition.indirectCount {
                stat(value: "\(direct) → \(indirect)", label: L("chosen directly → pulled in"), target: .composition)
            } else {
                stat(value: "–", label: a.graph == nil ? L("no dependency data") : L("product has no bom-ref"), target: .composition)
            }
            let known = a.composition.ecosystems.filter { !$0.unknown }
            stat(value: "\(known.count)",
                 label: known.count == 1 ? L("ecosystem (%@)", Self.ecosystemName(known[0].label)) : L("ecosystems"),
                 target: .composition)
            let licences = a.composition.licenses.filter { !$0.unknown }
            stat(value: "\(licences.count)", label: licences.count == 1 ? L("licence") : L("licences"), target: .composition)
        }
    }

    private func stat(value: String, label: String, target: WorkshopTab) -> some View {
        Button { model.show(tab: target) } label: {
            VStack(alignment: .leading, spacing: t.pad(2)) {
                Text(value)
                    .font(t.font(38, .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(label)
                    .font(t.font(13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel(t)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L("Open %@", target.title))
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
        let vendorSegments = vendors.map { StackedBar.Segment(label: $0.unknown ? L("no vendor named") : $0.label, count: $0.count,
                                                            filter: $0.unknown ? nil : ComponentFilter(vendor: $0.label), isOthers: $0.unknown) }
            + (others.map { [StackedBar.Segment(label: L("others"), count: $0.count, filter: nil, isOthers: true)] } ?? [])
        let licenceSegments = CompositionView.licenceSegments(a)
        return Grid(alignment: .leading, horizontalSpacing: t.pad(16), verticalSpacing: t.pad(10)) {
            GridRow {
                Text(L("Vendors")).font(t.font(13)).foregroundStyle(.secondary)
                StackedBar(segments: vendorSegments, total: a.bom.components.count, t: t, height: 26, showLegend: false) { model.showComponents($0) }
            }
            GridRow {
                Text(L("Licences")).font(t.font(13)).foregroundStyle(.secondary)
                StackedBar(segments: licenceSegments, total: licenceSegments.reduce(0) { $0 + $1.count }, t: t, height: 26, showLegend: false) { model.showComponents($0) }
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
                    .font(t.font(20, .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let gaps = v.gapList {
                    Text(gaps)
                        .font(t.font(15))
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Text(L("Presence and form of fields only."))
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
