// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VDJStatus",
    platforms: [
        .macOS(.v13)  // ScreenCaptureKit requires macOS 13+
    ],
    products: [
        // Shared core library containing business logic
        .library(
            name: "VDJStatusCore",
            targets: ["VDJStatusCore"]
        ),
        // CLI executable
        .executable(
            name: "vdjstatus-cli",
            targets: ["VDJStatusCLI"]
        ),
    ],
    dependencies: [
        // No external dependencies - all native macOS frameworks
    ],
    targets: [
        // Core business logic (shared between GUI and CLI)
        .target(
            name: "VDJStatusCore",
            dependencies: [],
            path: "Sources/VDJStatusCore"
        ),

        // CLI executable target
        .executableTarget(
            name: "VDJStatusCLI",
            dependencies: ["VDJStatusCore"],
            path: "Sources/VDJStatusCLI",
            resources: [
                .copy("Resources/Info.plist")
            ]
        ),

        // Tests
        .testTarget(
            name: "VDJStatusCoreTests",
            dependencies: ["VDJStatusCore"],
            path: "Tests/VDJStatusCoreTests"
        ),
    ]
)
