import Foundation
import Testing
@testable import BOMCore

@Suite struct DependencyMapTests {
    let laravel = DependencyMap(DependencyGraph(BOMDocument.recognize(fixtureTree(laravelPath))!)!)

    private func slice(_ map: DependencyMap, _ ref: String) -> (Int, DependencyMap.Slice)? {
        map.slices.enumerated().first { $0.element.ref == ref }.map { ($0.offset, $0.element) }
    }

    @Test func laravelRingOneIsTheWholeCircle() {
        let ring1 = laravel.slices.filter { $0.depth == 1 }
        #expect(ring1.count == 1)
        #expect(ring1.first?.ref == "laravel/laravel-7.12.0.0")
        #expect(ring1.first?.start == 0)
        #expect(ring1.first?.end == 1)
        #expect(ring1.first?.weight == 62)
        #expect(laravel.rings == 6)
    }

    @Test func laravelEveryReachablePartIsOnTheMapOnce() {
        #expect(laravel.slices.count == 62)
        #expect(Set(laravel.slices.compactMap(\.ref)).count == 62)
        #expect(laravel.slices.allSatisfy { !$0.isGroup })
    }

    @Test func childrenShareTheirParentsRangeByWeight() {
        for (i, s) in laravel.slices.enumerated() {
            let children = laravel.slices.filter { $0.parent == i }
            guard !children.isEmpty else { continue }
            #expect(children.allSatisfy { $0.start >= s.start - 1e-9 && $0.end <= s.end + 1e-9 })
            #expect(children.reduce(0) { $0 + $1.weight } == s.weight - 1)
            // Children fill their parent's whole range, in proportion to their weights.
            let filled = children.reduce(0.0) { $0 + ($1.end - $1.start) }
            #expect(abs(filled - (s.end - s.start)) < 1e-9)
        }
    }

    @Test func lexerPathMatchesWhyIsItHere() {
        let (i, lexer) = slice(laravel, "doctrine/lexer-1.2.3.0")!
        #expect(lexer.depth == 4)
        #expect(laravel.path(to: i).map { laravel.slices[$0].ref } == [
            "laravel/laravel-7.12.0.0", "laravel/framework-7.30.6.0",
            "egulias/email-validator-2.1.25.0", "doctrine/lexer-1.2.3.0",
        ])
    }

    @Test func sliceAtFindsRingAndAngle() {
        #expect(laravel.slice(atDepth: 1, fraction: 0.5) == slice(laravel, "laravel/laravel-7.12.0.0")?.0)
        #expect(laravel.slice(atDepth: 0, fraction: 0.5) == nil)
        #expect(laravel.slice(atDepth: 7, fraction: 0.5) == nil)
        let (i, lexer) = slice(laravel, "doctrine/lexer-1.2.3.0")!
        #expect(laravel.slice(atDepth: 4, fraction: (lexer.start + lexer.end) / 2) == i)
    }

    @Test func narrowSlicesMergeIntoOneGroupPerParent() {
        let refs = (0..<1000).map { "p\($0)" }
        let deps = refs.map { #"{"ref":"\#($0)","dependsOn":["\#($0)-x"]}"# }.joined(separator: ",")
        let doc = bom(#"""
        {"bomFormat":"CycloneDX","specVersion":"1.6",
         "metadata":{"component":{"bom-ref":"s","name":"s","version":"1"}},
         "components":[\#(refs.map { #"{"bom-ref":"\#($0)","name":"\#($0)"}"# }.joined(separator: ","))],
         "dependencies":[{"ref":"s","dependsOn":["big",\#(refs.map { "\"\($0)\"" }.joined(separator: ","))]},
                         {"ref":"big","dependsOn":[\#((0..<1000).map { "\"b\($0)\"" }.joined(separator: ","))]},\#(deps)]}
        """#)!
        let map = DependencyMap(DependencyGraph(doc)!)
        let ring1 = map.slices.filter { $0.depth == 1 }
        // "big" (1001 parts of 3001) keeps its slice; the 1000 two-part slices are each 0.07 %: one group.
        #expect(ring1.count == 2)
        let group = ring1.first { $0.isGroup }!
        #expect(group.groupCount == 1000)
        #expect(group.weight == 2000)
        #expect(group.ref == nil)
        // Nothing is drawn beneath a group.
        let g = map.slices.firstIndex(of: group)!
        #expect(!map.slices.contains { $0.parent == g })
        // Under "big" the 1000 one-part leaves are merged too.
        #expect(map.slices.filter { $0.depth == 2 }.count == 1)
    }

    @Test func ringsStopAtTheLimit() {
        let chain = (0..<20).map { "c\($0)" }
        let deps = zip(["s"] + chain, chain).map { #"{"ref":"\#($0)","dependsOn":["\#($1)"]}"# }.joined(separator: ",")
        let doc = bom(#"""
        {"bomFormat":"CycloneDX","specVersion":"1.6",
         "metadata":{"component":{"bom-ref":"s","name":"s","version":"1"}},
         "components":[\#(chain.map { #"{"bom-ref":"\#($0)","name":"\#($0)"}"# }.joined(separator: ","))],
         "dependencies":[\#(deps)]}
        """#)!
        let map = DependencyMap(DependencyGraph(doc)!, maxDepth: 12)
        #expect(map.rings == 12)
        #expect(map.slices.count == 12)
        #expect(map.hiddenDeeper == 8)
    }

    @Test func productWithoutDependenciesHasAnEmptyMap() {
        let doc = bom(#"""
        {"bomFormat":"CycloneDX","specVersion":"1.6",
         "metadata":{"component":{"bom-ref":"s","name":"s","version":"1"}},
         "components":[{"bom-ref":"a","name":"a"}],
         "dependencies":[{"ref":"a","dependsOn":[]}]}
        """#)!
        let map = DependencyMap(DependencyGraph(doc)!)
        #expect(map.slices.isEmpty)
        #expect(map.rings == 0)
    }

    @Test func generatedMegabyteStaysBounded() {
        let json = SyntheticSBOM.generate(sizeMB: 1, minified: true)
        let a = WorkshopAnalysis.analyse(parseJSON(SourceDocument(bytes: Array(json.utf8))))!
        let start = Date()
        let map = DependencyMap(a.graph!)
        #expect(Date().timeIntervalSince(start) < 0.5)
        #expect(map.slices.count < 3000)
        // Only slices at least minFraction wide have anything drawn beneath them.
        let parents = Set(map.slices.compactMap(\.parent))
        #expect(parents.allSatisfy { map.slices[$0].end - map.slices[$0].start >= DependencyMap.defaultMinFraction - 1e-12 })
    }
}
