#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="apfel-chat"
APP_BUNDLE="$ROOT_DIR/build/${APP_NAME}.app"
VERSION="$(tr -d '\n' < "$ROOT_DIR/.version")"
ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.icns"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
ENTITLEMENTS="${ENTITLEMENTS:-$ROOT_DIR/apfel-chat.entitlements}"

resolve_helper() {
    local name="$1"
    local env_var_name=""
    case "$name" in
        apfel) env_var_name="APFEL_HELPER_PATH" ;;
        auge)  env_var_name="AUGE_HELPER_PATH" ;;
        ohr)   env_var_name="OHR_HELPER_PATH" ;;
    esac
    if [[ -n "$env_var_name" ]]; then
        local override="${(P)env_var_name:-}"
        if [[ -n "$override" && -x "$override" ]]; then
            print -- "$override"; return 0
        fi
    fi
    if command -v "$name" >/dev/null 2>&1; then
        command -v "$name"; return 0
    fi
    return 1
}

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

    # Sign every embedded helper before signing the bundle.
    for helper in apfel auge ohr; do
        if [[ -x "$APP_BUNDLE/Contents/Helpers/$helper" ]]; then
            codesign_path "$APP_BUNDLE/Contents/Helpers/$helper"
        fi
    done

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
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$APP_BUNDLE/Contents/Helpers"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"
chmod +x "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"
cp "$ROOT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "$APP_BUNDLE/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$APP_BUNDLE/Contents/Info.plist" >/dev/null

[[ -f "$ICON_SOURCE" ]] && cp "$ICON_SOURCE" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
[[ -f "$ROOT_DIR/PrivacyInfo.xcprivacy" ]] && cp "$ROOT_DIR/PrivacyInfo.xcprivacy" "$APP_BUNDLE/Contents/Resources/"

MISSING_HELPERS=()
for helper in apfel auge ohr; do
    if HELPER_PATH="$(resolve_helper "$helper" 2>/dev/null)"; then
        print "==> Embedding ${helper} helper from ${HELPER_PATH}"
        cp "$HELPER_PATH" "$APP_BUNDLE/Contents/Helpers/${helper}"
        chmod +x "$APP_BUNDLE/Contents/Helpers/${helper}"
    else
        MISSING_HELPERS+=("$helper")
    fi
done

if (( ${#MISSING_HELPERS[@]} > 0 )); then
    print "==> ERROR: required helpers not found on this build host: ${MISSING_HELPERS[*]}" >&2
    print "==> Every GUI release must ship with all dependencies bundled. Install the missing tools or set <NAME>_HELPER_PATH and rerun." >&2
    exit 1
fi

print "==> Signing bundle (${SIGN_IDENTITY})"
sign_bundle

print "==> Built ${APP_BUNDLE}"
