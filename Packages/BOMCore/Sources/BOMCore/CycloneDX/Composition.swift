import Foundation

/// What the product is made of: components grouped by vendor, licence and
/// ecosystem, and how deep the dependencies go.
public struct Composition: Sendable {
    public struct Slice: Sendable, Hashable {
        /// Empty for the unknown slice and the "others" bucket.
        public let label: String
        public let unknown: Bool
        public var count: Int { components.count }
        /// Indexes into `BOMDocument.components`, document order.
        public let components: [Int]
    }

    public let vendors: [Slice]
    public let licenses: [Slice]
    public let ecosystems: [Slice]
    /// Components by licence family (`LicenceFamily.rawValue` as label), in the enum's order;
    /// empty families left out. "none" is the unknown slice.
    public let families: [Slice]
    /// How far the dependency data reaches from the product.
    public enum Reach: Sendable, Hashable {
        /// No `dependencies` array.
        case noData
        /// Dependency data, but the product has no bom-ref to start from.
        case noProductRef
        /// The product has a bom-ref, but no entry starts at it (Syft); `linked` components
        /// appear in the dependency data among themselves.
        case notFromProduct(linked: Int)
        case reached(direct: Int, indirect: Int)
    }

    public let reach: Reach
    /// Depth → reachable components; nil unless the data reaches from the product.
    public let depthHistogram: [Int: Int]?
    public let directCount: Int?
    public let indirectCount: Int?
    /// Components of type "file" (Syft lists every file of an image), document order. They are
    /// counted here and kept out of the vendor, licence, ecosystem and family slices.
    public let files: [Int]
    /// Components that are not files.
    public let packageCount: Int

    public init(_ bom: BOMDocument, graph: DependencyGraph?) {
        var vendors: [String?: [Int]] = [:], licenses: [String?: [Int]] = [:], ecosystems: [String?: [Int]] = [:]
        var families: [LicenceFamily: [Int]] = [:]
        var files: [Int] = []
        for (i, c) in bom.components.enumerated() {
            if c.type == "file" { files.append(i); continue }
            families[LicenceFamily.of(c), default: []].append(i)
            vendors[Self.vendor(of: c), default: []].append(i)
            ecosystems[Self.nonEmpty(c.packageURL?.type), default: []].append(i)
            let labels = Array(Set(c.licenses.map(\.label)))
            if labels.isEmpty { licenses[nil, default: []].append(i) }
            for l in labels { licenses[l, default: []].append(i) }
        }
        self.vendors = Self.slices(vendors)
        self.licenses = Self.slices(licenses)
        self.ecosystems = Self.slices(ecosystems)
        self.families = LicenceFamily.allCases.compactMap { f in
            families[f].map { Slice(label: f.rawValue, unknown: f == .none, components: $0) }
        }
        self.files = files
        packageCount = bom.components.count - files.count
        if let graph, graph.root != nil, !graph.direct.isEmpty {
            let histogram = graph.depthHistogram
            depthHistogram = histogram
            directCount = graph.direct.count
            indirectCount = histogram.values.reduce(0, +) - graph.direct.count
            reach = .reached(direct: directCount!, indirect: indirectCount!)
        } else {
            depthHistogram = nil
            directCount = nil
            indirectCount = nil
            if let graph {
                reach = graph.root == nil ? .noProductRef : .notFromProduct(linked: graph.linkedCount)
            } else {
                reach = .noData
            }
        }
    }

    /// The `keep` largest slices and one bucket with the rest (nil when nothing is left).
    public func top(_ slices: [Slice], keep: Int) -> (named: [Slice], others: Slice?) {
        guard slices.count > keep else { return (slices, nil) }
        let rest = Set(slices[keep...].flatMap(\.components)).sorted()
        return (Array(slices[..<keep]), Slice(label: "", unknown: false, components: rest))
    }

    /// The vendor a component is grouped under: its group, else its purl namespace.
    public static func vendor(of c: Component) -> String? {
        nonEmpty(c.group) ?? nonEmpty(c.packageURL?.namespace)
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return s
    }

    private static func slices(_ groups: [String?: [Int]]) -> [Slice] {
        groups.map { Slice(label: $0.key ?? "", unknown: $0.key == nil, components: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.label < $1.label }
    }
}
