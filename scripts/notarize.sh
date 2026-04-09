#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/build/apfel-chat.app}"
ZIP_PATH="$ROOT_DIR/dist/apfel-chat-notarize.zip"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:?set KEYCHAIN_PROFILE for xcrun notarytool}"

if [[ ! -d "$APP_PATH" ]]; then
    print "App bundle not found at $APP_PATH"
    exit 1
fi

mkdir -p "$ROOT_DIR/dist"
rm -f "$ZIP_PATH"
COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent "$APP_PATH" "$ZIP_PATH"

xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$KEYCHAIN_PROFILE" --wait
xcrun stapler staple "$APP_PATH"
syspolicy_check distribution "$APP_PATH"

print "==> Notarized and stapled ${APP_PATH}"
