# The gap list for the client

Updated: 2026-11-19. Status: built (`GapList` in BOMCore, `GapExport` in the app).

## Why

After the SBOM Kickstart the client's team needs a written list of what to fix; until now that was
screenshots (Toni, 2026-11-19: clients ask for it).

## What

File › Export Gap List as PDF… (⇧⌘E) / as CSV…, and "Export gap list" on Completeness. Only for
CycloneDX (SPDX has no TR verdict, see `design-spdx.md`). Made locally; nothing leaves the Mac.
`--export-gaps <folder>` writes both for checks.

- **CSV**: one row per gap (every offender of the TR-03183-2 checks): part, component, version,
  package URL, bom-ref, field, TR section, rule id, JSON Pointer to where the field is or would be.
  RFC 4180, UTF-8 with a byte order mark (spreadsheets read umlauts), localised headers and names;
  a cell that would start with = + - @ gets an apostrophe, so text from the SBOM never runs as a
  formula.
- **PDF handout** (A4, paginated, title and page numbers on each page): product, file name, tool,
  format, date, the file's SHA-256; the sentence that it reports presence and form only and is not
  a statement of conformity; the verdict and the summary per part as Completeness shows them; then
  per rule its section and either the pointer (SBOM, product) or the components that lack it (50
  names, then "and n more; the CSV lists all of them").

Not yet: a client logo or a cover page; choosing which rules to include.
