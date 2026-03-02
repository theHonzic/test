#!/usr/bin/env bash
# =============================================================================
# publish-internal.sh
# =============================================================================
#
# OVERVIEW
# --------
# Publishes the release artifacts to the internal GitHub repository.
# Creates a GitHub Release and uploads the XCFramework zip as an asset.
# Release notes are auto-generated from PR labels via the GitHub API.
#
# PREREQUISITES
# -------------
#   - gh CLI installed and authenticated (gh auth status)
#   - archive.sh has been run (build/ exists with zip + checksum)
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

# -----------------------------------------------------------------------------
# Create GitHub Release and upload artifact
#
# Creates a release on the internal repo tagged with the provided tag,
# uploads the XCFramework zip as a release asset, and auto-generates
# release notes from PR labels using the GitHub Release Notes API.
# -----------------------------------------------------------------------------

echo "==> Creating GitHub Release $TAG on $INTERNAL_REPO..."

gh release create "$TAG" "$ZIP_PATH" \
    --repo "$INTERNAL_REPO" \
    --title "$TAG" \
    --generate-notes

echo "==> Release created: https://github.com/$INTERNAL_REPO/releases/tag/$TAG"
echo ""
echo "Done."