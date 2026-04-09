#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="apfel-chat"
APP_BUNDLE="$ROOT_DIR/build/${APP_NAME}.app"
VERSION="$(tr -d '\n' < "$ROOT_DIR/.version")"
ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.icns"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
ENTITLEMENTS="${ENTITLEMENTS:-$ROOT_DIR/apfel-chat.entitlements}"

codesign_path() {
    local target="$1"
    shift || true

    if [[ "$SIGN_IDENTITY" == "-" ]]; then
        codesign --force --sign "$SIGN_IDENTITY" "$@" "$target"
    else
        codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$@" "$target"
    fi
}

sign_bundle() {
    xattr -cr "$APP_BUNDLE" 2>/dev/null || true

    if [[ -n "$ENTITLEMENTS" && -f "$ENTITLEMENTS" ]]; then
        codesign_path "$APP_BUNDLE" --entitlements "$ENTITLEMENTS"
    else
        codesign_path "$APP_BUNDLE"
    fi

    codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
}

print "==> Building ${APP_NAME} ${VERSION}"
swift build -c release --package-path "$ROOT_DIR"
BIN_DIR="$(swift build -c release --show-bin-path --package-path "$ROOT_DIR")"
BIN_PATH="${BIN_DIR}/${APP_NAME}"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"
chmod +x "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"
cp "$ROOT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "$APP_BUNDLE/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$APP_BUNDLE/Contents/Info.plist" >/dev/null

[[ -f "$ICON_SOURCE" ]] && cp "$ICON_SOURCE" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
[[ -f "$ROOT_DIR/PrivacyInfo.xcprivacy" ]] && cp "$ROOT_DIR/PrivacyInfo.xcprivacy" "$APP_BUNDLE/Contents/Resources/"

print "==> Signing bundle (${SIGN_IDENTITY})"
sign_bundle

print "==> Built ${APP_BUNDLE}"
