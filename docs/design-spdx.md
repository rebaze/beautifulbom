# SPDX in the workshop views

Updated: 2026-11-19. Status: in progress.

## Why

Clients bring what their tools write. Syft and Trivy write SPDX 2.3 JSON on request, cdxgen
SPDX 3.0.1 JSON-LD; until now an SPDX file opened in Source only, in front of the room.

## What SPDX gets

Overview, Composition (map, vendors, licences, depth), Components with their pages and "Why is it
here?", Source. Every statement keeps its evidence: the button opens the SPDX bytes.

**No TR-03183-2 judgement for SPDX.** rio refuses SPDX ("not a CycloneDX document") and lists SPDX
conversion as out of scope; two rebaze tools must never judge the same file differently, so neither
does. Completeness says so in one sentence and shows what the file does state, without a verdict;
the Overview's TR card becomes that sentence.

## Mapping (SPDX 2.3 JSON)

| View needs | SPDX 2.3 |
| --- | --- |
| Format line | `spdxVersion` ("SPDX-2.3") |
| Product (subject) | the package a `DESCRIBES` relationship (or `documentDescribes`) of the document names |
| Made when | `creationInfo.created` |
| Made by | `creationInfo.creators`, `Tool: name-version` |
| Manufacturer | `creationInfo.creators`, `Organization:` (the SBOM's author) |
| Component | each package but the subject; reference = `SPDXID` |
| name, version | `name`, `versionInfo` |
| type | `primaryPackagePurpose`, lowercased (`APPLICATION` → application) |
| package URL, vendor, ecosystem | `externalRefs` with `referenceType` `purl` |
| licence | `licenseConcluded`, else `licenseDeclared`; `NOASSERTION`/`NONE` are no licence |
| supplier, author | `supplier`, `originator` (`Organization: X` / `Person: X` → X) |
| hashes | `checksums` (`SHA256` → SHA-256) |
| references | `downloadLocation` (distribution), `homepage` (website), unless `NOASSERTION` |
| description | `description`, else `summary` |

## Dependencies

Edges come from the dependency relationships only: `DEPENDS_ON` (A → B), and `DEPENDENCY_OF`,
`DEV_DEPENDENCY_OF`, `BUILD_DEPENDENCY_OF`, `RUNTIME_DEPENDENCY_OF`, `OPTIONAL_DEPENDENCY_OF`,
`PROVIDED_DEPENDENCY_OF`, `TEST_DEPENDENCY_OF` (A of B: B → A). `CONTAINS` (A → B) counts only
when no package depends on B: Syft lists every package as contained in the scanned directory,
which would otherwise make everything "chosen directly"; Trivy chains filesystem → application
(the lock file) → project package by `CONTAINS`, then `DEPENDS_ON`, and that chain stays. The
evidence of an edge is its relationship object.

## SPDX 3.0 (JSON-LD)

cdxgen writes `@graph` with `software_Package` elements and `Relationship` elements
(`from`, `to[]`, `relationshipType` such as `dependsOn`, `contains`, `describes`). Same mapping
with the 3.0 names; second step, after 2.3.
