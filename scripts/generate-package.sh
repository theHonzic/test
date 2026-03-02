#!/usr/bin/env bash
# =============================================================================
# generate-package.sh
# =============================================================================
#
# OVERVIEW
# --------
# Generates the public-facing Package.swift by injecting the GitHub Release
# asset URL and checksum into a template. The resulting file is what SPM
# consumers point at in the public repo — it declares a single binary target
# so no source code is ever exposed.
#
# HOW IT WORKS
# ------------
# The template at templates/Package.swift contains two placeholders:
#   ASSET_URL  – replaced with the GitHub Release download URL for the zip
#   CHECKSUM   – replaced with the SHA-256 checksum of the zip
#
# Both values are produced by archive.sh:
#   - ASSET_URL is the GitHub Release asset download URL (known after the
#     release is created via gh CLI in release-local.sh)
#   - CHECKSUM is read from build/MinimalPackage.xcframework.zip.sha256
#
# OUTPUT
# ------
#   build/Package.swift  – ready to be pushed to the public repo root
#
# USAGE
# -----
#   ./scripts/generate-package.sh <asset_url> <checksum>
#
# EXAMPLE
# -------
#   ./scripts/generate-package.sh \
#     https://github.com/org/repo/releases/download/v1.0.0/MinimalPackage.xcframework.zip \
#     d4b43f848488a566113615023515d2b0011aa28d669ccd062aa66065f6167b05
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Paths
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="$SCRIPT_DIR/templates/Package.swift"
OUTPUT="$REPO_ROOT/build/Package.swift"

# -----------------------------------------------------------------------------
# Arguments
# -----------------------------------------------------------------------------

ASSET_URL="${1:-}"
CHECKSUM="${2:-}"

if [[ -z "$ASSET_URL" || -z "$CHECKSUM" ]]; then
    echo "Usage: $0 <asset_url> <checksum>" >&2
    echo ""
    echo "  asset_url  GitHub Release download URL for the xcframework zip"
    echo "  checksum   SHA-256 checksum (from build/*.zip.sha256)"
    exit 1
fi

# -----------------------------------------------------------------------------
# Preflight
# -----------------------------------------------------------------------------

[[ -f "$TEMPLATE" ]] || {
    echo "Error: Package.swift template not found at $TEMPLATE" >&2
    exit 1
}

mkdir -p "$REPO_ROOT/build"

# -----------------------------------------------------------------------------
# Inject values into template
#
# Copies the template then replaces ASSET_URL and CHECKSUM placeholders with
# the real values. Uses a temp file for the intermediate sed output to avoid
# in-place editing issues across platforms (macOS sed differs from GNU sed).
# -----------------------------------------------------------------------------

echo "==> Generating Package.swift..."
echo "    URL      : $ASSET_URL"
echo "    Checksum : $CHECKSUM"

sed \
    -e "s|ASSET_URL|$ASSET_URL|g" \
    -e "s|CHECKSUM|$CHECKSUM|g" \
    "$TEMPLATE" > "$OUTPUT"

echo "==> Written to $OUTPUT"
echo ""
cat "$OUTPUT"