import Foundation
import Testing
@testable import BOMCore

/// Findings of the review of 36c875a..facb2fc (2026-11-16).
@Suite struct BranchReviewTests {
    /// #1: a deeply nested licence expression must not exhaust a background thread's 512 KB stack.
    @Test func deeplyNestedExpressionDoesNotCrash() {
        let expr = String(repeating: "(", count: 5000) + "MIT" + String(repeating: ")", count: 5000)
        nonisolated(unsafe) var result: LicenceFamily?
        let done = DispatchSemaphore(value: 0)
        let thread = Thread { result = LicenceFamily.of(expr); done.signal() }
        thread.stackSize = 512 * 1024
        thread.start()
        done.wait()
        #expect(result == .unclassified)
        #expect(LicenceFamily.of("((MIT))") == .permissive)
    }

    /// #2: the map says how deep the SBOM goes and how many parts it does not draw one by one.
    @Test func mapReportsTheRealDepth() {
        let leaves = (0..<6000).map { "l\($0)" }
        let chain = (0..<20).map { "c\($0)" }
        let comps = (leaves + chain).map { #"{"bom-ref":"\#($0)","name":"\#($0)"}"# }.joined(separator: ",")
        let chainDeps = zip(chain, chain.dropFirst()).map { #"{"ref":"\#($0)","dependsOn":["\#($1)"]}"# }.joined(separator: ",")
        let doc = bom(#"""
        {"bomFormat":"CycloneDX","specVersion":"1.6",
         "metadata":{"component":{"bom-ref":"s","name":"s","version":"1"}},
         "components":[\#(comps)],
         "dependencies":[{"ref":"s","dependsOn":[\#((leaves + ["c0"]).map { "\"\($0)\"" }.joined(separator: ","))]},\#(chainDeps)]}
        """#)!
        let map = DependencyMap(DependencyGraph(doc)!)
        #expect(map.rings == 1)
        #expect(map.deepest == 20)
        #expect(map.notDrawn == 6020)
        let laravel = DependencyMap(DependencyGraph(BOMDocument.recognize(fixtureTree(laravelPath))!)!)
        #expect(laravel.deepest == 6)
        #expect(laravel.notDrawn == 0)
    }

    /// #7: MPL without the secondary-licence exhibit is still file-level copyleft.
    @Test func mplNoCopyleftExceptionIsWeakCopyleft() {
        #expect(LicenceFamily.of("MPL-2.0-no-copyleft-exception") == .weakCopyleft)
    }

    /// #8: a component's TR fields count only the rules that apply at its level.
    @Test func rulesPerComponentFollowItsLevel() {
        let doc = bom(#"""
        {"bomFormat":"CycloneDX","specVersion":"1.6","components":[
          {"name":"full","version":"1"},
          {"name":"ref","version":"1","externalReferences":[{"type":"bom","url":"https://example.org/bom.json"}]},
          {"name":"logical","version":"1","properties":[{"name":"rio:tr-03183-2:level","value":"logical"}]}]}
        """#)!
        let a = WorkshopAnalysis.analyse(doc.tree)!
        #expect((0..<3).map { a.ruleCount(component: $0) } == [11, 4, 6])
        #expect(a.ruleCount(component: 1) - a.gapCount(component: 1) >= 0)
    }

    /// #12: a dataset reference that points nowhere is its own gap; an unnamed inline dataset still counts.
    @Test func aibomDatasetEdgeCases() {
        let doc = bom(#"""
        {"bomFormat":"CycloneDX","specVersion":"1.6","metadata":{"component":{"type":"machine-learning-model","name":"m",
          "modelCard":{"modelParameters":{"datasets":[{"ref":"nowhere"},{"type":"dataset","contents":{"url":"https://example.org/d"}}]}}}}}
        """#)!
        let a = AIBOMAnalysis.analyse(doc)!
        #expect(a.model.datasets.count == 2)
        #expect(a.model.datasets[1].name == "")
        let kinds = a.gaps.map(\.kind)
        #expect(kinds.contains(.datasetRefMissing("nowhere")))
        #expect(!kinds.contains(.datasetNamedOnly("nowhere")))
        #expect(!kinds.contains(.noDatasets))
        #expect(kinds.contains(.datasetNamedOnly("")))
    }
}
