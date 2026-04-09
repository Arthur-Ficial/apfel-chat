#!/bin/zsh
set -euo pipefail

REPO="${REPO:-Arthur-Ficial/apfel-chat}"
APP_NAME="apfel-chat.app"
APP_DIR="${APP_DIR:-/Applications}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
TMP_DIR="$(mktemp -d)"
VERSION_ARG="${1:-latest}"
ASSET_URL_OVERRIDE="${ASSET_URL_OVERRIDE:-}"

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

ensure_dir() {
    local dir="$1" parent="$1"
    [[ -d "$dir" ]] && return
    while [[ ! -e "$parent" && "$parent" != "/" ]]; do parent="$(dirname "$parent")"; done
    if [[ -w "$parent" ]]; then mkdir -p "$dir"; else sudo mkdir -p "$dir"; fi
}

if [[ -n "$ASSET_URL_OVERRIDE" ]]; then
    ASSET_URL="$ASSET_URL_OVERRIDE"
elif [[ "$VERSION_ARG" == "latest" ]]; then
    ASSET_URL="https://github.com/${REPO}/releases/latest/download/apfel-chat-macos-arm64.zip"
else
    TAG="$VERSION_ARG"; [[ "$TAG" == v* ]] || TAG="v${TAG}"
    ASSET_URL="https://github.com/${REPO}/releases/download/${TAG}/apfel-chat-macos-arm64.zip"
fi

print "==> Downloading ${ASSET_URL}"
curl -fsSL "$ASSET_URL" -o "$TMP_DIR/apfel-chat.zip"
ditto -x -k "$TMP_DIR/apfel-chat.zip" "$TMP_DIR/unpacked"

ensure_dir "$APP_DIR"
ensure_dir "$BIN_DIR"

if [[ -w "$APP_DIR" ]]; then
    rm -rf "$APP_DIR/$APP_NAME"
    ditto "$TMP_DIR/unpacked/$APP_NAME" "$APP_DIR/$APP_NAME"
    xattr -dr com.apple.quarantine "$APP_DIR/$APP_NAME" 2>/dev/null || true
else
    sudo rm -rf "$APP_DIR/$APP_NAME"
    sudo ditto "$TMP_DIR/unpacked/$APP_NAME" "$APP_DIR/$APP_NAME"
    sudo xattr -dr com.apple.quarantine "$APP_DIR/$APP_NAME" 2>/dev/null || true
fi

if [[ -w "$BIN_DIR" ]]; then
    ln -sf "$APP_DIR/$APP_NAME/Contents/MacOS/apfel-chat" "$BIN_DIR/apfel-chat"
else
    sudo ln -sf "$APP_DIR/$APP_NAME/Contents/MacOS/apfel-chat" "$BIN_DIR/apfel-chat"
fi

print "==> Installed ${APP_DIR}/${APP_NAME}"
print "==> Linked ${BIN_DIR}/apfel-chat"
print "==> Launch with: open -a '${APP_DIR}/${APP_NAME}'"
