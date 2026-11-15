import Foundation

/// BSI TR-03183-2 2.1.0 as rio's profile `bsi-tr-03183-2@2.1.0` encodes it:
/// presence and form of fields only, never correctness or conformity.
public enum TR031832 {
    public static let name = "BSI TR-03183-2"
    public static let version = "2.1.0"
    /// The CycloneDX version the TR requires (§4).
    public static let requiredSpecVersion = "1.6"
    public static let levelProperty = "rio:tr-03183-2:level"

    /// The TR section a rule comes from; nil for `level` (rio's own property).
    public static func section(_ rule: RuleID) -> String? {
        switch (rule.scope, rule.requirement) {
        case (.sbom, .specVersion): return "§4"
        case (.sbom, .creator), (.sbom, .timestamp): return "§5.2.1"
        case (.sbom, .vulnerabilities): return "§3.1"
        case (.sbom, _): return nil
        case (_, .distributionLicences): return "§5.2.2, §6.1"
        case (_, .level), (_, .specVersion), (_, .timestamp), (_, .vulnerabilities): return nil
        default: return "§5.2.2"
        }
    }

    /// The CycloneDX version that introduced the field a requirement reads,
    /// from the CycloneDX schemas; nil when the field exists since 1.2.
    public static func introducedIn(_ r: Requirement) -> String? {
        switch r {
        case .creator, .distributionLicences: return "1.6"
        case .dependencies, .filename, .executable, .archive, .structured, .deployableHash: return "1.3"
        default: return nil
        }
    }

    /// rio's `identify`: the purl verbatim, else group:name, name or group,
    /// else the path; a version is appended with "@".
    public static func identify(purl: String?, group: String?, name: String?, version: String?, path: String) -> String {
        if let purl, !blank(purl) { return purl }
        let g = trim(group), n = trim(name)
        var id: String
        switch (g.isEmpty, n.isEmpty) {
        case (false, false): id = g + ":" + n
        case (true, false): id = n
        case (false, true): id = g
        case (true, true): id = path
        }
        let v = trim(version)
        if !v.isEmpty { id += "@" + v }
        return id
    }

    static func trim(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    static func blank(_ s: String?) -> Bool { trim(s).isEmpty }
}

public enum Scope: String, Sendable, Hashable, CaseIterable {
    case sbom, subject, components
}

public enum Requirement: String, Sendable, Hashable, CaseIterable {
    case specVersion, creator, timestamp, vulnerabilities
    case name, version, level, filename, dependencies, distributionLicences, deployableHash, executable, archive, structured

    /// Per-component profile fields in reporting order.
    static let profileFields: [Requirement] = [.level, .creator, .filename, .dependencies, .distributionLicences,
                                               .deployableHash, .executable, .archive, .structured]
    static let sbomFields: [Requirement] = [.specVersion, .creator, .timestamp, .vulnerabilities]
    static let componentOrder: [Requirement] = [.name, .version] + profileFields

    var bit: UInt32 { 1 << UInt32(Requirement.allCases.firstIndex(of: self)!) }
    static func mask(_ rs: [Requirement]) -> UInt32 { rs.reduce(0) { $0 | $1.bit } }
}

/// A rule id such as `components.creator`.
public struct RuleID: Hashable, Sendable, CustomStringConvertible {
    public let scope: Scope
    public let requirement: Requirement
    public init(_ scope: Scope, _ requirement: Requirement) {
        self.scope = scope
        self.requirement = requirement
    }
    public init?(_ s: String) {
        let parts = s.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2, let sc = Scope(rawValue: parts[0]), let r = Requirement(rawValue: parts[1]) else { return nil }
        self.init(sc, r)
    }
    public var description: String { "\(scope.rawValue).\(requirement.rawValue)" }

    /// A dense index for counting: 0 ..< RuleID.count.
    var index: Int {
        Scope.allCases.firstIndex(of: scope)! * Requirement.allCases.count + Requirement.allCases.firstIndex(of: requirement)!
    }
    static let count = Scope.allCases.count * Requirement.allCases.count
}

/// The level a component is described at (rio's `rio:tr-03183-2:level`).
public enum Level: String, Sendable, Hashable, CaseIterable {
    case full, logical, assembled, identified, referenced

    /// What each level demands beyond name, version and level (§3.2.1).
    var fields: Set<Requirement> { Set(Requirement.allCases.filter { mask & $0.bit != 0 }) }

    private static let fullMask = Requirement.mask([.creator, .filename, .dependencies, .distributionLicences, .deployableHash, .executable, .archive, .structured])
    private static let partMask = Requirement.mask([.creator, .dependencies, .distributionLicences])
    private static let identifiedMask = Requirement.mask([.creator])

    var mask: UInt32 {
        switch self {
        case .full: Self.fullMask
        case .assembled, .logical: Self.partMask
        case .identified, .referenced: Self.identifiedMask
        }
    }

    func applies(_ r: Requirement) -> Bool { r == .level || mask & r.bit != 0 }
}

public struct Evaluation: Sendable, Hashable {
    public enum Outcome: Sendable, Hashable { case pass, fail, notEvaluated }
    public let rule: RuleID
    public let evaluated: Int
    public let failed: Int
    public var outcome: Outcome { evaluated == 0 ? .notEvaluated : failed > 0 ? .fail : .pass }
}

/// One failed rule for one component (or the document, or the subject).
public struct Offender: Sendable, Hashable {
    public let rule: RuleID
    /// Index into `CycloneDXDocument.components`; nil for the document and the subject.
    public let component: Int?
    /// rio's identifier: what a reader searches for in the SBOM.
    public let identity: String
    public let evidence: Evidence
    public let detail: String?
}

public struct ProfileResult: Sendable {
    /// rio's reporting order and counts.
    public let evaluations: [Evaluation]
    /// Checked components per level, the subject included.
    public let levels: [Level: Int]
    /// In rio's order: the document, the subject, then each component.
    public let offenders: [Offender]

    public func evaluation(_ id: String) -> Evaluation? {
        RuleID(id).flatMap { r in evaluations.first { $0.rule == r } }
    }

    public func offenders(_ rule: RuleID) -> [Offender] { offenders.filter { $0.rule == rule } }
}
