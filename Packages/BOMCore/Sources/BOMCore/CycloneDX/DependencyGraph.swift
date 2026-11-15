/// The `dependencies` section as a graph from the subject (the product).
/// An SBOM without a `dependencies` array has no graph: `init` returns nil, so
/// views say so rather than drawing an empty chart.
public struct DependencyGraph: Sendable {
    /// The subject's bom-ref, or nil when the subject has none.
    public let root: String?
    private let edges: [String: [String]]
    private let reverse: [String: [String]]
    private let entries: [String: NodeID]
    private let depths: [String: Int]
    private let parents: [String: String]
    /// Component bom-refs (subject excluded) not reached from the subject, document order.
    public let unreachable: [String]

    public init?(_ bom: CycloneDXDocument) {
        let tree = bom.tree
        guard let list = tree.member(bom.root, "dependencies"), tree.kind(list) == .array else { return nil }
        var edges: [String: [String]] = [:], reverse: [String: [String]] = [:], entries: [String: NodeID] = [:]
        for e in tree.objectElements(list) {
            guard let ref = tree.memberString(e, "ref") else { continue }
            if entries[ref] == nil { entries[ref] = e }
            let targets = tree.elements(tree.member(e, "dependsOn")).compactMap { tree.string($0) }
            edges[ref, default: []].append(contentsOf: targets)
            for t in targets where !(reverse[t]?.contains(ref) ?? false) { reverse[t, default: []].append(ref) }
        }
        self.edges = edges
        self.reverse = reverse
        self.entries = entries
        root = bom.subject?.bomRef

        var depths: [String: Int] = [:], parents: [String: String] = [:]
        if let root {
            depths[root] = 0
            var queue = [root], head = 0
            while head < queue.count {
                let n = queue[head]; head += 1
                for m in edges[n] ?? [] where depths[m] == nil {
                    depths[m] = depths[n]! + 1
                    parents[m] = n
                    queue.append(m)
                }
            }
        }
        self.depths = depths
        self.parents = parents
        unreachable = bom.components.compactMap(\.bomRef).filter { depths[$0] == nil }
    }

    /// The subject's direct dependencies, document order.
    public var direct: [String] { root.flatMap { edges[$0] } ?? [] }

    /// Steps from the subject; nil when unreachable.
    public func depth(_ bomRef: String) -> Int? { depths[bomRef] }

    /// The shortest path from the subject to `bomRef`, both included.
    public func path(to bomRef: String) -> [String]? {
        guard depths[bomRef] != nil else { return nil }
        var out = [bomRef]
        while let p = parents[out.last!] { out.append(p) }
        return out.reversed()
    }

    /// Refs whose entry lists `bomRef` in `dependsOn`, document order.
    public func usedBy(_ bomRef: String) -> [String] { reverse[bomRef] ?? [] }

    /// Depth → number of reachable refs at that depth (the subject excluded).
    public var depthHistogram: [Int: Int] {
        var h: [Int: Int] = [:]
        for (ref, d) in depths where ref != root { h[d, default: 0] += 1 }
        return h
    }

    /// The `dependencies[]` object for `bomRef`.
    public func entry(_ bomRef: String) -> NodeID? { entries[bomRef] }

    /// Whether `bomRef` has its own entry in `dependencies`.
    public func hasEntry(_ bomRef: String) -> Bool { entries[bomRef] != nil }
}
