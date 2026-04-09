#!/bin/zsh
# release.sh — one script to rule them all
# Usage: ./scripts/release.sh
# Runs tests, builds, signs, notarises, tags, pushes, creates GitHub release,
# and deploys the website to Cloudflare Pages.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="apfel-chat"
VERSION="$(tr -d '\n' < "$ROOT_DIR/.version")"
TAG="v${VERSION}"
ARCH="$(uname -m)"
DIST_DIR="$ROOT_DIR/dist"

# ── Signing defaults ────────────────────────────────────────────────────────
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Franz Enzenhofer (7D2YX5DQ6M)}"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-notarytool}"
ENTITLEMENTS="${ENTITLEMENTS:-$ROOT_DIR/apfel-chat.entitlements}"

# ── Pre-flight ──────────────────────────────────────────────────────────────
print "==> Release $TAG"

BRANCH="$(git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD)"
if [[ "$BRANCH" != "main" ]]; then
    print "ERROR: Must be on main branch (currently: $BRANCH)" >&2; exit 1
fi

if ! git -C "$ROOT_DIR" diff-index --quiet HEAD --; then
    print "ERROR: Uncommitted changes. Commit or stash first." >&2; exit 1
fi

if git -C "$ROOT_DIR" tag --list "$TAG" | grep -q "^${TAG}$"; then
    print "ERROR: Tag $TAG already exists. Bump .version and try again." >&2; exit 1
fi

if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    print "ERROR: No Developer ID Application cert in Keychain." >&2; exit 1
fi

# ── Tests ───────────────────────────────────────────────────────────────────
print ""
print "==> Running tests..."
swift test --package-path "$ROOT_DIR"

# ── Build + Sign + Notarise ─────────────────────────────────────────────────
print ""
print "==> Building, signing, and notarising..."
SIGN_IDENTITY="$SIGN_IDENTITY" KEYCHAIN_PROFILE="$KEYCHAIN_PROFILE" ENTITLEMENTS="$ENTITLEMENTS" \
    "$ROOT_DIR/scripts/build-dist.sh"

# Verify the zip actually has a notarisation ticket before releasing
APP_ZIP="$DIST_DIR/${APP_NAME}-${TAG}-macos-${ARCH}.zip"
VERIFY_DIR="$(mktemp -d)"
ditto -x -k "$APP_ZIP" "$VERIFY_DIR"
if ! xcrun stapler validate "$VERIFY_DIR/${APP_NAME}.app" >/dev/null 2>&1; then
    print "ERROR: Notarisation ticket missing from app bundle. Aborting." >&2
    rm -rf "$VERIFY_DIR"
    exit 1
fi
rm -rf "$VERIFY_DIR"
print "==> Notarisation ticket verified."

# ── Git tag + push ──────────────────────────────────────────────────────────
print ""
print "==> Tagging $TAG and pushing..."
git -C "$ROOT_DIR" tag "$TAG"
git -C "$ROOT_DIR" push origin main
git -C "$ROOT_DIR" push origin "$TAG"

# ── GitHub Release ──────────────────────────────────────────────────────────
print ""
print "==> Creating GitHub release $TAG..."
APP_ZIP_STABLE="$DIST_DIR/${APP_NAME}-macos-${ARCH}.zip"
CLI_TARBALL="$DIST_DIR/${APP_NAME}-${TAG}-cli-macos-${ARCH}.tar.gz"
SHA_FILE="$DIST_DIR/SHA256SUMS"
HOMEBREW_CASK="$DIST_DIR/homebrew/${APP_NAME}.rb"

gh release create "$TAG" \
    --title "${APP_NAME} ${TAG}" \
    --generate-notes \
    "$APP_ZIP" \
    "$APP_ZIP_STABLE" \
    "$CLI_TARBALL" \
    "$SHA_FILE" \
    "$HOMEBREW_CASK"

# ── Deploy website ──────────────────────────────────────────────────────────
print ""
print "==> Deploying website to Cloudflare Pages..."
source ~/.env 2>/dev/null || true
npx wrangler pages deploy "$ROOT_DIR/site" --project-name apfel-chat

# ── Done ────────────────────────────────────────────────────────────────────
print ""
print "==> Done! $TAG is live."
print "    Release: https://github.com/Arthur-Ficial/apfel-chat/releases/tag/$TAG"
print "    Site:    https://apfel-chat.franzai.com"
