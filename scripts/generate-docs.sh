#!/usr/bin/env bash
# =============================================================================
# generate-docs.sh
# =============================================================================
#
# OVERVIEW
# --------
# Generates DocC documentation for the SDK and transforms it into a static
# HTML site suitable for hosting on GitHub Pages.
#
# The script supports two modes:
#   - Default : Builds a static site into /docs at the repo root
#   - Serve   : Builds static docs then serves them locally via python3,
#               mirroring the GitHub Pages URL structure so internal asset
#               paths resolve correctly
#
# DIRECTORY LAYOUT ASSUMED
# ------------------------
#   <repo-root>/
#   ├── minimal-package/        ← Swift package lives here (Package.swift)
#   │   └── Sources/
#   ├── scripts/
#   │   ├── generate-docs.sh    ← this file
#   │   └── templates/
#   │       └── index.html      ← redirect template (copied into docs/)
#   └── docs/                   ← generated output (created / replaced each run)
#
# GITHUB PAGES SETUP
# ------------------
# In your repo settings set Pages source to:
#   Branch: main   Folder: /docs
#
# The generated site will be reachable at:
#   https://<user>.github.io/<repo>/documentation/
#
# The hosting-base-path is automatically derived from the git remote URL so
# it always matches the repo name without any manual configuration.
#
# COMBINED DOCUMENTATION
# ----------------------
# --enable-experimental-combined-documentation merges the symbol graphs of
# all listed targets into a single navigable site. Internal targets do NOT
# need to be declared as products in Package.swift for this to work.
#
# TARGETS
# -------
# Targets are defined in the TARGETS array below. Add or remove entries to
# control which modules appear in the generated documentation.
#
# REQUIREMENTS
# ------------
#   - Xcode 15+ or a Swift 5.9+ toolchain that includes DocC
#   - swift-docc-plugin declared as a dependency in Package.swift:
#       .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0")
#   - python3 (only required for --serve mode)
#   - git remote configured (only required for automatic base-path derivation)
#
# USAGE
# -----
#   ./scripts/generate-docs.sh                          Build static docs into docs/
#   ./scripts/generate-docs.sh --base-path <name>       Override hosting base path
#   ./scripts/generate-docs.sh --serve                  Build docs, then serve locally
#   ./scripts/generate-docs.sh --serve 9000             Build docs, serve on port 9000
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Paths
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Location of the Swift package (Package.swift lives here).
PACKAGE_DIR="$REPO_ROOT/minimal-package"

# Where the static site will be written.
DOCS_OUTPUT="$REPO_ROOT/docs"

# Template directory — index.html is copied from here into the docs output.
TEMPLATES_DIR="$SCRIPT_DIR/templates"

# -----------------------------------------------------------------------------
# Targets
# Defines which Swift targets are included in the generated documentation.
# Adjust this list to match the targets declared in your Package.swift.
# -----------------------------------------------------------------------------

TARGETS=(MinimalPackage MinimalPackageCore MinimalPackageFeature)

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------

SERVE=false
CUSTOM_BASE_PATH=""

while [[ $# -gt 0 ]]; do
    case "${1:-}" in
        --base-path)
            CUSTOM_BASE_PATH="${2:-}"
            shift 2
            ;;
        --serve)
            SERVE=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# -----------------------------------------------------------------------------
# Preflight checks
# -----------------------------------------------------------------------------

# Ensure swift is available before attempting anything.
command -v swift >/dev/null 2>&1 || {
    echo "Error: swift is not installed or not on PATH." >&2
    exit 1
}

# Ensure the package directory exists.
[[ -d "$PACKAGE_DIR" ]] || {
    echo "Error: Package directory not found: $PACKAGE_DIR" >&2
    exit 1
}

# Ensure the templates directory and index.html exist.
[[ -f "$TEMPLATES_DIR/index.html" ]] || {
    echo "Error: index.html template not found at $TEMPLATES_DIR/index.html" >&2
    exit 1
}

# -----------------------------------------------------------------------------
# Derive hosting base path from git remote.
#
# GitHub Pages serves a project site at https://<user>.github.io/<repo>/.
# DocC's --hosting-base-path must match this repo name so that all internal
# asset URLs resolve correctly both on Pages and in --serve mode.
#
# Falls back to "docs" if no git remote is configured (e.g. local testing
# without a remote).
# -----------------------------------------------------------------------------

if [[ -n "$CUSTOM_BASE_PATH" ]]; then
    HOSTING_BASE_PATH="$CUSTOM_BASE_PATH"
else
    HOSTING_BASE_PATH="$(basename -s .git \
        "$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null)" \
        2>/dev/null || echo "docs")"
fi

echo "==> Hosting base path: /${HOSTING_BASE_PATH}"

# -----------------------------------------------------------------------------
# Resolve package dependencies
# -----------------------------------------------------------------------------

echo "==> Resolving package dependencies..."
swift package --package-path "$PACKAGE_DIR" resolve

# -----------------------------------------------------------------------------
# Build static documentation site
# -----------------------------------------------------------------------------

# Remove any previous output so the build is always clean.
rm -rf "$DOCS_OUTPUT"

# Build --target flags from the TARGETS array.
TARGET_FLAGS=()
for t in "${TARGETS[@]}"; do
    TARGET_FLAGS+=(--target "$t")
done

echo "==> Generating combined DocC documentation..."
echo "    Targets : ${TARGETS[*]}"
echo "    Output  : $DOCS_OUTPUT"

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

# -----------------------------------------------------------------------------
# Copy redirect index.html
#
# Copies the template from templates/index.html into the docs output root.
# This ensures that visiting the bare GitHub Pages URL (or the local server
# root) immediately redirects the browser to ./documentation/ without the
# user needing to know the full path.
# -----------------------------------------------------------------------------

cp "$TEMPLATES_DIR/index.html" "$DOCS_OUTPUT/index.html"
echo "==> Copied redirect index.html to $DOCS_OUTPUT/index.html"

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

echo ""
echo "==> Done."
echo "    GitHub Pages URL : https://<user>.github.io/${HOSTING_BASE_PATH}/documentation/"
echo "    Local server     : $0 --serve"

# -----------------------------------------------------------------------------
# Serve mode
#
# Builds docs (above) then starts a python3 HTTP server that mirrors the
# GitHub Pages URL structure. This is necessary because DocC generates all
# internal hrefs prefixed with /<HOSTING_BASE_PATH>/, so simply opening
# docs/index.html directly in a browser will produce broken asset links.
#
# To replicate the Pages structure we:
#   1. Create a temporary directory as the server root.
#   2. Symlink docs/ into it under the base-path name.
#   3. Serve the temp directory — URLs now match what Pages will serve.
#   4. Remove the temp directory on exit via trap.
# -----------------------------------------------------------------------------

if $SERVE; then
    PORT="${2:-8000}"

    SERVE_ROOT="$(mktemp -d)"
    ln -s "$DOCS_OUTPUT" "$SERVE_ROOT/$HOSTING_BASE_PATH"
    trap 'rm -rf "$SERVE_ROOT"' EXIT

    echo ""
    echo "==> Serving docs at http://localhost:${PORT}/${HOSTING_BASE_PATH}/documentation/"
    echo "    Ctrl-C to stop"
    python3 -m http.server "$PORT" -d "$SERVE_ROOT"
fi