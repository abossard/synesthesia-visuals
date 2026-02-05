// ShaderDirectoryLocator.swift - Resolve active shader directory

import Foundation

enum ShaderDirectoryLocator {
    static func resolve(customPath: String?) -> URL? {
        let fileManager = FileManager.default

        if let configuredPath = customPath, !configuredPath.isEmpty {
            let configuredURL = URL(fileURLWithPath: configuredPath)
            if fileManager.fileExists(atPath: configuredURL.path) {
                return configuredURL
            }
        }

        let executableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])

        var currentURL = executableURL.deletingLastPathComponent()
        for _ in 0..<10 {
            let shadersURL = currentURL.appendingPathComponent("Shaders")
            if fileManager.fileExists(atPath: shadersURL.appendingPathComponent("glsl").path) {
                return shadersURL
            }

            let swiftVJShaders = currentURL.appendingPathComponent("swift-vj/Shaders")
            if fileManager.fileExists(atPath: swiftVJShaders.appendingPathComponent("glsl").path) {
                return swiftVJShaders
            }

            currentURL = currentURL.deletingLastPathComponent()
        }

        let devPaths = [
            URL(fileURLWithPath: "/Users/abossard/Desktop/projects/synesthesia-visuals/swift-vj/Shaders"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("swift-vj/Shaders"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Shaders")
        ]

        for devPath in devPaths {
            if fileManager.fileExists(atPath: devPath.appendingPathComponent("glsl").path) {
                return devPath
            }
        }

        return nil
    }
}
