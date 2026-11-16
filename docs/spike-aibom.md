# Spike: AIBOMs (2026-11-16)

Toni, 2026-11-16: an AIBOM view "mostly for talks"; run a spike first. Throwaway; nothing here is
built into the app yet.

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
