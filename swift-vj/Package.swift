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
        // SwiftOSC for OSC communication
        .package(url: "https://github.com/ExistentialAudio/SwiftOSC.git", from: "1.4.0")
    ],
    targets: [
        .executableTarget(
            name: "SwiftVJ",
            dependencies: [
                .product(name: "SwiftOSC", package: "SwiftOSC")
            ],
            path: "Sources/SwiftVJ",
            resources: [
                .copy("Shaders"),
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "SwiftVJTests",
            dependencies: ["SwiftVJ"]
        )
    ]
)
