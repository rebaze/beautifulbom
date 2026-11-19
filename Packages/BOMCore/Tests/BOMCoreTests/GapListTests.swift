import Testing
@testable import BOMCore

/// The written list of TR-03183-2 gaps a client takes home (CSV and PDF).
@Suite struct GapListTests {
    let laravel = WorkshopAnalysis.analyse(fixtureTree(laravelPath))!

    @Test func oneEntryPerOffender() {
        let g = GapList(laravel)
        #expect(g.entries.count == laravel.profile!.offenders.count)
        #expect(!g.entries.isEmpty)
    }

    @Test func pointerToWhereTheFieldWouldBe() {
        let g = GapList(laravel)
        let ts = g.entries.first { $0.rule == RuleID(.sbom, .timestamp) }!
        #expect(ts.pointer == "/metadata/timestamp")
        #expect(ts.section == "§5.2.1")
        #expect(ts.component == nil)
    }

    @Test func componentEntries() {
        let g = GapList(laravel)
        let e = g.entries.first { $0.component != nil && $0.rule == RuleID(.components, .deployableHash) }!
        #expect(e.name != nil && e.version != nil && e.purl != nil && e.bomRef != nil)
        #expect(e.pointer.hasPrefix("/components/"))
    }

    @Test func groupedInRuleOrder() {
        let g = GapList(laravel)
        let order = laravel.profile!.evaluations.map(\.rule)
        let rules = g.byRule.map(\.rule)
        #expect(rules == order.filter { r in g.entries.contains { $0.rule == r } })
        #expect(g.byRule.map(\.entries.count).reduce(0, +) == g.entries.count)
    }

    @Test func noChecksNoGaps() {
        let spdx = WorkshopAnalysis.analyse(fixtureTree("synthetic/shop-2.3.spdx.json"))!
        #expect(GapList(spdx).entries.isEmpty)
        #expect(!GapList(spdx).checked)
        #expect(GapList(laravel).checked)
    }

    @Test func csv() {
        let g = GapList(laravel)
        let text = g.csv(header: ["Part", "Component", "Version", "Package URL", "bom-ref", "Field", "Section", "Rule", "JSON Pointer"]) {
            "\($0.requirement)"
        }
        let lines = text.split(separator: "\r\n", omittingEmptySubsequences: false)
        #expect(lines.first == "Part,Component,Version,Package URL,bom-ref,Field,Section,Rule,JSON Pointer")
        #expect(lines.count == g.entries.count + 2) // header, entries, final empty after the last CRLF
        #expect(lines.contains { $0.contains("sbom.timestamp") && $0.contains("/metadata/timestamp") })
    }

    @Test func csvQuotingAndFormulas() {
        #expect(GapList.field("plain") == "plain")
        #expect(GapList.field("a,b") == "\"a,b\"")
        #expect(GapList.field("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(GapList.field("two\nlines") == "\"two\nlines\"")
        // Untrusted text never starts a spreadsheet formula.
        #expect(GapList.field("=HYPERLINK(\"x\")") == "\"'=HYPERLINK(\"\"x\"\")\"")
        #expect(GapList.field("+1") == "'+1")
        #expect(GapList.field("@SUM(A1)") == "'@SUM(A1)")
        #expect(GapList.field("-1") == "'-1")
    }
}
