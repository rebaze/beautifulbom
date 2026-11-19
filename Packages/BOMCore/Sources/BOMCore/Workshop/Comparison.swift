/// Two bills of materials side by side: release against release, or two tools on the same
/// source. Components are paired by identity (the package URL without version, qualifiers and
/// subpath; else group and name), several versions of one package as sets: equal versions first,
/// then the rest in version order as changed, the remainder on one side only. Files listed as
/// components (Syft on an image) are counted, not paired. The products are not paired. Entries
/// that pair the same way (Syft lists a GitHub Action once per workflow) become one row with `times`.
public struct BOMComparison: Sendable {
    public enum Kind: Sendable, Hashable { case same, changed, onlyA, onlyB }
    public enum Direction: Sendable, Hashable { case up, down, unknown }

    public struct Row: Sendable, Hashable {
        public let kind: Kind
        /// `namespace/name` from the package URL, else `group/name`, else the name.
        public let name: String
        /// The package URL type ("npm", "maven"); nil without one.
        public let ecosystem: String?
        public let versionA: String?
        public let versionB: String?
        /// Indexes into each document's `components`.
        public let indexA: Int?
        public let indexB: Int?
        /// For changed rows: newer, older, or not comparable.
        public let direction: Direction
        /// Both sides state licences, and not the same ones (for any of the merged entries).
        public let licenceDiffers: Bool
        /// How many entries this row stands for: a package listed several times with the same
        /// version on each side is one row. The indexes point to the first.
        public let times: Int
    }

    /// What one side states, for the table of facts.
    public struct Facts: Sendable, Hashable {
        public let packages: Int
        public let files: Int
        public let withPurl: Int
        public let withVersion: Int
        public let withLicence: Int
        public let withHash: Int
        public let withSupplier: Int
        public let ecosystems: [String: Int]
    }

    public struct Counts: Sendable, Hashable {
        public let same, changed, onlyA, onlyB: Int
    }

    public let docA: BOMDocument
    public let docB: BOMDocument
    public let a: Facts
    public let b: Facts
    /// Sorted by name, then the version on side A (else B).
    public let rows: [Row]

    /// Entries, not rows: same + changed + onlyA is the packages of A.
    public var counts: Counts {
        var s = 0, c = 0, oa = 0, ob = 0
        for r in rows {
            switch r.kind { case .same: s += r.times; case .changed: c += r.times; case .onlyA: oa += r.times; case .onlyB: ob += r.times }
        }
        return Counts(same: s, changed: c, onlyA: oa, onlyB: ob)
    }

    public init(_ docA: BOMDocument, _ docB: BOMDocument) {
        self.docA = docA
        self.docB = docB
        a = Self.facts(docA)
        b = Self.facts(docB)

        struct Entry { let index: Int; let version: String? }
        func group(_ doc: BOMDocument) -> [String: (name: String, eco: String?, entries: [Entry])] {
            var out: [String: (name: String, eco: String?, entries: [Entry])] = [:]
            for (i, c) in doc.components.enumerated() where c.type != "file" {
                let (key, name, eco) = Self.identity(c)
                out[key, default: (name, eco, [])].entries.append(Entry(index: i, version: Self.version(c)))
            }
            return out
        }
        let ga = group(docA), gb = group(docB)
        var rows: [Row] = []
        for key in Set(ga.keys).union(gb.keys) {
            let name = ga[key]?.name ?? gb[key]!.name
            let eco = ga[key]?.eco ?? gb[key]?.eco
            var restA = ga[key]?.entries ?? [], restB = gb[key]?.entries ?? []
            func row(_ kind: Kind, _ x: Entry?, _ y: Entry?) -> Row {
                let la = x.map { Set(docA.components[$0.index].licenses.map(\.label)) } ?? []
                let lb = y.map { Set(docB.components[$0.index].licenses.map(\.label)) } ?? []
                return Row(kind: kind, name: name, ecosystem: eco, versionA: x?.version, versionB: y?.version,
                           indexA: x?.index, indexB: y?.index,
                           direction: kind == .changed ? Self.direction(x?.version, y?.version) : .unknown,
                           licenceDiffers: !la.isEmpty && !lb.isEmpty && la != lb, times: 1)
            }
            // Equal versions first.
            for x in restA {
                if let j = restB.firstIndex(where: { $0.version == x.version }) {
                    rows.append(row(.same, x, restB.remove(at: j)))
                    restA.removeAll { $0.index == x.index }
                }
            }
            // Then the rest in version order, pairwise.
            let order: (Entry, Entry) -> Bool = { Self.precedes($0.version, $1.version) }
            restA.sort(by: order)
            restB.sort(by: order)
            for (x, y) in zip(restA, restB) { rows.append(row(.changed, x, y)) }
            for x in restA.dropFirst(restB.count) { rows.append(row(.onlyA, x, nil)) }
            for y in restB.dropFirst(restA.count) { rows.append(row(.onlyB, nil, y)) }
        }
        // One row per kind, package and pair of versions, with the number of entries; the order
        // is that of the first entry.
        struct Key: Hashable { let kind: Kind; let name: String; let eco: String?; let va: String?; let vb: String? }
        var merged: [Row] = []
        var at: [Key: Int] = [:]
        for r in rows.sorted(by: {
            $0.name != $1.name ? $0.name < $1.name
                : $0.ecosystem != $1.ecosystem ? ($0.ecosystem ?? "") < ($1.ecosystem ?? "")
                : Self.precedes($0.versionA ?? $0.versionB, $1.versionA ?? $1.versionB)
        }) {
            let k = Key(kind: r.kind, name: r.name, eco: r.ecosystem, va: r.versionA, vb: r.versionB)
            if let i = at[k] {
                let m = merged[i]
                merged[i] = Row(kind: m.kind, name: m.name, ecosystem: m.ecosystem, versionA: m.versionA, versionB: m.versionB,
                                indexA: m.indexA, indexB: m.indexB, direction: m.direction,
                                licenceDiffers: m.licenceDiffers || r.licenceDiffers, times: m.times + 1)
            } else {
                at[k] = merged.count
                merged.append(r)
            }
        }
        self.rows = merged
    }

    // MARK: Identity and versions

    /// (pairing key, display name, ecosystem).
    static func identity(_ c: Component) -> (String, String, String?) {
        if let p = c.packageURL, !p.name.isEmpty {
            let ns = p.namespace.flatMap { $0.isEmpty ? nil : $0 }
            let name = ns.map { "\($0)/\(p.name)" } ?? p.name
            return ("\(p.type)|\(name)".lowercased(), name, p.type)
        }
        let g = c.group.flatMap { $0.isEmpty ? nil : $0 }
        let name = g.map { "\($0)/\(c.name ?? "")" } ?? c.name ?? c.path
        return ("~|\(name)".lowercased(), name, nil)
    }

    static func version(_ c: Component) -> String? { c.version ?? c.packageURL?.version }

    /// Dotted numbers (an optional leading "v") compare; anything else is not comparable.
    public static func direction(_ x: String?, _ y: String?) -> Direction {
        guard let x = numeric(x), let y = numeric(y) else { return .unknown }
        switch BOMDocument.compareVersions(x, y) {
        case ..<0: return .up
        case 1...: return .down
        default: return .unknown
        }
    }

    static func numeric(_ v: String?) -> String? {
        guard var v else { return nil }
        if v.hasPrefix("v") || v.hasPrefix("V") { v.removeFirst() }
        return BOMDocument.isDottedDecimal(v) ? v : nil
    }

    static func precedes(_ x: String?, _ y: String?) -> Bool {
        if let nx = numeric(x), let ny = numeric(y) { return BOMDocument.compareVersions(nx, ny) < 0 }
        return (x ?? "") < (y ?? "")
    }

    static func facts(_ doc: BOMDocument) -> Facts {
        let packages = doc.components.filter { $0.type != "file" }
        var ecosystems: [String: Int] = [:]
        for c in packages { if let t = c.packageURL?.type { ecosystems[t, default: 0] += 1 } }
        return Facts(packages: packages.count, files: doc.components.count - packages.count,
                     withPurl: packages.filter { $0.packageURL != nil }.count,
                     withVersion: packages.filter { version($0) != nil }.count,
                     withLicence: packages.filter { !$0.licenses.isEmpty }.count,
                     withHash: packages.filter { !$0.hashes.isEmpty }.count,
                     withSupplier: packages.filter { $0.supplierName != nil }.count,
                     ecosystems: ecosystems)
    }
}
