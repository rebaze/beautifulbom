#!/usr/bin/env bash
# Renders the README's pictures into docs/images/ from the public samples, with the Release app
# (make app CONFIG=Release first). 1440 × 900 windows, scaled to 1760 px wide: sharp on Retina at
# GitHub's column width.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=docs/images
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"
L=Fixtures/public/laravel-7.12.0.cdx-1.4.json
Z=Fixtures/aibom/zephyr-7b-beta.reference.aibom.json

shot() { # shot <name> <make snapshot arguments...>
  local name="$1"; shift
  make -s snapshot CONFIG=Release UILANG=en OUT="$TMP/$name.png" "$@" 2>&1 | grep -v ApplePersistence || true
  [[ -s "$TMP/$name.png" ]] || { echo "no snapshot: $name" >&2; exit 1; }
  sips -Z 1760 "$TMP/$name.png" --out "$OUT/$name.png" > /dev/null
  echo "$OUT/$name.png"
}

shot overview       FILE=$L VIEW=overview
shot overview-dark  FILE=$L VIEW=overview APPEARANCE=dark
shot evidence       FILE=$L VIEW=overview EVIDENCE=sbom.timestamp
shot composition    FILE=$L VIEW=composition
shot completeness   FILE=$L VIEW=completeness
shot component      FILE=$L COMPONENT=doctrine/lexer-1.2.3.0
shot source         FILE=$L VIEW=source SELECT=/components/3
shot aibom          FILE=$Z
