#!/usr/bin/env bash
# =============================================================================
# archive.sh
# =============================================================================
#
# OVERVIEW
# --------
# Builds a static XCFramework for MinimalPackage and bundles it into a zip
# ready for GitHub Releases. Only the top-level product target is archived —
# internal targets (Core, Feature) are compiled in automatically.
#
# OUTPUT
# ------
#   build/MinimalPackage.xcframework         – the framework
#   build/MinimalPackage.xcframework.zip     – release artifact
#   build/MinimalPackage.xcframework.zip.sha256 – checksum for Package.swift
#
# CACHING
# -------
# Build intermediates are cached in .derivedData/ (gitignored) so incremental
# rebuilds are fast. Delete .derivedData/ for a fully clean build.
#
# REQUIREMENTS
# ------------
#   Xcode 15+
#
# USAGE
# -----
#   ./scripts/archive.sh
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Paths
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGE_DIR="$REPO_ROOT/minimal-package"
BUILD_DIR="$REPO_ROOT/build"
DERIVED_DATA="$REPO_ROOT/.derivedData"

# -----------------------------------------------------------------------------
# Targets
# Only the product target — internal targets compile in automatically.
# -----------------------------------------------------------------------------

TARGETS=("MinimalPackage")

# -----------------------------------------------------------------------------
# Destinations
# Slug is used for naming intermediate archive paths.
# -----------------------------------------------------------------------------

DESTINATIONS=(
    "generic/platform=iOS"
    "generic/platform=iOS Simulator"
)

DEST_SLUGS=(
    "iphoneos"
    "iphonesimulator"
)

# -----------------------------------------------------------------------------
# Preflight
# -----------------------------------------------------------------------------

command -v xcodebuild >/dev/null 2>&1 || {
    echo "Error: xcodebuild is not installed (requires Xcode)." >&2
    exit 1
}

[[ -d "$PACKAGE_DIR" ]] || {
    echo "Error: Package directory not found: $PACKAGE_DIR" >&2
    exit 1
}

# Clean final output but preserve derived data cache for incremental builds.
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$DERIVED_DATA"

echo "==> Package   : $PACKAGE_DIR"
echo "==> Build dir : $BUILD_DIR"
echo "==> Cache     : $DERIVED_DATA (delete for clean build)"
echo ""

# -----------------------------------------------------------------------------
# Archive each target for every platform
# -----------------------------------------------------------------------------

cd "$PACKAGE_DIR"

for target in "${TARGETS[@]}"; do
    echo "━━━ Archiving target: $target ━━━"

    FRAMEWORK_ARGS=()

    for i in "${!DESTINATIONS[@]}"; do
        dest="${DESTINATIONS[$i]}"
        slug="${DEST_SLUGS[$i]}"
        archive_path="$BUILD_DIR/archives/${target}-${slug}"

        echo "  -> $dest"
        xcodebuild archive \
            -scheme "$target" \
            -configuration Release \
            -destination "$dest" \
            -archivePath "$archive_path" \
            -derivedDataPath "$DERIVED_DATA" \
            -clonedSourcePackagesDirPath "$DERIVED_DATA/SourcePackages" \
            SKIP_INSTALL=NO \
            SWIFT_SERIALIZE_DEBUGGING_OPTIONS=NO \
            2>&1 | tail -3

        # Locate the .framework inside the archive.
        # Path varies depending on whether the library is static or dynamic.
        fw_path="$(find "$archive_path.xcarchive/Products" \
            -name "${target}.framework" -type d -maxdepth 6 | head -1)"

        if [ -z "$fw_path" ]; then
            echo ""
            echo "Error: ${target}.framework not found inside xcarchive." >&2
            echo "Archive contents:" >&2
            find "$archive_path.xcarchive/Products" -type d -maxdepth 4 >&2
            exit 1
        fi

        echo "     Found: $fw_path"
        FRAMEWORK_ARGS+=("-framework" "$fw_path")
    done

    # -------------------------------------------------------------------------
    # Create XCFramework
    # -------------------------------------------------------------------------

    xcf_path="$BUILD_DIR/${target}.xcframework"
    echo "  -> Creating ${target}.xcframework"
    xcodebuild -create-xcframework \
        "${FRAMEWORK_ARGS[@]}" \
        -output "$xcf_path"

    echo "  -> Done: $xcf_path"
    echo ""
done

# -----------------------------------------------------------------------------
# Bundle into a zip
# All XCFrameworks are zipped together into a single release artifact.
# The checksum is computed for use in the public Package.swift binaryTarget.
# -----------------------------------------------------------------------------

echo "==> Bundling release artifact..."

ZIP_NAME="MinimalPackage.xcframework.zip"
ZIP_PATH="$BUILD_DIR/$ZIP_NAME"

(cd "$BUILD_DIR" && zip -qry "$ZIP_NAME" "${TARGETS[@]/%/.xcframework}")

CHECKSUM=$(swift package compute-checksum "$ZIP_PATH")
echo "$CHECKSUM" > "$ZIP_PATH.sha256"

echo ""
echo "==> Artifact : $ZIP_PATH"
echo "==> SHA-256  : $CHECKSUM"
echo ""
echo "Done."