#!/usr/bin/env bash
# Opens every SBOM from scripts/real-sboms.sh in the Release app and renders its views, with the
# engine's numbers per file, into build/screenshots/real/ (index.html shows them side by side).
#   scripts/real-sweep.sh [file ...]     default: Fixtures/generated/real/*.json
# Needs make app CONFIG=Release and make bench-build.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
OUT=build/screenshots/real
BENCH=Packages/BOMCore/.build/release/bbom-bench
mkdir -p "$OUT"
files=("$@"); [[ ${#files[@]} -gt 0 ]] || files=(Fixtures/generated/real/*.json)

rows=""
for f in "${files[@]}"; do
  name="$(basename "$f" .json)"
  stats="$("$BENCH" analyse "$f" 2>&1 | tail -1)"
  echo "$name: $stats"
  cells=""
  for view in overview composition completeness components; do
    png="$OUT/$name-$view.png"
    if make -s snapshot CONFIG=Release UILANG=en FILE="$f" OUT="$png" VIEW=$view > /dev/null 2>&1 && [[ -s "$png" ]]; then
      cells+="<td><a href=\"$name-$view.png\"><img src=\"$name-$view.png\" loading=\"lazy\"></a></td>"
    else
      cells+="<td class=fail>no $view</td>"
    fi
  done
  rows+="<tr><th>$name<br><small>$(du -h "$f" | cut -f1)</small><br><code>${stats//</&lt;}</code></th>$cells</tr>"$'\n'
done

cat > "$OUT/index.html" <<EOF
<!DOCTYPE html><html><head><meta charset="utf-8"><title>Real SBOMs in Beautiful BOM</title>
<style>body{font:13px -apple-system,sans-serif;margin:20px}table{border-collapse:collapse}
td,th{border:1px solid #ddd;padding:4px;vertical-align:top}th{text-align:left;width:220px}
img{width:300px}code{font-size:10px;word-break:break-all}.fail{color:#c00;width:300px}</style></head><body>
<h1>Real SBOMs: Overview, Composition, Completeness, Components</h1>
<p>$(tr '\n' ';' < Fixtures/generated/real/TOOLS.txt 2>/dev/null)</p>
<table>$rows</table></body></html>
EOF
echo "gallery: $OUT/index.html"
