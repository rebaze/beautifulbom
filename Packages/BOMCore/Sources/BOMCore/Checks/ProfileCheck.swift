import Foundation

/// Checks a CycloneDX document against BSI TR-03183-2 2.1.0 exactly as rio's
/// `bsi-tr-03183-2@2.1.0` profile does (`internal/gate/profile.go`, with
/// `gate.require: [name, version]`), except that `sbom.specVersion` is judged
/// on the file as it is: rio raises an older file to 1.6 before it checks.
public func checkTR031832(_ bom: CycloneDXDocument) -> ProfileResult {
    ProfileRun(bom).result()
}

private struct ProfileRun {
    let bom: CycloneDXDocument
    let tree: JSONTree
    let fields: FieldChecks
    let deps: Set<String>
    let covered: Set<String>

    struct Checked {
        var level: Level = .full
        var missing: Set<Requirement> = []
        var detail: String?
    }

    init(_ bom: CycloneDXDocument) {
        self.bom = bom
        tree = bom.tree
        fields = FieldChecks(tree: bom.tree)
        let t = bom.tree
        deps = Set(t.objectElements(t.member(bom.root, "dependencies")).compactMap { t.memberString($0, "ref") })
        var covered = Set<String>()
        for c in t.objectElements(t.member(bom.root, "compositions")) {
            guard let agg = t.memberString(c, "aggregate"), agg != "not_specified" else { continue }
            for key in ["assemblies", "dependencies"] {
                for r in t.elements(t.member(c, key)) { if let s = t.string(r) { covered.insert(s) } }
            }
        }
        self.covered = covered
    }

    /// The values of the properties the profile reads, from one pass over the
    /// component's properties (nil for a value that is missing or not a string).
    struct Properties {
        var level: [String?] = [], filename: [String?] = [], executable: [String?] = []
        var archive: [String?] = [], structured: [String?] = []

        init(_ c: Component) {
            for p in c.properties {
                switch p.name {
                case TR031832.levelProperty?: level.append(p.value)
                case "bsi:component:filename"?: filename.append(p.value)
                case "bsi:component:executable"?: executable.append(p.value)
                case "bsi:component:archive"?: archive.append(p.value)
                case "bsi:component:structured"?: structured.append(p.value)
                default: break
                }
            }
        }

        static func one(_ values: [String?], _ allowed: [String]) -> Bool {
            values.count == 1 && values[0].map(allowed.contains) == true
        }
    }

    func check(_ c: Component) -> Checked {
        var out = Checked()
        guard let obj = c.node else {
            out.missing = Level.full.fields
            return out
        }
        let props = Properties(c)
        (out.level, out.detail) = resolveLevel(c, props)
        if out.detail != nil { out.missing.insert(.level) }
        for r in Requirement.profileFields where r != .level && out.level.applies(r) && !passes(r, c, obj, props) {
            out.missing.insert(r)
        }
        return out
    }

    func passes(_ r: Requirement, _ c: Component, _ obj: NodeID, _ props: Properties) -> Bool {
        switch r {
        case .creator: return fields.validCreator(tree.member(obj, "manufacturer"))
        case .filename:
            guard props.filename.count == 1, let s = props.filename[0] else { return false }
            return !TR031832.blank(s) && !s.contains("/") && !s.contains("\\")
        case .dependencies:
            guard let ref = c.bomRef, !TR031832.blank(ref) else { return false }
            return deps.contains(ref) && covered.contains(ref)
        case .distributionLicences: return fields.validLicences(obj)
        case .deployableHash:
            return c.externalReferences.contains { ref in
                ref.type == "distribution" && ref.hashes.contains { $0.alg == "SHA-512" && $0.content.map { FieldChecks.validHex($0, 128) } == true }
            }
        case .executable: return Properties.one(props.executable, ["executable", "non-executable"])
        case .archive: return Properties.one(props.archive, ["archive", "no archive"])
        case .structured: return Properties.one(props.structured, ["structured", "unstructured"])
        default: return true
        }
    }

    /// A `bom` reference with a nonblank url makes a component referenced; an
    /// unusable level property leaves it full, with a detail.
    func resolveLevel(_ c: Component, _ props: Properties) -> (Level, String?) {
        if c.externalReferences.contains(where: { $0.type == "bom" && $0.url.map { !TR031832.blank($0) } == true }) {
            return (.referenced, nil)
        }
        let values = props.level
        let p = TR031832.levelProperty
        switch values.count {
        case 0: return (.full, nil)
        case 1: break
        default: return (.full, "the \(p) property appears \(values.count) times; it may appear once")
        }
        guard let s = values[0] else { return (.full, "the \(p) value is not a string") }
        if let level = Level(rawValue: s), [.logical, .identified, .assembled].contains(level) { return (level, nil) }
        return (.full, "the \(p) value \(goQuote(s)) is not logical, identified or assembled")
    }

    func sbomMissing() -> [Requirement] {
        let v = bom.specVersion.value
        let metadata = bom.metadata
        let failed: [Requirement: Bool] = [
            .specVersion: !(CycloneDXDocument.isDottedDecimal(v)
                && CycloneDXDocument.compareVersions(v, TR031832.requiredSpecVersion) >= 0),
            .creator: !fields.validCreator(metadata.flatMap { tree.member($0, "manufacturer") }),
            .timestamp: !(metadata.flatMap { tree.memberString($0, "timestamp") }.map(FieldChecks.validTimestamp) ?? false),
            .vulnerabilities: !tree.elements(tree.member(bom.root, "vulnerabilities")).isEmpty,
        ]
        return Requirement.sbomFields.filter { failed[$0]! }
    }

    func sbomEvidence(_ r: Requirement) -> Evidence {
        switch r {
        case .specVersion: return .located(bom.specVersion.node)
        case .vulnerabilities: return tree.evidence(bom.root, "vulnerabilities")
        default:
            guard let m = bom.metadata else { return tree.evidence(bom.root, "metadata") }
            return tree.evidence(m, r == .creator ? "manufacturer" : "timestamp")
        }
    }

    static func key(_ r: Requirement) -> String {
        switch r {
        case .creator: return "manufacturer"
        case .level, .filename, .executable, .archive, .structured: return "properties"
        case .distributionLicences: return "licenses"
        case .deployableHash: return "externalReferences"
        case .dependencies: return "bom-ref"
        default: return r.rawValue
        }
    }

    func componentEvidence(_ c: Component, _ r: Requirement) -> Evidence {
        guard let obj = c.node else { return .located(c.entry) }
        return tree.evidence(obj, Self.key(r))
    }

    func identity(_ c: Component) -> String {
        TR031832.identify(purl: c.purl, group: c.group, name: c.name, version: c.version, path: c.path)
    }

    func result() -> ProfileResult {
        var offenders: [Offender] = []
        var levels: [Level: Int] = Dictionary(uniqueKeysWithValues: Level.allCases.map { ($0, 0) })

        for r in sbomMissing() {
            let detail = r == .specVersion ? bom.specVersion.value : nil
            offenders.append(Offender(rule: RuleID(.sbom, r), component: nil, identity: "", evidence: sbomEvidence(r), detail: detail))
        }

        // The subject: name and version always, profile fields when metadata.component is an object.
        let subject = bom.subject
        let subjectChecked = subject.map(check)
        if let s = subjectChecked { levels[s.level, default: 0] += 1 }
        let subjectHolder: Evidence = bom.metadata.map { tree.evidence($0, "component") } ?? tree.evidence(bom.root, "metadata")
        let subjectID = subject.map(identity) ?? "metadata.component"
        for r in Requirement.componentOrder {
            let fails: Bool
            switch r {
            case .name: fails = TR031832.blank(subject?.name)
            case .version: fails = TR031832.blank(subject?.version)
            default: fails = subjectChecked?.missing.contains(r) ?? false
            }
            guard fails else { continue }
            let evidence = subject.map { componentEvidence($0, r) } ?? subjectHolder
            offenders.append(Offender(rule: RuleID(.subject, r), component: nil, identity: subjectID, evidence: evidence,
                                      detail: r == .level ? subjectChecked?.detail : nil))
        }

        var children: [Level: Int] = [:]
        for (i, c) in bom.components.enumerated() {
            let checked = check(c)
            levels[checked.level, default: 0] += 1
            children[checked.level, default: 0] += 1
            let id = identity(c)
            for r in Requirement.componentOrder {
                let fails: Bool
                switch r {
                case .name: fails = TR031832.blank(c.name)
                case .version: fails = TR031832.blank(c.version)
                default: fails = checked.missing.contains(r)
                }
                guard fails else { continue }
                offenders.append(Offender(rule: RuleID(.components, r), component: i, identity: id,
                                          evidence: componentEvidence(c, r), detail: r == .level ? checked.detail : nil))
            }
        }

        var failedCount = [Int](repeating: 0, count: RuleID.count)
        for o in offenders { failedCount[o.rule.index] += 1 }
        var evaluations: [Evaluation] = []
        func add(_ scope: Scope, _ r: Requirement, _ n: Int) {
            let rule = RuleID(scope, r)
            evaluations.append(Evaluation(rule: rule, evaluated: n, failed: failedCount[rule.index]))
        }
        for r in Requirement.sbomFields { add(.sbom, r, 1) }
        add(.subject, .name, 1)
        add(.subject, .version, 1)
        for r in Requirement.profileFields { add(.subject, r, subjectChecked.map { $0.level.applies(r) ? 1 : 0 } ?? 0) }
        let total = children.values.reduce(0, +)
        add(.components, .name, total)
        add(.components, .version, total)
        for r in Requirement.profileFields {
            add(.components, r, children.reduce(0) { $0 + ($1.key.applies(r) ? $1.value : 0) })
        }
        return ProfileResult(evaluations: evaluations, levels: levels, offenders: offenders)
    }
}

/// Go's `%q`: a double-quoted string with Go escapes for quotes, backslashes and control characters.
func goQuote(_ s: String) -> String {
    var out = "\""
    for u in s.unicodeScalars {
        switch u {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\t": out += "\\t"
        case "\r": out += "\\r"
        default:
            if u.value < 0x20 || u.value == 0x7F {
                out += String(format: "\\x%02x", u.value)
            } else {
                out.unicodeScalars.append(u)
            }
        }
    }
    return out + "\""
}
