#!/usr/bin/env bash
# Build, sign, and atomically update the local Simplified Chinese app.
# A stable Apple signing identity keeps macOS privacy permissions valid across
# code updates. Set SIGN_IDENTITY explicitly if more than one suitable identity
# is installed.

set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Mac Duo 中文版"
APP_IDENTIFIER="com.l4rxdx.MacDuo.zhCN"
INSTALL_PATH="/Applications/${APP_NAME}.app"
BUILT_APP="build/${APP_NAME}.app"
STAGING_ROOT="build/install-stage"
STAGED_APP="${STAGING_ROOT}/${APP_NAME}.app"
BACKUP_ROOT="build/install-backups"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

resolve_signing_identity() {
  if [[ -n "${SIGN_IDENTITY:-}" && "$SIGN_IDENTITY" != "-" ]]; then
    printf '%s\n' "$SIGN_IDENTITY"
    return
  fi

  local identity_output
  local candidates=()
  identity_output="$(security find-identity -v -p codesigning)"

  while IFS= read -r identity; do
    [[ -n "$identity" ]] && candidates+=("$identity")
  done < <(printf '%s\n' "$identity_output" | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p')

  if [[ ${#candidates[@]} -eq 0 ]]; then
    while IFS= read -r identity; do
      [[ -n "$identity" ]] && candidates+=("$identity")
    done < <(printf '%s\n' "$identity_output" | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p')
  fi

  if [[ ${#candidates[@]} -ne 1 ]]; then
    echo "Expected exactly one Developer ID Application or Apple Development identity." >&2
    echo "Set SIGN_IDENTITY to the exact identity shown by:" >&2
    echo "  security find-identity -v -p codesigning" >&2
    exit 65
  fi

  printf '%s\n' "${candidates[0]}"
}

resolved_identity="$(resolve_signing_identity)"

APP_NAME="$APP_NAME" \
APP_DISPLAY_NAME="$APP_NAME" \
BUNDLE_IDENTIFIER="$APP_IDENTIFIER" \
SIGN_IDENTITY="$resolved_identity" \
SIGN_TIMESTAMP=none \
  ./build.sh

codesign --verify --deep --strict --verbose=2 "$BUILT_APP"
designated_requirement="$(codesign -d -r- "$BUILT_APP" 2>&1 | sed -n 's/^designated => //p')"
if [[ -z "$designated_requirement" || "$designated_requirement" == *cdhash* ]]; then
  echo "The build does not have an update-stable designated requirement." >&2
  exit 66
fi

mkdir -p "$STAGING_ROOT" "$BACKUP_ROOT"
rm -rf "$STAGED_APP"
ditto "$BUILT_APP" "$STAGED_APP"
codesign --verify --deep --strict --verbose=2 "$STAGED_APP"

pkill -x MacDuo 2>/dev/null || true

backup_path=""
if [[ -d "$INSTALL_PATH" ]]; then
  backup_path="${BACKUP_ROOT}/${APP_NAME}-$(date +%Y%m%d-%H%M%S).app"
  mv "$INSTALL_PATH" "$backup_path"
fi

if ! mv "$STAGED_APP" "$INSTALL_PATH"; then
  if [[ -n "$backup_path" && -d "$backup_path" ]]; then
    mv "$backup_path" "$INSTALL_PATH"
  fi
  exit 67
fi

open "$INSTALL_PATH"

echo "installed ${INSTALL_PATH}"
echo "identifier ${APP_IDENTIFIER}"
echo "stable signing identity verified"
if [[ -n "$backup_path" ]]; then
  echo "previous version ${backup_path}"
fi
