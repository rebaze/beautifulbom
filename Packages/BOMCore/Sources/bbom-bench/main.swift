import BOMCore
import Foundation

// bbom-bench: synthetic CycloneDX fixtures and engine measurements.
//   bbom-bench generate --size <MB> [--minified] --out <path>
//   bbom-bench parse <path>

struct SplitMix64 {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func pick<T>(_ a: [T]) -> T { a[Int(next() % UInt64(a.count))] }
}

/// Minimal deterministic JSON writer: pretty (2 spaces) or minified.
struct Writer {
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

func generate(sizeMB: Double, minified: Bool) -> String {
    var rng = SplitMix64(state: 42)
    let target = Int(sizeMB * 1_000_000)
    let names = ["left-pad", "lodash", "zlib", "openssl", "jackson-databind", "log4j-core", "spring-core",
                 "react", "express", "commons-text", "guava", "netty-handler", "protobuf", "serde", "tokio"]
    let licenses = ["MIT", "Apache-2.0", "BSD-3-Clause", "ISC", "MPL-2.0", "Zlib", "EPL-2.0"]
    let ecosystems = ["npm", "maven", "pypi", "cargo", "golang"]
    let notes = ["Bibliothek für Ärger und Übermut", "日本語の説明", "emoji 😀 in text", "path\\with\\backslashes",
                 "quote \"inside\"", "plain description"]
    var w = Writer(pretty: !minified)
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
    w.field("type", "application"); w.field("name", "synthetic-product"); w.field("version", "1.0.0")
    w.close("}")
    w.close("}")
    w.open("[", key: "components")
    var n = 0
    while w.out.utf8.count < target {
        let name = rng.pick(names) + "-\(n)"
        let version = "\(rng.next() % 10).\(rng.next() % 20).\(rng.next() % 50)"
        let eco = rng.pick(ecosystems)
        let purl = "pkg:\(eco)/\(name)@\(version)"
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
    w.close("}")
    return w.out + (minified ? "" : "\n")
}

func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
func ms(_ a: UInt64, _ b: UInt64) -> String { String(format: "%.1f", Double(b - a) / 1e6) }

func peakRSSMB() -> String {
    var u = rusage()
    getrusage(RUSAGE_SELF, &u)
    return String(format: "%.0f", Double(u.ru_maxrss) / 1_048_576)  // ru_maxrss is in bytes on macOS
}

func parseCommand(_ path: String) throws {
    let bytes = [UInt8](try Data(contentsOf: URL(fileURLWithPath: path)))
    let t0 = now()
    let doc = SourceDocument(bytes: bytes)
    let t1 = now()
    let tree = parseJSON(doc)
    let t2 = now()
    var rng = SplitMix64(state: 7)
    var hits = 0
    let t3 = now()
    for _ in 0..<1000 where tree.node(at: ByteOffset(value: Int(rng.next() % UInt64(max(bytes.count, 1))))) != nil {
        hits += 1
    }
    let t4 = now()
    let mid = ByteOffset(value: bytes.count / 2)
    let start = tree.lexStart(atOrBefore: mid)
    let tokens = lex(doc, from: start, to: ByteOffset(value: mid.value + 65_536))
    let t5 = now()
    let lookupUs = String(format: "%.1f", Double(t4 - t3) / 1000 / 1000)
    let lexUs = String(format: "%.0f", Double(t5 - t4) / 1000)
    print("file=\((path as NSString).lastPathComponent) bytes=\(bytes.count) nodes=\(tree.nodeCount) "
        + "diagnostics=\(tree.diagnostics.count) sourceDocMs=\(ms(t0, t1)) parseMs=\(ms(t1, t2)) "
        + "lookupUs=\(lookupUs) lex64KUs=\(lexUs) tokens=\(tokens.count) hits=\(hits) peakRSSMB=\(peakRSSMB())")
}

let args = CommandLine.arguments
func value(_ flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

switch args.dropFirst().first {
case "generate":
    guard let size = value("--size").flatMap(Double.init), let out = value("--out") else {
        print("usage: bbom-bench generate --size <MB> [--minified] --out <path>")
        exit(2)
    }
    try generate(sizeMB: size, minified: args.contains("--minified"))
        .write(toFile: out, atomically: true, encoding: .utf8)
case "parse":
    guard args.count > 2 else {
        print("usage: bbom-bench parse <path>")
        exit(2)
    }
    try parseCommand(args[2])
default:
    print("usage: bbom-bench generate --size <MB> [--minified] --out <path> | parse <path>")
    exit(2)
}
