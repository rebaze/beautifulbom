import Testing
@testable import BOMCore

@Suite struct DependencyGraphTests {
    let laravel = DependencyGraph(CycloneDXDocument.recognize(fixtureTree(laravelPath))!)!

    @Test func laravelDirect() {
        #expect(laravel.direct == ["laravel/laravel-7.12.0.0"])
    }

    @Test func laravelHistogram() {
        #expect(laravel.depthHistogram == [1: 1, 2: 5, 3: 30, 4: 21, 5: 4, 6: 1])
        #expect(laravel.unreachable.isEmpty)
        #expect(laravel.depth("laravel/laravel-7.12.0.0") == 1)
    }

    @Test func laravelLexerPath() {
        #expect(laravel.path(to: "doctrine/lexer-1.2.3.0") == [
            "cyclonedx/cyclonedx-php-composer-demo-dev-master", "laravel/laravel-7.12.0.0",
            "laravel/framework-7.30.6.0", "egulias/email-validator-2.1.25.0", "doctrine/lexer-1.2.3.0",
        ])
        #expect(laravel.path(to: "nope") == nil)
    }

    @Test func laravelLexerUsedBy() {
        #expect(laravel.usedBy("doctrine/lexer-1.2.3.0") == ["egulias/email-validator-2.1.25.0"])
        #expect(laravel.entry("doctrine/lexer-1.2.3.0") != nil)
    }

    @Test func cernHasNoGraph() {
        #expect(DependencyGraph(CycloneDXDocument.recognize(fixtureTree(cernPath))!) == nil)
    }

    @Test func cycleTerminates() {
        let doc = bom(#"""
        {"bomFormat":"CycloneDX","specVersion":"1.6",
         "metadata":{"component":{"bom-ref":"s","name":"s","version":"1"}},
         "components":[{"bom-ref":"a","name":"a"},{"bom-ref":"b","name":"b"},{"bom-ref":"c","name":"c"}],
         "dependencies":[{"ref":"s","dependsOn":["a"]},{"ref":"a","dependsOn":["b"]},{"ref":"b","dependsOn":["a"]}]}
        """#)!
        let g = DependencyGraph(doc)!
        #expect(g.depth("b") == 2)
        #expect(g.unreachable == ["c"])
        #expect(g.usedBy("a") == ["s", "b"])
    }
}
