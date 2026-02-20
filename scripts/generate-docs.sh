#!/usr/bin/env bash
#
# generate-docs.sh
#
# Generates DocC documentation for MinimalPackage and transforms it
# into static HTML suitable for GitHub Pages.
#
# Output: <repo-root>/docs/
#
# Usage on GitHub Pages the site will be at:
#   https://<user>.github.io/<repo>/documentation/minimalpackage
#
# Requirements: Xcode 15+ (or Swift 5.9+ toolchain with DocC),
#               swift-docc-plugin declared in Package.swift

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGE_DIR="$REPO_ROOT/minimal-package"
DOCS_OUTPUT="$REPO_ROOT/docs"

# ── Preflight ────────────────────────────────────────────────────────────────

command -v swift >/dev/null 2>&1 || { echo "Error: swift is not installed." >&2; exit 1; }

# Derive the repo name from the git remote (used as hosting-base-path)
HOSTING_BASE_PATH="$(basename -s .git "$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null)" 2>/dev/null || echo "test")"

echo "==> Resolving package dependencies..."
swift package --package-path "$PACKAGE_DIR" resolve

# ── Clean previous output ────────────────────────────────────────────────────

rm -rf "$DOCS_OUTPUT"

# ── Generate DocC site ───────────────────────────────────────────────────────

echo "==> Generating DocC documentation for MinimalPackage..."
echo "    hosting-base-path: /${HOSTING_BASE_PATH}"

# Per the official swift-docc-plugin guide:
#   --allow-writing-to-directory  grants the plugin sandbox permission to write
#   --transform-for-static-hosting produces a directory servable as-is
#   --hosting-base-path           sets the root path for relative links
#   --disable-indexing            skips the LMDB index (not needed for static hosting)
swift package --package-path "$PACKAGE_DIR" \
    --allow-writing-to-directory "$DOCS_OUTPUT" \
    generate-documentation \
    --target MinimalPackage \
    --disable-indexing \
    --transform-for-static-hosting \
    --hosting-base-path "$HOSTING_BASE_PATH" \
    --output-path "$DOCS_OUTPUT"

echo "==> Documentation written to $DOCS_OUTPUT"
echo "    GitHub Pages URL: https://<user>.github.io/${HOSTING_BASE_PATH}/documentation/minimalpackage"
echo "    Local preview:    python3 -m http.server -d \"$DOCS_OUTPUT\""
