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
        // Sources are symlinked from VDJStatus/ folder for code sharing with Xcode project
        .executableTarget(
            name: "VDJStatusCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/VDJStatusCLI"
        ),
        // Note: Tests are run via Xcode project (VDJStatusTests target)
        // The tests import the Xcode target which includes all the same source files
    ]
)
