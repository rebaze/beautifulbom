#!/bin/bash
# Renders the app icon sizes from icon.svg into the asset catalog (needs rsvg-convert).
# Run from the repository root: scripts/icon/make-icon.sh
set -euo pipefail
out=App/Assets.xcassets/AppIcon.appiconset
for size in 16 32 128 256 512; do
  rsvg-convert -w $size -h $size scripts/icon/icon.svg -o $out/icon_${size}.png
  rsvg-convert -w $((size * 2)) -h $((size * 2)) scripts/icon/icon.svg -o $out/icon_${size}@2x.png
done
echo "Rendered $out"
