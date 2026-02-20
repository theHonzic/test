#!/usr/bin/env bash
#
# generate-docs.sh
#
# Generates DocC documentation for MinimalPackage and transforms it
# into static HTML suitable for GitHub Pages.
#
# Usage:
#   ./scripts/generate-docs.sh              Build static docs into docs/
#   ./scripts/generate-docs.sh --preview    Start live-reload preview server
#   ./scripts/generate-docs.sh --serve      Build docs, then serve locally
#
# GitHub Pages URL:
#   https://<user>.github.io/<repo>/documentation/minimalpackage
#
# Requirements: Xcode 15+ (or Swift 5.9+ toolchain with DocC),
#               swift-docc-plugin declared in Package.swift

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGE_DIR="$REPO_ROOT/minimal-package"
DOCS_OUTPUT="$REPO_ROOT/docs"

PREVIEW=false
SERVE=false
if [[ "${1:-}" == "--preview" ]]; then
    PREVIEW=true
elif [[ "${1:-}" == "--serve" ]]; then
    SERVE=true
fi

# ── Preflight ────────────────────────────────────────────────────────────────

command -v swift >/dev/null 2>&1 || { echo "Error: swift is not installed." >&2; exit 1; }

# Derive the repo name from the git remote (used as hosting-base-path).
# GitHub Pages serves /docs as the site root, so the base path is just the
# repo name — NOT repo/docs.
HOSTING_BASE_PATH="$(basename -s .git "$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null)" 2>/dev/null || echo "test")"

echo "==> Resolving package dependencies..."
swift package --package-path "$PACKAGE_DIR" resolve

# ── Preview mode ─────────────────────────────────────────────────────────────

if $PREVIEW; then
    echo "==> Starting live preview server (Ctrl-C to stop)..."
    echo "    Watching for changes in Sources/"
    # --disable-sandbox is required because the preview server binds a port.
    # preview-documentation only supports a single --target, so we preview
    # the umbrella target. For full combined docs, use the static build.
    swift package --package-path "$PACKAGE_DIR" \
        --disable-sandbox \
        preview-documentation \
        --target MinimalPackage
    exit 0
fi

# ── Build static site ───────────────────────────────────────────────────────

rm -rf "$DOCS_OUTPUT"

# All targets whose documentation should be included.
# Combined documentation merges symbol graphs from all targets into a single
# navigable site. Internal targets (Core, Feature) do NOT need to be products.
TARGETS=(MinimalPackage MinimalPackageCore MinimalPackageFeature)

TARGET_FLAGS=()
for t in "${TARGETS[@]}"; do
    TARGET_FLAGS+=(--target "$t")
done

echo "==> Generating combined DocC documentation..."
echo "    targets: ${TARGETS[*]}"
echo "    hosting-base-path: /${HOSTING_BASE_PATH}"

swift package --package-path "$PACKAGE_DIR" \
    --allow-writing-to-directory "$DOCS_OUTPUT" \
    generate-documentation \
    "${TARGET_FLAGS[@]}" \
    --enable-experimental-combined-documentation \
    --disable-indexing \
    --transform-for-static-hosting \
    --hosting-base-path "$HOSTING_BASE_PATH" \
    --output-path "$DOCS_OUTPUT"

echo "==> Documentation written to $DOCS_OUTPUT"
echo "    GitHub Pages URL: https://<user>.github.io/${HOSTING_BASE_PATH}/documentation/minimalpackage"
echo "    Live preview:     $0 --preview"
echo "    Local server:     $0 --serve"

# ── Local server ─────────────────────────────────────────────────────────────

if $SERVE; then
    PORT="${2:-8000}"

    # The static site's internal links use /<HOSTING_BASE_PATH>/... as the
    # prefix (matching the GitHub Pages URL structure).  python3's http.server
    # serves the given directory as "/", so we need to mount docs/ *under* the
    # base-path directory so the URLs resolve correctly.
    SERVE_ROOT="$(mktemp -d)"
    ln -s "$DOCS_OUTPUT" "$SERVE_ROOT/$HOSTING_BASE_PATH"
    trap 'rm -rf "$SERVE_ROOT"' EXIT

    echo ""
    echo "==> Starting local server on http://localhost:${PORT}/${HOSTING_BASE_PATH}/documentation/minimalpackage"
    echo "    Ctrl-C to stop"
    python3 -m http.server "$PORT" -d "$SERVE_ROOT"
fi
