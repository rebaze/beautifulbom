# Draft: issue for the OWASP AIBOM Generator (parked)

Not posted. Toni decides whether and when, under his GitHub account; repository
GenAI-Security-Project/aibom-generator. Checked against its code at commit 45851cb on 2026-11-16.
Possible additions: Hugging Face publishes SHA-256 hashes for the large model files, and CycloneDX
1.5+ has an external reference type `model-card`.

---

Title: Base model is read from the model card but not written to the AIBOM; metadata.component describes the generator run

**Version:** 1.0.2 (commit 45851cb), CLI, no inference or summarizer.
**Example:** `python3 -m src.cli HuggingFaceH4/zephyr-7b-beta`

**1. Base model missing**

`extractor.py` reads `base_model` from the card data (line 717); for zephyr-7b-beta that is `mistralai/Mistral-7B-v0.1`. The AIBOM does not contain it anywhere. CycloneDX 1.5+ can express it as the model component's `pedigree.ancestors`, for example:

```json
"pedigree": { "ancestors": [ {
  "type": "machine-learning-model",
  "bom-ref": "pkg:huggingface/mistralai/Mistral-7B-v0.1",
  "name": "Mistral-7B-v0.1", "group": "mistralai",
  "purl": "pkg:huggingface/mistralai/Mistral-7B-v0.1"
} ] }
```

For fine-tuned models the lineage is often the most important supply-chain fact.

**2. `metadata.component` is the generator run, not the model**

`service.py` (around line 425) sets `metadata.component` to an application named `job-<timestamp>` ("Generating SBOM for …") and makes it depend on the model. Tools that read `metadata.component` as the BOM's subject show the job instead of the model. Making the model itself `metadata.component` (and leaving the generator in `metadata.tools`, where it already is) would match how CycloneDX describes the subject.

**3. Datasets only named inline**

Training datasets appear only as `modelCard.modelParameters.datasets[].name`. Their licences (MIT for both zephyr datasets on the Hub) are not recorded. Emitting them as `data` components with `licenses`, referenced from the model card by `ref`, would carry the licence.

**Smaller observations**

- `description` is "No description available" although the card has a "Model description" section ("A 7B parameter GPT-like model fine-tuned on a mix of publicly available, synthetic datasets.").
- `technicalLimitations` is cut off mid-sentence.
- The model card property `serialNumber` has the value `urn:uuid:HuggingFaceH4-zephyr-7b-beta`, which is not a UUID.

Happy to provide the generated file and a hand-written reference AIBOM for the same model that validates against the CycloneDX 1.6 schema.
