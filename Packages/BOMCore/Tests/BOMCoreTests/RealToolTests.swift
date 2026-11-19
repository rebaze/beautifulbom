import Testing
@testable import BOMCore

/// Shapes the common generators write (Syft, Trivy, cdxgen), reduced to what each test needs.
@Suite struct RealToolTests {
    // MARK: How far the dependency data reaches

    @Test func reachWithoutDependencies() {
        let doc = bom(#"{"bomFormat":"CycloneDX","specVersion":"1.7","metadata":{"component":{"bom-ref":"p","name":"p"}},"components":[{"bom-ref":"a","name":"a"}]}"#)!
        #expect(Composition(doc, graph: DependencyGraph(doc)).reach == .noData)
    }

    @Test func reachWithoutProductRef() {
        let doc = bom(#"""
        {"bomFormat":"CycloneDX","specVersion":"1.7","metadata":{"component":{"name":"p"}},
         "components":[{"bom-ref":"a","name":"a"}],"dependencies":[{"ref":"a","dependsOn":[]}]}
        """#)!
        #expect(Composition(doc, graph: DependencyGraph(doc)).reach == .noProductRef)
    }

    /// Syft: the product has a bom-ref, but no entry starts at it; components link among themselves.
    @Test func reachNotFromProduct() {
        let doc = bom(#"""
        {"bomFormat":"CycloneDX","specVersion":"1.7","metadata":{"component":{"bom-ref":"p","name":".","type":"file"}},
         "components":[{"bom-ref":"a","name":"a"},{"bom-ref":"b","name":"b"}],
         "dependencies":[{"ref":"a","dependsOn":["b"]}]}
        """#)!
        let c = Composition(doc, graph: DependencyGraph(doc))
        #expect(c.reach == .notFromProduct(linked: 2))
        #expect(c.directCount == nil)
        #expect(c.depthHistogram == nil)
    }

    @Test func reachFromProduct() {
        let doc = bom(#"""
        {"bomFormat":"CycloneDX","specVersion":"1.6","metadata":{"component":{"bom-ref":"p","name":"p"}},
         "components":[{"bom-ref":"a","name":"a"},{"bom-ref":"b","name":"b"}],
         "dependencies":[{"ref":"p","dependsOn":["a"]},{"ref":"a","dependsOn":["b"]}]}
        """#)!
        let c = Composition(doc, graph: DependencyGraph(doc))
        #expect(c.reach == .reached(direct: 1, indirect: 1))
        #expect(c.directCount == 1 && c.indirectCount == 1)
    }

    // MARK: Files are not packages

    /// Syft on a container image lists every file as a component of type "file".
    @Test func filesCountedApart() {
        let doc = bom(#"""
        {"bomFormat":"CycloneDX","specVersion":"1.7","metadata":{"component":{"bom-ref":"p","name":"python","type":"container"}},
         "components":[
           {"bom-ref":"a","type":"library","name":"bash","purl":"pkg:deb/debian/bash@5.2","licenses":[{"license":{"id":"GPL-3.0-or-later"}}]},
           {"bom-ref":"f1","type":"file","name":"/usr/bin/bash"},
           {"bom-ref":"f2","type":"file","name":"/etc/passwd"}]}
        """#)!
        let c = Composition(doc, graph: DependencyGraph(doc))
        #expect(c.files == [1, 2])
        #expect(c.packageCount == 1)
        #expect(c.vendors.map(\.count).reduce(0, +) == 1)
        #expect(c.licenses.map(\.count).reduce(0, +) == 1)
        #expect(c.ecosystems.map(\.label) == ["deb"])
        #expect(c.families.map(\.count).reduce(0, +) == 1)
    }

    @Test func noFilesNoChange() {
        let doc = bom(#"{"bomFormat":"CycloneDX","specVersion":"1.6","components":[{"name":"a"},{"name":"b"}]}"#)!
        let c = Composition(doc, graph: nil)
        #expect(c.files.isEmpty)
        #expect(c.packageCount == 2)
    }
}

@Suite struct ProductTitleTests {
    @Test func plainName() {
        let t = ProductTitle("juice-shop")
        #expect(t.title == "juice-shop" && t.digest == nil)
    }

    @Test func directoryScanSaysNothing() {
        for n in [nil, "", " ", ".", "./", "/"] as [String?] { #expect(ProductTitle(n).title == nil) }
    }

    @Test func imageDigestMovesToSubtitle() {
        let t = ProductTitle("python:3.13-slim@sha256:e48f59cdba69a3cbd9ed2cf0f348d90d45a8d350d98134cf1070bc106ee9ed90")
        #expect(t.title == "python:3.13-slim")
        #expect(t.digest == "sha256:e48f59cdba69…")
    }
}
