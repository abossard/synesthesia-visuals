// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftVJ",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "SwiftVJ",
            targets: ["SwiftVJ"]
        )
    ],
    dependencies: [
        // TODO: Add SwiftOSC once SPM support is available
        // SwiftOSC requires manual integration via CocoaPods or source vendoring
        // See DEVELOPMENT.md for OSC integration instructions
    ],
    targets: [
        .executableTarget(
            name: "SwiftVJ",
            dependencies: [],
            path: "Sources/SwiftVJ"
            // Resources will be handled separately when Syphon integration is complete
        ),
        .testTarget(
            name: "SwiftVJTests",
            dependencies: ["SwiftVJ"]
        )
    ]
)
