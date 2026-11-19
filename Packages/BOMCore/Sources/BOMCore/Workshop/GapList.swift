import Foundation

/// The TR-03183-2 gaps as a list to take home: one entry per field that is missing or not in the
/// required form, for the SBOM, the product or a component, with the place in the file where it is
/// or would be. Presence and form only, like the checks it comes from. Empty without checks (SPDX).
public struct GapList: Sendable {
    public struct Entry: Sendable, Hashable {
        public let rule: RuleID
        /// The TR section ("§5.2.2"); nil for rio's level property.
        public let section: String?
        /// Index into `BOMDocument.components`; nil for the SBOM and the product.
        public let component: Int?
        public let name: String?
        public let version: String?
        public let purl: String?
        public let bomRef: String?
        /// JSON Pointer to the field, or to where it would be when absent.
        public let pointer: String
        public let detail: String?
    }

    /// Whether the TR checks ran (CycloneDX); false for SPDX.
    public let checked: Bool
    public let entries: [Entry]
    /// The entries grouped by rule, in the order Completeness shows the rules.
    public let byRule: [(rule: RuleID, entries: [Entry])]

    public init(_ a: WorkshopAnalysis) {
        guard let profile = a.profile else {
            checked = false
            entries = []
            byRule = []
            return
        }
        checked = true
        let bom = a.bom, tree = bom.tree
        let entries = profile.offenders.map { o -> Entry in
            let c: Component? = o.component.map { bom.components[$0] } ?? (o.rule.scope == .subject ? bom.subject : nil)
            let pointer: String
            switch o.evidence {
            case .located(let n): pointer = tree.pointer(n).description
            case .absent(let ab): pointer = JSONPointer(tokens: tree.pointer(ab.parent).tokens + [ab.key]).description
            }
            return Entry(rule: o.rule, section: TR031832.section(o.rule), component: o.component,
                         name: c.map { $0.displayName }, version: c?.version, purl: c?.purl, bomRef: c?.bomRef,
                         pointer: pointer, detail: o.detail)
        }
        self.entries = entries
        var groups: [RuleID: [Entry]] = [:]
        for e in entries { groups[e.rule, default: []].append(e) }
        byRule = profile.evaluations.map(\.rule).compactMap { r in groups[r].map { (r, $0) } }
    }

    // MARK: CSV

    /// RFC 4180, CRLF line ends. The caller gives the header, the part names and the field titles
    /// (localised); the rule id and the pointer stay as they are, for search.
    public func csv(header: [String], part: (Scope) -> String = { $0.rawValue }, title: (RuleID) -> String) -> String {
        var out = header.map(Self.field).joined(separator: ",") + "\r\n"
        for e in entries {
            let part = part(e.rule.scope)
            let row = [part, e.name ?? "", e.version ?? "", e.purl ?? "", e.bomRef ?? "", title(e.rule),
                       e.section ?? "", e.rule.description, e.pointer]
            out += row.map(Self.field).joined(separator: ",") + "\r\n"
        }
        return out
    }

    /// One CSV field: quoted when it holds a comma, quote or line break. A leading = + - @ (or tab,
    /// carriage return) gets an apostrophe, so text from the SBOM never runs as a spreadsheet formula.
    public static func field(_ s: String) -> String {
        var v = s
        if let first = v.first, "=+-@\t\r".contains(first) { v = "'" + v }
        guard v.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return v }
        return "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
