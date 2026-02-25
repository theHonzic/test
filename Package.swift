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
            url: "https://github.com/theHonzic/test/releases/download/1.0.12/MinimalPackage.xcframework.zip",
            checksum: "b3bb53f02ddc08f84bed71251e73fa83754855ce3ebd15bf38b9d555bd1f84bf"
        ),
        .binaryTarget(
            name: "MinimalPackageCoreBinary",
            url: "https://github.com/theHonzic/test/releases/download/1.0.12/MinimalPackageCore.xcframework.zip",
            checksum: "PLACEHOLDER_CORE"
        ),
        .binaryTarget(
            name: "MinimalPackageFeatureBinary",
            url: "https://github.com/theHonzic/test/releases/download/1.0.12/MinimalPackageFeature.xcframework.zip",
            checksum: "PLACEHOLDER_FEATURE"
        ),
    ]
)
