# SBOMs as the tools write them

Written by `scripts/real-sboms.sh` on 2026-11-19 with each tool's default settings (versions in
`TOOLS.txt`: Syft 1.57.2, Trivy 0.76.2, cdxgen 12.9.2, CycloneDX Maven plugin 2.9.1), from inside
each project with `.` as the target, as a CI job runs them. Not edited, except that cdxgen's
absolute paths of the local checkout are replaced by `/src`.

| Subject | Source | Revision |
| --- | --- | --- |
| `partner-portal` | rebaze/sbom-kickstart-demo (rebaze's public demo product; illustrative, no customer data) | `6ef22cb` |
| `rio` | rebaze/rio (Apache-2.0) | `v0.10.2` |
| `juice-shop` | juice-shop/juice-shop (MIT) | `v20.4.0` |
| `python-slim` | the public image `python:3.13-slim` | `sha256:e48f59cd…` |

The files describe public software; the subjects' licences apply to the subjects. Larger outputs
(Juice Shop from Syft and cdxgen, the image from Syft and cdxgen) are not committed:
`scripts/real-sboms.sh` writes them to `Fixtures/generated/real/`.
