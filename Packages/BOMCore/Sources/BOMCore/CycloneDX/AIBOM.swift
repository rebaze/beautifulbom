/// An AI bill of materials: a CycloneDX BOM about a machine-learning model. The model, its family
/// (base models under `pedigree.ancestors`), its training data (`modelCard` datasets, inline or as
/// `data` components) and what the file leaves out. Presence and form only, as for SBOMs.
public struct AIBOMAnalysis: Sendable {
    public struct Dataset: Sendable, Hashable {
        public let name: String
        /// The `data` component the model card refers to; nil when the dataset is only named inline.
        public let component: Component?
        /// The element in `modelCard.modelParameters.datasets`.
        public let node: NodeID
        public let url: String?
        /// The `ref` when the model card refers to a component by bom-ref.
        public let ref: String?
    }

    public struct Model: Sendable, Hashable {
        public let component: Component
        public let task: String?
        public let architecture: String?
        public let datasets: [Dataset]
        public let ancestors: [Model]
        public let parameters: Int?
        public let contextLength: Int?
        public let fileSize: Int?
        public let limitations: [String]
        public let useCases: [String]
        /// The model card, when present.
        public let modelCard: NodeID?
    }

    public struct Gap: Sendable, Hashable {
        public enum Kind: Sendable, Hashable {
            /// `metadata.component` describes something else (named), not the model.
            case subjectIsNotTheModel(String)
            case noLicence
            case noAncestors
            case noDatasets
            /// A dataset named inline: no licence, no version of its own ("" when unnamed).
            case datasetNamedOnly(String)
            /// A dataset reference (`ref`) that matches no component.
            case datasetRefMissing(String)
            case noHash
            /// A base model (named) states no training data.
            case ancestorWithoutDatasets(String)
        }
        public let kind: Kind
        public let evidence: Evidence
    }

    public let model: Model
    public let gaps: [Gap]

    /// Generations on the family tree, the model included.
    public var generations: Int { Self.depth(model) }

    static func depth(_ m: Model) -> Int { 1 + (m.ancestors.map(depth).max() ?? 0) }

    /// Nil unless the BOM is about a model: its subject is one, or every component is a model or data.
    public static func analyse(_ bom: BOMDocument) -> AIBOMAnalysis? {
        let tree = bom.tree
        let entry: Component
        if let s = bom.subject, s.type == "machine-learning-model" {
            entry = s
        } else if bom.components.allSatisfy({ $0.type == "machine-learning-model" || $0.type == "data" }),
                  let first = bom.components.first(where: { $0.type == "machine-learning-model" }) {
            entry = first
        } else {
            return nil
        }
        let model = read(entry, bom)
        var gaps: [Gap] = []
        if let s = bom.subject, s.entry != entry.entry {
            gaps.append(Gap(kind: .subjectIsNotTheModel(s.name ?? s.path), evidence: .located(s.entry)))
        }
        if entry.licenses.isEmpty { gaps.append(Gap(kind: .noLicence, evidence: tree.evidence(entry.entry, "licenses"))) }
        if model.ancestors.isEmpty {
            let pedigree = tree.member(entry.entry, "pedigree")
            gaps.append(Gap(kind: .noAncestors, evidence: pedigree.map { tree.evidence($0, "ancestors") } ?? tree.evidence(entry.entry, "pedigree")))
        }
        if model.datasets.isEmpty {
            gaps.append(Gap(kind: .noDatasets, evidence: datasetsEvidence(model, tree)))
        }
        for d in model.datasets where d.component == nil {
            gaps.append(Gap(kind: d.ref.map { .datasetRefMissing($0) } ?? .datasetNamedOnly(d.name), evidence: .located(d.node)))
        }
        if entry.hashes.isEmpty { gaps.append(Gap(kind: .noHash, evidence: tree.evidence(entry.entry, "hashes"))) }
        func ancestorGaps(_ m: Model) {
            for a in m.ancestors {
                if a.datasets.isEmpty {
                    gaps.append(Gap(kind: .ancestorWithoutDatasets(a.component.displayName), evidence: datasetsEvidence(a, tree)))
                }
                ancestorGaps(a)
            }
        }
        ancestorGaps(model)
        return AIBOMAnalysis(model: model, gaps: gaps)
    }

    private static func datasetsEvidence(_ m: Model, _ tree: JSONTree) -> Evidence {
        guard let card = m.modelCard else { return tree.evidence(m.component.entry, "modelCard") }
        guard let params = tree.member(card, "modelParameters") else { return tree.evidence(card, "modelParameters") }
        return tree.evidence(params, "datasets")
    }

    private static func read(_ c: Component, _ bom: BOMDocument, depth: Int = 0) -> Model {
        let tree = bom.tree
        let card = tree.member(c.entry, "modelCard").flatMap { tree.kind($0) == .object ? $0 : nil }
        let params = card.flatMap { tree.member($0, "modelParameters") }
        let considerations = card.flatMap { tree.member($0, "considerations") }
        let datasets: [Dataset] = tree.objectElements(params.flatMap { tree.member($0, "datasets") }).compactMap { e in
            if let ref = tree.memberString(e, "ref") {
                let comp = bom.component(bomRef: ref)
                return Dataset(name: comp?.displayName ?? ref, component: comp, node: e,
                               url: comp?.externalReferences.first?.url, ref: ref)
            }
            // The name is optional in the schema: an unnamed dataset still counts, named "".
            return Dataset(name: tree.memberString(e, "name") ?? "", component: nil, node: e,
                           url: tree.member(e, "contents").flatMap { tree.memberString($0, "url") }, ref: nil)
        }
        // Base models; deep chains are cut at 16 generations.
        let ancestors: [Model] = depth >= 16 ? [] : tree.objectElements(tree.member(c.entry, "pedigree").flatMap { tree.member($0, "ancestors") })
            .enumerated().map { i, n in
                read(Component(entry: n, path: c.path + ".pedigree.ancestors[\(i)]", isSubject: false, tree: tree), bom, depth: depth + 1)
            }
        var props: [(String, String)] = c.properties.compactMap { p in p.name.flatMap { n in p.value.map { (n, $0) } } }
        for e in tree.objectElements(card.flatMap { tree.member($0, "properties") }) {
            if let n = tree.memberString(e, "name"), let v = tree.memberString(e, "value") { props.append((n, v)) }
        }
        func number(_ suffixes: [String]) -> Int? {
            props.first { p in suffixes.contains { p.0.hasSuffix($0) } }.flatMap { Int($0.1) }
        }
        func strings(_ key: String) -> [String] {
            tree.elements(considerations.flatMap { tree.member($0, key) }).compactMap { tree.string($0) }
        }
        return Model(component: c,
                     task: params.flatMap { tree.memberString($0, "task") },
                     architecture: params.flatMap { tree.memberString($0, "modelArchitecture") ?? tree.memberString($0, "architectureFamily") },
                     datasets: datasets, ancestors: ancestors,
                     parameters: number(["total_parameters", ":parameters"]),
                     contextLength: number(["contextLength"]),
                     fileSize: number(["modelFileSize"]),
                     limitations: strings("technicalLimitations"), useCases: strings("useCases"),
                     modelCard: card)
    }
}
