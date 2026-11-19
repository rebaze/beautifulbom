import BOMCore
import Foundation

// bbom-bench: synthetic CycloneDX fixtures and engine measurements.
//   bbom-bench generate --size <MB> [--minified] --out <path>
//   bbom-bench parse <path>
//   bbom-bench analyse <path>   parse, then the workshop analysis (model, graph, checks)

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

func analyseCommand(_ path: String) throws {
    let bytes = [UInt8](try Data(contentsOf: URL(fileURLWithPath: path)))
    let t0 = now()
    let tree = parseJSON(SourceDocument(bytes: bytes))
    let t1 = now()
    let a = WorkshopAnalysis.analyse(tree)
    let t2 = now()
    // Stage by stage, for profiling.
    if let bom = BOMDocument.recognize(tree) {
        let s0 = now()
        _ = BOMDocument.recognize(tree)
        let s1 = now()
        let graph = DependencyGraph(bom)
        let s2 = now()
        let profile = checkTR031832(bom)
        let s3 = now()
        _ = Composition(bom, graph: graph)
        let s4 = now()
        print("  stages: modelMs=\(ms(s0, s1)) graphMs=\(ms(s1, s2)) checksMs=\(ms(s2, s3)) compositionMs=\(ms(s3, s4)) offenders=\(profile.offenders.count)")
    }
    print("file=\((path as NSString).lastPathComponent) bytes=\(bytes.count) components=\(a?.bom.components.count ?? 0) "
        + "graph=\(a?.graph != nil) offenders=\(a?.profile.offenders.count ?? 0) parseMs=\(ms(t0, t1)) analyseMs=\(ms(t1, t2)) "
        + "peakRSSMB=\(peakRSSMB())")
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
    try SyntheticSBOM.generate(sizeMB: size, minified: args.contains("--minified"))
        .write(toFile: out, atomically: true, encoding: .utf8)
case "analyse":
    guard args.count > 2 else {
        print("usage: bbom-bench analyse <path>")
        exit(2)
    }
    try analyseCommand(args[2])
case "parse":
    guard args.count > 2 else {
        print("usage: bbom-bench parse <path>")
        exit(2)
    }
    try parseCommand(args[2])
default:
    print("usage: bbom-bench generate --size <MB> [--minified] --out <path> | parse <path> | analyse <path>")
    exit(2)
}
