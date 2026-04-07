// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftVJ",
    platforms: [
        .macOS(.v15),
        .iOS(.v17)  // Required by OSCKit dependency, though we only target macOS
    ],
    products: [
        // CLI executable
        .executable(
            name: "swift-vj",
            targets: ["SwiftVJ"]),
        // SwiftUI macOS app
        .executable(
            name: "SwiftVJApp",
            targets: ["SwiftVJApp"]),
        // Shader compilation CLI
        .executable(
            name: "shader-compile",
            targets: ["ShaderCompile"]),
        // Shader Repository compilation CLI
        .executable(
            name: "compile-shaders",
            targets: ["CompileShaders"]),
        // Core library (for embedding)
        .library(
            name: "SwiftVJCore",
            targets: ["SwiftVJCore"]),
        // Shader Repository - single source of truth for shaders
        .library(
            name: "ShaderRepository",
            targets: ["ShaderRepository"]),
        // Song Repository - single source of truth for songs
        .library(
            name: "SongRepository",
            targets: ["SongRepository"]),
        // Shadertoy Runtime library
        .library(
            name: "ShadertoyRuntime",
            targets: ["ShadertoyRuntime"]),
        // OSC Rest Bridge - generic OSC → REST bridge
        .library(
            name: "OscRestBridge",
            targets: ["OscRestBridge"]),
    ],
    dependencies: [
        // OSC communication
        .package(url: "https://github.com/orchetect/OSCKit", from: "2.0.0"),
        // Command-line argument parsing
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
        // YAML parsing for config files
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.0.0"),
        // SwiftUI view inspection for tests
        .package(url: "https://github.com/nalexn/ViewInspector", from: "0.9.10"),
        // Multi-provider LLM abstraction
        .package(path: "Vendor/Tachikoma"),
        // Terminal emulator (VT100/Xterm) for embedded terminal windows
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.0.0"),
    ],
    targets: [
        // Syphon binary framework (built from Syphon-Framework)
        .binaryTarget(
            name: "Syphon",
            path: "Frameworks/Syphon.xcframework"
        ),
        
        // SyphonKit - Swift wrapper for Syphon
        .target(
            name: "SyphonKit",
            dependencies: ["Syphon"],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("IOSurface"),
                .linkedFramework("OpenGL"),
            ]
        ),
        
        // CLI executable
        .executableTarget(
            name: "SwiftVJ",
            dependencies: [
                "SwiftVJCore",
                "ShaderRepository",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            linkerSettings: [
                .linkedFramework("Metal"),
            ]),

        // SwiftUI macOS app
        .executableTarget(
            name: "SwiftVJApp",
            dependencies: [
                "SwiftVJCore",
                "ShaderRepository",
                "SongRepository",
                "SyphonKit",
                "OscRestBridge",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            resources: [
                .copy("Resources/Shaders.metallib"),
                .process("Resources/SharedVertex.metal"),
                .process("Resources/Assets.xcassets"),
            ]),

        // Core library containing all business logic
        .target(
            name: "SwiftVJCore",
            dependencies: [
                "ShaderRepository",
                "SongRepository",
                .product(name: "OSCKit", package: "OSCKit"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "Tachikoma", package: "Tachikoma"),
            ],
            resources: [
                .copy("Resources/launchpad-config.yaml"),
            ]),

        // Shader Repository - pure functions for shader management
        .target(
            name: "ShaderRepository",
            dependencies: [
                .product(name: "Tachikoma", package: "Tachikoma"),
            ]),

        // Song Repository - pure functions for song management
        .target(
            name: "SongRepository",
            dependencies: ["ShaderRepository"]),  // Depends on ShaderRepository for Phase type

        // Shadertoy Runtime - GLSL to Metal shader runtime
        .target(
            name: "ShadertoyRuntime",
            dependencies: [],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("CoreGraphics"),
            ]
        ),

        // Shader compilation CLI tool
        .executableTarget(
            name: "ShaderCompile",
            dependencies: [
                "ShadertoyRuntime",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]),

        // ShaderRepository compilation CLI tool
        .executableTarget(
            name: "CompileShaders",
            dependencies: [
                "ShaderRepository",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]),

        // Behavior tests - pure functions, no external dependencies
        .testTarget(
            name: "BehaviorTests",
            dependencies: [
                "SwiftVJCore",
                .product(name: "Yams", package: "Yams"),
            ]),

        // E2E tests - require external services
        .testTarget(
            name: "E2ETests",
            dependencies: ["SwiftVJCore"]),

        // ShaderRepository tests - use real shader files
        .testTarget(
            name: "ShaderRepositoryTests",
            dependencies: ["ShaderRepository"]),

        // SwiftVJApp tests - karaoke engine and UI behavior
        .testTarget(
            name: "SwiftVJAppTests",
            dependencies: [
                "SwiftVJApp",
                "SwiftVJCore",
                .product(name: "ViewInspector", package: "ViewInspector"),
            ]),
        
        // OscRestBridge - generic OSC → REST bridge
        .target(
            name: "OscRestBridge",
            dependencies: [
                "SwiftVJCore",
                .product(name: "OSCKit", package: "OSCKit"),
                .product(name: "Yams", package: "Yams"),
            ],
            exclude: [
                "IMPLEMENTATION_SUMMARY.md",
                "INTEGRATION.md",
                "README.md",
            ],
            resources: [
                .copy("Resources/config-ledfx.yaml"),
            ]),
        
        // OscRestBridge tests - behavioral tests
        .testTarget(
            name: "OscRestBridgeTests",
            dependencies: ["OscRestBridge"]),
    ]
)
