# Working on Beautiful BOM

Updated: 2026-11-17. Read this first; it is the shared guide for every agent (`CLAUDE.md` points
here). Read further only what your task needs.

## Why this app exists

From the proposal (Toni Menzel, rebaze/rebaze-sscs#151):

> Opening a bill of materials should feel like reading a document. In workshops and everyday
> inspection we fall back to a text editor showing JSON. Beautiful Bill of Materials (working
> title) is a native Apple reader for SBOMs, later AIBOMs and other BOMs: readable where
> abstraction helps, always one step from the exact bytes that support what is shown. For
> practitioners, customer workshops and teaching; monetization is not the driver.

The defining interaction: open a BOM, select something, read it, **reveal it in the source**, copy
its path or bytes, and come back without losing your place. Every statement on screen leads to the
bytes that support it.

## Who rebaze is, and where the app is used

rebaze (rebaze.de, rebaze GmbH) is Toni Menzel's consultancy for **software supply chain
governance**: he clarifies with management who decides what, introduces the processes with the
teams, enforces them in the pipelines, and hands everything over. Laws and audits (CRA, NIS2, DORA,
BSI IT-Grundschutz, ISO 27001) are reasons clients call, never a promise of conformity. Website and
positioning live in rebaze/rebaze-sscs; you do not need it for app work.

The app serves three situations, in this order:

1. **The SBOM Kickstart workshop.** rebaze's entry offer: five days, one product, fixed price. On
   day 5 Toni presents the client's SBOM to a mixed room (management and developers) on a
   projector: what the product is made of, how deep it goes, where the gaps are against BSI
   TR-03183-2. The workshop views (Overview, Composition with the map, Completeness, Components) and
   presentation size (⌥⌘P) exist for this. A client's SBOM is opened on Toni's Mac and never leaves
   it; nothing is uploaded.
2. **Talks.** The AIBOM view shows what an AI bill of materials could say and what tools write
   today (the two Zephyr samples on the welcome window).
3. **Teaching and everyday inspection** by practitioners.

rio (github.com/rebaze/rio, Apache-2.0) is rebaze's open-source evidence compiler. The
Completeness rules are ported from rio's `bsi-tr-03183-2@2.1.0` profile and parity-tested against
it (`Fixtures/parity/`, `make parity-refresh`), because two rebaze tools must never judge the same
client SBOM differently in one workshop. rebaze does not require rio, and the app does not either.

## Rules that hold everywhere

- **Never claim conformity.** Completeness reports presence and form of fields only and says so; no
  invented scores; nothing on screen that the file does not say (licence families say they are
  derived). `make strings-check` rejects "compliant", "konform" and the like.
- **No customer data in the repository**, not even git-ignored. Fixtures are public (CycloneDX
  bom-examples, CC0; rio's synthetic cases, Apache-2.0; public Hugging Face metadata) or synthetic,
  each folder with a NOTICE.
- **The reader never goes online**: no network access, uploads or accounts.
- **BOMCore** (`Packages/BOMCore`) has no dependencies and stays shareable with a later iPad app;
  logic goes there, tests first (Swift Testing).
- **Every user-visible string** goes through `L()` / `Lp()` with English and German in
  `App/Localizable.xcstrings`. German uses formal "Sie" and the industry's English terms (SBOM,
  AIBOM, Finding); never "Stückliste".
- **Large files**: stay responsive on 50 MB SBOMs with more than 100,000 components
  (`make fixtures` writes them to `Fixtures/generated/`).
- **Look**: Apple's Human Interface Guidelines; system colours in the UI; the serif for headings
  and numbers; brand only in the icon, the wordmark, the welcome window and About.
- Never add Co-Authored-By lines or any AI attribution to commits, PRs or issues.

## How Toni works with agents

- Once a direction is set, build and show; ask only for his decisions or for outward-facing steps
  (pushing, publishing, posting issues, anything signed).
- Show, don't describe: look changes go through mockups first, then `--snapshot` renders. Put
  images in `build/screenshots/` with an `index.html`; Toni views them from another machine with
  `python3 -m http.server 8790 --bind 0.0.0.0 --directory build/screenshots`.
- What snapshots cannot show goes into `docs/hand-check.md` for him.
- Before building an idea for the offer or the product, check it against demand, proof and capacity.

## Start here

1. `README.md`: what it does, build and run, launch options.
2. `docs/roadmap.md`: the current state and **the next step** (the signed release pipeline).
3. The design for the area you touch: `docs/design.md` (source reader), `docs/design-workshop-views.md`,
   `docs/design-branding.md`, `docs/design-beautiful-views.md`, `docs/spike-aibom.md` (AIBOM view).
4. `docs/findings.md` (measurements, review results) and `docs/checklist.md` (what is verified).

## Verify

- `make test`: BOMCore tests and the strings check.
- `make app CONFIG=Release`, then `make snapshot FILE=… OUT=…` to see a view. Shell screen capture
  does not work for agents here; the app renders its own window (launch options in the README).
- Tools: Xcode 27.2, xcodegen, xcbeautify (Homebrew).

## Release

`make install` (own Mac) and `make dmg` (signed ad hoc) work today. A signed and notarized release
is the next step: see `docs/roadmap.md`.
