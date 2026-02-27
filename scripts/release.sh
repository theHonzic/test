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

echo "==> Releasing v${VERSION}"
echo "    Internal: ${GITHUB_REPO}"
echo ""

# Remember which branch we started on so we can return
SOURCE_BRANCH="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"

# ── Step 1: Generate documentation ───────────────────────────────────────────

echo "==> Step 1/4: Generating documentation..."
bash "$SCRIPT_DIR/generate-docs.sh"

# ── Step 2: Build XCFrameworks ───────────────────────────────────────────────

echo ""
echo "==> Step 2/4: Building XCFrameworks..."
bash "$SCRIPT_DIR/archive.sh"

# ── Step 3: Sync internal repository ──────────────────────────────────────────

echo ""
echo "==> Step 3/4: Syncing internal repository..."

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

# ── Step 4: Create GitHub release ──────────────────────────────────────────

echo ""
echo "==> Step 4/4: Creating GitHub release on ${GITHUB_REPO}..."

gh release create "$VERSION" \
    "$BUILD_DIR/MinimalPackage.xcframework.zip" \
    --repo "$GITHUB_REPO" \
    --title "v${VERSION}" \
    --generate-notes

echo ""
echo "==> Release v${VERSION} complete!"
echo "    Internal: https://github.com/${GITHUB_REPO}/releases/tag/${VERSION}"
