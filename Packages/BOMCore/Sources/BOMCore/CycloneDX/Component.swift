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
    /// CycloneDX `scope`: required, optional (cdxgen: development dependencies) or excluded.
    public var scope: String?
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
        // One pass over the members; a later duplicate key wins, as in rio.
        var authorNode, authorsNode, supplierNode, manufacturerNode, licensesNode, hashesNode, refsNode, propsNode: NodeID?
        var unknown: [String] = []
        var c = tree.firstChildren[entry.index]
        while c >= 0 {
            let n = NodeID(rawValue: c)
            c = tree.nextSiblings[Int(c)]
            guard let k = tree.key(n) else { continue }
            switch k {
            case "bom-ref": bomRef = tree.string(n)
            case "type": type = tree.string(n)
            case "group": group = tree.string(n)
            case "name": name = tree.string(n)
            case "version": version = tree.string(n)
            case "purl": purl = tree.string(n)
            case "description": description = tree.string(n)
            case "scope": scope = tree.string(n)
            case "author": authorNode = n
            case "authors": authorsNode = n
            case "supplier": supplierNode = n
            case "manufacturer": manufacturerNode = n
            case "licenses": licensesNode = n
            case "hashes": hashesNode = n
            case "externalReferences": refsNode = n
            case "properties": propsNode = n
            default:
                if !Self.knownKeys.contains(k), !unknown.contains(k) { unknown.append(k) }
            }
        }
        unknownKeys = unknown
        packageURL = purl.flatMap(PackageURL.parse)
        author = tree.string(authorNode) ?? Self.names(tree, authorsNode)
        supplierName = supplierNode.flatMap { tree.memberString($0, "name") }
        manufacturerName = manufacturerNode.flatMap { tree.memberString($0, "name") }
        licenses = License.read(tree, licensesNode)
        hashes = Hash.read(tree, hashesNode)
        externalReferences = tree.objectElements(refsNode).map {
            ExternalReference(type: tree.memberString($0, "type"), url: tree.memberString($0, "url"),
                              hashes: Hash.read(tree, tree.member($0, "hashes")), node: $0)
        }
        properties = tree.objectElements(propsNode).map {
            Property(name: tree.memberString($0, "name"), value: tree.memberString($0, "value"), node: $0)
        }
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

/// How the product's name reads as a title. Directory scans name the product "." and image scans
/// add the digest to the name; both make poor headlines.
public struct ProductTitle: Sendable, Hashable {
    /// The headline; nil when the name says nothing (absent, empty, ".", "/"), so the view uses the
    /// file name and says what the SBOM calls the product.
    public let title: String?
    /// The digest after "@", shortened to 12 hex digits, for the subtitle.
    public let digest: String?

    public init(_ name: String?) {
        let n = name?.trimmingCharacters(in: .whitespaces) ?? ""
        if n.isEmpty || n.allSatisfy({ $0 == "." || $0 == "/" }) {
            title = nil
            digest = nil
            return
        }
        if let at = n.range(of: "@sha256:"), at.lowerBound > n.startIndex {
            title = String(n[..<at.lowerBound])
            let hex = n[at.upperBound...]
            digest = "sha256:" + hex.prefix(12) + (hex.count > 12 ? "…" : "")
        } else {
            title = n
            digest = nil
        }
    }
}
