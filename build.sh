#!/usr/bin/env bash
# Modified by l4rxx in 2026 for the l4rxx edition.
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
UNIVERSAL=false
RUN_APP=false
for argument in "$@"; do
  case "$argument" in
    --universal) UNIVERSAL=true ;;
    --run) RUN_APP=true ;;
    *) echo "Unknown argument: $argument" >&2; exit 1 ;;
  esac
done

if "$UNIVERSAL"; then
  ARM_TRIPLE="arm64-apple-macosx14.0"
  INTEL_TRIPLE="x86_64-apple-macosx14.0"

  for product in MacDuo lidprobe; do
    swift build "${BUILD_ARGS[@]}" --triple "$ARM_TRIPLE" --product "$product"
    swift build "${BUILD_ARGS[@]}" --triple "$INTEL_TRIPLE" --product "$product"
  done

  ARM_BIN_PATH="$(swift build "${BUILD_ARGS[@]}" --triple "$ARM_TRIPLE" --show-bin-path)"
  INTEL_BIN_PATH="$(swift build "${BUILD_ARGS[@]}" --triple "$INTEL_TRIPLE" --show-bin-path)"
  UNIVERSAL_BIN_PATH="build/universal"
  mkdir -p "$UNIVERSAL_BIN_PATH"
  lipo -create "$ARM_BIN_PATH/MacDuo" "$INTEL_BIN_PATH/MacDuo" \
    -output "$UNIVERSAL_BIN_PATH/MacDuo"
  lipo -create "$ARM_BIN_PATH/lidprobe" "$INTEL_BIN_PATH/lidprobe" \
    -output "$UNIVERSAL_BIN_PATH/lidprobe"
  BINARY="$UNIVERSAL_BIN_PATH/MacDuo"
  PROBE="$UNIVERSAL_BIN_PATH/lidprobe"
else
  swift build "${BUILD_ARGS[@]}" --product MacDuo
  swift build "${BUILD_ARGS[@]}" --product lidprobe

  BIN_PATH="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
  BINARY="$BIN_PATH/MacDuo"
  PROBE="$BIN_PATH/lidprobe"
fi

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BINARY" "$BUNDLE/Contents/MacOS/MacDuo"
if xcrun -sdk macosx metal -help >/dev/null 2>&1; then
  xcrun -sdk macosx metal -c Sources/MacDuo/Metal/DepthShaders.metal \
    -o build/DepthShaders.air
  xcrun -sdk macosx metallib build/DepthShaders.air \
    -o "$BUNDLE/Contents/Resources/DepthShaders.metallib"
else
  cp Sources/MacDuo/Metal/DepthShaders.metal \
    "$BUNDLE/Contents/Resources/DepthShaders.metal"
fi
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
