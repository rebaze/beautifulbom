# Working on Beautiful BOM

A native macOS reader for bills of materials (SBOMs and AIBOMs), by rebaze: for looking at them,
and for showing them in client workshops and talks. Proof of concept. Toni Menzel decides.

## Start here

1. `README.md`: what it does, build and run, launch options.
2. The design for the area you touch: `docs/design.md` (source reader), `docs/design-workshop-views.md`,
   `docs/design-branding.md`, `docs/design-beautiful-views.md`, `docs/spike-aibom.md` (AIBOM view).
3. `docs/findings.md` (measurements, review results) and `docs/checklist.md` (what is verified).

## Rules that hold everywhere

- Never claim conformity. Completeness reports presence and form of fields only, and says so;
  no invented scores; nothing on screen the file does not say. `make strings-check` rejects
  "compliant", "konform" and the like.
- Fixtures are public (CycloneDX bom-examples, CC0; rio's synthetic cases, Apache-2.0; public
  Hugging Face metadata) or synthetic, with a NOTICE in their folder. Never customer data, not even
  git-ignored.
- The reader never goes online: no network access, uploads or accounts.
- BOMCore has no dependencies and stays shareable with iOS; logic goes there, with tests first.
- Every user-visible string goes through `L()`/`Lp()` with English and German in
  `App/Localizable.xcstrings`.
- Must stay responsive on 50 MB SBOMs (`make fixtures` writes them to `Fixtures/generated/`).
- Never add Co-Authored-By lines or AI attribution to commits, PRs or issues.

## Verify

- `make test`: BOMCore tests and the strings check.
- `make app CONFIG=Release`, then `make snapshot FILE=… OUT=…` to see a view (screen capture does
  not work for agents here; the app renders its own window, see the launch options in README).
- What snapshots cannot show goes to `docs/hand-check.md` for Toni.

## Release

`make install` (own Mac), `make dmg` (signed ad hoc). Developer ID signing and notarization come
with a release workflow in this repository, reusing rio's setup (see `docs/design.md`, Extraction).
