// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftVJ",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // CLI executable
        .executable(
            name: "swift-vj",
            targets: ["SwiftVJ"]),
        // Core library (for embedding)
        .library(
            name: "SwiftVJCore",
            targets: ["SwiftVJCore"]),
    ],
    dependencies: [
        // OSC communication
        .package(url: "https://github.com/orchetect/OSCKit", from: "0.6.0"),
        // Command-line argument parsing
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
    ],
    targets: [
        // CLI executable
        .executableTarget(
            name: "SwiftVJ",
            dependencies: [
                "SwiftVJCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]),

        // Core library containing all business logic
        .target(
            name: "SwiftVJCore",
            dependencies: [
                .product(name: "OSCKit", package: "OSCKit"),
            ]),

        // Behavior tests - pure functions, no external dependencies
        .testTarget(
            name: "BehaviorTests",
            dependencies: ["SwiftVJCore"]),

        // E2E tests - require external services
        .testTarget(
            name: "E2ETests",
            dependencies: ["SwiftVJCore"]),
    ]
)
