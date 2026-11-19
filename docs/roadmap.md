# Roadmap

Updated: 2026-11-17.

## Where it stands

A proof of concept that works end to end: the source reader, the workshop views with the map and
licence families, the AIBOM view, branding, English and German, 132 tests. Moved with its history
from rebaze/rebaze-sscs on 2026-11-16. Open: Toni's hand check
(`docs/hand-check.md`) and VoiceOver access to the map's slices (`docs/findings.md`).

## Done: the release pipeline (2026-11-17)

`v0.1.0` is out: https://github.com/rebaze/beautifulbom/releases/tag/v0.1.0. The disk image and
the zip are signed with rebaze's Developer ID, notarized and stapled; `verify` passed on fresh
macOS 15 and macOS 27 runners (Gatekeeper: `source=Notarized Developer ID`, origin rebaze GmbH),
and again on Toni's Mac from the public download. The repository is public since 2026-11-17.
How to release: `docs/release.md`. Open: hand-check.md section 7 (the DMG on a Mac that never saw
the app); whether the repository gets a licence.

## Done: SBOMs as clients produce them (2026-11-19)

Syft, Trivy, cdxgen and the CycloneDX Maven plugin on four public subjects, every view checked
(`scripts/real-sboms.sh`, `scripts/real-sweep.sh`, `docs/findings.md`); nine real CycloneDX files
in the rio parity tests; SPDX 2.3 and 3.0 get every view without a TR verdict
(`docs/design-spdx.md`).

## Next, in Toni's order of 2026-11-19

1. ~~Comparing two SBOMs~~: built 2026-11-19 (`docs/design-compare.md`).
2. **The gap list for the client**: TR-03183-2 gaps per part and component as a PDF handout and
   CSV, made locally; clients ask for a written list (Toni, 2026-11-19).
3. **Talk material** for "What an AIBOM could say, and what tools write today", when a talk is set.

## Parked

- The OWASP AIBOM Generator issue (`docs/drafts/owasp-aibom-issue.md`): base model, metadata
  component, dataset licences. Toni decides whether and when it is posted, under his account.
- A better AIBOM generator from Hugging Face data (base model, dataset licences and file hashes are
  all public): a separate tool, never inside the reader, which stays offline.
- VoiceOver access to the map's slices.
- Distribution beyond GitHub releases: a Homebrew cask, a download on rebaze.de. Not the Mac App
  Store.
- Not wanted in this app: a Dependency-Track front end (network, accounts; a different product).
