#!/usr/bin/env bash
#
# generate-docs.sh
#
# Generates DocC documentation for MinimalPackage and transforms it
# into static HTML suitable for GitHub Pages or any web host.
#
# Output: <repo-root>/docs/
#
# Requirements: Xcode 15+ (or Swift 5.9+ toolchain with DocC)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGE_DIR="$REPO_ROOT/minimal-package"
DOCS_OUTPUT="$REPO_ROOT/docs"

# ── Preflight ────────────────────────────────────────────────────────────────

command -v swift >/dev/null 2>&1 || { echo "Error: swift is not installed." >&2; exit 1; }

echo "==> Resolving package dependencies..."
swift package --package-path "$PACKAGE_DIR" resolve

# ── Generate DocC archive ────────────────────────────────────────────────────

echo "==> Generating DocC documentation for MinimalPackage..."

# swift-docc-plugin provides the generate-documentation verb.
# --transform-for-static-hosting produces a directory that can be served as-is.
# --hosting-base-path is set to the repo name for GitHub Pages compatibility.
swift package --package-path "$PACKAGE_DIR" generate-documentation \
    --target MinimalPackage \
    --disable-indexing \
    --transform-for-static-hosting \
    --hosting-base-path test \
    --output-path "$DOCS_OUTPUT"

echo "==> Documentation written to $DOCS_OUTPUT"
echo "    Serve locally with:  python3 -m http.server -d \"$DOCS_OUTPUT\""
