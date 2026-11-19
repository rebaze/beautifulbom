import Foundation

/// SPDX 3.0 JSON-LD (`@context` + `@graph`) read into the shared model (docs/design-spdx.md).
/// Only what SPDX 3 defines: licences come from `hasConcludedLicense` / `hasDeclaredLicense`
/// relationships, not from a generator's private extensions.
extension BOMDocument {
    /// "A dependsOn B" and the link kinds: A uses B.
    static let spdx3Uses: Set<String> = [
        "dependsOn", "hasDynamicLink", "hasStaticLink", "hasOptionalDependency", "hasProvidedDependency",
    ]

    var isSPDX3: Bool { format == .spdx && specVersion.value.hasPrefix("3") }

    static func readSPDX3(_ tree: JSONTree, root: NodeID, graph: NodeID) -> BOMDocument? {
        let elements = tree.objectElements(graph)
        func id(_ e: NodeID) -> String? { tree.memberString(e, "spdxId") ?? tree.memberString(e, "@id") }
        var byID: [String: NodeID] = [:]
        for e in elements { if let i = id(e), byID[i] == nil { byID[i] = e } }
        func type(_ e: NodeID) -> String? { tree.memberString(e, "type") ?? tree.memberString(e, "@type") }
        func name(_ ref: String?) -> String? { ref.flatMap { byID[$0] }.flatMap { tree.memberString($0, "name") } }

        guard let info = elements.first(where: { type($0) == "CreationInfo" }),
              let versionNode = tree.member(info, "specVersion"), let version = tree.string(versionNode),
              version.hasPrefix("3.")
        else { return nil }
        let timestamp = tree.member(info, "created").flatMap { n in tree.string(n).map { Located($0, node: n) } }
        let createdBy = tree.elements(tree.member(info, "createdBy")).compactMap { tree.string($0) }
        var tools: [Tool] = []
        for n in tree.elements(tree.member(info, "createdUsing")) {
            guard let ref = tree.string(n), let toolName = name(ref) else { continue }
            let (tn, tv) = splitToolVersion(toolName)
            tools.append(Tool(vendor: nil, name: tn, version: tv, node: byID[ref] ?? n))
        }
        if tools.isEmpty {
            for e in elements where type(e) == "Tool" {
                if let toolName = tree.memberString(e, "name") {
                    let (tn, tv) = splitToolVersion(toolName)
                    tools.append(Tool(vendor: nil, name: tn, version: tv, node: e))
                }
            }
        }

        // Licences and edges from the relationships.
        var concluded: [String: NodeID] = [:], declared: [String: NodeID] = [:]
        var rels: [(from: String, to: String, contains: Bool, node: NodeID)] = []
        var depended: Set<String> = []
        for e in elements where type(e) == "Relationship" {
            guard let from = tree.memberString(e, "from"), let kind = tree.memberString(e, "relationshipType") else { continue }
            let targets = tree.elements(tree.member(e, "to")).compactMap { tree.string($0) }
            switch kind {
            case "hasConcludedLicense": if concluded[from] == nil, let t = targets.first, let l = byID[t] { concluded[from] = l }
            case "hasDeclaredLicense": if declared[from] == nil, let t = targets.first, let l = byID[t] { declared[from] = l }
            case _ where spdx3Uses.contains(kind):
                for t in targets { rels.append((from, t, false, e)); depended.insert(t) }
            case "contains":
                for t in targets { rels.append((from, t, true, e)) }
            default: break
            }
        }
        var edges = SPDXEdges()
        for r in rels where !(r.contains && depended.contains(r.to)) {
            if edges.edges[r.from]?.contains(r.to) == true { continue }
            edges.edges[r.from, default: []].append(r.to)
            if edges.entries[r.from] == nil { edges.entries[r.from] = r.node }
        }

        let document = elements.first { type($0) == "SpdxDocument" || type($0) == "software_Sbom" }
        let described = document.flatMap { tree.elements(tree.member($0, "rootElement")).lazy.compactMap { tree.string($0) }.first }

        var subject: Component?
        var components: [Component] = []
        for (i, e) in tree.elements(graph).enumerated() where type(e) == "software_Package" {
            let ref = id(e)
            var c = Component(spdx3: e, path: "@graph[\(i)]", isSubject: ref != nil && ref == described, tree: tree, name: name)
            if let ref, let l = concluded[ref] ?? declared[ref],
               let n = tree.member(l, "simplelicensing_licenseExpression"), let v = asserted(tree.string(n)) {
                c.licenses = [License(kind: SPDX.isLicence(v) ? .id(v) : .expression(v),
                                      acknowledgement: concluded[ref] != nil ? "concluded" : "declared", node: n)]
            }
            if c.isSubject, subject == nil { subject = c } else { components.append(c) }
        }

        return BOMDocument(tree: tree, root: root, format: .spdx, specVersion: Located(version, node: versionNode),
                           metadata: info, timestamp: timestamp, tools: tools,
                           manufacturerName: createdBy.first.map { name($0) ?? $0 }, supplierName: nil,
                           subject: subject, components: components, spdxEdges: edges.edges.isEmpty ? nil : edges)
    }
}

extension Component {
    init(spdx3 e: NodeID, path: String, isSubject: Bool, tree: JSONTree, name agentName: (String?) -> String?) {
        self.entry = e
        self.path = path
        self.isSubject = isSubject
        node = e
        bomRef = tree.memberString(e, "spdxId") ?? tree.memberString(e, "@id")
        name = tree.memberString(e, "name")
        version = tree.memberString(e, "software_packageVersion")
        type = tree.memberString(e, "software_primaryPurpose")?.lowercased()
        description = tree.memberString(e, "description") ?? tree.memberString(e, "summary")
        purl = tree.memberString(e, "software_packageUrl")
        packageURL = purl.flatMap(PackageURL.parse)
        supplierName = tree.memberString(e, "suppliedBy").map { agentName($0) ?? $0 }
        if let o = tree.elements(tree.member(e, "originatedBy")).lazy.compactMap({ tree.string($0) }).first {
            author = agentName(o) ?? o
        }
        hashes = tree.objectElements(tree.member(e, "verifiedUsing")).filter { tree.memberString($0, "type") == "Hash" }.map {
            Hash(alg: tree.memberString($0, "algorithm").map(Self.algorithm3), content: tree.memberString($0, "hashValue"), node: $0)
        }
        var refs: [ExternalReference] = []
        for (key, type) in [("software_downloadLocation", "distribution"), ("software_homePage", "website")] {
            if let n = tree.member(e, key), let url = BOMDocument.asserted(tree.string(n)) {
                refs.append(ExternalReference(type: type, url: url, hashes: [], node: n))
            }
        }
        externalReferences = refs
    }

    /// SPDX 3 "sha512" / "sha3_256" / "md5" → CycloneDX "SHA-512" / "SHA3-256" / "MD5".
    static func algorithm3(_ a: String) -> String {
        let up = a.uppercased().replacingOccurrences(of: "_", with: "-")
        return algorithm(up)
    }
}
