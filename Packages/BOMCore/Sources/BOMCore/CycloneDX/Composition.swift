import Foundation

/// What the product is made of: components grouped by vendor, licence and
/// ecosystem, and how deep the dependencies go.
public struct Composition: Sendable {
    public struct Slice: Sendable, Hashable {
        /// Empty for the unknown slice and the "others" bucket.
        public let label: String
        public let unknown: Bool
        public var count: Int { components.count }
        /// Indexes into `CycloneDXDocument.components`, document order.
        public let components: [Int]
    }

    public let vendors: [Slice]
    public let licenses: [Slice]
    public let ecosystems: [Slice]
    /// Components by licence family (`LicenceFamily.rawValue` as label), in the enum's order;
    /// empty families left out. "none" is the unknown slice.
    public let families: [Slice]
    /// Depth → reachable components; nil without dependency data.
    public let depthHistogram: [Int: Int]?
    public let directCount: Int?
    public let indirectCount: Int?

    public init(_ bom: CycloneDXDocument, graph: DependencyGraph?) {
        var vendors: [String?: [Int]] = [:], licenses: [String?: [Int]] = [:], ecosystems: [String?: [Int]] = [:]
        var families: [LicenceFamily: [Int]] = [:]
        for (i, c) in bom.components.enumerated() {
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
        if let graph, graph.root != nil {
            let histogram = graph.depthHistogram
            depthHistogram = histogram
            directCount = graph.direct.count
            indirectCount = histogram.values.reduce(0, +) - graph.direct.count
        } else {
            depthHistogram = nil
            directCount = nil
            indirectCount = nil
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
