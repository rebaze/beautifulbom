import BOMCore
import SwiftUI

/// TR-03183-2 field by field: how many components carry each required field in
/// the required form. A row opens the components that do not; each opens its
/// evidence. Presence and form only, and it says so.
struct CompletenessView: View {
    let model: DocumentModel
    let a: WorkshopAnalysis
    @State private var expanded: Set<RuleID> = LaunchOptions.evidence.flatMap(RuleID.init).map { [$0] } ?? []

    private var t: Typo { Typo(s: model.scale) }
    private var report: CompletenessReport { a.report }

    /// Flattened, so a row with 100 000 offenders stays lazy.
    private enum Item: Identifiable {
        case header, versionGap, parseErrors
        case section(Scope)
        case row(CompletenessReport.Row)
        case offender(RuleID, Int, Offender)
        case more(RuleID, Int)

        var id: String {
            switch self {
            case .header: "header"
            case .versionGap: "gap"
            case .parseErrors: "errors"
            case .section(let s): "s-\(s.rawValue)"
            case .row(let r): "r-\(r.rule)"
            case .offender(let r, let i, _): "o-\(r)-\(i)"
            case .more(let r, _): "m-\(r)"
            }
        }
    }

    private var items: [Item] {
        var out: [Item] = [.header]
        if report.versionGap != nil { out.append(.versionGap) }
        if report.parseErrors > 0 { out.append(.parseErrors) }
        for section in report.sections where !section.rows.isEmpty {
            out.append(.section(section.scope))
            for row in section.rows {
                out.append(.row(row))
                if expanded.contains(row.rule), row.total > 1 || section.scope == .components {
                    out += row.offenders.enumerated().map { .offender(row.rule, $0.offset, $0.element) }
                }
            }
        }
        return out
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    view(item)
                }
            }
            .padding(t.pad(36))
            .frame(maxWidth: 1400 * t.s, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func view(_ item: Item) -> some View {
        switch item {
        case .header:
            VStack(alignment: .leading, spacing: t.pad(6)) {
                Eyebrow(text: L("BSI TR-03183-2 2.1.0 · presence and form of fields"), t: t)
                Text(a.verdict.headline).font(t.font(30, .semibold))
                Text(L("Each row counts the components that carry the field in the form the TR asks for. It does not check that the values are true."))
                    .font(t.font(14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, t.pad(18))
        case .versionGap:
            if let gap = report.versionGap {
                EvidenceButton(gap.evidence) {
                    HStack(alignment: .top, spacing: t.pad(12)) {
                        Image(systemName: "clock.arrow.circlepath").font(t.font(20)).foregroundStyle(.orange)
                        Text(L("This SBOM is CycloneDX %@. TR-03183-2 requires %@ or later. A conversion to %@ fixes the version; it adds none of the missing fields.",
                               gap.found, gap.required, gap.required))
                            .font(t.font(15)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel(t, tint: .orange)
                }
                .padding(.bottom, t.pad(10))
            }
        case .parseErrors:
            HStack(spacing: t.pad(12)) {
                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                Text(L("The file has %d errors. The results cover what could be read.", report.parseErrors)).font(t.font(15))
                Spacer()
                Button(L("Show in Source")) { model.show(tab: .source) }
            }
            .panel(t, tint: .red)
            .padding(.bottom, t.pad(10))
        case .section(let scope):
            VStack(alignment: .leading, spacing: t.pad(2)) {
                Text(Self.sectionTitle(scope)).font(t.font(22, .semibold))
                Text(sectionCaption(scope)).font(t.font(13)).foregroundStyle(.secondary)
            }
            .padding(.top, t.pad(22))
            .padding(.bottom, t.pad(8))
        case .row(let row):
            rowView(row)
        case .offender(let rule, _, let o):
            EvidenceButton(o.evidence) {
                HStack(spacing: t.pad(10)) {
                    Image(systemName: "arrow.turn.down.right").foregroundStyle(.tertiary)
                    Text(o.component.map { a.bom.components[$0].displayName } ?? o.identity)
                        .font(t.font(14)).lineLimit(1)
                    if let v = o.component.flatMap({ a.bom.components[$0].version }) {
                        Text(v).font(t.font(13)).foregroundStyle(.secondary)
                    }
                    if let d = o.detail { Text(d).font(t.font(12)).foregroundStyle(.secondary).lineLimit(1) }
                    Spacer(minLength: 0)
                    if let i = o.component {
                        Button(L("Open")) { model.openComponent(i) }
                            .buttonStyle(.link).font(t.font(12))
                    }
                }
                .padding(.vertical, t.pad(3))
                .padding(.leading, t.pad(24))
            }
            .id("\(rule)")
        case .more:
            EmptyView()
        }
    }

    private func rowView(_ row: CompletenessReport.Row) -> some View {
        let single = row.total == 1 && row.rule.scope != .components
        let open = expanded.contains(row.rule)
        return Button {
            if single || row.offenders.count == 1 {
                if let e = row.offenders.first?.evidence { model.show(e) }
            } else if !row.offenders.isEmpty {
                if open { expanded.remove(row.rule) } else { expanded.insert(row.rule) }
            }
        } label: {
            HStack(alignment: .center, spacing: t.pad(14)) {
                Image(systemName: row.outcome == .notEvaluated ? "minus.circle" : row.offenders.isEmpty ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(row.outcome == .notEvaluated ? Color.secondary : row.offenders.isEmpty ? .green : .red)
                    .font(t.font(16))
                VStack(alignment: .leading, spacing: t.pad(1)) {
                    Text(Self.title(row.rule.requirement)).font(t.font(16, .medium))
                    HStack(spacing: t.pad(8)) {
                        if let s = row.section { Text(s).foregroundStyle(.secondary) }
                        if let v = row.introducedIn {
                            Text(L("field introduced in CycloneDX %@", v)).foregroundStyle(.orange)
                        }
                        if row.outcome == .notEvaluated { Text(L("not checked at this level")).foregroundStyle(.secondary) }
                    }
                    .font(t.font(12))
                }
                Spacer(minLength: t.pad(12))
                if single {
                    Pill(text: row.offenders.isEmpty ? L("present") : L("missing or malformed"), kind: row.offenders.isEmpty ? .ok : .gap, t: t)
                } else if row.outcome != .notEvaluated {
                    Text("\(row.covered) / \(row.total)")
                        .font(t.font(16, .semibold)).monospacedDigit()
                        .frame(minWidth: t.pad(90), alignment: .trailing)
                    CoverageBar(covered: row.covered, total: row.total, t: t)
                        .frame(width: t.pad(220), height: t.pad(10))
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .foregroundStyle(row.offenders.count > 1 ? Color.secondary : .clear)
                }
            }
            .padding(.vertical, t.pad(10))
            .padding(.horizontal, t.pad(4))
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Hairline() }
        }
        .buttonStyle(.plain)
        .opacity(row.outcome == .notEvaluated ? 0.55 : 1)
    }

    private func sectionCaption(_ scope: Scope) -> String {
        switch scope {
        case .sbom: return L("Fields of the SBOM itself (§5.2.1).")
        case .subject: return L("The product the SBOM describes: %@.", a.bom.subject?.displayName ?? L("not named"))
        case .components: return L("%d components, checked at their level.", a.bom.components.count)
        }
    }

    static func sectionTitle(_ scope: Scope) -> String {
        switch scope {
        case .sbom: L("The SBOM")
        case .subject: L("The product")
        case .components: L("The components")
        }
    }

    static func title(_ r: Requirement) -> String {
        switch r {
        case .specVersion: L("Format version")
        case .creator: L("Manufacturer with contact")
        case .timestamp: L("Creation time (RFC 3339)")
        case .vulnerabilities: L("No vulnerability data in the SBOM")
        case .name: L("Name")
        case .version: L("Version")
        case .level: L("Level property valid")
        case .filename: L("File name")
        case .dependencies: L("Dependencies, covered by a composition")
        case .distributionLicences: L("Concluded licence (SPDX)")
        case .deployableHash: L("SHA-512 hash of the deployable file")
        case .executable: L("Executable property")
        case .archive: L("Archive property")
        case .structured: L("Structured property")
        }
    }
}

/// Covered in green, the rest in red.
struct CoverageBar: View {
    let covered: Int
    let total: Int
    let t: Typo

    var body: some View {
        GeometryReader { geo in
            let w = total == 0 ? 0 : geo.size.width * CGFloat(covered) / CGFloat(total)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.red.opacity(0.22))
                Capsule().fill(Color.green).frame(width: w)
            }
        }
    }
}
