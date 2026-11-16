/// Everything the workshop views show about one SBOM, computed once off the
/// main thread. No UI types: the app lays it out and localises it.
public struct WorkshopAnalysis: Sendable {
    public let bom: CycloneDXDocument
    public let graph: DependencyGraph?
    /// The map of the product; nil without dependency data from the product.
    public let map: DependencyMap?
    /// The AI view's reading; nil unless the BOM is about a machine-learning model.
    public let ai: AIBOMAnalysis?
    public let composition: Composition
    public let profile: ProfileResult
    public let report: CompletenessReport
    /// Offenders per component index, in rule order.
    private let byComponent: [Int: [Offender]]
    /// The first component with each bom-ref.
    private let indexByRef: [String: Int]

    /// Nil when the tree is not CycloneDX 1.2 or later.
    public static func analyse(_ tree: JSONTree) -> WorkshopAnalysis? {
        guard let bom = CycloneDXDocument.recognize(tree) else { return nil }
        let graph = DependencyGraph(bom)
        let profile = checkTR031832(bom)
        var byComponent: [Int: [Offender]] = [:]
        for o in profile.offenders { if let i = o.component { byComponent[i, default: []].append(o) } }
        var indexByRef: [String: Int] = [:]
        for (i, c) in bom.components.enumerated() { if let r = c.bomRef, indexByRef[r] == nil { indexByRef[r] = i } }
        let map = graph.map { DependencyMap($0) }.flatMap { $0.slices.isEmpty ? nil : $0 }
        return WorkshopAnalysis(bom: bom, graph: graph, map: map, ai: AIBOMAnalysis.analyse(bom), composition: Composition(bom, graph: graph),
                                profile: profile, report: CompletenessReport(bom, profile), byComponent: byComponent,
                                indexByRef: indexByRef)
    }

    public var verdict: Verdict { Verdict(report) }

    /// Offenders for one component, in rule order.
    public func offenders(component index: Int) -> [Offender] { byComponent[index] ?? [] }

    /// The index of the first component with this bom-ref (the subject is not a component).
    public func componentIndex(bomRef: String) -> Int? { indexByRef[bomRef] }

    /// Number of failed TR-03183-2 rules for one component.
    public func gapCount(component index: Int) -> Int { byComponent[index]?.count ?? 0 }
}

public struct CompletenessReport: Sendable {
    public struct VersionGap: Sendable, Hashable {
        public let found: String
        public let required: String
        public let evidence: Evidence
    }

    public struct Row: Sendable, Hashable, Identifiable {
        public let rule: RuleID
        public let covered: Int
        public let total: Int
        public let outcome: Evaluation.Outcome
        public let section: String?
        /// The CycloneDX version that introduced the field, only when the file is older.
        public let introducedIn: String?
        public let offenders: [Offender]
        public var id: RuleID { rule }
    }

    public struct Section: Sendable, Hashable, Identifiable {
        public let scope: Scope
        public let rows: [Row]
        /// Rules of this part met in full, and rules evaluated (the format version included
        /// for the SBOM, though it has no row; judged on the file as it is).
        public let present: Int
        public let evaluated: Int
        public var id: Scope { scope }
    }

    public let versionGap: VersionGap?
    /// Errors the parser reported; results cover what could be read.
    public let parseErrors: Int
    public let sections: [Section]

    init(_ bom: CycloneDXDocument, _ profile: ProfileResult) {
        let version = bom.specVersion.value
        let spec = profile.evaluations.first { $0.rule == RuleID(.sbom, .specVersion) }
        versionGap = (spec?.failed ?? 0) > 0
            ? VersionGap(found: version, required: TR031832.requiredSpecVersion, evidence: .located(bom.specVersion.node))
            : nil
        parseErrors = bom.tree.diagnostics.filter { $0.severity == .error }.count + bom.tree.unlistedDiagnostics
        var offenders: [RuleID: [Offender]] = [:]
        for o in profile.offenders { offenders[o.rule, default: []].append(o) }
        sections = Scope.allCases.map { scope in
            let rows = profile.evaluations.filter { $0.rule.scope == scope && $0.rule.requirement != .specVersion }.map { e in
                let introduced = TR031832.introducedIn(e.rule.requirement)
                    .flatMap { CycloneDXDocument.compareVersions(version, $0) < 0 ? $0 : nil }
                return Row(rule: e.rule, covered: e.evaluated - e.failed, total: e.evaluated, outcome: e.outcome,
                           section: TR031832.section(e.rule), introducedIn: introduced, offenders: offenders[e.rule] ?? [])
            }
            let all = profile.evaluations.filter { $0.rule.scope == scope && $0.outcome != .notEvaluated }
            return Section(scope: scope, rows: rows, present: all.filter { $0.outcome == .pass }.count, evaluated: all.count)
        }
    }
}

/// What failed, grouped the way a room talks about it, in the order the verdict names them.
public enum GapTopic: String, Sendable, Hashable, CaseIterable {
    case timestamp, manufacturer, hashes, licences, dependencies, fileProperties, identity, vulnerabilities

    init(_ r: Requirement) {
        switch r {
        case .timestamp: self = .timestamp
        case .creator: self = .manufacturer
        case .deployableHash: self = .hashes
        case .distributionLicences: self = .licences
        case .dependencies: self = .dependencies
        case .filename, .executable, .archive, .structured: self = .fileProperties
        case .vulnerabilities: self = .vulnerabilities
        case .name, .version, .level, .specVersion: self = .identity
        }
    }
}

/// The one sentence the Overview says about Completeness.
public struct Verdict: Sendable, Equatable {
    /// No rule fails, the version is 1.6 or later, and the file parsed without errors.
    public let ready: Bool
    /// Errors the parser reported; a file with errors is never ready.
    public let parseErrors: Int
    /// The file's version when it is older than the TR requires.
    public let versionGap: String?
    /// Failing topics in `GapTopic` order.
    public let gaps: [GapTopic]

    public init(ready: Bool, versionGap: String?, gaps: [GapTopic], parseErrors: Int = 0) {
        self.ready = ready
        self.parseErrors = parseErrors
        self.versionGap = versionGap
        self.gaps = gaps
    }

    init(_ report: CompletenessReport) {
        let failing = Set(report.sections.flatMap(\.rows).filter { $0.outcome == .fail }.map { GapTopic($0.rule.requirement) })
        let gaps = GapTopic.allCases.filter(failing.contains)
        self.init(ready: gaps.isEmpty && report.versionGap == nil && report.parseErrors == 0,
                  versionGap: report.versionGap?.found, gaps: gaps, parseErrors: report.parseErrors)
    }
}
