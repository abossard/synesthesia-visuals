// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VDJStatus",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "vdjstatus", targets: ["VDJStatusCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        // CLI executable - includes all source files via symlinks
        .executableTarget(
            name: "VDJStatusCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/VDJStatusCLI"
        ),
        // Tests for core logic
        .testTarget(
            name: "VDJStatusCoreTests",
            dependencies: [],
            path: "Tests/VDJStatusCoreTests"
        ),
    ]
)
