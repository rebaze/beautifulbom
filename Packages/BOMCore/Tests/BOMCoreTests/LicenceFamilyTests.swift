import Testing
@testable import BOMCore

@Suite struct LicenceFamilyTests {
    @Test func identifiers() {
        #expect(LicenceFamily.of("MIT") == .permissive)
        #expect(LicenceFamily.of("Apache-2.0") == .permissive)
        #expect(LicenceFamily.of("bsd-3-clause") == .permissive)
        #expect(LicenceFamily.of("LGPL-2.1-only") == .weakCopyleft)
        #expect(LicenceFamily.of("MPL-2.0") == .weakCopyleft)
        #expect(LicenceFamily.of("GPL-3.0-or-later") == .strongCopyleft)
        #expect(LicenceFamily.of("GPL-2.0+") == .strongCopyleft)
        #expect(LicenceFamily.of("AGPL-3.0") == .strongCopyleft)
        #expect(LicenceFamily.of("LicenseRef-acme") == .unclassified)
        #expect(LicenceFamily.of("Some proprietary terms") == .unclassified)
    }

    @Test func expressions() {
        #expect(LicenceFamily.of("MIT OR GPL-3.0-only") == .permissive)
        #expect(LicenceFamily.of("MIT AND GPL-3.0-only") == .strongCopyleft)
        #expect(LicenceFamily.of("(MIT AND LGPL-2.1-only) OR GPL-2.0-only") == .weakCopyleft)
        #expect(LicenceFamily.of("GPL-2.0-only WITH Classpath-exception-2.0") == .weakCopyleft)
        #expect(LicenceFamily.of("GPL-2.0-only WITH Autoconf-exception-2.0") == .strongCopyleft)
        #expect(LicenceFamily.of("MIT OR LicenseRef-x") == .permissive)
        #expect(LicenceFamily.of("MIT AND LicenseRef-x") == .unclassified)
        #expect(LicenceFamily.of("GPL-3.0-only AND LicenseRef-x") == .strongCopyleft)
        #expect(LicenceFamily.of("(MIT") == .unclassified)
    }

    @Test func componentsCombineTheirEntriesAsAnd() {
        let doc = bom(#"""
        {"bomFormat":"CycloneDX","specVersion":"1.6","components":[
          {"name":"a","licenses":[{"license":{"id":"MIT"}},{"license":{"id":"GPL-2.0-only"}}]},
          {"name":"b","licenses":[{"expression":"MIT OR Apache-2.0"}]},
          {"name":"c"},
          {"name":"d","licenses":[{"license":{"name":"MIT"}}]}]}
        """#)!
        #expect(doc.components.map { LicenceFamily.of($0) } == [.strongCopyleft, .permissive, .none, .permissive])
    }

    @Test func laravelIsAllPermissive() {
        let a = WorkshopAnalysis.analyse(fixtureTree(laravelPath))!
        #expect(a.composition.families.map(\.label) == ["permissive"])
        #expect(a.composition.families.first?.count == 62)
        #expect(ComponentFilter(family: .permissive).apply(a).count == 62)
        #expect(ComponentFilter(family: .strongCopyleft).apply(a).isEmpty)
    }

    @Test func familiesKeepTheirOrderAndSkipEmptyOnes() {
        let doc = bom(#"""
        {"bomFormat":"CycloneDX","specVersion":"1.6","components":[
          {"name":"a","licenses":[{"license":{"id":"GPL-3.0-only"}}]},
          {"name":"b"},{"name":"c","licenses":[{"license":{"id":"MIT"}}]},{"name":"d","licenses":[{"license":{"id":"MIT"}}]}]}
        """#)!
        let c = Composition(doc, graph: nil)
        #expect(c.families.map(\.label) == ["permissive", "strongCopyleft", "none"])
        #expect(c.families.map(\.count) == [2, 1, 1])
        #expect(c.families.last?.unknown == true)
    }

    @Test func completenessSummaryPerPart() {
        let a = WorkshopAnalysis.analyse(fixtureTree(laravelPath))!
        let s = Dictionary(uniqueKeysWithValues: a.report.sections.map { ($0.scope, ($0.present, $0.evaluated)) })
        // The SBOM 1 of 4: the format version is judged on the file (1.4), unlike rio, which uplifts it first.
        #expect(s[.sbom]! == (1, 4))
        #expect(s[.subject]! == (3, 11))
        #expect(s[.components]! == (3, 11))
    }
}
