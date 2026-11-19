# Comparing two SBOMs

Updated: 2026-11-19. Status: built (`BOMComparison`, `CompareView`); mockups in
`build/screenshots/compare/` (A chosen: a document; B, mirrored columns, read like a diff tool).

## The questions

- **Release against release** (one tool, two files): what came, what went, what changed version?
- **Tool against tool** (one source, two tools): what does each find, and why do they differ?
  Juice Shop: cdxgen 1,108 packages, Trivy 533, Syft 584; 532 in all three.

## How it works

File › Compare With… (⌥⌘K) picks a second SBOM (CycloneDX 1.2+ or SPDX 2.3/3.0); the window's own
file is A. The Compare tab appears after Components. `--compare <file>` does the same at launch.

Pairing (`BOMComparison`, BOMCore): identity is the package URL without version, qualifiers and
subpath (`npm/express`), else group and name. Several versions of one package pair as sets: equal
versions first, then the rest in version order as "different version", the remainder on one side
only. Files listed as components are counted, not paired; the products are not paired. Dotted
versions (optional "v") give a direction; anything else is "not comparable".
Entries that pair the same way (same package, kind and versions; Syft lists a GitHub Action once
per workflow) are one row, "listed 3 times"; every count still counts entries, so the numbers add
up to each file's packages.

## The view

A sentence answers the question ("532 packages in both. 576 only in cdxgen, 1 only in trivy.") and
explains what the files state about the difference: how many of the one-sided packages carry
`scope` optional or excluded (cdxgen marks development dependencies so; 509 of its 576). One bar
shows the proportions; "What each file states" puts package URL, version, licence, hash, supplier,
dependencies and ecosystems side by side (the tool-against-tool lesson); then different versions
(with ↗ newer / ↘ older) and the two one-sided lists, 40 rows each and "n more". Sides are named
by their tools when they differ, else by the product versions, else A and B. Rows from file A open
its component page; rows from file B show only (they belong to the other file).

Not yet: opening B's components and evidence; a full list beyond 40 rows; comparing AIBOMs.
