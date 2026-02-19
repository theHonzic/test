#!/usr/bin/env bash
#
# archive.sh
#
# Builds XCFrameworks for every target in MinimalPackage and bundles them
# into a single zip ready for GitHub Releases.
#
# Output:
#   build/MinimalPackage.xcframework.zip   – release artifact
#   build/MinimalPackage.xcframework.zip.sha256  – checksum
#
# Requirements: Xcode 15+

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGE_DIR="$REPO_ROOT/minimal-package"
BUILD_DIR="$REPO_ROOT/build"

# Platforms to archive (scheme → destinations).
# Each target that is part of the library must be archived separately
# and then merged into one XCFramework.
TARGETS=("MinimalPackage" "MinimalPackageCore" "MinimalPackageFeature")

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

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ── Archive each target for every platform ───────────────────────────────────

for target in "${TARGETS[@]}"; do
    echo ""
    echo "━━━ Archiving target: $target ━━━"

    FRAMEWORK_ARGS=()

    for i in "${!DESTINATIONS[@]}"; do
        dest="${DESTINATIONS[$i]}"
        slug="${DEST_SLUGS[$i]}"
        archive_path="$BUILD_DIR/archives/${target}-${slug}"

        echo "  -> $dest"
        xcodebuild archive \
            -workspace "$PACKAGE_DIR" \
            -scheme "$target" \
            -configuration Release \
            -destination "$dest" \
            -archivePath "$archive_path" \
            SKIP_INSTALL=NO \
            BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
            SWIFT_SERIALIZE_DEBUGGING_OPTIONS=NO \
            2>&1 | tail -3

        # Locate the .framework inside the archive
        fw_path="$archive_path.xcarchive/Products/usr/local/lib/${target}.framework"
        if [ ! -d "$fw_path" ]; then
            echo "Error: framework not found at $fw_path" >&2
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
done

# ── Bundle into a single zip ─────────────────────────────────────────────────

echo ""
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
