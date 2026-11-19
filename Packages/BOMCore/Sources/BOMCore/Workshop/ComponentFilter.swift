import Foundation

/// A query over the Components list: "everything not MIT", "everything
/// without a hash", "everything six steps away".
public struct ComponentFilter: Sendable, Equatable {
    public enum LicenceFilter: Sendable, Equatable {
        case `is`(String), isNot(String), unknown
    }

    public var text: String
    public var licence: LicenceFilter?
    public var missing: RuleID?
    public var depth: Int?
    /// The vendor as Composition groups it: the group, else the purl namespace.
    public var vendor: String?
    public var family: LicenceFamily?

    public init(text: String = "", licence: LicenceFilter? = nil, missing: RuleID? = nil, depth: Int? = nil, vendor: String? = nil,
                family: LicenceFamily? = nil) {
        self.text = text
        self.vendor = vendor
        self.family = family
        self.licence = licence
        self.missing = missing
        self.depth = depth
    }

    public var isEmpty: Bool { self == ComponentFilter() }

    /// Matching indexes into `bom.components`, document order.
    public func apply(_ a: WorkshopAnalysis) -> [Int] {
        let offending: Set<Int>? = missing.map { rule in Set(a.profile?.offenders(rule).compactMap(\.component) ?? []) }
        let needle = text.trimmingCharacters(in: .whitespaces).lowercased()
        return a.bom.components.indices.filter { i in
            let c = a.bom.components[i]
            if let offending, !offending.contains(i) { return false }
            if let vendor, Composition.vendor(of: c) != vendor { return false }
            if let family, LicenceFamily.of(c) != family { return false }
            if let depth, c.bomRef.flatMap({ a.graph?.depth($0) }) != depth { return false }
            if let licence {
                let labels = c.licenses.map(\.label)
                switch licence {
                case .is(let l): if !labels.contains(l) { return false }
                case .isNot(let l): if labels.contains(l) { return false }
                case .unknown: if !labels.isEmpty { return false }
                }
            }
            if !needle.isEmpty {
                let hay = [c.name, c.group, c.purl, c.version].compactMap { $0?.lowercased() }
                if !hay.contains(where: { $0.contains(needle) }) { return false }
            }
            return true
        }
    }
}
