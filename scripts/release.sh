#!/usr/bin/env bash
# Builds the release assets: the app signed with rebaze's Developer ID (hardened runtime, secure
# timestamp), notarized and stapled; the disk image with that app, signed, notarized and stapled;
# a zip of the app; SHA-256 checksums. Writes them to build/release/.
#
#   scripts/release.sh --tag v0.1.0 --build-number 17     the release (needs the credentials)
#   scripts/release.sh --ad-hoc                           a rehearsal of the packaging only
#
# The release needs, in the environment (the values rio uses):
#   MACOS_SIGN_P12          the Developer ID Application certificate and key, .p12, base64
#   MACOS_SIGN_PASSWORD     its password
#   MACOS_NOTARY_KEY        the App Store Connect API key, .p8, base64 or PEM
#   MACOS_NOTARY_KEY_ID     its key ID
#   MACOS_NOTARY_ISSUER_ID  its issuer ID
# Without any of them it fails; it never falls back to unsigned assets. --ad-hoc signs ad hoc,
# does not notarize and writes to build/release-adhoc/, which the release workflow never uploads.
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="Developer ID Application: rebaze GmbH (32Z95ATB2T)"
VERSION="$(make -s version)"
TAG="" BUILD_NUMBER="1" ADHOC=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) TAG="$2"; shift 2 ;;
    --build-number) BUILD_NUMBER="$2"; shift 2 ;;
    --ad-hoc) ADHOC=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

say() { printf '\n==> %s\n' "$*"; }
fail() { echo "release: $*" >&2; exit 1; }

[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || fail "build number must be a positive integer: $BUILD_NUMBER"
if [[ $ADHOC == 1 ]]; then
  OUT=build/release-adhoc
  SIGN_IDENTITY="-"
else
  OUT=build/release
  [[ -n "$TAG" ]] || fail "--tag is required (or --ad-hoc for a rehearsal)"
  # The tag names the version the app says it is; one source: project.yml.
  [[ "$TAG" == "v$VERSION" ]] || fail "tag $TAG does not match CFBundleShortVersionString $VERSION in project.yml"
  missing=()
  for name in MACOS_SIGN_P12 MACOS_SIGN_PASSWORD MACOS_NOTARY_KEY MACOS_NOTARY_KEY_ID MACOS_NOTARY_ISSUER_ID; do
    [[ -n "${!name:-}" ]] || missing+=("$name")
  done
  [[ ${#missing[@]} == 0 ]] || fail "missing macOS signing credentials: ${missing[*]}"
  SIGN_IDENTITY="$IDENTITY"
fi

DMG="$OUT/BeautifulBOM-$VERSION.dmg"
ZIP="$OUT/BeautifulBOM-$VERSION.zip"
STAGE="$OUT/stage"
APP="$STAGE/Beautiful BOM.app"
rm -rf "$OUT" && mkdir -p "$STAGE"

# --- Credentials: a temporary keychain and key file, removed on exit -------------------------
SECRETS="" KEYCHAIN="" OLD_KEYCHAINS=()
cleanup() {
  if [[ -n "$KEYCHAIN" ]]; then
    security list-keychains -d user -s ${OLD_KEYCHAINS[@]+"${OLD_KEYCHAINS[@]}"} || true
    security delete-keychain "$KEYCHAIN" || true
  fi
  [[ -z "$SECRETS" ]] || rm -rf "$SECRETS"
}
trap cleanup EXIT

if [[ $ADHOC == 0 ]]; then
  say "Importing the Developer ID certificate into a temporary keychain"
  SECRETS="$(mktemp -d)"
  chmod 700 "$SECRETS"
  printf '%s' "$MACOS_SIGN_P12" | base64 -D > "$SECRETS/sign.p12"
  if [[ "$MACOS_NOTARY_KEY" == -----BEGIN* ]]; then
    printf '%s\n' "$MACOS_NOTARY_KEY" > "$SECRETS/notary.p8"
  else
    printf '%s' "$MACOS_NOTARY_KEY" | base64 -D > "$SECRETS/notary.p8"
  fi
  KEYCHAIN="$SECRETS/release.keychain-db"
  KEYCHAIN_PASSWORD="$(uuidgen)"
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"; OLD_KEYCHAINS+=("${line//\"/}")
  done < <(security list-keychains -d user)
  security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
  security set-keychain-settings -lut 21600 "$KEYCHAIN"
  security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
  security import "$SECRETS/sign.p12" -k "$KEYCHAIN" -f pkcs12 -P "$MACOS_SIGN_PASSWORD" -T /usr/bin/codesign
  # The intermediate, in case the .p12 lacks it; codesign needs the chain to Apple's root.
  curl -fsSL https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer -o "$SECRETS/DeveloperIDG2CA.cer"
  security import "$SECRETS/DeveloperIDG2CA.cer" -k "$KEYCHAIN" || true
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" > /dev/null
  security list-keychains -d user -s "$KEYCHAIN" ${OLD_KEYCHAINS[@]+"${OLD_KEYCHAINS[@]}"}
  security find-identity -v -p codesigning "$KEYCHAIN" | grep -qF "\"$IDENTITY\"" \
    || fail "the certificate in MACOS_SIGN_P12 is not \"$IDENTITY\""
fi

json_field() { python3 -Ic 'import json,sys
try: print(json.load(sys.stdin).get(sys.argv[1], ""))
except Exception: print("")' "$1"; }

notarize() { # notarize <file>: submit, wait, require Accepted, print Apple's log on anything else
  local file="$1" result status id
  result="$(xcrun notarytool submit "$file" --key "$SECRETS/notary.p8" --key-id "$MACOS_NOTARY_KEY_ID" \
    --issuer "$MACOS_NOTARY_ISSUER_ID" --wait --timeout 30m --output-format json)" || true
  status="$(json_field status <<< "$result")"
  id="$(json_field id <<< "$result")"
  echo "notarization of $(basename "$file"): $status (submission $id)"
  if [[ "$status" != "Accepted" ]]; then
    echo "$result" >&2
    [[ -z "$id" ]] || xcrun notarytool log "$id" --key "$SECRETS/notary.p8" \
      --key-id "$MACOS_NOTARY_KEY_ID" --issuer "$MACOS_NOTARY_ISSUER_ID" >&2 || true
    fail "notarization of $file was not accepted"
  fi
}

sign() { # sign <path>: Developer ID (or ad hoc), hardened runtime, secure timestamp, no entitlements
  local args=(--force --sign "$SIGN_IDENTITY" --options runtime)
  if [[ $ADHOC == 0 ]]; then args+=(--timestamp --keychain "$KEYCHAIN"); fi
  codesign "${args[@]}" "$1"
}

# --- The app ---------------------------------------------------------------------------------
say "Building the Release app $VERSION ($BUILD_NUMBER)"
make app CONFIG=Release XCODEFLAGS="CURRENT_PROJECT_VERSION=$BUILD_NUMBER"
ditto build/Build/Products/Release/BeautifulBOM.app "$APP"
plist="$APP/Contents/Info.plist"
[[ "$(plutil -extract CFBundleShortVersionString raw -o - "$plist")" == "$VERSION" ]] || fail "app version differs"
[[ "$(plutil -extract CFBundleVersion raw -o - "$plist")" == "$BUILD_NUMBER" ]] || fail "app build number differs"

# Xcode's ad hoc signature carries get-task-allow, which notarization refuses; signing again
# without --preserve-metadata leaves no entitlements (the app is not sandboxed and needs none).
# The only nested item is the BOMCore resource bundle, which holds no code.
say "Signing the app ($SIGN_IDENTITY)"
sign "$APP"
codesign --verify --strict --deep --verbose=2 "$APP"

if [[ $ADHOC == 0 ]]; then
  say "Notarizing and stapling the app"
  ditto -c -k --keepParent "$APP" "$OUT/notarize-app.zip"
  notarize "$OUT/notarize-app.zip"
  rm "$OUT/notarize-app.zip"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
fi

say "Zipping the app"
ditto -c -k --keepParent "$APP" "$ZIP"

# --- The disk image --------------------------------------------------------------------------
say "Building the disk image with that app"
make dmg-image DMG_APP="$APP" DMG="$DMG"
sign "$DMG"
codesign --verify --strict --verbose=2 "$DMG"
if [[ $ADHOC == 0 ]]; then
  say "Notarizing and stapling the disk image"
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
fi

# --- Checksums -------------------------------------------------------------------------------
rm -rf "$STAGE"
(cd "$OUT" && shasum -a 256 "$(basename "$DMG")" "$(basename "$ZIP")" > checksums.txt)
say "Release assets in $OUT"
ls -l "$OUT"
cat "$OUT/checksums.txt"
[[ $ADHOC == 0 ]] || echo "Rehearsal only: signed ad hoc and not notarized. Never publish these."
