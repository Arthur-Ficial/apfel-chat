#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 <version>"
  exit 1
fi

REPO="Arthur-Ficial/apfel-chat"
BINARY="apfel-chat"
TAP_REPO="Arthur-Ficial/homebrew-tap"
TAP_DIR="/opt/homebrew/Library/Taps/arthur-ficial/homebrew-tap"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

SKIP_SIGNING="${SKIP_SIGNING:-1}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-1}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
APPLE_ID="${APPLE_ID:-}"
TEAM_ID="${TEAM_ID:-}"

echo "=== apfel-chat release v${VERSION} ==="

# 1. Run tests
echo ""
echo "[1/8] Running tests..."
cd "$PROJECT_DIR"
swift test
echo "  All tests passed"

# 2. Build release binary
echo ""
echo "[2/8] Building release binary..."
swift build -c release
BINARY_PATH="$PROJECT_DIR/.build/release/$BINARY"
[[ -f "$BINARY_PATH" ]] || { echo "Error: binary not found"; exit 1; }
echo "  Built: $BINARY_PATH"

# 3. Create .app bundle
echo ""
echo "[3/8] Creating .app bundle..."
APP_DIR="/tmp/apfel-chat-app-$$"
APP_BUNDLE="$APP_DIR/apfel chat.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/apfel-chat"

# Use project Info.plist with version substituted
sed "s/1\.0\.0/${VERSION}/g" "$PROJECT_DIR/Info.plist" > "$APP_BUNDLE/Contents/Info.plist"

# Copy icon if available
if [[ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "  Icon: copied"
fi

# Copy privacy manifest
if [[ -f "$PROJECT_DIR/PrivacyInfo.xcprivacy" ]]; then
    cp "$PROJECT_DIR/PrivacyInfo.xcprivacy" "$APP_BUNDLE/Contents/Resources/PrivacyInfo.xcprivacy"
    echo "  Privacy manifest: copied"
fi

echo "  App bundle: $APP_BUNDLE"

# 3b. Code signing (optional)
if [[ "$SKIP_SIGNING" != "1" && -n "$SIGNING_IDENTITY" ]]; then
    echo ""
    echo "[3b/8] Signing app bundle..."
    ENTITLEMENTS="$PROJECT_DIR/apfel-chat.entitlements"
    codesign --force --options runtime \
        --sign "$SIGNING_IDENTITY" \
        --entitlements "$ENTITLEMENTS" \
        --timestamp \
        "$APP_BUNDLE/Contents/MacOS/apfel-chat"
    codesign --force --options runtime \
        --sign "$SIGNING_IDENTITY" \
        --entitlements "$ENTITLEMENTS" \
        --timestamp \
        "$APP_BUNDLE"
    codesign --verify --deep --strict "$APP_BUNDLE"
    echo "  Signed: $APP_BUNDLE"
else
    echo "  Signing: skipped (set SKIP_SIGNING=0 and SIGNING_IDENTITY to enable)"
fi

# 4. Create DMG
echo ""
echo "[4/8] Creating DMG..."
DMG_STAGING="/tmp/apfel-chat-dmg-$$"
DMG_PATH="/tmp/$BINARY-${VERSION}.dmg"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create -volname "apfel chat ${VERSION}" \
  -srcfolder "$DMG_STAGING" \
  -ov -format UDZO \
  "$DMG_PATH" > /dev/null 2>&1
echo "  DMG: $DMG_PATH"

# 4b. Notarization (optional)
if [[ "$SKIP_NOTARIZE" != "1" && -n "$APPLE_ID" && -n "$TEAM_ID" ]]; then
    echo ""
    echo "[4b/8] Notarizing DMG..."
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --keychain-profile "apfel-chat-notary" \
        --wait
    xcrun stapler staple "$DMG_PATH"
    echo "  Notarized and stapled: $DMG_PATH"
else
    echo "  Notarization: skipped (set SKIP_NOTARIZE=0, APPLE_ID, TEAM_ID to enable)"
fi

# 5. Package tarball (for Homebrew)
echo ""
echo "[5/8] Packaging tarball..."
STAGING="/tmp/apfel-chat-release-$$"
mkdir -p "$STAGING/$BINARY-${VERSION}"
cp "$BINARY_PATH" "$STAGING/$BINARY-${VERSION}/$BINARY"
TARBALL="$STAGING/$BINARY-${VERSION}-arm64-macos.tar.gz"
cd "$STAGING"
tar czf "$TARBALL" "$BINARY-${VERSION}"
echo "  Tarball: $TARBALL"

# 6. Compute sha256
echo ""
echo "[6/8] Computing sha256..."
SHA256=$(shasum -a 256 "$TARBALL" | awk '{print $1}')
DMG_SHA256=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
echo "  Tarball SHA256: $SHA256"
echo "  DMG SHA256: $DMG_SHA256"

# 7. Create GitHub release
echo ""
echo "[7/8] Creating GitHub release v${VERSION}..."
cd "$PROJECT_DIR"
gh release create "v${VERSION}" "$TARBALL" "$DMG_PATH" \
  --repo "$REPO" \
  --title "apfel chat v${VERSION}" \
  --notes "Release v${VERSION}

## Install

### Direct download (recommended)
Download the DMG, open it, drag **apfel chat** to Applications.

### Homebrew
\`\`\`bash
brew tap Arthur-Ficial/tap
brew install apfel-chat
\`\`\`

### Build from source
\`\`\`bash
git clone https://github.com/${REPO}.git
cd apfel-chat && make install
\`\`\`

Requires [apfel](https://github.com/Arthur-Ficial/apfel) installed on your Mac.

## What's New
- Super-fast, lightweight chat client for on-device AI
- Multi-chat with conversation management
- Speech input and output
- Markdown and JSON rendering
- 100% local — no data leaves your Mac"

echo "  Release: https://github.com/${REPO}/releases/tag/v${VERSION}"

# 8. Generate and push Homebrew formula
echo ""
echo "[8/8] Updating Homebrew formula..."
FORMULA_PATH="$TAP_DIR/Formula/apfel-chat.rb"
cat > "$FORMULA_PATH" <<FORMULA
class ApfelChat < Formula
  desc "Super-fast, lightweight chat client for on-device AI via apfel"
  homepage "https://github.com/${REPO}"
  url "https://github.com/${REPO}/releases/download/v${VERSION}/${BINARY}-${VERSION}-arm64-macos.tar.gz"
  sha256 "${SHA256}"
  license "MIT"

  depends_on "arthur-ficial/tap/apfel"

  def install
    odie "apfel-chat requires a Mac with Apple Silicon." unless Hardware::CPU.arm?
    bin.install "apfel-chat"
  end

  def caveats
    <<~EOS
      apfel-chat requires apfel:
        brew install arthur-ficial/tap/apfel

      Run: apfel-chat

      Or download the .app from:
        https://github.com/${REPO}/releases
    EOS
  end

  test do
    assert_predicate bin/"apfel-chat", :executable?
  end
end
FORMULA

cd "$TAP_DIR"
git add "Formula/apfel-chat.rb"
git commit -m "apfel-chat ${VERSION}"
git push origin main

echo ""
echo "=== Done! ==="
echo ""
echo "Downloads:"
echo "  DMG: https://github.com/${REPO}/releases/download/v${VERSION}/${BINARY}-${VERSION}.dmg"
echo "  Brew: brew tap Arthur-Ficial/tap && brew install apfel-chat"
echo ""
echo "Release: https://github.com/${REPO}/releases/tag/v${VERSION}"

# Cleanup
rm -rf "$STAGING" "$APP_DIR" "$DMG_STAGING"
