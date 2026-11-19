import Foundation

/// SPDX 2.x JSON read into the model the views share with CycloneDX (docs/design-spdx.md).
/// Every value keeps the node it came from, so evidence opens the SPDX bytes.

/// Dependency edges read from SPDX `relationships`, in the direction "uses".
struct SPDXEdges: Sendable {
    /// SPDXID → SPDXIDs it uses, document order, no repeats.
    var edges: [String: [String]] = [:]
    /// The first relationship object that gave an SPDXID an outgoing edge.
    var entries: [String: NodeID] = [:]
}

extension BOMDocument {
    /// "A DEPENDS_ON B": A uses B.
    static let spdxUses: Set<String> = ["DEPENDS_ON"]
    /// "A …_OF B": B uses A.
    static let spdxUsedBy: Set<String> = [
        "DEPENDENCY_OF", "DEV_DEPENDENCY_OF", "BUILD_DEPENDENCY_OF", "RUNTIME_DEPENDENCY_OF",
        "OPTIONAL_DEPENDENCY_OF", "PROVIDED_DEPENDENCY_OF", "TEST_DEPENDENCY_OF",
    ]

    static func readSPDX(_ tree: JSONTree, root: NodeID, versionNode: NodeID) -> BOMDocument? {
        guard let raw = tree.string(versionNode), raw.hasPrefix("SPDX-2.") else { return nil }
        let version = String(raw.dropFirst("SPDX-".count))
        guard isDottedDecimal(version) else { return nil }

        let info = tree.member(root, "creationInfo").flatMap { tree.kind($0) == .object ? $0 : nil }
        var tools: [Tool] = []
        var organisation: String?
        for n in tree.elements(info.flatMap { tree.member($0, "creators") }) {
            guard let creator = tree.string(n) else { continue }
            if let tool = value(creator, prefix: "Tool:") {
                let (name, v) = splitToolVersion(tool)
                tools.append(Tool(vendor: nil, name: name, version: v, node: n))
            } else if organisation == nil, let org = value(creator, prefix: "Organization:") {
                organisation = org
            }
        }
        let timestamp = info.flatMap { tree.member($0, "created") }.flatMap { n in tree.string(n).map { Located($0, node: n) } }

        // The product: what the document DESCRIBES, else documentDescribes.
        let documentID = tree.memberString(root, "SPDXID") ?? "SPDXRef-DOCUMENT"
        let relationships = tree.objectElements(tree.member(root, "relationships"))
        var described = relationships.first {
            tree.memberString($0, "relationshipType") == "DESCRIBES" && tree.memberString($0, "spdxElementId") == documentID
        }.flatMap { tree.memberString($0, "relatedSpdxElement") }
        if described == nil {
            described = tree.elements(tree.member(root, "documentDescribes")).lazy.compactMap { tree.string($0) }.first
        }

        var subject: Component?
        var components: [Component] = []
        for (i, p) in tree.elements(tree.member(root, "packages")).enumerated() {
            let id = tree.memberString(p, "SPDXID")
            let c = Component(spdx: p, path: "packages[\(i)]", isSubject: id != nil && id == described, tree: tree)
            if c.isSubject, subject == nil { subject = c } else { components.append(c) }
        }

        return BOMDocument(tree: tree, root: root, format: .spdx, specVersion: Located(version, node: versionNode),
                           metadata: info, timestamp: timestamp, tools: tools, manufacturerName: organisation,
                           supplierName: nil, subject: subject, components: components,
                           spdxEdges: readEdges(tree, relationships))
    }

    /// Dependency relationships give edges; CONTAINS (A → B) only when nothing depends on B, so a
    /// directory that "contains" every package does not make them all direct.
    static func readEdges(_ tree: JSONTree, _ relationships: [NodeID]) -> SPDXEdges? {
        struct Rel { let from: String, to: String, contains: Bool, node: NodeID }
        var rels: [Rel] = []
        var depended: Set<String> = []
        for r in relationships {
            guard let type = tree.memberString(r, "relationshipType"),
                  let a = tree.memberString(r, "spdxElementId"), let b = tree.memberString(r, "relatedSpdxElement")
            else { continue }
            if spdxUses.contains(type) { rels.append(Rel(from: a, to: b, contains: false, node: r)); depended.insert(b) }
            else if spdxUsedBy.contains(type) { rels.append(Rel(from: b, to: a, contains: false, node: r)); depended.insert(a) }
            else if type == "CONTAINS" { rels.append(Rel(from: a, to: b, contains: true, node: r)) }
        }
        var out = SPDXEdges()
        for r in rels where !(r.contains && depended.contains(r.to)) {
            if out.edges[r.from]?.contains(r.to) == true { continue }
            out.edges[r.from, default: []].append(r.to)
            if out.entries[r.from] == nil { out.entries[r.from] = r.node }
        }
        return out.edges.isEmpty ? nil : out
    }

    /// "Tool: syft-1.57.2" → ("syft", "1.57.2"): the version starts after the last "-" before a digit.
    static func splitToolVersion(_ s: String) -> (String, String?) {
        guard let dash = s.lastIndex(of: "-"), s.index(after: dash) < s.endIndex,
              s[s.index(after: dash)].isNumber else { return (s, nil) }
        return (String(s[..<dash]), String(s[s.index(after: dash)...]))
    }

    /// "Organization: X" → "X" for the given prefix; nil for another prefix or no value.
    static func value(_ s: String, prefix: String) -> String? {
        guard s.hasPrefix(prefix) else { return nil }
        let v = s.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        return v.isEmpty ? nil : v
    }

    /// NOASSERTION and NONE say nothing.
    static func asserted(_ s: String?) -> String? {
        guard let s, !s.isEmpty, s != "NOASSERTION", s != "NONE" else { return nil }
        return s
    }
}

extension Component {
    init(spdx p: NodeID, path: String, isSubject: Bool, tree: JSONTree) {
        self.entry = p
        self.path = path
        self.isSubject = isSubject
        guard tree.kind(p) == .object else {
            node = nil
            return
        }
        node = p
        bomRef = tree.memberString(p, "SPDXID")
        name = tree.memberString(p, "name")
        version = tree.memberString(p, "versionInfo")
        type = tree.memberString(p, "primaryPackagePurpose")?.lowercased()
        description = tree.memberString(p, "description") ?? tree.memberString(p, "summary")
        purl = tree.objectElements(tree.member(p, "externalRefs")).first { tree.memberString($0, "referenceType") == "purl" }
            .flatMap { tree.memberString($0, "referenceLocator") }
        packageURL = purl.flatMap(PackageURL.parse)

        supplierName = BOMDocument.asserted(tree.memberString(p, "supplier")).flatMap(Self.party)
        if let originator = BOMDocument.asserted(tree.memberString(p, "originator")) {
            if originator.hasPrefix("Organization:") { manufacturerName = Self.party(originator) } else { author = Self.party(originator) }
        }

        // The concluded licence, else the declared one.
        for key in ["licenseConcluded", "licenseDeclared"] {
            guard let n = tree.member(p, key), let v = BOMDocument.asserted(tree.string(n)) else { continue }
            licenses = [License(kind: SPDX.isLicence(v) ? .id(v) : .expression(v), acknowledgement: key == "licenseConcluded" ? "concluded" : "declared", node: n)]
            break
        }
        hashes = tree.objectElements(tree.member(p, "checksums")).map {
            Hash(alg: tree.memberString($0, "algorithm").map(Self.algorithm), content: tree.memberString($0, "checksumValue"), node: $0)
        }
        var refs: [ExternalReference] = []
        for (key, type) in [("downloadLocation", "distribution"), ("homepage", "website")] {
            if let n = tree.member(p, key), let url = BOMDocument.asserted(tree.string(n)) {
                refs.append(ExternalReference(type: type, url: url, hashes: [], node: n))
            }
        }
        externalReferences = refs
    }

    /// "Organization: Acme" / "Person: Jane (jane@example.com)" → the name.
    static func party(_ s: String) -> String? {
        for prefix in ["Organization:", "Person:", "Tool:"] { if let v = BOMDocument.value(s, prefix: prefix) { return v } }
        return s
    }

    /// SPDX "SHA256" → CycloneDX "SHA-256"; others unchanged.
    static func algorithm(_ a: String) -> String {
        if a.hasPrefix("SHA"), !a.hasPrefix("SHA3-"), let d = a.dropFirst(3).first, d.isNumber { return "SHA-" + a.dropFirst(3) }
        return a
    }
}
