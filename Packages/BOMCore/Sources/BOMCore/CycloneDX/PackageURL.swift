import Foundation

/// A package URL (purl), decoded: `pkg:type/namespace/name@version?qualifiers#subpath`.
public struct PackageURL: Sendable, Hashable {
    public var type: String
    public var namespace: String?
    public var name: String
    public var version: String?
    public var qualifiers: [String: String]
    public var subpath: String?

    public init(type: String, namespace: String?, name: String, version: String?,
                qualifiers: [String: String] = [:], subpath: String? = nil) {
        self.type = type
        self.namespace = namespace
        self.name = name
        self.version = version
        self.qualifiers = qualifiers
        self.subpath = subpath
    }

    /// Parses following the purl specification; nil when the string is not a purl.
    public static func parse(_ s: String) -> PackageURL? {
        var rest = s.trimmingCharacters(in: .whitespaces)
        guard rest.count > 4, rest.prefix(4).lowercased() == "pkg:" else { return nil }
        rest.removeFirst(4)
        while rest.hasPrefix("/") { rest.removeFirst() }

        var subpath: String?
        if let hash = rest.lastIndex(of: "#") {
            let sp = rest[rest.index(after: hash)...].split(separator: "/").filter { $0 != "." && $0 != ".." }
            subpath = sp.isEmpty ? nil : sp.map { decode(String($0)) }.joined(separator: "/")
            rest = String(rest[..<hash])
        }
        var qualifiers: [String: String] = [:]
        if let q = rest.lastIndex(of: "?") {
            for pair in rest[rest.index(after: q)...].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2, !kv[1].isEmpty { qualifiers[kv[0].lowercased()] = decode(String(kv[1])) }
            }
            rest = String(rest[..<q])
        }
        guard let slash = rest.firstIndex(of: "/") else { return nil }
        let type = rest[..<slash].lowercased()
        rest = String(rest[rest.index(after: slash)...])
        while rest.hasSuffix("/") { rest.removeLast() }
        var version: String?
        if let at = rest.lastIndex(of: "@") {
            version = decode(String(rest[rest.index(after: at)...]))
            rest = String(rest[..<at])
        }
        var segments = rest.split(separator: "/").map { decode(String($0)) }
        guard !type.isEmpty, let name = segments.popLast(), !name.isEmpty else { return nil }
        return PackageURL(type: type, namespace: segments.isEmpty ? nil : segments.joined(separator: "/"),
                          name: name, version: version?.isEmpty == true ? nil : version,
                          qualifiers: qualifiers, subpath: subpath)
    }

    private static func decode(_ s: String) -> String { s.removingPercentEncoding ?? s }
}
