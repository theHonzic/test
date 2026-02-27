#!/usr/bin/env bash
#
# release.sh
#
# Full release workflow:
#   1. Generate DocC documentation          (docs/)
#   2. Build & archive XCFrameworks         (build/)
#   3. Prepare main branch with:
#        - Distribution Package.swift (binary targets)
#        - docs/ directory
#   4. Commit as "vX.Y.Z", tag X.Y.Z
#   5. Push main and tag
#   6. Create GitHub Release and upload the XCFramework zip
#
# Usage:
#   ./scripts/release.sh <version>          e.g. ./scripts/release.sh 1.0.0
#
# Requirements: Xcode 15+, gh CLI (https://cli.github.com), swift 5.9+

set -euo pipefail

# ── Parse arguments ──────────────────────────────────────────────────────────

if [ $# -ne 1 ]; then
    echo "Usage: $0 <version>   (e.g. 1.0.0)" >&2
    exit 1
fi

VERSION="$1"

# Validate semver-ish format
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
    echo "Error: version must be semver (e.g. 1.0.0 or 1.0.0-beta.1)" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build"

# ── Preflight ────────────────────────────────────────────────────────────────

command -v swift  >/dev/null 2>&1 || { echo "Error: swift not found."  >&2; exit 1; }
command -v xcodebuild >/dev/null 2>&1 || { echo "Error: xcodebuild not found (requires Xcode)." >&2; exit 1; }
command -v gh     >/dev/null 2>&1 || { echo "Error: gh CLI not found. Install from https://cli.github.com" >&2; exit 1; }

# Make sure we're in a clean repo
if [ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]; then
    echo "Error: working tree is not clean. Commit or stash changes first." >&2
    exit 1
fi

# Derive internal repo details
REMOTE_URL="$(git -C "$REPO_ROOT" remote get-url origin)"
GITHUB_REPO="$(echo "$REMOTE_URL" | sed -E 's#.*[:/]([^/]+/[^/.]+)(\.git)?$#\1#')"

# Public distribution repo
PUBLIC_REMOTE="public"
PUBLIC_REPO_URL="https://github.com/theHonzic/test-public.git"
PUBLIC_REPO="theHonzic/test-public"

echo "==> Releasing v${VERSION}"
echo "    Internal: ${GITHUB_REPO}"
echo "    Public:   ${PUBLIC_REPO}"
echo ""

# Remember which branch we started on so we can return
SOURCE_BRANCH="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"

# ── Step 1: Generate documentation ───────────────────────────────────────────

echo "==> Step 1/6: Generating documentation..."
bash "$SCRIPT_DIR/generate-docs.sh"

# ── Step 2: Build XCFrameworks ───────────────────────────────────────────────

echo ""
echo "==> Step 2/6: Building XCFrameworks..."
bash "$SCRIPT_DIR/archive.sh"

ZIP_PATH="$BUILD_DIR/MinimalPackage.xcframework.zip"
CHECKSUM="$(cat "$ZIP_PATH.sha256")"
# Download URL points to the PUBLIC repo releases
DOWNLOAD_URL="https://github.com/${PUBLIC_REPO}/releases/download/${VERSION}/MinimalPackage.xcframework.zip"

# ── Step 3: Prepare distribution Package.swift ───────────────────────────────

echo ""
echo "==> Step 3/6: Preparing distribution Package.swift..."

DIST_PACKAGE="$BUILD_DIR/Package.swift"
# Use envsubst to process the template
export DOWNLOAD_URL CHECKSUM PUBLIC_REPO VERSION
envsubst < "$SCRIPT_DIR/templates/Package.swift.template" > "$DIST_PACKAGE"

# ── Step 4: Sync internal repository ──────────────────────────────────────────

echo ""
echo "==> Step 4/6: Syncing internal repository..."

# 1. Tag the source code state locally
echo "    Tagging v${VERSION}..."
git -C "$REPO_ROOT" tag -a "$VERSION" -m "Release $VERSION"

# 2. Push source + tag to internal repo (origin)
echo "    Pushing ${SOURCE_BRANCH} and tag ${VERSION} to origin..."
git -C "$REPO_ROOT" push origin "$SOURCE_BRANCH"
git -C "$REPO_ROOT" push origin "$VERSION"

# 3. Update internal main via merge
echo "    Merging ${SOURCE_BRANCH} into main..."
git -C "$REPO_ROOT" checkout main
git -C "$REPO_ROOT" pull origin main --rebase
git -C "$REPO_ROOT" merge "$SOURCE_BRANCH" --no-ff -m "Release $VERSION"
git -C "$REPO_ROOT" push origin main

# Return to source branch
git -C "$REPO_ROOT" checkout "$SOURCE_BRANCH"

# ── Step 5: Assemble and push public distribution ────────────────────────────

echo ""
echo "==> Step 5/6: Assembling and pushing public distribution..."

# Work in a temporary directory
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT

cp "$DIST_PACKAGE" "$STAGE_DIR/Package.swift"
mkdir -p "$STAGE_DIR/Sources/MinimalPackageTarget"

cat > "$STAGE_DIR/Sources/MinimalPackageTarget/Exports.swift" <<'SWIFTSRC'
@_exported import MinimalPackage
SWIFTSRC

cp -R "$REPO_ROOT/docs" "$STAGE_DIR/docs"
touch "$STAGE_DIR/.nojekyll"
touch "$STAGE_DIR/docs/.nojekyll"

# Use envsubst to process the redirection template
envsubst < "$SCRIPT_DIR/templates/index.html.template" > "$STAGE_DIR/index.html"

# Use a temporary branch for the public push
TEMP_RELEASE_BRANCH="temp-public-release-${VERSION}"
git -C "$REPO_ROOT" checkout -b "$TEMP_RELEASE_BRANCH"

# Remove everything except .git
(
    cd "$REPO_ROOT"
    find . -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
)

cp -R "$STAGE_DIR/"* "$REPO_ROOT/"

git -C "$REPO_ROOT" add -A
git -C "$REPO_ROOT" commit -m "v${VERSION} (distribution)"

# Force push the "clean" state to public repo main
echo "    Pushing clean state to public/main..."
git -C "$REPO_ROOT" push "$PUBLIC_REMOTE" "${TEMP_RELEASE_BRANCH}:main" --force

# ── Step 6: Create GitHub release (on Public Repo) ──────────────────────────

echo ""
echo "==> Step 6/6: Creating GitHub release on ${PUBLIC_REPO}..."

gh release create "$VERSION" \
    "$BUILD_DIR/MinimalPackage.xcframework.zip" \
    --repo "$PUBLIC_REPO" \
    --title "v${VERSION}" \
    --generate-notes

# Return to source branch and cleanup
git -C "$REPO_ROOT" checkout "$SOURCE_BRANCH"
git -C "$REPO_ROOT" branch -D "$TEMP_RELEASE_BRANCH"

echo ""
echo "==> Release v${VERSION} complete!"
echo "    Internal: https://github.com/${GITHUB_REPO}"
echo "    Public:   https://github.com/${PUBLIC_REPO}/releases/tag/${VERSION}"
