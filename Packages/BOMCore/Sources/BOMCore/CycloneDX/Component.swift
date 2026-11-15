/// One component as the SBOM states it. String fields are nil when absent or
/// not a string. `node` is nil only for an entry that is not an object.
public struct Component: Sendable, Hashable {
    /// The array element (or `metadata.component`) this component was read from.
    public let entry: NodeID
    public let node: NodeID?
    /// rio's path form: `metadata.component`, `components[3].components[0]`.
    public let path: String
    public let isSubject: Bool
    public var bomRef, type, group, name, version, purl, description, author: String?
    public var packageURL: PackageURL?
    public var licenses: [License] = []
    public var hashes: [Hash] = []
    public var externalReferences: [ExternalReference] = []
    public var properties: [Property] = []
    public var supplierName, manufacturerName: String?
    public var unknownKeys: [String] = []

    /// `group/name` when both are present, else the name, else the path.
    public var displayName: String {
        switch (group, name) {
        case let (g?, n?) where !g.isEmpty: return "\(g)/\(n)"
        case let (_, n?): return n
        default: return path
        }
    }

    init(entry: NodeID, path: String, isSubject: Bool, tree: JSONTree) {
        self.entry = entry
        self.path = path
        self.isSubject = isSubject
        guard tree.kind(entry) == .object else {
            node = nil
            return
        }
        node = entry
        let o = entry
        bomRef = tree.memberString(o, "bom-ref")
        type = tree.memberString(o, "type")
        group = tree.memberString(o, "group")
        name = tree.memberString(o, "name")
        version = tree.memberString(o, "version")
        purl = tree.memberString(o, "purl")
        description = tree.memberString(o, "description")
        packageURL = purl.flatMap(PackageURL.parse)
        author = tree.memberString(o, "author") ?? Self.names(tree, tree.member(o, "authors"))
        supplierName = tree.member(o, "supplier").flatMap { tree.memberString($0, "name") }
        manufacturerName = tree.member(o, "manufacturer").flatMap { tree.memberString($0, "name") }
        licenses = License.read(tree, tree.member(o, "licenses"))
        hashes = Hash.read(tree, tree.member(o, "hashes"))
        externalReferences = tree.objectElements(tree.member(o, "externalReferences")).map {
            ExternalReference(type: tree.memberString($0, "type"), url: tree.memberString($0, "url"),
                              hashes: Hash.read(tree, tree.member($0, "hashes")), node: $0)
        }
        properties = tree.objectElements(tree.member(o, "properties")).map {
            Property(name: tree.memberString($0, "name"), value: tree.memberString($0, "value"), node: $0)
        }
        var seen = Set<String>()
        unknownKeys = tree.keys(o).filter { !Self.knownKeys.contains($0) && seen.insert($0).inserted }
    }

    static func names(_ tree: JSONTree, _ list: NodeID?) -> String? {
        let names = tree.objectElements(list).compactMap { tree.memberString($0, "name") }
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    /// The component properties of CycloneDX 1.6.
    static let knownKeys: Set<String> = [
        "type", "mime-type", "bom-ref", "supplier", "manufacturer", "authors", "author", "publisher", "group",
        "name", "version", "description", "scope", "hashes", "licenses", "copyright", "cpe", "purl", "omniborId",
        "swhid", "swid", "modified", "pedigree", "externalReferences", "properties", "components", "evidence",
        "releaseNotes", "modelCard", "data", "cryptoProperties", "tags", "signature",
    ]
}

public struct License: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case id(String), name(String), expression(String)
    }
    public let kind: Kind
    public let acknowledgement: String?
    /// The entry in `licenses`.
    public let node: NodeID

    /// The label used for grouping: the SPDX id, the expression or the name.
    public var label: String {
        switch kind {
        case .id(let s), .name(let s), .expression(let s): return s
        }
    }

    static func read(_ tree: JSONTree, _ list: NodeID?) -> [License] {
        tree.objectElements(list).compactMap { e in
            if let expr = tree.memberString(e, "expression") {
                return License(kind: .expression(expr), acknowledgement: tree.memberString(e, "acknowledgement"), node: e)
            }
            guard let l = tree.member(e, "license"), tree.kind(l) == .object else { return nil }
            let ack = tree.memberString(l, "acknowledgement")
            if let id = tree.memberString(l, "id") { return License(kind: .id(id), acknowledgement: ack, node: e) }
            if let name = tree.memberString(l, "name") { return License(kind: .name(name), acknowledgement: ack, node: e) }
            return nil
        }
    }
}

public struct Hash: Sendable, Hashable {
    public let alg: String?
    public let content: String?
    public let node: NodeID

    static func read(_ tree: JSONTree, _ list: NodeID?) -> [Hash] {
        tree.objectElements(list).map { Hash(alg: tree.memberString($0, "alg"), content: tree.memberString($0, "content"), node: $0) }
    }
}

public struct ExternalReference: Sendable, Hashable {
    public let type: String?
    public let url: String?
    public let hashes: [Hash]
    public let node: NodeID
}

public struct Property: Sendable, Hashable {
    public let name: String?
    public let value: String?
    public let node: NodeID
}

public struct Tool: Sendable, Hashable {
    public let vendor: String?
    public let name: String?
    public let version: String?
    public let node: NodeID
}
