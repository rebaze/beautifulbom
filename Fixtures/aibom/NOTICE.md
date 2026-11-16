# AIBOM fixtures

Both describe the public model HuggingFaceH4/zephyr-7b-beta (MIT) and contain only public metadata
from Hugging Face. No customer data.

- `zephyr-7b-beta.generated.aibom.json`: written on 2026-11-16 by the OWASP GenAI Security
  Project's AIBOM Generator 1.0.2 (https://github.com/GenAI-Security-Project/aibom-generator,
  commit 45851cb, Apache-2.0), unchanged. See `docs/spike-aibom.md`.
- `zephyr-7b-beta.reference.aibom.json`: hand-made by rebaze for talks from the model cards and
  API metadata of HuggingFaceH4/zephyr-7b-beta and mistralai/Mistral-7B-v0.1, read on 2026-11-16;
  it says so in `metadata.properties`. Quotes are from the Zephyr model card (MIT). It uses the
  standard fully: the base model under `pedigree.ancestors`, the datasets as `data` components
  referenced from the model card.
