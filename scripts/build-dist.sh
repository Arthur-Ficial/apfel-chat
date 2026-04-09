#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="apfel-chat"
VERSION="$(tr -d '\n' < "$ROOT_DIR/.version")"
ARCH="$(uname -m)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$ROOT_DIR/build/${APP_NAME}.app"
APP_ZIP="$DIST_DIR/${APP_NAME}-v${VERSION}-macos-${ARCH}.zip"
APP_ZIP_STABLE="$DIST_DIR/${APP_NAME}-macos-${ARCH}.zip"
CLI_STAGE="$DIST_DIR/${APP_NAME}-cli"
CLI_TARBALL="$DIST_DIR/${APP_NAME}-v${VERSION}-cli-macos-${ARCH}.tar.gz"
SHA_FILE="$DIST_DIR/SHA256SUMS"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-}"
ENTITLEMENTS="${ENTITLEMENTS:-$ROOT_DIR/apfel-chat.entitlements}"

SIGN_IDENTITY="$SIGN_IDENTITY" ENTITLEMENTS="$ENTITLEMENTS" "$ROOT_DIR/scripts/build-app.sh"

if [[ "$SIGN_IDENTITY" != "-" && -n "$KEYCHAIN_PROFILE" ]]; then
    KEYCHAIN_PROFILE="$KEYCHAIN_PROFILE" "$ROOT_DIR/scripts/notarize.sh" "$APP_BUNDLE"
fi

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR/homebrew" "$CLI_STAGE"

# Use ditto WITHOUT --norsrc so the stapled notarisation ticket is preserved
COPYFILE_DISABLE=1 ditto -c -k --keepParent "$APP_BUNDLE" "$APP_ZIP"
# Stable name for the always-works landing page download URL
cp "$APP_ZIP" "$APP_ZIP_STABLE"

cp "$APP_BUNDLE/Contents/MacOS/${APP_NAME}" "$CLI_STAGE/${APP_NAME}"
chmod +x "$CLI_STAGE/${APP_NAME}"

cat > "$CLI_STAGE/README.txt" <<EOF
apfel-chat CLI bundle

Contents:
- apfel-chat

Requires apfel on PATH to run.
EOF

tar -C "$CLI_STAGE" -czf "$CLI_TARBALL" .

(
    cd "$DIST_DIR"
    shasum -a 256 "$(basename "$APP_ZIP")" "$(basename "$APP_ZIP_STABLE")" "$(basename "$CLI_TARBALL")" > "$SHA_FILE"
)

APP_SHA="$(shasum -a 256 "$APP_ZIP" | awk '{print $1}')"
"$ROOT_DIR/scripts/render-homebrew-cask.sh" "$VERSION" "$APP_SHA" > "$DIST_DIR/homebrew/apfel-chat.rb"

print "==> Created:"
print "    $APP_ZIP"
print "    $CLI_TARBALL"
print "    $SHA_FILE"
print "    $DIST_DIR/homebrew/apfel-chat.rb"
