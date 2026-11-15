import Testing
@testable import BOMCore

@Suite struct WorkshopReportTests {
    let laravel = WorkshopAnalysis.analyse(fixtureTree(laravelPath))!
    let cern = WorkshopAnalysis.analyse(fixtureTree(cernPath))!

    @Test func laravelVersionGap() {
        let gap = laravel.report.versionGap!
        #expect(gap.found == "1.4")
        #expect(gap.required == "1.6")
        #expect(gap.evidence == .located(laravel.bom.specVersion.node))
        #expect(laravel.report.sections.map(\.scope) == [.sbom, .subject, .components])
        #expect(!laravel.report.sections[0].rows.contains { $0.rule.requirement == .specVersion })
    }

    @Test func laravelNotes() {
        let rows = laravel.report.sections[2].rows
        #expect(rows.first { $0.rule.requirement == .creator }?.introducedIn == "1.6")
        #expect(rows.first { $0.rule.requirement == .distributionLicences }?.introducedIn == "1.6")
        #expect(rows.first { $0.rule.requirement == .filename }?.introducedIn == nil)
        #expect(cern.report.sections[2].rows.first { $0.rule.requirement == .filename }?.introducedIn == "1.3")
        let creator = rows.first { $0.rule.requirement == .creator }!
        #expect(creator.covered == 0 && creator.total == 62 && creator.offenders.count == 62)
        #expect(creator.section == "§5.2.2")
    }

    @Test func laravelVerdict() {
        let v = laravel.verdict
        #expect(!v.ready)
        #expect(v.versionGap == "1.4")
        #expect(v.gaps == [.timestamp, .manufacturer, .hashes, .licences, .dependencies, .fileProperties])
    }

    @Test func rioPassVerdict() {
        let a = WorkshopAnalysis.analyse(fixtureTree("rio/bsi-pass.cdx.json"))!
        #expect(a.verdict == Verdict(ready: true, versionGap: nil, gaps: []))
        #expect(a.report.versionGap == nil)
    }

    @Test func brokenFileStillReported() {
        let a = WorkshopAnalysis.analyse(fixtureTree("edge/cyclonedx-broken.json"))
        #expect(a != nil)
        #expect((a?.report.parseErrors ?? 0) >= 1)
        #expect(laravel.report.parseErrors == 0)
        #expect(WorkshopAnalysis.analyse(fixtureTree("edge/workshop-broken.json")) == nil)
    }

    @Test func offendersPerComponent() {
        #expect(laravel.offenders(component: 0).count == 8)
        #expect(laravel.gapCount(component: 0) == 8)
        #expect(laravel.offenders(component: 0).first?.rule == RuleID(.components, .creator))
        let nested = WorkshopAnalysis.analyse(fixtureTree("synthetic/nested-1.6.cdx.json"))!
        #expect(nested.gapCount(component: 4) == 10)
    }

    @Test func filters() {
        #expect(ComponentFilter(licence: .isNot("MIT")).apply(laravel).count == 5)
        #expect(ComponentFilter(licence: .is("BSD-3-Clause")).apply(laravel).count == 4)
        #expect(ComponentFilter(missing: RuleID(.components, .deployableHash)).apply(laravel).count == 62)
        #expect(ComponentFilter(depth: 6).apply(laravel).map { laravel.bom.components[$0].bomRef } == ["psr/event-dispatcher-1.0.0.0"])
        #expect(ComponentFilter(depth: 4).apply(laravel).contains { laravel.bom.components[$0].name == "lexer" })
        #expect(ComponentFilter(text: "symfony").apply(laravel).count == 27)
        #expect(ComponentFilter(text: "SYMFONY", licence: .isNot("MIT")).apply(laravel).isEmpty)
        #expect(ComponentFilter().apply(cern).count == 43)
        #expect(ComponentFilter(licence: .unknown).apply(cern).isEmpty)
    }
}

@Suite struct HistoryTests {
    @Test func backAndForward() {
        var h = History<String>()
        h.visit("a"); h.visit("b"); h.visit("c")
        #expect(h.back() == "b")
        #expect(h.back() == "a")
        #expect(!h.canGoBack)
        #expect(h.forward() == "b")
        h.visit("d")
        #expect(!h.canGoForward)
        h.visit("d")
        #expect(h.current == "d")
        #expect(h.back() == "b")
    }
}
