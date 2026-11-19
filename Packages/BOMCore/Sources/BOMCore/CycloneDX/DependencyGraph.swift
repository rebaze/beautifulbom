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
    private let children: [String: [String]]
    /// Reachable refs in breadth-first order from the subject, the subject first.
    public let order: [String]
    /// Component bom-refs (subject excluded) not reached from the subject, document order.
    public let unreachable: [String]
    /// Components (subject excluded) that appear in the dependency data, as a ref or a target.
    public let linkedCount: Int

    /// CycloneDX: `dependencies`. SPDX: the dependency relationships (`SPDXEdges`). Nil without any.
    public init?(_ bom: BOMDocument) {
        let tree = bom.tree
        var edges: [String: [String]] = [:], reverse: [String: [String]] = [:], entries: [String: NodeID] = [:]
        switch bom.format {
        case .spdx:
            guard let spdx = bom.spdxEdges else { return nil }
            edges = spdx.edges
            entries = spdx.entries
            for (ref, targets) in spdx.edges.sorted(by: { (entries[$0.key]?.index ?? 0) < (entries[$1.key]?.index ?? 0) }) {
                for t in targets where !(reverse[t]?.contains(ref) ?? false) { reverse[t, default: []].append(ref) }
            }
        case .cyclonedx:
            guard let list = tree.member(bom.root, "dependencies"), tree.kind(list) == .array else { return nil }
            for e in tree.objectElements(list) {
                guard let ref = tree.memberString(e, "ref") else { continue }
                if entries[ref] == nil { entries[ref] = e }
                let targets = tree.elements(tree.member(e, "dependsOn")).compactMap { tree.string($0) }
                edges[ref, default: []].append(contentsOf: targets)
                for t in targets where !(reverse[t]?.contains(ref) ?? false) { reverse[t, default: []].append(ref) }
            }
        }
        self.edges = edges
        self.reverse = reverse
        self.entries = entries
        root = bom.subject?.bomRef

        var depths: [String: Int] = [:], parents: [String: String] = [:], children: [String: [String]] = [:]
        var queue: [String] = []
        if let root {
            depths[root] = 0
            queue = [root]
            var head = 0
            while head < queue.count {
                let n = queue[head]; head += 1
                for m in edges[n] ?? [] where depths[m] == nil {
                    depths[m] = depths[n]! + 1
                    parents[m] = n
                    children[n, default: []].append(m)
                    queue.append(m)
                }
            }
        }
        self.depths = depths
        self.parents = parents
        self.children = children
        order = queue
        unreachable = bom.components.compactMap(\.bomRef).filter { depths[$0] == nil }
        linkedCount = Set(bom.components.compactMap(\.bomRef)).filter { edges[$0] != nil || reverse[$0] != nil }.count
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

    /// The refs `bomRef` reaches first (its children on the shortest-path tree), document order.
    public func treeChildren(_ bomRef: String) -> [String] { children[bomRef] ?? [] }

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
