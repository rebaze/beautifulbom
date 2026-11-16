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

1. **CI on every push and pull request** (no secrets): macOS runner, `brew install xcodegen
   xcbeautify`, `make test`, `make app CONFIG=Release`. Check first that the hosted runner image
   offers the Xcode the project needs (Xcode 27.2, macOS 27 SDK; deployment target macOS 15); pin
   the Xcode version with `xcode-select`.
2. **Release workflow on a tag `v*`**, in a protected environment (as in rio, `release-build`):
   - the tag must equal `CFBundleShortVersionString` in `project.yml`; the build number is the run
     number;
   - import the Developer ID certificate ("Developer ID Application: rebaze GmbH (32Z95ATB2T)")
     into a temporary keychain from `MACOS_SIGN_P12` and `MACOS_SIGN_PASSWORD`;
   - sign the app with hardened runtime and a secure timestamp; notarize with `notarytool` using
     the App Store Connect key (`MACOS_NOTARY_KEY`, `MACOS_NOTARY_KEY_ID`, `MACOS_NOTARY_ISSUER_ID`);
     staple the app;
   - build the DMG as `make dmg` does, sign it, notarize it, staple it;
   - publish two assets, `BeautifulBOM-<version>.dmg` and `BeautifulBOM-<version>.zip` (`ditto -c -k
     --keepParent` of the app), with SHA-256 checksums;
   - a release without the credentials fails; it never falls back to unsigned assets.
3. **Verification job** after publishing, as rio's `verify-release`: download the assets on a
   fresh runner; `codesign --verify --strict`, `spctl --assess` reports
   `source=Notarized Developer ID` and `origin=Developer ID Application: rebaze GmbH (32Z95ATB2T)`,
   `stapler validate` on both.

Reuse: rio's `.github/workflows/release.yaml` and `verify-release.yaml` and its
`tools/verify-release.py` show the same credentials and checks for Go binaries.

Toni's part (outward-facing, credentials): create the `release-build` environment in this
repository and add the five secrets and variables (the values rio uses, from 1Password), or tell the
agent to set them with `gh secret set` from the 1Password service account. Pushing a tag is his
call too.

Done when: a tag `v0.1.0` produces both assets; a Mac that never saw the app opens the downloaded
DMG and the app without "Open Anyway"; the verification job is green.

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
