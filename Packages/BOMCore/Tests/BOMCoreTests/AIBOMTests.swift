import Testing
@testable import BOMCore

@Suite struct AIBOMTests {
    let reference = AIBOMAnalysis.analyse(BOMDocument.recognize(fixtureTree("aibom/zephyr-7b-beta.reference.aibom.json"))!)!
    let generated = AIBOMAnalysis.analyse(BOMDocument.recognize(fixtureTree("aibom/zephyr-7b-beta.generated.aibom.json"))!)!

    @Test func anSBOMIsNotAnAIBOM() {
        #expect(AIBOMAnalysis.analyse(BOMDocument.recognize(fixtureTree(laravelPath))!) == nil)
    }

    @Test func referenceModelIsTheSubject() {
        let m = reference.model
        #expect(m.component.displayName == "HuggingFaceH4/zephyr-7b-beta")
        #expect(m.component.isSubject)
        #expect(m.task == "text-generation")
        #expect(m.architecture == "MistralForCausalLM")
        #expect(m.parameters == 7_241_732_096)
        #expect(m.contextLength == 32768)
        #expect(m.fileSize == 28_967_059_598)
        #expect(m.limitations.count == 2)
        #expect(m.useCases == ["Chat"])
    }

    @Test func referenceFamily() {
        #expect(reference.model.ancestors.map(\.component.displayName) == ["mistralai/Mistral-7B-v0.1"])
        #expect(reference.model.ancestors[0].component.licenses.map(\.label) == ["Apache-2.0"])
        #expect(reference.model.ancestors[0].datasets.isEmpty)
        let ds = reference.model.datasets
        #expect(ds.map(\.name) == ["HuggingFaceH4/ultrachat_200k", "HuggingFaceH4/ultrafeedback_binarized"])
        #expect(ds.allSatisfy { $0.component != nil && $0.component?.licenses.map(\.label) == ["MIT"] })
    }

    @Test func referenceGaps() {
        // Only what the file leaves out: no hash on the model, no training data stated for the base model.
        #expect(reference.gaps.map(\.kind) == [.noHash, .ancestorWithoutDatasets("mistralai/Mistral-7B-v0.1")])
    }

    @Test func generatedModelIsTheOnlyModelComponent() {
        let m = generated.model
        #expect(m.component.displayName == "HuggingFaceH4/zephyr-7b-beta")
        #expect(!m.component.isSubject)
        #expect(m.architecture == "mistral")
        #expect(m.contextLength == 32768)
        #expect(m.parameters == nil)
        #expect(m.ancestors.isEmpty)
        #expect(m.datasets.map(\.name) == ["HuggingFaceH4/ultrachat_200k", "HuggingFaceH4/ultrafeedback_binarized"])
        #expect(m.datasets.allSatisfy { $0.component == nil })
    }

    @Test func generatedGaps() {
        #expect(generated.gaps.map(\.kind) == [
            .subjectIsNotTheModel("job-2026-11-16-22:03:54"),
            .noAncestors,
            .datasetNamedOnly("HuggingFaceH4/ultrachat_200k"),
            .datasetNamedOnly("HuggingFaceH4/ultrafeedback_binarized"),
            .noHash,
        ])
        // Every gap opens its evidence in the source.
        #expect(generated.gaps.allSatisfy { if case .absent = $0.evidence { true } else if case .located = $0.evidence { true } else { false } })
    }

    @Test func aModelInsideAnSBOMKeepsTheSBOMViews() {
        let doc = bom(#"""
        {"bomFormat":"CycloneDX","specVersion":"1.6","components":[
          {"type":"library","name":"left-pad"},{"type":"machine-learning-model","name":"m"}]}
        """#)!
        #expect(AIBOMAnalysis.analyse(doc) == nil)
    }

    @Test func modelCardWithAncestorsOfAncestors() {
        let doc = bom(#"""
        {"bomFormat":"CycloneDX","specVersion":"1.6","metadata":{"component":{"type":"machine-learning-model","name":"c",
          "pedigree":{"ancestors":[{"type":"machine-learning-model","name":"b",
            "pedigree":{"ancestors":[{"type":"machine-learning-model","name":"a"}]}}]}}}}
        """#)!
        let a = AIBOMAnalysis.analyse(doc)!
        #expect(a.model.ancestors.map(\.component.displayName) == ["b"])
        #expect(a.model.ancestors[0].ancestors.map(\.component.displayName) == ["a"])
        #expect(a.generations == 3)
    }
}
