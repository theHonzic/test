#!/usr/bin/env bash
# =============================================================================
# publish-internal.sh
# =============================================================================
#
# OVERVIEW
# --------
# Publishes the release artifacts to the internal GitHub repository:
#   1. Pushes the generated docs/ folder to main so GitHub Pages updates
#   2. Creates a GitHub Release and uploads the XCFramework zip as an asset
#
# PREREQUISITES
# -------------
#   - gh CLI installed and authenticated (gh auth status)
#   - archive.sh has been run (build/ exists with zip + checksum)
#   - generate-docs.sh has been run (docs/ exists)
#   - Working directory is the repo root
#   - docs/ is committed or tracked in the repo
#
# USAGE
# -----
#   ./scripts/publish-internal.sh <tag>
#
# EXAMPLE
# -------
#   ./scripts/publish-internal.sh v1.0.0
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Config
# -----------------------------------------------------------------------------

INTERNAL_REPO="theHonzic/test"

# -----------------------------------------------------------------------------
# Paths
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build"
DOCS_DIR="$REPO_ROOT/docs"

ZIP_NAME="MinimalPackage.xcframework.zip"
ZIP_PATH="$BUILD_DIR/$ZIP_NAME"

# -----------------------------------------------------------------------------
# Arguments
# -----------------------------------------------------------------------------

TAG="${1:-}"

if [[ -z "$TAG" ]]; then
    echo "Usage: $0 <tag>" >&2
    echo "  e.g. $0 v1.0.0"
    exit 1
fi

# -----------------------------------------------------------------------------
# Preflight
# -----------------------------------------------------------------------------

command -v gh >/dev/null 2>&1 || {
    echo "Error: gh CLI is not installed." >&2
    exit 1
}

[[ -f "$ZIP_PATH" ]] || {
    echo "Error: $ZIP_PATH not found. Run archive.sh first." >&2
    exit 1
}

[[ -d "$DOCS_DIR" ]] || {
    echo "Error: docs/ not found. Run generate-docs.sh first." >&2
    exit 1
}

# -----------------------------------------------------------------------------
# Push docs to gh-pages branch
#
# Force pushes the contents of docs/ as the root of the gh-pages branch.
# No history is kept — each release replaces the previous cleanly.
#
# GitHub Pages must be configured to serve from:
#   Branch: gh-pages   Folder: / (root)
# -----------------------------------------------------------------------------

echo "==> Pushing docs to gh-pages branch on $INTERNAL_REPO..."

touch "$DOCS_DIR/.nojekyll"

cd "$REPO_ROOT"
git add --force "$DOCS_DIR"
TREE=$(git write-tree --prefix=docs/)
COMMIT=$(git commit-tree "$TREE" -m "docs: $TAG")
git push -f origin "$COMMIT:refs/heads/gh-pages"

echo "==> Docs pushed to gh-pages"

# -----------------------------------------------------------------------------
# Create GitHub Release and upload artifact
#
# Creates a release on the internal repo tagged with the provided tag and
# uploads the XCFramework zip as a release asset.
# -----------------------------------------------------------------------------

echo ""
echo "==> Creating GitHub Release $TAG on $INTERNAL_REPO..."

gh release create "$TAG" "$ZIP_PATH" \
    --repo "$INTERNAL_REPO" \
    --title "$TAG" \
    --generate-notes

echo "==> Release created: https://github.com/$INTERNAL_REPO/releases/tag/$TAG"
echo ""
echo "Done."