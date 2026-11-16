// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SwiftCode",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "SwiftCodeCore",
            targets: ["SwiftCodeCore"]
        ),
        .library(
            name: "SwiftCodeDaemon",
            targets: ["SwiftCodeDaemon"]
        ),
        .executable(
            name: "swiftcode",
            targets: ["swiftcode"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "604.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.105.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.17.0"),
        .package(url: "https://github.com/apple/swift-metrics.git", from: "2.13.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "5.1.1"),
    ],
    targets: [
        .target(
            name: "SwiftCodeCore",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Metrics", package: "swift-metrics"),
            ]
        ),
        .target(
            name: "SwiftCodeDaemon",
            dependencies: [
                "SwiftCodeCore",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Metrics", package: "swift-metrics"),
            ]
        ),
        .executableTarget(
            name: "swiftcode",
            dependencies: [
                "SwiftCodeCore",
                "SwiftCodeDaemon",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Metrics", package: "swift-metrics"),
            ]
        ),
        .testTarget(
            name: "SwiftCodeCoreTests",
            dependencies: [
                "SwiftCodeCore",
                "SwiftCodeDaemon",
            ]
        ),
    ]
)
