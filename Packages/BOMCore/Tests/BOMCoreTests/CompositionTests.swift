import Testing
@testable import BOMCore

@Suite struct CompositionTests {
    static func composition(_ path: String) -> Composition {
        let doc = BOMDocument.recognize(fixtureTree(path))!
        return Composition(doc, graph: DependencyGraph(doc))
    }
    let laravel = composition(laravelPath)
    let cern = composition(cernPath)

    @Test func laravelVendors() {
        #expect(laravel.vendors.count == 24)
        #expect(laravel.vendors.prefix(5).map { "\($0.label) \($0.count)" } ==
            ["symfony 27", "psr 5", "guzzlehttp 3", "laravel 3", "league 3"])
    }

    @Test func laravelLicenses() {
        #expect(laravel.licenses.map { "\($0.label) \($0.count)" } == ["MIT 57", "BSD-3-Clause 4", "Apache-2.0 1"])
    }

    @Test func laravelEcosystems() {
        #expect(laravel.ecosystems.map { "\($0.label) \($0.count)" } == ["composer 62"])
        #expect(laravel.directCount == 1)
        #expect(laravel.indirectCount == 61)
        #expect(laravel.depthHistogram == [1: 1, 2: 5, 3: 30, 4: 21, 5: 4, 6: 1])
    }

    @Test func cernVendorsUnknown() {
        #expect(cern.vendors.count == 1)
        #expect(cern.vendors[0].unknown && cern.vendors[0].count == 43)
        #expect(cern.ecosystems.map { "\($0.label) \($0.count)" } == ["npm 43"])
        #expect(cern.depthHistogram == nil)
        #expect(cern.directCount == nil)
    }

    @Test func topKeepsOthers() {
        let (named, others) = laravel.top(laravel.vendors, keep: 5)
        #expect(named.count == 5)
        #expect(others?.count == 21)
        #expect(others?.components.count == 21)
        #expect(laravel.top(laravel.licenses, keep: 5).others == nil)
    }
}
