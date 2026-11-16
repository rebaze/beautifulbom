/// The layout of the map of the product: a sunburst over the shortest-path tree of the
/// dependency graph. The product is the centre; ring 1 holds its direct dependencies; each
/// further ring is one step further away. A slice's angle is its share of its parent's,
/// in proportion to the parts it stands for (itself and everything beneath it).
///
/// Slices narrower than `minFraction` of the circle are merged per parent into one group
/// (a lone narrow one stays itself), and nothing is drawn beneath a narrow slice or a group,
/// so large SBOMs stay drawable.
public struct DependencyMap: Sendable {
    public struct Slice: Sendable, Hashable {
        /// The part's bom-ref; nil for a group of merged parts.
        public let ref: String?
        /// 1 = chosen directly by the product.
        public let depth: Int
        /// Start and end as fractions of the circle, clockwise from the top.
        public let start: Double
        public let end: Double
        /// Index of the parent slice in `slices`; nil on ring 1.
        public let parent: Int?
        /// The parts it stands for: itself and everything beneath it (for a group, all of its members').
        public let weight: Int
        /// Parts merged into this slice; 0 for a single part.
        public let groupCount: Int
        /// The merged parts' refs (a group only).
        public let members: [String]

        public var isGroup: Bool { groupCount > 0 }
    }

    public static let defaultMinFraction = 0.004
    public static let defaultMaxDepth = 12

    /// Slices, ring by ring (ring 1 first), each ring in angle order.
    public let slices: [Slice]
    /// Rings drawn.
    public let rings: Int
    /// Reachable parts deeper than the last ring drawn.
    public let hiddenDeeper: Int
    /// How many steps from the product the deepest reachable part is, drawn or not.
    public let deepest: Int
    /// Reachable parts without a slice of their own: merged, beneath a narrow slice, or too deep.
    public let notDrawn: Int

    public init(_ graph: DependencyGraph, minFraction: Double = defaultMinFraction, maxDepth: Int = defaultMaxDepth) {
        guard let root = graph.root else {
            slices = []; rings = 0; hiddenDeeper = 0; deepest = 0; notDrawn = 0
            return
        }
        // Weights bottom-up over the breadth-first order: no recursion, so deep graphs are safe.
        var weight: [String: Int] = [:]
        for ref in graph.order.reversed() {
            weight[ref] = 1 + graph.treeChildren(ref).reduce(0) { $0 + (weight[$1] ?? 0) }
        }
        var out: [Slice] = []
        var frontier: [(ref: String, slice: Int?, start: Double, end: Double)] = [(root, nil, 0, 1)]
        var depth = 0
        while !frontier.isEmpty, depth < maxDepth {
            depth += 1
            var next: [(ref: String, slice: Int?, start: Double, end: Double)] = []
            for parent in frontier {
                let kids = graph.treeChildren(parent.ref)
                let total = kids.reduce(0) { $0 + weight[$1]! }
                guard total > 0 else { continue }
                let span = parent.end - parent.start
                var a = parent.start
                var small: [String] = [], smallWeight = 0, smallStart = 0.0
                func flushGroup() {
                    guard !small.isEmpty else { return }
                    let end = smallStart + span * Double(smallWeight) / Double(total)
                    if small.count == 1 {
                        out.append(Slice(ref: small[0], depth: depth, start: smallStart, end: end, parent: parent.slice,
                                         weight: smallWeight, groupCount: 0, members: []))
                    } else {
                        out.append(Slice(ref: nil, depth: depth, start: smallStart, end: end, parent: parent.slice,
                                         weight: smallWeight, groupCount: small.count, members: small))
                    }
                    small = []; smallWeight = 0
                }
                for kid in kids {
                    let w = weight[kid]!
                    let width = span * Double(w) / Double(total)
                    if width < minFraction {
                        if small.isEmpty { smallStart = a }
                        small.append(kid); smallWeight += w
                    } else {
                        flushGroup()
                        out.append(Slice(ref: kid, depth: depth, start: a, end: a + width, parent: parent.slice,
                                         weight: w, groupCount: 0, members: []))
                        next.append((kid, out.count - 1, a, a + width))
                    }
                    a += width
                }
                flushGroup()
            }
            frontier = next
        }
        slices = out
        rings = out.map(\.depth).max() ?? 0
        hiddenDeeper = graph.order.dropFirst().filter { (graph.depth($0) ?? 0) > maxDepth }.count
        deepest = graph.order.compactMap { graph.depth($0) }.max() ?? 0
        notDrawn = graph.order.count - 1 - out.filter { !$0.isGroup }.count
    }

    /// Slice indices from ring 1 down to `index`.
    public func path(to index: Int) -> [Int] {
        var out = [index]
        while let p = slices[out.last!].parent { out.append(p) }
        return out.reversed()
    }

    /// The slice on ring `depth` that covers `fraction` of the circle (0 at the top, clockwise).
    public func slice(atDepth depth: Int, fraction: Double) -> Int? {
        slices.indices.first { slices[$0].depth == depth && slices[$0].start <= fraction && fraction < slices[$0].end }
    }
}
