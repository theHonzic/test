#!/usr/bin/env bash
# =============================================================================
# publish-public.sh
# =============================================================================
#
# OVERVIEW
# --------
# Publishes the release artifacts to the public GitHub repository:
#   1. Fetches release notes from the internal repo release
#   2. Creates a GitHub Release on the public repo and uploads the zip
#   3. Captures the asset download URL from the release
#   4. Runs generate-package.sh to inject URL + checksum into Package.swift
#   5. Pushes Package.swift, docs/ and .nojekyll to public repo main
#
# The public repo main branch contains only release artifacts — no source.
# Consumers point their SPM at this repo and get the binary via Package.swift.
#
# PUBLIC REPO MAIN STRUCTURE
# --------------------------
#   /
#   ├── Package.swift     ← binary target pointing to release asset
#   ├── .nojekyll         ← disables Jekyll on GitHub Pages
#   └── docs/             ← same DocC output as internal, served via Pages
#
# GITHUB PAGES SETUP
# ------------------
# In the public repo settings set Pages source to:
#   Branch: main   Folder: /docs
#
# RELEASE NOTES
# -------------
# Notes are fetched from the internal repo release and mirrored to the public
# one. This ensures consumers see the same changelog without needing PRs on
# the public repo.
#
# PREREQUISITES
# -------------
#   - gh CLI installed and authenticated with access to both repos
#   - archive.sh has been run (build/ exists with zip + checksum)
#   - generate-docs.sh has been run (docs/ exists)
#   - publish-internal.sh has been run (internal release exists for the tag)
#   - Public repo main branch exists
#
# USAGE
# -----
#   ./scripts/publish-public.sh <tag>
#
# EXAMPLE
# -------
#   ./scripts/publish-public.sh v1.0.0
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Config
# -----------------------------------------------------------------------------

INTERNAL_REPO="theHonzic/test"
PUBLIC_REPO="theHonzic/test-public"

# -----------------------------------------------------------------------------
# Paths
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build"
DOCS_DIR="$REPO_ROOT/docs"

ZIP_NAME="MinimalPackage.xcframework.zip"
ZIP_PATH="$BUILD_DIR/$ZIP_NAME"
CHECKSUM_PATH="$ZIP_PATH.sha256"
PACKAGE_SWIFT="$BUILD_DIR/Package.swift"

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

[[ -f "$CHECKSUM_PATH" ]] || {
    echo "Error: $CHECKSUM_PATH not found. Run archive.sh first." >&2
    exit 1
}

[[ -d "$DOCS_DIR" ]] || {
    echo "Error: docs/ not found. Run generate-docs.sh first." >&2
    exit 1
}

CHECKSUM=$(cat "$CHECKSUM_PATH")

# -----------------------------------------------------------------------------
# Fetch release notes from internal repo
#
# Mirrors the internal release notes to the public release so consumers
# see the same changelog without needing PRs on the public repo.
# -----------------------------------------------------------------------------

echo "==> Fetching release notes from $INTERNAL_REPO..."

RELEASE_NOTES=$(gh release view "$TAG" \
    --repo "$INTERNAL_REPO" \
    --json body \
    --jq '.body')

echo "==> Release notes fetched"

# -----------------------------------------------------------------------------
# Create public GitHub Release and upload artifact
#
# The asset download URL is captured immediately after creation — it is
# needed by generate-package.sh to populate the binaryTarget in Package.swift.
# -----------------------------------------------------------------------------

echo ""
echo "==> Creating GitHub Release $TAG on $PUBLIC_REPO..."

gh release create "$TAG" "$ZIP_PATH" \
    --repo "$PUBLIC_REPO" \
    --title "$TAG" \
    --notes "$RELEASE_NOTES"

ASSET_URL=$(gh release view "$TAG" \
    --repo "$PUBLIC_REPO" \
    --json assets \
    --jq '.assets[0].url')

echo "==> Release created"
echo "    Asset URL: $ASSET_URL"

# -----------------------------------------------------------------------------
# Generate public Package.swift
#
# Injects the asset URL and checksum into the Package.swift template.
# Output is written to build/Package.swift.
# -----------------------------------------------------------------------------

echo ""
echo "==> Generating Package.swift..."
"$SCRIPT_DIR/generate-package.sh" "$ASSET_URL" "$CHECKSUM"

# -----------------------------------------------------------------------------
# Push artifacts to public repo main
#
# Clones the public repo, copies Package.swift, docs/ and .nojekyll into it,
# then commits and pushes to main. The public repo main branch is not a source
# repo — it only ever contains release artifacts.
# -----------------------------------------------------------------------------

echo ""
echo "==> Pushing artifacts to $PUBLIC_REPO main..."

CLONE_DIR="$(mktemp -d)"
trap 'rm -rf "$CLONE_DIR"' EXIT

gh repo clone "$PUBLIC_REPO" "$CLONE_DIR"

cp "$PACKAGE_SWIFT" "$CLONE_DIR/Package.swift"
touch "$CLONE_DIR/.nojekyll"
cp -r "$DOCS_DIR" "$CLONE_DIR/docs"

cd "$CLONE_DIR"
git add Package.swift .nojekyll docs/
git commit -m "release: $TAG"
git push origin main

echo "==> Artifacts pushed to $PUBLIC_REPO main"
echo ""
echo "==> Release $TAG published to $PUBLIC_REPO"
echo "    Release : https://github.com/$PUBLIC_REPO/releases/tag/$TAG"
echo "    Pages   : https://theHonzic.github.io/test-public/documentation/"
echo ""
echo "Done."