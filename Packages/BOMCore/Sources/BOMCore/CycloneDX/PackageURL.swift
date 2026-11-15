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
    /// Works on UTF-8 bytes: it runs once per component, 100 000 times for a large SBOM.
    public static func parse(_ s: String) -> PackageURL? {
        let b = Array(s.utf8)
        var lo = 0, hi = b.count
        while lo < hi, b[lo] == 0x20 || b[lo] == 0x09 { lo += 1 }
        while hi > lo, b[hi - 1] == 0x20 || b[hi - 1] == 0x09 { hi -= 1 }
        guard hi - lo > 4, b[lo] | 0x20 == UInt8(ascii: "p"), b[lo + 1] | 0x20 == UInt8(ascii: "k"),
              b[lo + 2] | 0x20 == UInt8(ascii: "g"), b[lo + 3] == UInt8(ascii: ":") else { return nil }
        lo += 4
        while lo < hi, b[lo] == UInt8(ascii: "/") { lo += 1 }

        var subpath: String?
        if let h = lastIndex(b, UInt8(ascii: "#"), lo, hi) {
            let parts = split(b, UInt8(ascii: "/"), h + 1, hi).map { decode(b, $0) }.filter { !$0.isEmpty && $0 != "." && $0 != ".." }
            subpath = parts.isEmpty ? nil : parts.joined(separator: "/")
            hi = h
        }
        var qualifiers: [String: String] = [:]
        if let q = lastIndex(b, UInt8(ascii: "?"), lo, hi) {
            for r in split(b, UInt8(ascii: "&"), q + 1, hi) {
                guard let eq = firstIndex(b, UInt8(ascii: "="), r.lowerBound, r.upperBound), eq + 1 < r.upperBound else { continue }
                qualifiers[decode(b, r.lowerBound..<eq).lowercased()] = decode(b, eq + 1..<r.upperBound)
            }
            hi = q
        }
        guard let slash = firstIndex(b, UInt8(ascii: "/"), lo, hi) else { return nil }
        let type = String(decoding: b[lo..<slash], as: UTF8.self).lowercased()
        lo = slash + 1
        while hi > lo, b[hi - 1] == UInt8(ascii: "/") { hi -= 1 }
        var version: String?
        if let at = lastIndex(b, UInt8(ascii: "@"), lo, hi) {
            let v = decode(b, at + 1..<hi)
            version = v.isEmpty ? nil : v
            hi = at
        }
        var segments = split(b, UInt8(ascii: "/"), lo, hi).filter { !$0.isEmpty }.map { decode(b, $0) }
        guard !type.isEmpty, let name = segments.popLast(), !name.isEmpty else { return nil }
        return PackageURL(type: type, namespace: segments.isEmpty ? nil : segments.joined(separator: "/"),
                          name: name, version: version, qualifiers: qualifiers, subpath: subpath)
    }

    private static func lastIndex(_ b: [UInt8], _ c: UInt8, _ lo: Int, _ hi: Int) -> Int? {
        var i = hi - 1
        while i >= lo { if b[i] == c { return i }; i -= 1 }
        return nil
    }

    private static func firstIndex(_ b: [UInt8], _ c: UInt8, _ lo: Int, _ hi: Int) -> Int? {
        var i = lo
        while i < hi { if b[i] == c { return i }; i += 1 }
        return nil
    }

    private static func split(_ b: [UInt8], _ c: UInt8, _ lo: Int, _ hi: Int) -> [Range<Int>] {
        var out: [Range<Int>] = [], start = lo
        for i in lo..<max(lo, hi) where b[i] == c {
            out.append(start..<i)
            start = i + 1
        }
        out.append(start..<max(start, hi))
        return out
    }

    /// Percent-decodes a byte range; an invalid escape stays as written.
    private static func decode(_ b: [UInt8], _ r: Range<Int>) -> String {
        guard b[r].contains(UInt8(ascii: "%")) else { return String(decoding: b[r], as: UTF8.self) }
        var out: [UInt8] = []
        var i = r.lowerBound
        while i < r.upperBound {
            if b[i] == UInt8(ascii: "%"), i + 2 < r.upperBound,
               let h = hex(b[i + 1]), let l = hex(b[i + 2]) {
                out.append(h << 4 | l)
                i += 3
            } else {
                out.append(b[i])
                i += 1
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    private static func hex(_ c: UInt8) -> UInt8? {
        switch c {
        case 48...57: c - 48
        case 65...70: c - 55
        case 97...102: c - 87
        default: nil
        }
    }
}
