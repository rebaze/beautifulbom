import Testing
@testable import BOMCore

@Suite struct WorkshopScaleTests {
    @Test func analysesGeneratedMegabyte() {
        let json = SyntheticSBOM.generate(sizeMB: 1, minified: false)
        let tree = parseJSON(SourceDocument(bytes: Array(json.utf8)))
        #expect(tree.diagnostics.isEmpty)
        let a = WorkshopAnalysis.analyse(tree)!
        #expect(a.bom.components.count > 1000)
        #expect(a.graph != nil)
        #expect(a.graph?.unreachable.isEmpty == true)
        #expect(a.profile!.evaluation("components.dependencies")?.failed == 0)
        #expect((a.composition.depthHistogram?.keys.max() ?? 99) <= 8)
    }
}
