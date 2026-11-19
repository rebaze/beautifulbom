import Testing
@testable import BOMCore

/// SPDX 2.3 JSON read into the same model as CycloneDX (docs/design-spdx.md).
@Suite struct SPDXDocumentTests {
    let shop = BOMDocument.recognize(fixtureTree("synthetic/shop-2.3.spdx.json"))!

    func c(_ ref: String) -> Component { shop.component(bomRef: ref)! }

    @Test func recognisedAsSPDX() {
        #expect(shop.format == .spdx)
        #expect(shop.specVersion.value == "2.3")
        #expect(shop.tree.string(shop.specVersion.node) == "SPDX-2.3")
    }

    @Test func creationInfo() {
        #expect(shop.timestamp?.value == "2026-11-18T09:30:00Z")
        #expect(shop.tools.map(\.name) == ["example-scanner"])
        #expect(shop.tools.map(\.version) == ["2.1.0"])
        #expect(shop.manufacturerName == "Acme Devices GmbH")
    }

    @Test func subjectFromDescribes() {
        let s = shop.subject!
        #expect(s.bomRef == "SPDXRef-Package-shop")
        #expect(s.name == "acme-shop" && s.version == "1.4.0" && s.type == "application")
        #expect(s.supplierName == "Acme Devices GmbH")
        #expect(s.hashes.map(\.alg) == ["SHA-512"])
        #expect(s.externalReferences.map(\.type) == ["distribution"])
        #expect(s.licenses.map(\.label) == ["LicenseRef-Acme-Proprietary"])
        #expect(s.isSubject)
    }

    @Test func packagesAreComponents() {
        #expect(shop.components.map(\.name) == ["express", "body-parser", "bytes", "@types/node", "left-alone"])
        #expect(shop.components.map(\.path) == ["packages[1]", "packages[2]", "packages[3]", "packages[4]", "packages[5]"])
    }

    @Test func packageFields() {
        let e = c("SPDXRef-Package-express")
        #expect(e.version == "4.21.2" && e.type == "library")
        #expect(e.purl == "pkg:npm/express@4.21.2" && e.packageURL?.type == "npm")
        #expect(e.author == "TJ Holowaychuk")
        #expect(e.description == "Fast, unopinionated, minimalist web framework")
        #expect(e.hashes.map(\.alg) == ["SHA-256"])
        #expect(e.externalReferences.map(\.type) == ["distribution", "website"])
        #expect(c("SPDXRef-Package-body-parser").externalReferences.isEmpty)
    }

    /// Concluded wins; NOASSERTION falls back to declared; none at all is no licence.
    @Test func licences() {
        #expect(c("SPDXRef-Package-express").licenses.map(\.kind) == [.id("MIT")])
        #expect(c("SPDXRef-Package-body-parser").licenses.map(\.kind) == [.id("MIT")])
        #expect(c("SPDXRef-Package-bytes").licenses.isEmpty)
        #expect(c("SPDXRef-Package-types-node").licenses.map(\.kind) == [.expression("MIT OR Apache-2.0")])
        #expect(c("SPDXRef-Package-left-alone").licenses.isEmpty)
    }

    @Test func vendorFromPurlNamespace() {
        #expect(Composition.vendor(of: c("SPDXRef-Package-types-node")) == "@types")
    }

    // MARK: Dependencies

    @Test func graphFromRelationships() {
        let g = DependencyGraph(shop)!
        #expect(g.root == "SPDXRef-Package-shop")
        // CONTAINS counts for express (nothing depends on it), not for body-parser or bytes.
        #expect(g.direct == ["SPDXRef-Package-express", "SPDXRef-Package-types-node"])
        #expect(g.depth("SPDXRef-Package-body-parser") == 2)
        #expect(g.depth("SPDXRef-Package-bytes") == 3)
        #expect(g.unreachable == ["SPDXRef-Package-left-alone"])
        #expect(g.usedBy("SPDXRef-Package-bytes") == ["SPDXRef-Package-body-parser"])
        #expect(g.entry("SPDXRef-Package-express").map { shop.tree.memberString($0, "relationshipType") } == "DEPENDS_ON")
    }

    @Test func compositionReaches() {
        let comp = Composition(shop, graph: DependencyGraph(shop))
        #expect(comp.reach == .reached(direct: 2, indirect: 2))
    }

    @Test func noRelationshipsNoGraph() {
        let doc = bom(#"{"spdxVersion":"SPDX-2.3","SPDXID":"SPDXRef-DOCUMENT","packages":[{"SPDXID":"SPDXRef-a","name":"a"}]}"#)!
        #expect(DependencyGraph(doc) == nil)
        #expect(doc.subject == nil)
        #expect(doc.components.map(\.name) == ["a"])
    }

    @Test func notSPDXTwo() {
        #expect(bom(#"{"spdxVersion":"SPDX-1.2","packages":[]}"#) == nil)
        #expect(bom(#"{"spdxVersion":"2.3","packages":[]}"#) == nil)
        #expect(bom(#"{"packages":[]}"#) == nil)
    }

    // MARK: Evidence keys

    @Test func keysForSPDX() {
        #expect(shop.key("version") == "versionInfo")
        #expect(shop.key("hashes") == "checksums")
        #expect(shop.metadataKey("timestamp") == "created")
        #expect(shop.metadataKey("manufacturer") == "creators")
        #expect(shop.rootKey("dependencies") == "relationships")
        #expect(shop.key("name") == "name")
    }

    // MARK: As the tools write it

    @Test func trivy() {
        let doc = BOMDocument.recognize(fixtureTree("tools/partner-portal.trivy.spdx.json"))!
        #expect(doc.tools.map(\.name) == ["trivy"])
        #expect(doc.subject?.type == "source")
        let g = DependencyGraph(doc)!
        // filesystem → application (pom.xml) → the project → its libraries
        #expect(Composition(doc, graph: g).reach != .noData)
        #expect(g.depthHistogram.values.reduce(0, +) == doc.components.count)
    }

    @Test func syft() {
        let doc = BOMDocument.recognize(fixtureTree("tools/partner-portal.syft.spdx.json"))!
        #expect(doc.tools.map(\.name) == ["syft"])
        #expect(doc.components.count == 5)
        #expect(doc.components.allSatisfy { $0.purl != nil || $0.name != nil })
        #expect(DependencyGraph(doc) != nil)
    }

    // MARK: The analysis

    @Test func analysisWithoutTRChecks() throws {
        let a = try #require(WorkshopAnalysis.analyse(fixtureTree("synthetic/shop-2.3.spdx.json")))
        #expect(a.bom.format == .spdx)
        #expect(a.profile == nil && a.report == nil && a.verdict == nil && a.ai == nil)
        #expect(a.map != nil)
        #expect(a.gapCount(component: 0) == 0 && a.ruleCount(component: 0) == 0)
    }
}
