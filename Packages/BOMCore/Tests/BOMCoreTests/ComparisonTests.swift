import Testing
@testable import BOMCore

/// Two SBOMs side by side: release against release, tool against tool.
@Suite struct ComparisonTests {
    func doc(_ components: String, subject: String = #"{"bom-ref":"p","name":"p"}"#) -> BOMDocument {
        bom(#"{"bomFormat":"CycloneDX","specVersion":"1.6","metadata":{"component":\#(subject)},"components":[\#(components)]}"#)!
    }

    let a = #"""
    {"name":"express","version":"4.21.2","purl":"pkg:npm/express@4.21.2","licenses":[{"license":{"id":"MIT"}}]},
    {"name":"debug","version":"2.6.9","purl":"pkg:npm/debug@2.6.9"},
    {"name":"debug","version":"4.3.4","purl":"pkg:npm/debug@4.3.4"},
    {"name":"lodash","version":"4.17.20","purl":"pkg:npm/lodash@4.17.20"},
    {"group":"org.example","name":"gone","version":"1.0","scope":"optional"},
    {"type":"file","name":"/usr/bin/bash"}
    """#
    let b = #"""
    {"name":"express","version":"4.21.2","purl":"pkg:npm/express@4.21.2?vcs_url=x","licenses":[{"license":{"id":"Apache-2.0"}}]},
    {"name":"debug","version":"4.3.4","purl":"pkg:npm/debug@4.3.4"},
    {"name":"debug","version":"4.3.5","purl":"pkg:npm/debug@4.3.5"},
    {"name":"lodash","version":"4.17.21","purl":"pkg:npm/lodash@4.17.21"},
    {"name":"left-pad","version":"1.3.0","purl":"pkg:npm/left-pad@1.3.0"}
    """#

    var cmp: BOMComparison { BOMComparison(doc(a), doc(b)) }

    func rows(_ kind: BOMComparison.Kind) -> [String] {
        cmp.rows.filter { $0.kind == kind }.map { "\($0.name) \($0.versionA ?? "-")→\($0.versionB ?? "-")" }
    }

    @Test func sameIdentityAndVersion() {
        // The purl's qualifiers do not change the identity.
        #expect(rows(.same) == ["debug 4.3.4→4.3.4", "express 4.21.2→4.21.2"])
    }

    @Test func versionsPairUpAfterExactMatches() {
        #expect(rows(.changed) == ["debug 2.6.9→4.3.5", "lodash 4.17.20→4.17.21"])
        #expect(cmp.rows.first { $0.name == "lodash" }?.direction == .up)
        #expect(cmp.rows.first { $0.name == "debug" && $0.kind == .changed }?.direction == .up)
    }

    @Test func onlyOnOneSide() {
        #expect(rows(.onlyA) == ["org.example/gone 1.0→-"])
        #expect(rows(.onlyB) == ["left-pad -→1.3.0"])
    }

    @Test func licenceDifferenceOnSameVersion() {
        #expect(cmp.rows.first { $0.name == "express" }?.licenceDiffers == true)
        #expect(cmp.rows.first { $0.name == "debug" && $0.kind == .same }?.licenceDiffers == false)
    }

    @Test func filesAreLeftOut() {
        #expect(!cmp.rows.contains { $0.name.contains("bash") })
        #expect(cmp.a.files == 1 && cmp.b.files == 0)
    }

    @Test func counts() {
        let c = cmp.counts
        #expect(c.same == 2 && c.changed == 2 && c.onlyA == 1 && c.onlyB == 1)
    }

    @Test func facts() {
        #expect(cmp.a.packages == 5 && cmp.b.packages == 5)
        #expect(cmp.a.withPurl == 4 && cmp.b.withPurl == 5)
        #expect(cmp.a.withLicence == 1 && cmp.b.withLicence == 1)
    }

    @Test func indexesPointIntoEachDocument() {
        let r = cmp.rows.first { $0.name == "left-pad" }!
        #expect(r.indexA == nil && r.indexB == 4)
        let g = cmp.rows.first { $0.name == "org.example/gone" }!
        #expect(g.indexA == 4 && g.indexB == nil)
        #expect(cmp.docA.components[g.indexA!].scope == "optional")
    }

    @Test func versionDirection() {
        #expect(BOMComparison.direction("1.2.3", "1.10.0") == .up)
        #expect(BOMComparison.direction("2.0", "1.9.9") == .down)
        #expect(BOMComparison.direction("1.0.0-rc1", "1.0.0") == .unknown)
        #expect(BOMComparison.direction("v1.2", "v1.3") == .up)
    }

    /// Syft lists a GitHub Action once per workflow that uses it: one row, listed three times;
    /// the counts still count every entry, so they add up to the packages of each file.
    @Test func duplicatesMergeIntoOneRow() {
        let action = { (v: String) in #"{"name":"actions/setup-python","version":"\#(v)","purl":"pkg:github/actions/setup-python@\#(v)"}"# }
        let x = doc([action("v7.0.0"), action("v7.0.0"), action("v7.0.0"), #"{"name":"a","version":"1"}"#, #"{"name":"a","version":"1"}"#].joined(separator: ","))
        let y = doc([action("v7.1.0"), action("v7.1.0"), action("v7.1.0"), #"{"name":"a","version":"1"}"#, #"{"name":"a","version":"1"}"#].joined(separator: ","))
        let c = BOMComparison(x, y)
        #expect(c.rows.map { "\($0.name) \($0.kind) ×\($0.times)" } == ["a same ×2", "actions/setup-python changed ×3"])
        #expect(c.counts == BOMComparison.Counts(same: 2, changed: 3, onlyA: 0, onlyB: 0))
        #expect(c.rows.first { $0.kind == .changed }?.direction == .up)
    }

    @Test func distinctVersionsStaySeparate() {
        #expect(cmp.rows.allSatisfy { $0.times == 1 })
        #expect(cmp.rows.count == 6)
    }

    /// The same Java service, by the Maven plugin and by Syft on the source: Syft reads the
    /// declared dependencies from pom.xml (no transitive ones) and lists the project twice.
    @Test func mavenAgainstSyft() {
        let maven = BOMDocument.recognize(fixtureTree("tools/partner-portal.maven.cdx.json"))!
        let syft = BOMDocument.recognize(fixtureTree("tools/partner-portal.syft.cdx.json"))!
        let c = BOMComparison(maven, syft)
        #expect(c.counts == BOMComparison.Counts(same: 3, changed: 0, onlyA: 3, onlyB: 2))
        #expect(c.rows.filter { $0.kind == .onlyA }.map(\.name) == [
            "com.fasterxml.jackson.core/jackson-annotations", "com.fasterxml.jackson.core/jackson-core",
            "org.apache.logging.log4j/log4j-api"])
        #expect(c.b.files == 2)
    }
}
