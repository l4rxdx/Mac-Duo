#!/usr/bin/env bash
#
# Builds Mac Duo.app from the SwiftPM package.
#
#   ./build.sh            build and sign
#   ./build.sh --run      build, sign, and relaunch the app
#   ./build.sh --universal  build for Apple Silicon and Intel
#
# Uses ad-hoc signing by default. macOS may require Screen Recording permission
# again after rebuilding. Set SIGN_IDENTITY to use your own signing identity.
# Set SIGN_TIMESTAMP=none for local development signing without a timestamp
# service request; the default is auto.
# APP_NAME, APP_DISPLAY_NAME, and BUNDLE_IDENTIFIER may be overridden by a
# packaging script without changing the upstream app metadata.

set -euo pipefail
cd "$(dirname "$0")"

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SIGN_TIMESTAMP="${SIGN_TIMESTAMP:-auto}"
APP_NAME="${APP_NAME:-Mac Duo}"
APP_DISPLAY_NAME="${APP_DISPLAY_NAME:-$APP_NAME}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-}"
BUNDLE="build/${APP_NAME}.app"

BUILD_ARGS=(-c release)
RUN_APP=false
for argument in "$@"; do
  case "$argument" in
    --universal) BUILD_ARGS+=(--arch arm64 --arch x86_64) ;;
    --run) RUN_APP=true ;;
    *) echo "Unknown argument: $argument" >&2; exit 1 ;;
  esac
done

swift build "${BUILD_ARGS[@]}" --product MacDuo
swift build "${BUILD_ARGS[@]}" --product lidprobe

BIN_PATH="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
BINARY="$BIN_PATH/MacDuo"
PROBE="$BIN_PATH/lidprobe"

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BINARY" "$BUNDLE/Contents/MacOS/MacDuo"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
plutil -replace CFBundleName -string "$APP_DISPLAY_NAME" "$BUNDLE/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string "$APP_DISPLAY_NAME" "$BUNDLE/Contents/Info.plist"
if [[ -n "$BUNDLE_IDENTIFIER" ]]; then
  plutil -replace CFBundleIdentifier -string "$BUNDLE_IDENTIFIER" "$BUNDLE/Contents/Info.plist"
fi
cp LICENSE NOTICE "$BUNDLE/Contents/Resources/"
for localization in Resources/*.lproj; do
  [[ -d "$localization" ]] || continue
  cp -R "$localization" "$BUNDLE/Contents/Resources/"
done
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
fi
cp "$PROBE" build/lidprobe

if [[ "$SIGN_TIMESTAMP" != auto && "$SIGN_TIMESTAMP" != none ]]; then
  echo "SIGN_TIMESTAMP must be auto or none." >&2
  exit 2
fi

TIMESTAMP=--timestamp
if [[ "$SIGN_IDENTITY" == - || "$SIGN_TIMESTAMP" == none ]]; then
  TIMESTAMP=--timestamp=none
fi
codesign --force --options runtime "$TIMESTAMP" \
  --identifier "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$BUNDLE/Contents/Info.plist")" \
  --sign "$SIGN_IDENTITY" "$BUNDLE"
codesign --verify --strict --verbose=1 "$BUNDLE"

echo "built ${BUNDLE}"
codesign -dv "$BUNDLE" 2>&1 | grep -E "Identifier|TeamIdentifier|Signature" || true

if "$RUN_APP"; then
  pkill -x MacDuo 2>/dev/null || true
  sleep 0.5
  open "$BUNDLE"
  echo "launched"
fi
