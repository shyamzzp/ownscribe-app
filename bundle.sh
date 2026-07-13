#!/bin/bash
# Build a distributable Ownscribe.app bundle from the SPM executable.
set -eo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="Ownscribe.app"
BIN_NAME="Ownscribe"

echo "Building ($CONFIG)…"
swift build -c "$CONFIG" 1>&2
BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path 2>/dev/null)/$BIN_NAME"

echo "Assembling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/$BIN_NAME"
cp Info.plist "$APP/Contents/Info.plist"

# Ad-hoc sign so TCC (mic / screen-recording) prompts attach to a stable identity.
if codesign --force --deep --sign - \
     --entitlements Ownscribe.entitlements \
     --options runtime "$APP" 2>/dev/null; then
  echo "Signed (with entitlements)."
else
  codesign --force --deep --sign - "$APP"
  echo "Signed (ad-hoc)."
fi

echo "Done: $(pwd)/$APP"
