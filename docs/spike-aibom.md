# Spike: AIBOMs (2026-11-16)

Toni, 2026-11-16: an AIBOM view "mostly for talks"; run a spike first. Built after Toni's "yes go"
(2026-11-16): see "Built" at the end.

## What we did

- Ran the OWASP GenAI Security Project's AIBOM Generator (commit 45851cb, v1.0.2) locally, without
  its optional summariser, on four public Hugging Face models: HuggingFaceH4/zephyr-7b-beta,
  google-bert/bert-base-uncased, Qwen/Qwen2.5-7B-Instruct,
  distilbert/distilbert-base-uncased-finetuned-sst-2-english. Output: CycloneDX 1.6 and 1.7
  (identical but for the version), about 5 to 6 KB each; copies in `build/aiboms/` (not committed).
- Opened them in the app, and compared them with the models' metadata on Hugging Face.
- Mocked up an AI view: `build/screenshots/mockups/ai-full.png` (a complete AIBOM) and
  `ai-generated.png` (the generator's file, gaps shown).

## What an AIBOM can say (CycloneDX 1.5+)

- The model as a `machine-learning-model` component with a `modelCard`: task, architecture,
  datasets, inputs and outputs, considerations (limitations, risks, fairness, energy).
- Datasets as `data` components with their own licence and version.
- The base model through `pedigree.ancestors`; a product's SBOM can point at the AIBOM with BOM-Link.

## What the generator writes today

- One component: the model, with licence, task, architecture, context length, vocabulary, file
  size, commit and links.
- Datasets only as names inside the model card: no licence, no version, not components.
- No base model, although the generator reads it from Hugging Face (`extractor.py` reads
  `base_model`; it is not written). Zephyr comes from mistralai/Mistral-7B-v0.1 per Hugging Face.
- `metadata.component` is the generator's job ("job-2026-11-16-22:03:54"), not the model, so the
  app today shows the job as the product.
- "No description available"; a limitation cut off mid-sentence; no hash of the model files; a
  `serialNumber` property that is not a UUID.

## What the app does with them today

Opens them as SBOMs: the job as headline, TR-03183-2 gaps that do not apply to a model, and the
model card visible only in Source.

## Proposal

1. An AI view when the BOM's main component is a `machine-learning-model` (or the only component
   is one): tabs Model, Family tree, Datasets, Source. The family tree draws base models
   (pedigree.ancestors), datasets (data components or model-card datasets), and gaps in red dashes,
   as the SBOM views do: presence and form only, nothing invented.
2. For talks, two files side by side: the generator's AIBOM, and a hand-made reference AIBOM for
   the same model built from its public model card, using the standard fully. The reference file
   is labelled as hand-made in its metadata.
3. Optional, Toni's call: report the base-model and metadata.component findings upstream to the
   OWASP project.

## Built (2026-11-16)

- `AIBOMAnalysis` in BOMCore (`AIBOMTests`): the model is the subject when it is a
  `machine-learning-model`, else the first model when every component is a model or data; a model
  inside an ordinary SBOM keeps the SBOM views. Base models from `pedigree.ancestors` (any depth),
  datasets inline or as `data` components, facts from model-card properties, and the gaps above.
- The Model tab (`AIModelView`) replaces the SBOM tabs for an AIBOM: header, facts, family tree
  with arrows, "Left out" beside or below it, and what the model card says. Every node and gap
  opens its source.
- Fixtures in `Fixtures/aibom/` (see its NOTICE): the generator's Zephyr AIBOM unchanged, and the
  hand-made reference, both valid against the CycloneDX 1.6 schema. Both are samples on the welcome
  window.
- Not built: a Datasets tab (the datasets stand on the tree), "used by your product" (needs an SBOM
  linking the AIBOM with BOM-Link), SPDX 3 AI profiles.
