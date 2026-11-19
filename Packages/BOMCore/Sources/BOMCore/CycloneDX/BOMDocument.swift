/// A bill of materials read from the tree: CycloneDX 1.2 or later, or SPDX 2.x JSON. Nothing is
/// copied out of the source except decoded strings; every part keeps the node it came from.
public struct BOMDocument: Sendable {
    public enum Format: Sendable, Hashable { case cyclonedx, spdx }

    public let tree: JSONTree
    public let root: NodeID
    public let format: Format
    /// The format's version ("1.6", or "2.3" read from "SPDX-2.3"), with its node.
    public let specVersion: Located<String>
    /// CycloneDX `metadata`; SPDX `creationInfo`.
    public let metadata: NodeID?
    public let timestamp: Located<String>?
    public let tools: [Tool]
    public let manufacturerName: String?
    public let supplierName: String?
    public let subject: Component?
    /// Every component but the subject. CycloneDX in rio's order: the subject's nested
    /// components, then `components`, each walked depth first. SPDX: the packages in order.
    public let components: [Component]
    /// SPDX: the dependency edges read from `relationships`; nil for CycloneDX or without any.
    let spdxEdges: SPDXEdges?

    /// The lowest CycloneDX version the views understand.
    public static let minimumVersion = "1.2"

    /// The document when the tree is CycloneDX 1.2 or later or SPDX 2.x JSON; nil otherwise.
    public static func recognize(_ tree: JSONTree) -> BOMDocument? {
        guard let root = tree.root, tree.kind(root) == .object else { return nil }
        if let versionNode = tree.member(root, "spdxVersion") { return readSPDX(tree, root: root, versionNode: versionNode) }
        if let graph = tree.member(root, "@graph"), tree.kind(graph) == .array,
           tree.elements(tree.member(root, "@context")).compactMap({ tree.string($0) }).contains(where: { $0.contains("spdx.org/rdf/3") })
            || tree.memberString(root, "@context")?.contains("spdx.org/rdf/3") == true {
            return readSPDX3(tree, root: root, graph: graph)
        }
        guard tree.memberString(root, "bomFormat") == "CycloneDX",
              let versionNode = tree.member(root, "specVersion"), let version = tree.string(versionNode),
              isDottedDecimal(version), compareVersions(version, minimumVersion) >= 0
        else { return nil }
        return BOMDocument(cyclonedx: tree, root: root, specVersion: Located(version, node: versionNode))
    }

    init(tree: JSONTree, root: NodeID, format: Format, specVersion: Located<String>, metadata: NodeID?,
         timestamp: Located<String>?, tools: [Tool], manufacturerName: String?, supplierName: String?,
         subject: Component?, components: [Component], spdxEdges: SPDXEdges?) {
        self.tree = tree
        self.root = root
        self.format = format
        self.specVersion = specVersion
        self.metadata = metadata
        self.timestamp = timestamp
        self.tools = tools
        self.manufacturerName = manufacturerName
        self.supplierName = supplierName
        self.subject = subject
        self.components = components
        self.spdxEdges = spdxEdges
    }

    private init(cyclonedx tree: JSONTree, root: NodeID, specVersion: Located<String>) {
        let metadata = tree.member(root, "metadata").flatMap { tree.kind($0) == .object ? $0 : nil }
        var components: [Component] = []
        var timestamp: Located<String>?, tools: [Tool] = [], manufacturerName: String?, supplierName: String?
        var subject: Component?
        if let metadata {
            timestamp = tree.member(metadata, "timestamp").flatMap { n in tree.string(n).map { Located($0, node: n) } }
            tools = Self.readTools(tree, tree.member(metadata, "tools"))
            manufacturerName = tree.member(metadata, "manufacturer").flatMap { tree.memberString($0, "name") }
            supplierName = tree.member(metadata, "supplier").flatMap { tree.memberString($0, "name") }
            if let s = tree.member(metadata, "component"), tree.kind(s) == .object {
                subject = Component(entry: s, path: "metadata.component", isSubject: true, tree: tree)
                Self.walk(tree, tree.member(s, "components"), "metadata.component.components", into: &components)
            }
        }
        Self.walk(tree, tree.member(root, "components"), "components", into: &components)
        self.init(tree: tree, root: root, format: .cyclonedx, specVersion: specVersion, metadata: metadata,
                  timestamp: timestamp, tools: tools, manufacturerName: manufacturerName, supplierName: supplierName,
                  subject: subject, components: components, spdxEdges: nil)
    }

    /// Where a component keeps what CycloneDX calls `key`, in this document's format, for
    /// evidence: the views ask in CycloneDX terms ("version", "hashes").
    public func key(_ key: String) -> String {
        guard format == .spdx else { return key }
        return (isSPDX3 ? Self.spdx3Keys[key] : Self.spdxKeys[key]) ?? key
    }

    /// The same for the document's `metadata` (SPDX: `creationInfo`).
    public func metadataKey(_ key: String) -> String {
        guard format == .spdx else { return key }
        return (isSPDX3 ? Self.spdx3MetadataKeys[key] : Self.spdxMetadataKeys[key]) ?? key
    }

    /// The same for the document's top level.
    public func rootKey(_ key: String) -> String {
        guard format == .spdx else { return key }
        return isSPDX3 ? "@graph" : Self.spdxRootKeys[key] ?? key
    }

    static let spdxKeys: [String: String] = [
        "version": "versionInfo", "bom-ref": "SPDXID", "purl": "externalRefs", "licenses": "licenseConcluded",
        "hashes": "checksums", "manufacturer": "originator", "author": "originator", "externalReferences": "externalRefs",
    ]
    static let spdxMetadataKeys: [String: String] = [
        "timestamp": "created", "tools": "creators", "manufacturer": "creators", "supplier": "creators",
    ]
    static let spdx3Keys: [String: String] = [
        "version": "software_packageVersion", "bom-ref": "spdxId", "purl": "software_packageUrl",
        "licenses": "hasConcludedLicense", "hashes": "verifiedUsing", "supplier": "suppliedBy",
        "manufacturer": "originatedBy", "author": "originatedBy", "externalReferences": "software_downloadLocation",
    ]
    static let spdx3MetadataKeys: [String: String] = [
        "timestamp": "created", "tools": "createdUsing", "manufacturer": "createdBy", "supplier": "createdBy",
    ]
    static let spdxRootKeys: [String: String] = [
        "metadata": "creationInfo", "component": "relationships", "dependencies": "relationships", "components": "packages",
    ]

    private static func walk(_ tree: JSONTree, _ list: NodeID?, _ path: String, into out: inout [Component]) {
        for (i, e) in tree.elements(list).enumerated() {
            let here = "\(path)[\(i)]"
            out.append(Component(entry: e, path: here, isSubject: false, tree: tree))
            if tree.kind(e) == .object { walk(tree, tree.member(e, "components"), here + ".components", into: &out) }
        }
    }

    /// Tools in the ≤1.4 array form, or the 1.5+ object form (components, services).
    private static func readTools(_ tree: JSONTree, _ n: NodeID?) -> [Tool] {
        guard let n else { return [] }
        let entries: [NodeID]
        if tree.kind(n) == .array {
            entries = tree.objectElements(n)
        } else if tree.kind(n) == .object {
            entries = tree.objectElements(tree.member(n, "components")) + tree.objectElements(tree.member(n, "services"))
        } else {
            entries = []
        }
        return entries.map { e in
            let vendor = tree.memberString(e, "vendor") ?? tree.memberString(e, "group")
                ?? tree.member(e, "manufacturer").flatMap { tree.memberString($0, "name") }
                ?? tree.member(e, "provider").flatMap { tree.memberString($0, "name") }
            return Tool(vendor: vendor, name: tree.memberString(e, "name"), version: tree.memberString(e, "version"), node: e)
        }
    }

    /// What to call the SBOM's manufacturer: its name, else a contact email, else a URL.
    public var manufacturerLabel: String? {
        if let manufacturerName { return manufacturerName }
        guard let m = metadata.flatMap({ tree.member($0, "manufacturer") }) else { return nil }
        for c in tree.objectElements(tree.member(m, "contact")) { if let e = tree.memberString(c, "email") { return e } }
        return tree.elements(tree.member(m, "url")).lazy.compactMap { self.tree.string($0) }.first
    }

    /// The first component (or the subject) with this bom-ref.
    public func component(bomRef: String) -> Component? {
        if subject?.bomRef == bomRef { return subject }
        return components.first { $0.bomRef == bomRef }
    }

    /// Orders dotted versions like rio: a segment that is not a number sorts
    /// after every number; missing segments count as 0.
    public static func compareVersions(_ a: String, _ b: String) -> Int {
        let x = a.split(separator: ".", omittingEmptySubsequences: false)
        let y = b.split(separator: ".", omittingEmptySubsequences: false)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? Int(x[i]) : 0
            let q = i < y.count ? Int(y[i]) : 0
            switch (p, q) {
            case (nil, nil): continue
            case (nil, _): return 1
            case (_, nil): return -1
            case let (p?, q?) where p != q: return p < q ? -1 : 1
            default: continue
            }
        }
        return 0
    }

    /// Plain decimal segments separated by dots, none empty.
    public static func isDottedDecimal(_ v: String) -> Bool {
        let segs = v.split(separator: ".", omittingEmptySubsequences: false)
        return !segs.isEmpty && segs.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }
    }
}
