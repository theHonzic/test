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

# Derive GitHub owner/repo from the remote (works with HTTPS and SSH)
REMOTE_URL="$(git -C "$REPO_ROOT" remote get-url origin)"
GITHUB_REPO="$(echo "$REMOTE_URL" | sed -E 's#.*[:/]([^/]+/[^/.]+)(\.git)?$#\1#')"

echo "==> Releasing v${VERSION} for ${GITHUB_REPO}"
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
DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${VERSION}/MinimalPackage.xcframework.zip"

# ── Step 3: Prepare distribution Package.swift ───────────────────────────────

echo ""
echo "==> Step 3/6: Preparing main branch..."

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
            url: "https://github.com/${GITHUB_REPO}/releases/download/${VERSION}/MinimalPackageCore.xcframework.zip",
            checksum: "PLACEHOLDER_CORE"
        ),
        .binaryTarget(
            name: "MinimalPackageFeatureBinary",
            url: "https://github.com/${GITHUB_REPO}/releases/download/${VERSION}/MinimalPackageFeature.xcframework.zip",
            checksum: "PLACEHOLDER_FEATURE"
        ),
    ]
)
SWIFT

# ── Step 4: Assemble main branch ────────────────────────────────────────────

echo ""
echo "==> Step 4/6: Assembling main branch content..."

# Fetch latest state of main (may not exist yet)
git -C "$REPO_ROOT" fetch origin main 2>/dev/null || true

# Work in a temporary directory so we don't clobber anything
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT

# Copy only what belongs on main
cp "$DIST_PACKAGE" "$STAGE_DIR/Package.swift"
mkdir -p "$STAGE_DIR/Sources/MinimalPackageTarget"

# Thin wrapper source: re-exports so `import MinimalPackage` works via the binary
cat > "$STAGE_DIR/Sources/MinimalPackageTarget/Exports.swift" <<'SWIFTSRC'
@_exported import MinimalPackage
SWIFTSRC

# Copy generated docs
cp -R "$REPO_ROOT/docs" "$STAGE_DIR/docs"

# Switch to main (create orphan if it doesn't exist yet)
if git -C "$REPO_ROOT" show-ref --verify --quiet refs/heads/main; then
    git -C "$REPO_ROOT" checkout main
else
    git -C "$REPO_ROOT" checkout --orphan main
    git -C "$REPO_ROOT" rm -rf . 2>/dev/null || true
fi

# Replace working tree with staged content
# Remove everything except .git
find "$REPO_ROOT" -maxdepth 1 \
    ! -name '.git' ! -name '.' ! -name '..' \
    -exec rm -rf {} +

cp -R "$STAGE_DIR/Package.swift" "$REPO_ROOT/Package.swift"
cp -R "$STAGE_DIR/Sources"       "$REPO_ROOT/Sources"
cp -R "$STAGE_DIR/docs"          "$REPO_ROOT/docs"

# ── Step 5: Commit, tag, push ────────────────────────────────────────────────

echo ""
echo "==> Step 5/6: Committing v${VERSION} and pushing..."

git -C "$REPO_ROOT" add -A
git -C "$REPO_ROOT" commit -m "v${VERSION}"
git -C "$REPO_ROOT" tag -a "$VERSION" -m "Release $VERSION"

git -C "$REPO_ROOT" push -u origin main
git -C "$REPO_ROOT" push origin "$VERSION"

# ── Step 6: Create GitHub release ────────────────────────────────────────────

echo ""
echo "==> Step 6/6: Creating GitHub release..."

gh release create "$VERSION" \
    "$ZIP_PATH" \
    --repo "$GITHUB_REPO" \
    --title "v${VERSION}" \
    --notes "$(cat <<EOF
## MinimalPackage v${VERSION}

### Installation (Swift Package Manager)

Add to your \`Package.swift\`:

\`\`\`swift
dependencies: [
    .package(url: "https://github.com/${GITHUB_REPO}.git", from: "${VERSION}")
]
\`\`\`

Then import in your code:

\`\`\`swift
import MinimalPackage
\`\`\`

### Checksums

| Artifact | SHA-256 |
|----------|---------|
| MinimalPackage.xcframework.zip | \`${CHECKSUM}\` |
EOF
)"

# Return to the original branch
git -C "$REPO_ROOT" checkout "$SOURCE_BRANCH"

echo ""
echo "==> Release v${VERSION} complete!"
echo "    https://github.com/${GITHUB_REPO}/releases/tag/${VERSION}"
