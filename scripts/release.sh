#!/usr/bin/env bash
#
# release.sh
#
# Full release workflow:
#   1. Generate DocC documentation          (docs/)
#   2. Build & archive XCFrameworks         (build/)
#   3. Prepare main branch with:
#        - Distribution Package.swift (binary targets)
#        - docs/ directory
#   4. Commit as "vX.Y.Z", tag X.Y.Z
#   5. Push main and tag
#   6. Create GitHub Release and upload the XCFramework zip
#
# Usage:
#   ./scripts/release.sh <version>          e.g. ./scripts/release.sh 1.0.0
#
# Requirements: Xcode 15+, gh CLI (https://cli.github.com), swift 5.9+

set -euo pipefail

# ── Parse arguments ──────────────────────────────────────────────────────────

if [ $# -ne 1 ]; then
    echo "Usage: $0 <version>   (e.g. 1.0.0)" >&2
    exit 1
fi

VERSION="$1"

# Validate semver-ish format
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
    echo "Error: version must be semver (e.g. 1.0.0 or 1.0.0-beta.1)" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build"

# ── Preflight ────────────────────────────────────────────────────────────────

command -v swift  >/dev/null 2>&1 || { echo "Error: swift not found."  >&2; exit 1; }
command -v xcodebuild >/dev/null 2>&1 || { echo "Error: xcodebuild not found (requires Xcode)." >&2; exit 1; }
command -v gh     >/dev/null 2>&1 || { echo "Error: gh CLI not found. Install from https://cli.github.com" >&2; exit 1; }

# Make sure we're in a clean repo
if [ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]; then
    echo "Error: working tree is not clean. Commit or stash changes first." >&2
    exit 1
fi

# Derive internal repo details
REMOTE_URL="$(git -C "$REPO_ROOT" remote get-url origin)"
GITHUB_REPO="$(echo "$REMOTE_URL" | sed -E 's#.*[:/]([^/]+/[^/.]+)(\.git)?$#\1#')"

# Public distribution repo
PUBLIC_REMOTE="public"
PUBLIC_REPO_URL="https://github.com/theHonzic/test-public.git"
PUBLIC_REPO="theHonzic/test-public"

echo "==> Releasing v${VERSION}"
echo "    Internal: ${GITHUB_REPO}"
echo "    Public:   ${PUBLIC_REPO}"
echo ""

# Remember which branch we started on so we can return
SOURCE_BRANCH="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"

# ── Step 1: Generate documentation ───────────────────────────────────────────

echo "==> Step 1/6: Generating documentation..."
bash "$SCRIPT_DIR/generate-docs.sh"

# ── Step 2: Build XCFrameworks ───────────────────────────────────────────────

echo ""
echo "==> Step 2/6: Building XCFrameworks..."
bash "$SCRIPT_DIR/archive.sh"

ZIP_PATH="$BUILD_DIR/MinimalPackage.xcframework.zip"
CHECKSUM="$(cat "$ZIP_PATH.sha256")"
# Download URL points to the PUBLIC repo releases
DOWNLOAD_URL="https://github.com/${PUBLIC_REPO}/releases/download/${VERSION}/MinimalPackage.xcframework.zip"

# ── Step 3: Prepare distribution Package.swift ───────────────────────────────

echo ""
echo "==> Step 3/6: Preparing distribution Package.swift..."

DIST_PACKAGE="$BUILD_DIR/Package.swift"
cat > "$DIST_PACKAGE" <<SWIFT
// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MinimalPackage",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "MinimalPackage",
            targets: ["MinimalPackageTarget"]
        ),
    ],
    dependencies: [
        // External runtime dependencies required by the binary
        .package(url: "https://github.com/airbnb/lottie-spm.git", .upToNextMajor(from: "4.5.2")),
        .package(url: "https://github.com/dagronf/qrcode.git", .upToNextMajor(from: "27.11.0")),
        .package(url: "https://github.com/apple/swift-openapi-runtime.git", .upToNextMajor(from: "1.8.3")),
        .package(url: "https://github.com/apple/swift-openapi-urlsession.git", .upToNextMajor(from: "1.2.0")),
        .package(url: "https://github.com/evgenyneu/keychain-swift.git", .upToNextMajor(from: "24.0.0")),
        .package(url: "https://github.com/getsentry/sentry-cocoa.git", from: "8.40.0"),
    ],
    targets: [
        // Thin wrapper that links the binary frameworks and their runtime deps
        .target(
            name: "MinimalPackageTarget",
            dependencies: [
                "MinimalPackageBinary",
                "MinimalPackageCoreBinary",
                "MinimalPackageFeatureBinary",
                .product(name: "Lottie", package: "lottie-spm"),
                .product(name: "QRCode", package: "qrcode"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
                .product(name: "KeychainSwift", package: "keychain-swift"),
                .product(name: "Sentry", package: "sentry-cocoa"),
            ],
            path: "Sources/MinimalPackageTarget"
        ),
        .binaryTarget(
            name: "MinimalPackageBinary",
            url: "$DOWNLOAD_URL",
            checksum: "$CHECKSUM"
        ),
        .binaryTarget(
            name: "MinimalPackageCoreBinary",
            url: "https://github.com/${PUBLIC_REPO}/releases/download/${VERSION}/MinimalPackageCore.xcframework.zip",
            checksum: "PLACEHOLDER_CORE"
        ),
        .binaryTarget(
            name: "MinimalPackageFeatureBinary",
            url: "https://github.com/${PUBLIC_REPO}/releases/download/${VERSION}/MinimalPackageFeature.xcframework.zip",
            checksum: "PLACEHOLDER_FEATURE"
        ),
    ]
)
SWIFT

# ── Step 4: Assemble public branch content ──────────────────────────────────

echo ""
echo "==> Step 4/6: Assembling public branch content..."

# Work in a temporary directory
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT

cp "$DIST_PACKAGE" "$STAGE_DIR/Package.swift"
mkdir -p "$STAGE_DIR/Sources/MinimalPackageTarget"

cat > "$STAGE_DIR/Sources/MinimalPackageTarget/Exports.swift" <<'SWIFTSRC'
@_exported import MinimalPackage
SWIFTSRC

cp -R "$REPO_ROOT/docs" "$STAGE_DIR/docs"
touch "$STAGE_DIR/.nojekyll"
touch "$STAGE_DIR/docs/.nojekyll"

cat > "$STAGE_DIR/index.html" <<EOF
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Redirecting...</title>
    <link rel="canonical" href="docs/documentation/minimalpackage">
    <script>location="docs/documentation/minimalpackage"</script>
    <meta http-equiv="refresh" content="0; url=docs/documentation/minimalpackage">
  </head>
  <body>
    <h1>Redirecting...</h1>
    <a href="docs/documentation/minimalpackage">Click here if you are not redirected.</a>
  </body>
</html>
EOF

# Use a temporary branch for the public push
TEMP_RELEASE_BRANCH="temp-public-release-${VERSION}"
git -C "$REPO_ROOT" checkout -b "$TEMP_RELEASE_BRANCH"

# Remove everything except .git
(
    cd "$REPO_ROOT"
    find . -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
)

cp -R "$STAGE_DIR/"* "$REPO_ROOT/"

# ── Step 5: Committing and Pushing ───────────────────────────────────────────

echo ""
echo "==> Step 5/6: Committing and pushing..."

git -C "$REPO_ROOT" add -A
git -C "$REPO_ROOT" commit -m "v${VERSION}"

# 1. Tag locally (on the source code state)
git -C "$REPO_ROOT" tag -a "$VERSION" -m "Release $VERSION"

# 2. Push source + tag to internal repo (origin)
git -C "$REPO_ROOT" push origin "$SOURCE_BRANCH"
git -C "$REPO_ROOT" push origin "$VERSION"

# 3. Force push the "clean" state to public repo main
git -C "$REPO_ROOT" push "$PUBLIC_REMOTE" "${TEMP_RELEASE_BRANCH}:main" --force

# ── Step 6: Create GitHub release (on Public Repo) ──────────────────────────

echo ""
echo "==> Step 6/6: Creating GitHub release on ${PUBLIC_REPO}..."

gh release create "$VERSION" \
    "$BUILD_DIR/MinimalPackage.xcframework.zip" \
    --repo "$PUBLIC_REPO" \
    --title "v${VERSION}" \
    --generate-notes \
    --notes "$(cat <<EOF
### Installation (Swift Package Manager)

Add to your \`Package.swift\`:

\`\`\`swift
dependencies: [
    .package(url: "https://github.com/${PUBLIC_REPO}.git", from: "${VERSION}")
]
\`\`\`

---
EOF
)"

# Return to source branch and cleanup
git -C "$REPO_ROOT" checkout "$SOURCE_BRANCH"
git -C "$REPO_ROOT" branch -D "$TEMP_RELEASE_BRANCH"

echo ""
echo "==> Release v${VERSION} complete!"
echo "    Internal: https://github.com/${GITHUB_REPO}"
echo "    Public:   https://github.com/${PUBLIC_REPO}/releases/tag/${VERSION}"
