/// A CycloneDX SBOM read from the tree. Nothing is copied out of the source
/// except decoded strings; every part keeps the node it came from.
public struct BOMDocument: Sendable {
    public let tree: JSONTree
    public let root: NodeID
    public let specVersion: Located<String>
    public let metadata: NodeID?
    public let timestamp: Located<String>?
    public let tools: [Tool]
    public let manufacturerName: String?
    public let supplierName: String?
    public let subject: Component?
    /// Every component but the subject, in rio's order: the subject's nested
    /// components, then `components`, each walked depth first.
    public let components: [Component]

    /// The lowest version the views understand.
    public static let minimumVersion = "1.2"

    /// The document when the tree is CycloneDX 1.2 or later; nil otherwise.
    public static func recognize(_ tree: JSONTree) -> BOMDocument? {
        guard let root = tree.root, tree.kind(root) == .object,
              tree.memberString(root, "bomFormat") == "CycloneDX",
              let versionNode = tree.member(root, "specVersion"), let version = tree.string(versionNode),
              isDottedDecimal(version), compareVersions(version, minimumVersion) >= 0
        else { return nil }
        return BOMDocument(tree: tree, root: root, specVersion: Located(version, node: versionNode))
    }

    private init(tree: JSONTree, root: NodeID, specVersion: Located<String>) {
        self.tree = tree
        self.root = root
        self.specVersion = specVersion
        let metadata = tree.member(root, "metadata").flatMap { tree.kind($0) == .object ? $0 : nil }
        self.metadata = metadata
        var components: [Component] = []
        if let metadata {
            timestamp = tree.member(metadata, "timestamp").flatMap { n in tree.string(n).map { Located($0, node: n) } }
            tools = Self.readTools(tree, tree.member(metadata, "tools"))
            manufacturerName = tree.member(metadata, "manufacturer").flatMap { tree.memberString($0, "name") }
            supplierName = tree.member(metadata, "supplier").flatMap { tree.memberString($0, "name") }
            if let s = tree.member(metadata, "component"), tree.kind(s) == .object {
                subject = Component(entry: s, path: "metadata.component", isSubject: true, tree: tree)
                Self.walk(tree, tree.member(s, "components"), "metadata.component.components", into: &components)
            } else {
                subject = nil
            }
        } else {
            timestamp = nil
            tools = []
            manufacturerName = nil
            supplierName = nil
            subject = nil
        }
        Self.walk(tree, tree.member(root, "components"), "components", into: &components)
        self.components = components
    }

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
