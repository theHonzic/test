// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MinimalPackage",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "MinimalPackage",
            type: .dynamic,
            targets: ["MinimalPackage"]
        ),
    ],
    dependencies: [
        // UI
        .package(url: "https://github.com/airbnb/lottie-spm.git", .upToNextMajor(from: "4.5.2")),
        // .package(url: "https://github.com/dagronf/qrcode.git", .upToNextMajor(from: "27.11.0")),

        // OpenAPI
        .package(url: "https://github.com/apple/swift-openapi-generator.git", .upToNextMajor(from: "1.10.3")),
        .package(url: "https://github.com/apple/swift-openapi-runtime.git", .upToNextMajor(from: "1.8.3")),
        .package(url: "https://github.com/apple/swift-openapi-urlsession.git", .upToNextMajor(from: "1.2.0")),

        // Persistence
        // .package(url: "https://github.com/evgenyneu/keychain-swift.git", .upToNextMajor(from: "24.0.0")),

        // Monitoring
        .package(url: "https://github.com/getsentry/sentry-cocoa.git", from: "8.40.0"),

        // Documentation
        .package(url: "https://github.com/swiftlang/swift-docc-plugin.git", from: "1.4.3"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "MinimalPackage",
            dependencies: [
                .target(name: "MinimalPackageCore"),
                .target(name: "MinimalPackageFeature")
            ],
            path: "Sources/MinimalPackage"
        ),
        .target(
            name: "MinimalPackageCore",
            dependencies: [
                .product(name: "Sentry", package: "sentry-cocoa")
            ],
            path: "Sources/MinimalPackageCore"
        ),
        .target(
            name: "MinimalPackageFeature",
            dependencies: [
                .product(name: "Lottie", package: "lottie-spm"),
                // .product(name: "QRCode", package: "qrcode"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
                // .product(name: "KeychainSwift", package: "keychain-swift"),
                .target(name: "MinimalPackageCore")
            ],
            path: "Sources/MinimalPackageFeature"
        ),
    ]
)
