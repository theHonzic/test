#!/usr/bin/env bash
# =============================================================================
# validate-version.sh
# =============================================================================
#
# OVERVIEW
# --------
# Validates that a new version tag follows strict sequential semver rules
# relative to the latest tag on the remote. Prevents accidental version skips.
#
# RULES
# -----
# Given latest tag MAJOR.MINOR.PATCH, the new tag must be one of:
#   - MAJOR.MINOR.(PATCH+1)   patch bump, no skip
#   - MAJOR.(MINOR+1).0       minor bump, patch resets to 0
#   - (MAJOR+1).0.0           major bump, minor and patch reset to 0
#
# EXAMPLES
# --------
#   2.3.21 → 2.3.22  ✅
#   2.3.21 → 2.4.0   ✅
#   2.3.21 → 3.0.0   ✅
#   2.3.21 → 2.3.23  ❌ patch skipped
#   2.3.21 → 2.5.0   ❌ minor skipped
#   2.3.21 → 4.0.0   ❌ major skipped
#   2.3.21 → 3.1.0   ❌ major bump but minor not reset
#   2.3.21 → 2.4.1   ❌ minor bump but patch not reset
#
# USAGE
# -----
#   ./scripts/validate-version.sh <new-tag>
#
# EXAMPLE
# -------
#   ./scripts/validate-version.sh v2.4.0
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Arguments
# -----------------------------------------------------------------------------

NEW_TAG="${1:-}"

if [[ -z "$NEW_TAG" ]]; then
    echo "Usage: $0 <new-tag>" >&2
    echo "  e.g. $0 v2.4.0"
    exit 1
fi

# Strip leading 'v' if present
NEW_VERSION="${NEW_TAG#v}"

# -----------------------------------------------------------------------------
# Fetch latest tag from remote
# -----------------------------------------------------------------------------

echo "==> Fetching latest tag..."

git fetch --tags --quiet

LATEST_TAG=$(git tag --sort=-version:refname | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | head -1)

if [[ -z "$LATEST_TAG" ]]; then
    echo "==> No existing tags found, skipping version validation."
    exit 0
fi

LATEST_VERSION="${LATEST_TAG#v}"

echo "    Latest  : $LATEST_TAG"
echo "    New     : $NEW_TAG"

# -----------------------------------------------------------------------------
# Parse versions
# -----------------------------------------------------------------------------

IFS='.' read -r LATEST_MAJOR LATEST_MINOR LATEST_PATCH <<< "$LATEST_VERSION"
IFS='.' read -r NEW_MAJOR NEW_MINOR NEW_PATCH <<< "$NEW_VERSION"

# -----------------------------------------------------------------------------
# Validate
# -----------------------------------------------------------------------------

VALID=false

# Patch bump: MAJOR.MINOR.(PATCH+1)
if [[ "$NEW_MAJOR" -eq "$LATEST_MAJOR" ]] && \
   [[ "$NEW_MINOR" -eq "$LATEST_MINOR" ]] && \
   [[ "$NEW_PATCH" -eq $(( LATEST_PATCH + 1 )) ]]; then
    VALID=true
fi

# Minor bump: MAJOR.(MINOR+1).0
if [[ "$NEW_MAJOR" -eq "$LATEST_MAJOR" ]] && \
   [[ "$NEW_MINOR" -eq $(( LATEST_MINOR + 1 )) ]] && \
   [[ "$NEW_PATCH" -eq 0 ]]; then
    VALID=true
fi

# Major bump: (MAJOR+1).0.0
if [[ "$NEW_MAJOR" -eq $(( LATEST_MAJOR + 1 )) ]] && \
   [[ "$NEW_MINOR" -eq 0 ]] && \
   [[ "$NEW_PATCH" -eq 0 ]]; then
    VALID=true
fi

if ! $VALID; then
    echo ""
    echo "Error: invalid version bump $LATEST_TAG → $NEW_TAG" >&2
    echo ""
    echo "  Allowed next versions:"
    echo "    v${LATEST_MAJOR}.${LATEST_MINOR}.$(( LATEST_PATCH + 1 ))  (patch)"
    echo "    v${LATEST_MAJOR}.$(( LATEST_MINOR + 1 )).0  (minor)"
    echo "    v$(( LATEST_MAJOR + 1 )).0.0  (major)"
    exit 1
fi

echo "==> Version $NEW_TAG is valid."