#!/usr/bin/env bash
# =============================================================================
# release-local.sh
# =============================================================================
#
# OVERVIEW
# --------
# Entry point for the local release flow. Runs all steps in sequence:
#   1. archive.sh        – builds XCFramework zip + checksum
#   2. generate-docs.sh  – generates static DocC documentation
#   3. publish-internal.sh – pushes docs and creates internal GitHub release
#
# USAGE
# -----
#   ./scripts/release-local.sh <tag>
#
# EXAMPLE
# -------
#   ./scripts/release-local.sh v1.0.0
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -----------------------------------------------------------------------------
# Arguments
# -----------------------------------------------------------------------------

TAG="${1:-}"

if [[ -z "$TAG" ]]; then
    echo "Usage: $0 <tag>" >&2
    echo "  e.g. $0 v1.0.0"
    exit 1
fi

echo "==> Starting release $TAG"
echo ""

# -----------------------------------------------------------------------------
# Steps
# -----------------------------------------------------------------------------

echo "━━━ Step 1: Archive ━━━"
"$SCRIPT_DIR/archive.sh"

echo ""
echo "━━━ Step 2: Generate Docs ━━━"
"$SCRIPT_DIR/generate-docs.sh"

echo ""
echo "━━━ Step 3: Publish Internal ━━━"
"$SCRIPT_DIR/publish-internal.sh" "$TAG"

echo ""
echo "==> Release $TAG complete."