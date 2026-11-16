#!/usr/bin/env bash
# Prepares a GitHub macOS runner (label xcode-27, macOS 27): the Xcode the project needs, pinned,
# and the build tools. Fails if the image no longer offers that Xcode.
set -euo pipefail
XCODE=/Applications/Xcode_27.2.app
[[ -d "$XCODE" ]] || { echo "this runner image has no $XCODE; installed: $(echo /Applications/Xcode*.app)" >&2; exit 1; }
sudo xcode-select -s "$XCODE"
xcodebuild -version
xcodebuild -version | grep -qx 'Xcode 27.2'
HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install --quiet xcodegen xcbeautify
xcodegen --version
