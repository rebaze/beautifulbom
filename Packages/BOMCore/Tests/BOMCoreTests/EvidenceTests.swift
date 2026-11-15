import Testing
@testable import BOMCore

@Suite struct EvidenceTests {
    @Test func absentTimestampSitsOnMetadataLine() {
        let t = fixtureTree(laravelPath)
        let metadata = t.member(t.root!, "metadata")!
        let absent = Absent(parent: metadata, key: "timestamp", in: t)
        #expect(t.source.lineColumn(of: absent.insertion).line == 6)
        #expect(t.evidence(metadata, "timestamp") == .absent(absent))
    }

    @Test func evidenceLocatedWhenPresent() {
        let t = fixtureTree(cernPath)
        let metadata = t.member(t.root!, "metadata")!
        guard case .located(let n) = t.evidence(metadata, "timestamp") else { Issue.record("absent"); return }
        #expect(t.string(n) == "2020-08-03T01:28:52.765Z")
    }

    @Test func purlComposer() {
        let p = PackageURL.parse("pkg:composer/doctrine/lexer@1.2.3")
        #expect(p == PackageURL(type: "composer", namespace: "doctrine", name: "lexer", version: "1.2.3"))
    }

    @Test func purlScopedNpm() {
        let p = PackageURL.parse("pkg:npm/%40angular/core@16.0.0?arch=x64#src")
        #expect(p?.namespace == "@angular")
        #expect(p?.name == "core")
        #expect(p?.version == "16.0.0")
        #expect(p?.qualifiers == ["arch": "x64"])
        #expect(p?.subpath == "src")
    }

    @Test func purlRejectsNonPkg() {
        #expect(PackageURL.parse("https://x") == nil)
        #expect(PackageURL.parse("pkg:") == nil)
        #expect(PackageURL.parse("pkg:npm/") == nil)
    }

    @Test func purlTypeLowercasedAndNoNamespace() {
        let p = PackageURL.parse("pkg:NPM/lodash@4.17.21")
        #expect(p == PackageURL(type: "npm", namespace: nil, name: "lodash", version: "4.17.21"))
    }
}
