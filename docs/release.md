# Releasing Beautiful BOM

Updated: 2026-11-17.

A tag `v<version>` produces a GitHub release with the app signed with rebaze's Developer ID
("Developer ID Application: rebaze GmbH (32Z95ATB2T)"), notarized and stapled, so it opens on any
Apple silicon Mac with macOS 15 or later without "Open Anyway":

- `BeautifulBOM-<version>.dmg`: the app and a link to Applications, signed, notarized, stapled;
- `BeautifulBOM-<version>.zip`: the same app (`ditto -c -k --keepParent`);
- `checksums.txt`: SHA-256 of both.

The app is arm64 only: the macOS 27 SDK no longer builds for Intel.

## Cutting a release

1. Set `CFBundleShortVersionString` in `project.yml` to the version; commit and push to `main`.
2. Optional: release notes in `docs/releases/v<version>.md`; without them GitHub generates notes.
3. Push the tag: `git tag v0.1.0 && git push origin v0.1.0`. Pushing the tag is the decision to
   release.

The workflows (`.github/workflows/`):

| Workflow | When | What |
| --- | --- | --- |
| `ci.yaml` | push to `main`, pull requests; first job of a release | `make test`, `make dmg` (ad hoc), no secrets |
| `release.yaml` | tag `v*` | CI → build (environment `release-build`) → draft release → verify → publish |
| `verify-release.yaml` | called by the release; by hand for any tag | the downloaded assets, as a new Mac meets them |

The build job refuses a tag that already has a release or draft, a tag that differs from the
version in `project.yml`, and missing credentials: it never falls back to unsigned assets. The build
number (`CFBundleVersion`) is the workflow run number. The release stays a **draft** until
`verify` has passed on macOS 15 and macOS 27, and is then published. If anything fails, delete the
draft (and the tag, if the commit changes), fix, tag again.

`verify` (`scripts/verify-release.sh`) checks the checksums; marks both files as downloaded
(quarantine); verifies the disk image and the app in it and in the zip with `codesign --verify
--strict`; requires `spctl` to report `source=Notarized Developer ID` and `origin=Developer ID
Application: rebaze GmbH (32Z95ATB2T)`; validates the stapled tickets; requires the version, no
`get-task-allow`, the same code in both assets; starts the app from the disk image and renders a
bundled sample. The evidence (reports and the PNG) is kept as a workflow artifact.

Runners: GitHub's preview image `xcode-27` (macOS 27, Xcode 27.2, actions/runner-images#14404);
`scripts/ci-setup.sh` pins `/Applications/Xcode_27.2.app` and fails if the image drops it.

## Credentials (environment `release-build`)

The same values rio uses, from 1Password (vault `agent_vault`):

| Name | Kind | Content |
| --- | --- | --- |
| `MACOS_SIGN_P12` | secret | the Developer ID Application certificate with key, `.p12`, base64 |
| `MACOS_SIGN_PASSWORD` | secret | its password |
| `MACOS_NOTARY_KEY` | secret | the App Store Connect API key, `.p8`, base64 (PEM works too) |
| `MACOS_NOTARY_KEY_ID` | variable | its key ID |
| `MACOS_NOTARY_ISSUER_ID` | variable | its issuer ID |

Create the environment under Settings › Environments with a deployment rule that allows only tags
`v*`, as in rio. `scripts/release.sh` imports the certificate into a temporary keychain, which it
deletes on exit, together with the key file.

## Locally

```sh
scripts/release.sh --ad-hoc                                   # rehearsal: build/release-adhoc/
scripts/verify-release.sh --dir build/release-adhoc --version 0.1.0 --rehearsal
```

The rehearsal runs everything except the Developer ID, notarization, quarantine, Gatekeeper and
stapler steps; its assets are signed ad hoc and must never be published. With the five credentials
in the environment, `scripts/release.sh --tag v0.1.0` builds the real assets into `build/release/`
on any Mac with Xcode 27.2.
