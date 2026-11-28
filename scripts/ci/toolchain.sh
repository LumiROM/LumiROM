#!/bin/bash
#
# Android build-tools used by the hotspot APEX patch.
#
# Ubuntu's android-sdk-build-tools ships an apksigner without
# --alignment-preserved (added in build-tools 35), so a recent build-tools
# release is downloaded and added to $GITHUB_PATH.

set -eo pipefail

: "${GITHUB_PATH:?GITHUB_PATH is not set; run this from GitHub Actions}"

BT_URL="${BT_URL:-https://dl.google.com/android/repository/build-tools_r37_linux.zip}"
BT_ZIP="/tmp/build-tools.zip"
BT_ROOT="/tmp/build-tools"

curl -fsSL "$BT_URL" -o "$BT_ZIP"
rm -rf "$BT_ROOT"
unzip -q "$BT_ZIP" -d "$BT_ROOT"

BT_DIR="$(dirname "$(find "$BT_ROOT" -type f -name apksigner | head -n 1)")"
chmod +x "$BT_DIR/apksigner" "$BT_DIR/zipalign" 2>/dev/null || true
echo "$BT_DIR" >> "$GITHUB_PATH"

"$BT_DIR/apksigner" version
