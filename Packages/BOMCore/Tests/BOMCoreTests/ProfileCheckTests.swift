import Testing
@testable import BOMCore

/// A CycloneDX 1.6 document with a valid subject and the given components.
func profile(components: String, extra: String = "") -> (CycloneDXDocument, ProfileResult) {
    let doc = bom(#"""
    {"bomFormat":"CycloneDX","specVersion":"1.6",
     "metadata":{"timestamp":"2026-11-15T10:00:00Z","component":{"bom-ref":"s","name":"s","version":"1"}},
     "components":[\#(components)]\#(extra)}
    """#)!
    return (doc, checkTR031832(doc))
}

func failed(_ r: ProfileResult, _ id: String) -> Int? { r.evaluation(id)?.failed }
func evaluated(_ r: ProfileResult, _ id: String) -> Int? { r.evaluation(id)?.evaluated }

@Suite struct ProfileCheckTests {
    @Test func laravelCounts() {
        let r = checkTR031832(CycloneDXDocument.recognize(fixtureTree(laravelPath))!)
        for f in ["name", "version", "level"] {
            #expect(evaluated(r, "components.\(f)") == 62)
            #expect(failed(r, "components.\(f)") == 0)
        }
        for f in ["creator", "filename", "dependencies", "distributionLicences", "deployableHash", "executable", "archive", "structured"] {
            #expect(evaluated(r, "components.\(f)") == 62)
            #expect(failed(r, "components.\(f)") == 62)
        }
        #expect(failed(r, "sbom.specVersion") == 1)
        #expect(failed(r, "sbom.creator") == 1)
        #expect(failed(r, "sbom.timestamp") == 1)
        #expect(failed(r, "sbom.vulnerabilities") == 0)
        #expect(r.levels == [.full: 63, .logical: 0, .assembled: 0, .identified: 0, .referenced: 0])
        #expect(r.evaluations.map(\.rule.description).prefix(6) ==
            ["sbom.specVersion", "sbom.creator", "sbom.timestamp", "sbom.vulnerabilities", "subject.name", "subject.version"])
        #expect(r.evaluations.count == 4 + 11 + 11)
    }

    @Test func laravelTimestampEvidence() {
        let doc = CycloneDXDocument.recognize(fixtureTree(laravelPath))!
        let r = checkTR031832(doc)
        guard case .absent(let a) = r.offenders(RuleID("sbom.timestamp")!).first?.evidence else { Issue.record("not absent"); return }
        #expect(a.key == "timestamp")
        #expect(a.parent == doc.metadata)
    }

    @Test func levelsFromProperty() {
        let (_, r) = profile(components: #"""
        {"name":"a","version":"1","properties":[{"name":"rio:tr-03183-2:level","value":"assembled"}]},
        {"name":"i","version":"1","properties":[{"name":"rio:tr-03183-2:level","value":"identified"}]},
        {"name":"r","version":"1","externalReferences":[{"type":"bom","url":"urn:x"}],"properties":[{"name":"rio:tr-03183-2:level","value":"assembled"}]},
        {"name":"d","version":"1","properties":[{"name":"rio:tr-03183-2:level","value":"logical"},{"name":"rio:tr-03183-2:level","value":"logical"}]},
        {"name":"b","version":"1","properties":[{"name":"rio:tr-03183-2:level","value":"bogus"}]},
        {"name":"f","version":"1","properties":[{"name":"rio:tr-03183-2:level","value":"full"}]}
        """#)
        #expect(r.levels == [.full: 4, .logical: 0, .assembled: 1, .identified: 1, .referenced: 1])
        #expect(evaluated(r, "components.filename") == 3)
        #expect(evaluated(r, "components.creator") == 6)
        #expect(evaluated(r, "components.dependencies") == 4)
        #expect(failed(r, "components.level") == 3)
        let details = r.offenders(RuleID("components.level")!).map(\.detail)
        #expect(details == [
            "the rio:tr-03183-2:level property appears 2 times; it may appear once",
            #"the rio:tr-03183-2:level value "bogus" is not logical, identified or assembled"#,
            #"the rio:tr-03183-2:level value "full" is not logical, identified or assembled"#,
        ])
    }

    @Test func creatorForms() {
        let (doc, r) = profile(components: #"""
        {"name":"a","version":"1","manufacturer":{"contact":[{"email":"a@b"}]}},
        {"name":"b","version":"1","manufacturer":{"contact":[{"email":"@b"}]}},
        {"name":"c","version":"1","manufacturer":{"url":["https://example.com"]}},
        {"name":"d","version":"1","manufacturer":{"url":["https://"]}},
        {"name":"e","version":"1","manufacturer":{"url":["ftp://x"]}},
        {"name":"f","version":"1","manufacturer":{"url":["https://x"]},"manufacturer":{}},
        {"name":"g","version":"1","manufacturer":{"url":[" HTTPS://x "]}}
        """#)
        #expect(r.offenders(RuleID("components.creator")!).map(\.identity) == ["b@1", "d@1", "e@1", "f@1"])
        let f = r.offenders(RuleID("components.creator")!).last!
        guard case .located(let n) = f.evidence else { Issue.record("absent"); return }
        #expect(n == doc.tree.member(doc.components[5].node!, "manufacturer"))
        #expect(doc.tree.childCount(n) == 0)
    }

    @Test(arguments: [
        ("2020-08-03T01:28:52.765Z", true), ("2026-11-15T10:00:00+01:00", true), ("2020-08-03T01:28:52,5Z", true),
        ("2020-08-03T1:28:52Z", true), ("2020-08-03T01:28:52+23:60", true), ("2020-02-29T00:00:00Z", true),
        ("2020-13-01T00:00:00Z", false), ("2020-08-03 01:28:52Z", false), ("2020-02-30T00:00:00Z", false),
        ("2020-08-03t01:28:52z", false), ("2020-08-03T24:00:00Z", false), ("2020-08-03T01:28:52+25:00", false),
        ("2020-08-03T01:28:52+0100", false), ("2020-08-03T01:28:52.Z", false), ("2021-02-29T00:00:00Z", false),
        ("2020-08-03T01:28:52Z ", false),
    ])
    func timestampForms(_ s: String, _ ok: Bool) {
        #expect(FieldChecks.validTimestamp(s) == ok)
    }

    @Test func timestampNumberFails() {
        let doc = bom(#"{"bomFormat":"CycloneDX","specVersion":"1.6","metadata":{"timestamp":20200803}}"#)!
        #expect(failed(checkTR031832(doc), "sbom.timestamp") == 1)
    }

    @Test func licences() {
        let (_, r) = profile(components: #"""
        {"name":"a","version":"1","licenses":[{"expression":"MIT OR Apache-2.0","acknowledgement":"concluded"}]},
        {"name":"b","version":"1","licenses":[{"license":{"id":"MIT","acknowledgement":"concluded"}}]},
        {"name":"c","version":"1","licenses":[{"license":{"id":"MIT","acknowledgement":"declared"}}]},
        {"name":"d","version":"1","licenses":[{"license":{"name":"MIT","acknowledgement":"concluded"}}]},
        {"name":"e","version":"1","licenses":[{"license":{"id":"Classpath-exception-2.0","acknowledgement":"concluded"}}]},
        {"name":"f","version":"1","licenses":[{"expression":"MIT","acknowledgement":"declared"},{"license":{"id":"ISC","acknowledgement":"concluded"}}]}
        """#)
        #expect(r.offenders(RuleID("components.distributionLicences")!).map(\.identity) == ["c@1", "d@1", "e@1"])
    }

    @Test func deployableHash() {
        let h128 = String(repeating: "a", count: 128), h127 = String(repeating: "a", count: 127)
        let (_, r) = profile(components: #"""
        {"name":"a","version":"1","externalReferences":[{"type":"distribution","url":"https://x","hashes":[{"alg":"SHA-512","content":"\#(h128)"}]}]},
        {"name":"b","version":"1","hashes":[{"alg":"SHA-512","content":"\#(h128)"}]},
        {"name":"c","version":"1","externalReferences":[{"type":"distribution","url":"https://x","hashes":[{"alg":"SHA-512","content":"\#(h127)"}]}]},
        {"name":"d","version":"1","externalReferences":[{"type":"distribution","url":"https://x","hashes":[{"alg":"SHA-256","content":"\#(h128)"}]}]}
        """#)
        #expect(r.offenders(RuleID("components.deployableHash")!).map(\.identity) == ["b@1", "c@1", "d@1"])
    }

    @Test func dependenciesNeedComposition() {
        let (_, r) = profile(components: #"""
        {"bom-ref":"a","name":"a","version":"1"},
        {"bom-ref":"b","name":"b","version":"1"},
        {"bom-ref":"c","name":"c","version":"1"},
        {"name":"d","version":"1"}
        """#, extra: #"""
        ,"dependencies":[{"ref":"a"},{"ref":"b"},{"ref":"c"},{"ref":"s","dependsOn":["a"]}],
        "compositions":[{"aggregate":"complete","assemblies":["b","s"]},{"aggregate":"not_specified","assemblies":["c"]}]
        """#)
        #expect(r.offenders(RuleID("components.dependencies")!).map(\.identity) == ["a@1", "c@1", "d@1"])
        #expect(failed(r, "subject.dependencies") == 0)
    }

    @Test func fileProperties() {
        let (_, r) = profile(components: #"""
        {"name":"a","version":"1","properties":[{"name":"bsi:component:executable","value":"executable"},{"name":"bsi:component:filename","value":"app.jar"}]},
        {"name":"b","version":"1","properties":[{"name":"bsi:component:executable","value":"yes"},{"name":"bsi:component:filename","value":"lib/app.jar"}]},
        {"name":"c","version":"1","properties":[{"name":"bsi:component:executable","value":"executable"},{"name":"bsi:component:executable","value":"executable"},{"name":"bsi:component:filename","value":"  "}]},
        {"name":"d","version":"1","properties":[{"name":"bsi:component:archive","value":"no archive"},{"name":"bsi:component:structured","value":"unstructured"}]}
        """#)
        #expect(r.offenders(RuleID("components.executable")!).map(\.identity) == ["b@1", "c@1", "d@1"])
        #expect(r.offenders(RuleID("components.filename")!).map(\.identity) == ["b@1", "c@1", "d@1"])
        #expect(r.offenders(RuleID("components.archive")!).map(\.identity) == ["a@1", "b@1", "c@1"])
        #expect(r.offenders(RuleID("components.structured")!).map(\.identity) == ["a@1", "b@1", "c@1"])
    }

    @Test func vulnerabilities() {
        let (_, r) = profile(components: "", extra: #","vulnerabilities":[{"id":"CVE-1"}]"#)
        #expect(failed(r, "sbom.vulnerabilities") == 1)
        let (_, empty) = profile(components: "", extra: #","vulnerabilities":[]"#)
        #expect(failed(empty, "sbom.vulnerabilities") == 0)
    }

    @Test func nonObjectEntry() {
        let doc = CycloneDXDocument.recognize(fixtureTree("synthetic/nested-1.6.cdx.json"))!
        let r = checkTR031832(doc)
        #expect(evaluated(r, "components.name") == 7)
        let oops = r.offenders.filter { $0.component == 4 }
        #expect(oops.map(\.rule.requirement) == [.name, .version, .creator, .filename, .dependencies,
                                                  .distributionLicences, .deployableHash, .executable, .archive, .structured])
        #expect(oops.first?.identity == "components[1]")
        #expect(oops.first?.evidence == .located(doc.components[4].entry))
        #expect(failed(r, "components.version") == 2)
    }

    @Test func identityLikeRio() {
        #expect(TR031832.identify(purl: "pkg:npm/x@1", group: "g", name: "n", version: "1", path: "p") == "pkg:npm/x@1")
        #expect(TR031832.identify(purl: "  ", group: "g", name: "n", version: "1", path: "p") == "g:n@1")
        #expect(TR031832.identify(purl: nil, group: nil, name: " n ", version: nil, path: "p") == "n")
        #expect(TR031832.identify(purl: nil, group: "g", name: nil, version: nil, path: "p") == "g")
        #expect(TR031832.identify(purl: nil, group: nil, name: nil, version: "2", path: "components[0]") == "components[0]@2")
    }

    @Test func subjectWithoutObject() {
        let doc = bom(#"{"bomFormat":"CycloneDX","specVersion":"1.6","metadata":{"component":"x"},"components":[]}"#)!
        let r = checkTR031832(doc)
        #expect(failed(r, "subject.name") == 1)
        #expect(failed(r, "subject.version") == 1)
        #expect(evaluated(r, "subject.creator") == 0)
        #expect(r.evaluation("subject.creator")?.outcome == .notEvaluated)
        #expect(r.levels.values.reduce(0, +) == 0)
    }

    @Test func sections() {
        #expect(TR031832.section(RuleID("sbom.specVersion")!) == "§4")
        #expect(TR031832.section(RuleID("sbom.timestamp")!) == "§5.2.1")
        #expect(TR031832.section(RuleID("sbom.vulnerabilities")!) == "§3.1")
        #expect(TR031832.section(RuleID("components.distributionLicences")!) == "§5.2.2, §6.1")
        #expect(TR031832.section(RuleID("subject.filename")!) == "§5.2.2")
        #expect(TR031832.section(RuleID("components.level")!) == nil)
        #expect(TR031832.introducedIn(.creator) == "1.6")
        #expect(TR031832.introducedIn(.deployableHash) == "1.3")
        #expect(TR031832.introducedIn(.timestamp) == nil)
    }
}
