import Foundation

/// A small deterministic random generator (SplitMix64).
public struct SplitMix64: Sendable {
    public var state: UInt64
    public init(state: UInt64) { self.state = state }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    public mutating func pick<T>(_ a: [T]) -> T { a[Int(next() % UInt64(a.count))] }
}

/// Minimal deterministic JSON writer: pretty (2 spaces) or minified.
struct SyntheticWriter {
    var out = ""
    let pretty: Bool
    var depth = 0
    var first = [true]

    mutating func newline() { if pretty { out += "\n" + String(repeating: "  ", count: depth) } }
    mutating func separator() {
        if !first[first.count - 1] { out += "," }
        first[first.count - 1] = false
        newline()
    }
    mutating func open(_ c: String, key: String? = nil) {
        if depth > 0 { separator() }
        if let key { out += quote(key) + (pretty ? ": " : ":") }
        out += c
        depth += 1
        first.append(true)
    }
    mutating func close(_ c: String) {
        let empty = first.removeLast()
        depth -= 1
        if !empty { newline() }
        out += c
    }
    mutating func field(_ key: String, _ value: String) {
        separator()
        out += quote(key) + (pretty ? ": " : ":") + quote(value)
    }
    mutating func value(_ v: String) {
        separator()
        out += quote(v)
    }
    mutating func raw(_ key: String, _ value: String) {
        separator()
        out += quote(key) + (pretty ? ": " : ":") + value
    }
    func quote(_ s: String) -> String {
        var r = "\""
        for ch in s.unicodeScalars {
            switch ch {
            case "\"": r += "\\\""
            case "\\": r += "\\\\"
            case "\n": r += "\\n"
            default: r.unicodeScalars.append(ch)
            }
        }
        return r + "\""
    }
}

/// Deterministic synthetic CycloneDX 1.6 SBOMs for measurements and scale tests:
/// components with licences, hashes and properties, a dependency tree from the
/// product (six children per node, so 100 000 components stay within eight
/// steps), and one composition that covers every component.
public enum SyntheticSBOM {
    public static func generate(sizeMB: Double, minified: Bool) -> String {
    var rng = SplitMix64(state: 42)
    let target = Int(sizeMB * 1_000_000)
    let names = ["left-pad", "lodash", "zlib", "openssl", "jackson-databind", "log4j-core", "spring-core",
                 "react", "express", "commons-text", "guava", "netty-handler", "protobuf", "serde", "tokio"]
    let licenses = ["MIT", "Apache-2.0", "BSD-3-Clause", "ISC", "MPL-2.0", "Zlib", "EPL-2.0"]
    let ecosystems = ["npm", "maven", "pypi", "cargo", "golang"]
    let notes = ["Bibliothek für Ärger und Übermut", "日本語の説明", "emoji 😀 in text", "path\\with\\backslashes",
                 "quote \"inside\"", "plain description"]
    var w = SyntheticWriter(pretty: !minified)
    w.open("{")
    w.field("$schema", "http://cyclonedx.org/schema/bom-1.6.schema.json")
    w.field("bomFormat", "CycloneDX")
    w.field("specVersion", "1.6")
    w.field("serialNumber", "urn:uuid:3e671687-395b-41f5-a30f-a58921a69b79")
    w.raw("version", "1")
    w.open("{", key: "metadata")
    w.field("timestamp", "2026-11-15T12:00:00Z")
    w.open("{", key: "tools"); w.open("[", key: "components"); w.open("{")
    w.field("type", "application"); w.field("name", "bbom-bench"); w.field("version", "0.1.0")
    w.close("}"); w.close("]"); w.close("}")
    w.open("{", key: "component")
    w.field("type", "application"); w.field("bom-ref", "synthetic-product"); w.field("name", "synthetic-product"); w.field("version", "1.0.0")
    w.close("}")
    w.close("}")
    w.open("[", key: "components")
    var n = 0
    var refs: [String] = []
    while w.out.utf8.count < target {
        let name = rng.pick(names) + "-\(n)"
        let version = "\(rng.next() % 10).\(rng.next() % 20).\(rng.next() % 50)"
        let eco = rng.pick(ecosystems)
        let purl = "pkg:\(eco)/\(name)@\(version)"
        refs.append(purl)
        w.open("{")
        w.field("type", "library")
        w.field("bom-ref", purl)
        w.field("name", name)
        w.field("version", version)
        w.field("description", rng.pick(notes))
        w.field("purl", purl)
        w.open("[", key: "licenses"); w.open("{"); w.open("{", key: "license")
        w.field("id", rng.pick(licenses))
        w.close("}"); w.close("}"); w.close("]")
        w.open("[", key: "hashes"); w.open("{")
        w.field("alg", "SHA-256")
        w.field("content", (0..<4).map { _ in String(format: "%016llx", rng.next()) }.joined())
        w.close("}"); w.close("]")
        w.open("[", key: "properties"); w.open("{")
        w.field("name", "cdx:\(eco):package:path")
        w.field("value", "vendor/\(name)")
        w.close("}"); w.close("]")
        w.close("}")
        n += 1
    }
    w.close("]")
    // Node 0 is the product, node k ≥ 1 is refs[k - 1]; node k depends on nodes 6k+1 … 6k+6.
    let all = ["synthetic-product"] + refs
    w.open("[", key: "dependencies")
    for k in all.indices {
        w.open("{")
        w.field("ref", all[k])
        let children = min(6 * k + 1, all.count)..<min(6 * k + 7, all.count)
        if !children.isEmpty {
            w.open("[", key: "dependsOn")
            for c in children { w.value(all[c]) }
            w.close("]")
        }
        w.close("}")
    }
    w.close("]")
    w.open("[", key: "compositions"); w.open("{")
    w.field("aggregate", "complete")
    w.open("[", key: "assemblies")
    for r in all { w.value(r) }
    w.close("]")
    w.close("}"); w.close("]")
    w.close("}")
    return w.out + (minified ? "" : "\n")
}
}
