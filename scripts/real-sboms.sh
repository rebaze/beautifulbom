#!/usr/bin/env bash
# Generates SBOMs the way clients make them: Syft, Trivy, cdxgen and the CycloneDX Maven plugin,
# each with its default settings, on public subjects pinned to a revision. Writes to
# Fixtures/generated/real/ (git-ignored); the small ones are copied into Fixtures/tools/.
#
#   scripts/real-sboms.sh            all subjects
#   scripts/real-sboms.sh rio image  some
#
# Needs syft, trivy, mvn with a JDK, node (cdxgen via npx), git, network. The app never goes
# online; this script does, on the developer's Mac.
set -euo pipefail
cd "$(dirname "$0")/.."

CDXGEN="@cyclonedx/cdxgen@12.9.2"
ROOT="$PWD"
OUT=Fixtures/generated/real
SRC=build/real-src
mkdir -p "$OUT" "$SRC"

# name|git url|revision|tree inside the repository
SUBJECTS=(
  "partner-portal|https://github.com/rebaze/sbom-kickstart-demo.git|6ef22cb37c45e17fa44cb728c3932eaf8ffb9ec5|partner-portal"
  "juice-shop|https://github.com/juice-shop/juice-shop.git|v20.4.0|."
  "rio|https://github.com/rebaze/rio.git|v0.10.2|."
)
IMAGE="python:3.13-slim@sha256:e48f59cdba69a3cbd9ed2cf0f348d90d45a8d350d98134cf1070bc106ee9ed90"

want() { [[ $# -le 1 ]] && return 0; local x; for x in "${@:2}"; do [[ "$x" == "$1" ]] && return 0; done; return 1; }
say() { printf '\n==> %s\n' "$*"; }
run() { # run <output> <command...>: keep going when one tool fails; record why
  local out="$1"; shift
  if "$@" > "$ROOT/$OUT/.log" 2>&1 && [[ -s "$out" ]]; then echo "  ok   $(basename "$out") ($(du -h "$out" | cut -f1 | tr -d ' '))"
  else echo "  FAIL $(basename "$out")"; tail -5 "$ROOT/$OUT/.log" | sed 's/^/       /'; rm -f "$out"; fi
}

checkout() { # checkout <name> <url> <revision>
  local dir="$SRC/$1"
  if [[ ! -d "$dir/.git" ]]; then git clone -q --filter=blob:none "$2" "$dir"; fi
  git -C "$dir" fetch -q --tags origin
  git -C "$dir" -c advice.detachedHead=false checkout -q --force "$3"
  git -C "$dir" clean -qfdx
}

for subject in "${SUBJECTS[@]}"; do
  IFS='|' read -r name url rev tree <<< "$subject"
  want "$name" "$@" || continue
  say "$name @ $rev"
  checkout "$name" "$url" "$rev"
  dir="$SRC/$name/$tree"
  case "$name" in
    partner-portal)
      run "$OUT/$name.maven.cdx.json" bash -c "cd '$dir' && mvn -B -q -DskipTests package && cp target/bom.json '$ROOT/$OUT/$name.maven.cdx.json'"
      cdx_type=java ;;
    juice-shop)
      # The repository has no lock file; npm writes one from the registry, without running scripts.
      (cd "$dir" && npm install --package-lock-only --ignore-scripts --no-audit --no-fund > /dev/null 2>&1)
      cdx_type=js ;;
    rio) cdx_type=go ;;
  esac
  # From inside the project with "." as the target, as a CI job runs them.
  pushd "$dir" > /dev/null
  o="$ROOT/$OUT/$name"
  run "$o.syft.cdx.json"    syft scan dir:. -q -o "cyclonedx-json=$o.syft.cdx.json"
  run "$o.syft.spdx.json"   syft scan dir:. -q -o "spdx-json=$o.syft.spdx.json"
  run "$o.trivy.cdx.json"   trivy fs -q --format cyclonedx --output "$o.trivy.cdx.json" .
  run "$o.trivy.spdx.json"  trivy fs -q --format spdx-json --output "$o.trivy.spdx.json" .
  run "$o.cdxgen.cdx.json"  npx -y "$CDXGEN" -t "$cdx_type" -o "$o.cdxgen.cdx.json" .
  run "$o.cdxgen.spdx.json" npx -y "$CDXGEN" -t "$cdx_type" --format spdx -o "$o.cdxgen.spdx.json" .
  popd > /dev/null
done

if want image "$@"; then
  say "image $IMAGE"
  run "$OUT/python-slim.syft.cdx.json"   syft scan "registry:$IMAGE" -q -o "cyclonedx-json=$OUT/python-slim.syft.cdx.json"
  run "$OUT/python-slim.syft.spdx.json"  syft scan "registry:$IMAGE" -q -o "spdx-json=$OUT/python-slim.syft.spdx.json"
  run "$OUT/python-slim.trivy.cdx.json"  trivy image -q --format cyclonedx --output "$OUT/python-slim.trivy.cdx.json" "$IMAGE"
  run "$OUT/python-slim.trivy.spdx.json" trivy image -q --format spdx-json --output "$OUT/python-slim.trivy.spdx.json" "$IMAGE"
  run "$OUT/python-slim.cdxgen.cdx.json" npx -y "$CDXGEN" -t docker -o "$OUT/python-slim.cdxgen.cdx.json" "$IMAGE"
fi
rm -f "$OUT/.log"

# Some tools write absolute paths of the checkout (cdxgen: evidence and file names). They name
# this Mac's user; the fixtures are public. Replace the checkout root with /src, then make sure
# nothing of the home folder is left.
say "Removing local paths"
for f in "$OUT"/*.json; do
  sed -i '' -e "s#$ROOT/$SRC/#/src/#g" -e "s#$ROOT/$SRC#/src#g" -e "s#$HOME#/home/builder#g" "$f"
done
if grep -l -e "$HOME" -e "$(id -un)" "$OUT"/*.json; then echo "local paths left in the files above" >&2; exit 1; fi

say "Tools"
{ syft version | sed -n 's/^Version: */syft /p'; trivy --version | sed -n 's/^Version: */trivy /p'
  echo "cdxgen ${CDXGEN##*@}"; mvn -v | head -1; } | tee "$OUT/TOOLS.txt"
