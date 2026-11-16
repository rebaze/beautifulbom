#!/usr/bin/env bash
# Checks downloaded release assets as a Mac that never saw the app would meet them:
#   scripts/verify-release.sh --dir <folder with the dmg, zip and checksums.txt> --version 0.1.0
# The checksums match; both files carry the quarantine mark a browser sets; the disk image and
# the app in it and in the zip are signed with rebaze's Developer ID (strict), Gatekeeper accepts
# them as notarized, the tickets are stapled; the app says the expected version, has no
# get-task-allow, is the same code in both assets, and starts: it renders a bundled sample.
# Evidence goes to <folder>/verification/.
#
# --rehearsal checks ad hoc assets from scripts/release.sh --ad-hoc: everything except the
# quarantine mark and the Developer ID, Gatekeeper and stapler checks.
set -euo pipefail

ORIGIN="Developer ID Application: rebaze GmbH (32Z95ATB2T)"
DIR="" VERSION="" REHEARSAL=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) DIR="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --rehearsal) REHEARSAL=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$DIR" && -n "$VERSION" ]] || { echo "usage: $0 --dir <folder> --version <x.y.z> [--rehearsal]" >&2; exit 2; }

DIR="$(cd "$DIR" && pwd)"
DMG="$DIR/BeautifulBOM-$VERSION.dmg"
ZIP="$DIR/BeautifulBOM-$VERSION.zip"
EVIDENCE="$DIR/verification"
WORK="$(mktemp -d)"
MOUNT="$WORK/mount"
rm -rf "$EVIDENCE" && mkdir -p "$EVIDENCE" "$MOUNT"
cleanup() { hdiutil detach -quiet "$MOUNT" 2>/dev/null || true; rm -rf "$WORK"; }
trap cleanup EXIT

say() { printf '\n==> %s\n' "$*"; }
fail() { echo "verify: $*" >&2; exit 1; }

# with_timeout <seconds> <command...>: macOS has no timeout(1) without coreutils; perl's alarm
# kills the command when time is up.
with_timeout() { perl -e 'alarm shift; exec @ARGV or die "exec: $!"' "$@"; }

say "Checksums"
[[ -f "$DMG" && -f "$ZIP" && -f "$DIR/checksums.txt" ]] || fail "expected $(basename "$DMG"), $(basename "$ZIP") and checksums.txt in $DIR"
listed="$(awk '{print $2}' "$DIR/checksums.txt" | sort | tr '\n' ' ')"
[[ "$listed" == "BeautifulBOM-$VERSION.dmg BeautifulBOM-$VERSION.zip " ]] || fail "checksums.txt lists: $listed"
(cd "$DIR" && shasum -a 256 -c checksums.txt) | tee "$EVIDENCE/checksums.txt"

# Gatekeeper judges quarantined code on first launch; macOS kills ad hoc code from a quarantined
# image, so a rehearsal leaves the mark off.
if [[ $REHEARSAL == 0 ]]; then
  say "Marking both files as downloaded (quarantine)"
  quarantine="0081;$(printf '%x' "$(date +%s)");Safari;$(uuidgen)"
  xattr -w com.apple.quarantine "$quarantine" "$DMG"
  xattr -w com.apple.quarantine "$quarantine" "$ZIP"
else
  xattr -d com.apple.quarantine "$DMG" "$ZIP" 2>/dev/null || true
fi

check_signature() { # check_signature <label> <path> <spctl type>
  local label="$1" path="$2" type="$3" report="$EVIDENCE/$1.txt"
  codesign --verify --strict --deep --verbose=2 "$path" 2>&1 | tee "$report"
  codesign -dvv "$path" >> "$report" 2>&1
  if [[ $REHEARSAL == 1 ]]; then echo "(rehearsal: Developer ID, Gatekeeper and stapler not checked)"; return; fi
  grep -qxF "Authority=$ORIGIN" "$report" || fail "$label is not signed by $ORIGIN"
  local gatekeeper=(spctl --assess -vv --type "$type")
  [[ "$type" == open ]] && gatekeeper+=(--context context:primary-signature)
  "${gatekeeper[@]}" "$path" > "$EVIDENCE/$label-gatekeeper.txt" 2>&1 || { cat "$EVIDENCE/$label-gatekeeper.txt"; fail "Gatekeeper rejects $label"; }
  cat "$EVIDENCE/$label-gatekeeper.txt"
  grep -qx 'source=Notarized Developer ID' "$EVIDENCE/$label-gatekeeper.txt" || fail "$label is not accepted as notarized"
  grep -qxF "origin=$ORIGIN" "$EVIDENCE/$label-gatekeeper.txt" || fail "$label has another origin"
  xcrun stapler validate "$path" | tee -a "$report"
}

check_app() { # check_app <label> <app>
  local label="$1" app="$2" plist="$2/Contents/Info.plist"
  say "The app from the $label"
  [[ "$(plutil -extract CFBundleShortVersionString raw -o - "$plist")" == "$VERSION" ]] || fail "the app in the $label is not version $VERSION"
  echo "version $VERSION ($(plutil -extract CFBundleVersion raw -o - "$plist"))"
  if codesign -d --entitlements - "$app" 2>/dev/null | grep -q get-task-allow; then
    fail "the app in the $label carries get-task-allow"
  fi
  check_signature "app-from-$label" "$app" execute
}

say "The disk image"
check_signature dmg "$DMG" open
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MOUNT" "$DMG"
[[ -L "$MOUNT/Applications" ]] || fail "the disk image has no link to Applications"
check_app dmg "$MOUNT/Beautiful BOM.app"

ditto -x -k "$ZIP" "$WORK/zip"
check_app zip "$WORK/zip/Beautiful BOM.app"

cdhash() { codesign -dvvv "$1" 2>&1 | sed -n 's/^CDHash=//p'; }
[[ "$(cdhash "$MOUNT/Beautiful BOM.app")" == "$(cdhash "$WORK/zip/Beautiful BOM.app")" ]] \
  || fail "the disk image and the zip hold different builds"

say "Starting the app from the disk image: it renders a bundled sample"
app="$MOUNT/Beautiful BOM.app"
with_timeout 90 "$app/Contents/MacOS/BeautifulBOM" -ApplePersistenceIgnoreState YES \
  --open "$app/Contents/Resources/laravel-7.12.0.cdx-1.4.json" --view overview --language en \
  --snapshot "$EVIDENCE/overview.png" --window-size 1440x900 || fail "the app did not render a snapshot"
[[ -s "$EVIDENCE/overview.png" ]] || fail "no snapshot written"
echo "rendered $EVIDENCE/overview.png"

say "Verified: BeautifulBOM $VERSION"
