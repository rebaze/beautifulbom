# Roadmap

Updated: 2026-11-17.

## Where it stands

A proof of concept that works end to end: the source reader, the workshop views with the map and
licence families, the AIBOM view, branding, English and German, 132 tests. Moved with its history
from rebaze/rebaze-sscs on 2026-11-16. Open from the last session: Toni's hand check
(`docs/hand-check.md`) and VoiceOver access to the map's slices (`docs/findings.md`).

## Next step: the release pipeline (signed DMG and app)

Goal: a tag produces a Developer ID signed, notarized and stapled DMG and app on a GitHub release
that opens on any Mac without a Gatekeeper prompt. Decided by Toni on 2026-11-16: signing comes with
this repository, not before.

**Built on 2026-11-17, not yet run on GitHub** (how it works: `docs/release.md`):

- `ci.yaml`: `make test` and `make dmg` on every push to `main` and every pull request, on
  GitHub's preview runner `xcode-27` (macOS 27 with Xcode 27.2 pinned); no secrets.
- `release.yaml` on a tag `v*`: CI, then `scripts/release.sh` in the environment `release-build`
  (tag must equal `CFBundleShortVersionString`, build number = run number, Developer ID with
  hardened runtime and secure timestamp, `notarytool`, stapled app and DMG, zip, checksums; fails
  without the credentials), a **draft** release, `verify`, then publish.
- `verify-release.yaml`: `scripts/verify-release.sh` on fresh macOS 15 and macOS 27 runners;
  rio's checks (`codesign --verify --strict`, `spctl` reports `source=Notarized Developer ID` and
  the rebaze origin, `stapler validate`) plus quarantine, versions and a launch that renders a
  sample. Unlike rio, it runs on the draft, so a release that fails it never becomes public.
- Rehearsed locally with ad hoc signing (`scripts/release.sh --ad-hoc`); actionlint and shellcheck
  clean.

Open, Toni's part (outward-facing, credentials):

1. Push the commit; CI is the first test of the `xcode-27` runner.
2. Create the environment `release-build` in this repository (deployment rule: tags `v*`) with the
   secrets `MACOS_SIGN_P12`, `MACOS_SIGN_PASSWORD`, `MACOS_NOTARY_KEY` and the variables
   `MACOS_NOTARY_KEY_ID`, `MACOS_NOTARY_ISSUER_ID` (rio's values, from 1Password), or let the agent
   set them with `gh` from the 1Password service account.
3. The repository is private: release assets then download only for signed-in members. Public
   repository, or another place for the download (rebaze.de)?
4. Push `v0.1.0`.

Done when: a tag `v0.1.0` produces both assets; a Mac that never saw the app opens the downloaded
DMG and the app without "Open Anyway" (`docs/hand-check.md`, 7); the verification job is green.

## After that, in Toni's order of 2026-11-16

1. **SBOMs as clients produce them**: generate SBOMs from public projects (for example
   rebaze/sbom-kickstart-demo) with Syft, Trivy, cdxgen and the CycloneDX Maven plugin; check the
   views hold up; give SPDX files the workshop views (today SPDX opens in Source only).
2. **Talk material** for "What an AIBOM could say, and what tools write today", when a talk is set.
3. **Comparing two SBOMs**: release against release, tool against tool.

## Parked

- The OWASP AIBOM Generator issue (`docs/drafts/owasp-aibom-issue.md`): base model, metadata
  component, dataset licences. Toni decides whether and when it is posted, under his account.
- A better AIBOM generator from Hugging Face data (base model, dataset licences and file hashes are
  all public): a separate tool, never inside the reader, which stays offline.
- VoiceOver access to the map's slices.
- Distribution beyond GitHub releases: a Homebrew cask, a download on rebaze.de. Not the Mac App
  Store.
- Not wanted in this app: a Dependency-Track front end (network, accounts; a different product).
