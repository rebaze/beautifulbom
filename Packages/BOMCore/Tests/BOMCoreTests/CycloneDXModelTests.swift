import Testing
@testable import BOMCore

func bom(_ json: String) -> CycloneDXDocument? { CycloneDXDocument.recognize(tree(json)) }

@Suite struct CycloneDXModelTests {
    let laravel = CycloneDXDocument.recognize(fixtureTree(laravelPath))!
    let cern = CycloneDXDocument.recognize(fixtureTree(cernPath))!
    let nested = CycloneDXDocument.recognize(fixtureTree("synthetic/nested-1.6.cdx.json"))!

    @Test func laravelRecognised() {
        #expect(laravel.specVersion.value == "1.4")
        #expect(laravel.subject?.name == "cyclonedx-php-composer-demo")
        #expect(laravel.subject?.version == "dev-master")
        #expect(laravel.subject?.type == "application")
        #expect(laravel.subject?.isSubject == true)
        #expect(laravel.subject?.path == "metadata.component")
        #expect(laravel.components.count == 62)
        #expect(laravel.tools.map { [$0.vendor, $0.name, $0.version] } == [["cyclonedx", "cyclonedx-php-composer", "in-dev"]])
        #expect(laravel.timestamp == nil)
    }

    @Test func laravelLexer() {
        let lexer = laravel.components.first { $0.name == "lexer" }!
        #expect(lexer.group == "doctrine")
        #expect(lexer.packageURL?.type == "composer")
        #expect(lexer.licenses.map(\.kind) == [.id("MIT")])
        #expect(lexer.externalReferences.count == 5)
        #expect(lexer.path == "components[3]")
        #expect(lexer.displayName == "doctrine/lexer")
        #expect(lexer.author == "Guilherme Blanco, Roman Borschel, Johannes Schmitt")
    }

    @Test func cernRecognised() {
        #expect(cern.specVersion.value == "1.2")
        #expect(cern.components.count == 43)
        #expect(cern.components.allSatisfy { $0.hashes.count == 1 })
        #expect(cern.components.filter { $0.hashes[0].alg == "SHA-512" }.count == 17)
        #expect(cern.components.filter { $0.hashes[0].alg == "SHA-1" }.count == 26)
        #expect(cern.timestamp?.value == "2020-08-03T01:28:52.765Z")
    }

    @Test func nestedOrderMatchesRio() {
        #expect(nested.components.map(\.path) == [
            "metadata.component.components[0]", "components[0]", "components[0].components[0]",
            "components[0].components[1]", "components[1]", "components[2]", "components[3]",
        ])
        let oops = nested.components[4]
        #expect(oops.node == nil)
        #expect(oops.name == nil)
        #expect(nested.components[3].unknownKeys == ["x-vendor"])
    }

    @Test func wrongTypesReadAsAbsent() {
        #expect(nested.components[5].name == "numver")
        #expect(nested.components[5].version == nil)
        #expect(nested.components[6].licenses.isEmpty)
        #expect(nested.components[1].licenses.map(\.kind) == [.expression("MIT OR Apache-2.0")])
        #expect(nested.components[1].licenses.first?.acknowledgement == "concluded")
    }

    @Test func toolsObjectForm() {
        #expect(nested.tools.map(\.name) == ["acme-sbom"])
        #expect(nested.manufacturerName == "Acme Devices GmbH")
    }

    @Test func notCycloneDX() {
        #expect(CycloneDXDocument.recognize(fixtureTree("edge/duplicates.json")) == nil)
        #expect(bom(#"{"bomFormat":"SPDX","specVersion":"2.3"}"#) == nil)
        #expect(bom(#"{"bomFormat":"CycloneDX","specVersion":"1.1"}"#) == nil)
        #expect(bom(#"{"bomFormat":"CycloneDX","specVersion":"1.7"}"#) != nil)
        #expect(bom(#"{"bomFormat":"CycloneDX","specVersion":"1.x"}"#) == nil)
        #expect(bom(#"{"bomFormat":"CycloneDX","specVersion":1.6}"#) == nil)
        #expect(bom("[]") == nil)
    }

    @Test func compareVersionsLikeRio() {
        #expect(CycloneDXDocument.compareVersions("1.10", "1.6") == 1)
        #expect(CycloneDXDocument.compareVersions("1.6", "1.6.0") == 0)
        #expect(CycloneDXDocument.compareVersions("1.x", "1.6") == 1)
        #expect(CycloneDXDocument.compareVersions("1.4", "1.6") == -1)
    }
}
