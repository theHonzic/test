#!/usr/bin/env bash
#
# archive.sh
#
# Builds XCFrameworks for every target in MinimalPackage and bundles them
# into a single zip ready for GitHub Releases.
#
# Build intermediates are cached in .derivedData/ (gitignored) so
# incremental rebuilds are fast. Only the final build/ output is
# recreated each run.
#
# Output:
#   build/MinimalPackage.xcframework.zip          – release artifact
#   build/MinimalPackage.xcframework.zip.sha256    – checksum
#
# Requirements: Xcode 15+

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGE_DIR="$REPO_ROOT/minimal-package"
BUILD_DIR="$REPO_ROOT/build"
DERIVED_DATA="$REPO_ROOT/.derivedData"

# Only archive products (library targets exposed in Package.swift products).
# Internal targets (Core, Feature) are compiled into the product automatically.
TARGETS=("MinimalPackage")

DESTINATIONS=(
    "generic/platform=iOS"
    "generic/platform=iOS Simulator"
    "generic/platform=macOS"
)

DEST_SLUGS=(
    "iphoneos"
    "iphonesimulator"
    "macosx"
)

# ── Preflight ────────────────────────────────────────────────────────────────

command -v xcodebuild >/dev/null 2>&1 || { echo "Error: xcodebuild is not installed (requires Xcode)." >&2; exit 1; }

# Clean final output but keep derived data cache for incremental builds
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$DERIVED_DATA"

echo "==> Derived data cache: $DERIVED_DATA"
echo "    (delete .derivedData/ for a fully clean build)"
echo ""

# ── Archive each target for every platform ───────────────────────────────────

# xcodebuild locates Package.swift via the working directory; all other paths
# used below are absolute, so this cd does not affect them.
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
            BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
            SWIFT_SERIALIZE_DEBUGGING_OPTIONS=NO \
            2>&1 | tail -3

        # Locate the .framework inside the archive (path varies by Xcode version)
        fw_path="$(find "$archive_path.xcarchive/Products" -name "${target}.framework" -type d -maxdepth 4 | head -1)"
        if [ -z "$fw_path" ]; then
            echo "Error: ${target}.framework not found inside xcarchive. Contents:" >&2
            find "$archive_path.xcarchive/Products" -type d -maxdepth 3 >&2
            exit 1
        fi

        FRAMEWORK_ARGS+=("-framework" "$fw_path")
    done

    # ── Create XCFramework ───────────────────────────────────────────────

    xcf_path="$BUILD_DIR/${target}.xcframework"
    echo "  -> Creating ${target}.xcframework"
    xcodebuild -create-xcframework \
        "${FRAMEWORK_ARGS[@]}" \
        -output "$xcf_path"

    echo "  -> Done: $xcf_path"
    echo ""
done

# ── Bundle into a single zip ─────────────────────────────────────────────────

echo "==> Creating release archive..."

ZIP_NAME="MinimalPackage.xcframework.zip"
ZIP_PATH="$BUILD_DIR/$ZIP_NAME"

# Zip all XCFrameworks together
(cd "$BUILD_DIR" && zip -qry "$ZIP_NAME" "${TARGETS[@]/%/.xcframework}")

# Compute checksum (used by Package.swift binaryTarget)
CHECKSUM=$(swift package compute-checksum "$ZIP_PATH")
echo "$CHECKSUM" > "$ZIP_PATH.sha256"

echo "==> Archive: $ZIP_PATH"
echo "==> SHA-256: $CHECKSUM"
echo ""
echo "Done. Upload $ZIP_NAME to GitHub Releases."
