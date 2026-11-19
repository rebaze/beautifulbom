import Testing
@testable import BOMCore

/// SPDX 3.0 JSON-LD (`@graph`) read into the same model (docs/design-spdx.md).
@Suite struct SPDX3DocumentTests {
    let shop = BOMDocument.recognize(fixtureTree("synthetic/shop-3.0.spdx.json"))!

    @Test func recognised() {
        #expect(shop.format == .spdx)
        #expect(shop.specVersion.value == "3.0.1")
        #expect(shop.timestamp?.value == "2026-11-18T09:30:00Z")
        #expect(shop.tools.map(\.name) == ["example-scanner"])
        #expect(shop.tools.map(\.version) == ["2.1.0"])
        #expect(shop.manufacturerName == "Acme Devices GmbH")
    }

    @Test func subjectAndPackages() {
        #expect(shop.subject?.name == "acme-shop")
        #expect(shop.subject?.type == "application")
        #expect(shop.subject?.supplierName == "Acme Devices GmbH")
        #expect(shop.subject?.hashes.map(\.alg) == ["SHA-512"])
        #expect(shop.subject?.externalReferences.map(\.type) == ["distribution"])
        #expect(shop.components.map(\.name) == ["express", "body-parser"])
    }

    @Test func packageFields() {
        let e = shop.component(bomRef: "https://example.com/spdx/express")!
        #expect(e.version == "4.21.2" && e.purl == "pkg:npm/express@4.21.2")
        #expect(e.description == "Fast, unopinionated, minimalist web framework")
        #expect(e.hashes.map(\.alg) == ["SHA-256"])
        #expect(e.externalReferences.map(\.type) == ["website"])
        // Concluded wins over declared.
        #expect(e.licenses.map(\.kind) == [.id("MIT")])
        #expect(shop.component(bomRef: "https://example.com/spdx/body-parser")!.licenses.isEmpty)
    }

    @Test func graph() {
        let g = DependencyGraph(shop)!
        #expect(g.direct == ["https://example.com/spdx/express"])
        #expect(g.depth("https://example.com/spdx/body-parser") == 2)
        #expect(Composition(shop, graph: g).reach == .reached(direct: 1, indirect: 1))
    }

    @Test func keys() {
        #expect(shop.key("version") == "software_packageVersion")
        #expect(shop.key("hashes") == "verifiedUsing")
        #expect(shop.metadataKey("timestamp") == "created")
    }

    /// cdxgen 12.9.2: licences only in its CycloneDX extension, so none in SPDX terms.
    @Test func cdxgen() {
        let doc = BOMDocument.recognize(fixtureTree("tools/partner-portal.cdxgen.spdx.json"))!
        #expect(doc.specVersion.value == "3.0.1")
        #expect(doc.subject?.name == "partner-portal-backend")
        #expect(doc.components.count == 6)
        #expect(doc.components.allSatisfy { $0.licenses.isEmpty })
        let comp = Composition(doc, graph: DependencyGraph(doc))
        #expect(comp.reach == .reached(direct: 3, indirect: 3))
    }

    @Test func notSPDX3() {
        #expect(bom(#"{"@context":"https://example.com/other","@graph":[]}"#) == nil)
    }
}
