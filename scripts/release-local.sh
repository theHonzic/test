#!/usr/bin/env bash
# =============================================================================
# release-local.sh
# =============================================================================
#
# OVERVIEW
# --------
# Entry point for the local release flow. Runs all steps in sequence:
#   1. archive.sh          – builds XCFramework zip + checksum
#   2. generate-docs.sh    – generates static DocC documentation
#   3. publish-internal.sh – pushes docs and creates internal GitHub release
#   4. publish-public.sh   – pushes artifacts and creates public GitHub release
#
# USAGE
# -----
#   ./scripts/release-local.sh <tag>
#   ./scripts/release-local.sh <tag> --clean    Clears .derivedData cache before building
#
# EXAMPLE
# -------
#   ./scripts/release-local.sh v1.0.0
#   ./scripts/release-local.sh v1.0.0 --clean
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# -----------------------------------------------------------------------------
# Arguments
# -----------------------------------------------------------------------------

TAG="${1:-}"
CLEAN=false

if [[ -z "$TAG" ]]; then
    echo "Usage: $0 <tag> [--clean]" >&2
    echo "  e.g. $0 v1.0.0"
    echo "  e.g. $0 v1.0.0 --clean"
    exit 1
fi

if [[ "${2:-}" == "--clean" ]]; then
    CLEAN=true
fi

# -----------------------------------------------------------------------------
# Clean cache
# -----------------------------------------------------------------------------

if $CLEAN; then
    echo "==> Clearing .derivedData cache..."
    rm -rf "$REPO_ROOT/.derivedData"
    echo "==> Cache cleared"
    echo ""
fi

echo "==> Starting release $TAG"
echo ""

# -----------------------------------------------------------------------------
# Steps
# -----------------------------------------------------------------------------

echo "━━━ Step 1: Validate Version ━━━"
"$SCRIPT_DIR/validate-version.sh" "$TAG"

echo ""
echo "━━━ Step 2: Archive ━━━"
"$SCRIPT_DIR/archive.sh"

echo ""
echo "━━━ Step 3: Generate Docs ━━━"
"$SCRIPT_DIR/generate-docs.sh"

echo ""
echo "━━━ Step 4: Publish Internal ━━━"
"$SCRIPT_DIR/publish-internal.sh" "$TAG"

echo ""
echo "━━━ Step 5: Publish Public ━━━"
"$SCRIPT_DIR/publish-public.sh" "$TAG"

echo ""
echo "==> Release $TAG complete."