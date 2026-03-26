// BridgeConfigLoader.swift - Loads/saves OSCBridgeConfig from YAML files
// Following Grokking Simplicity: file I/O is an action, isolated in this actor

import Foundation
import Yams

/// Errors specific to bridge configuration loading.
public enum OSCBridgeConfigError: Error, CustomStringConvertible {
    case fileNotFound(String)
    case invalidEncoding
    case parseError(String)
    case writeError(String)

    public var description: String {
        switch self {
        case .fileNotFound(let path): return "Bridge config file not found: \(path)"
        case .invalidEncoding: return "Bridge config file is not valid UTF-8"
        case .parseError(let detail): return "Bridge config parse error: \(detail)"
        case .writeError(let detail): return "Bridge config write error: \(detail)"
        }
    }
}

/// Actor that loads and saves `OSCBridgeConfig` from YAML files.
/// Deep module: hides YAML parsing, validation, and file I/O behind two methods.
public actor OSCBridgeConfigLoader {

    /// Default config file location: ~/.config/swift-vj/bridge-config.yaml
    public static let defaultConfigURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/swift-vj/bridge-config.yaml")
    }()

    private var cached: OSCBridgeConfig?

    public init() {}

    // MARK: - Public API

    /// Load a `OSCBridgeConfig` from a YAML file.
    /// Falls back to `OSCBridgeConfig.default` if the file does not exist.
    public func load(from url: URL? = nil) async throws -> OSCBridgeConfig {
        let configURL = url ?? Self.defaultConfigURL

        guard FileManager.default.fileExists(atPath: configURL.path) else {
            let config = OSCBridgeConfig.default
            cached = config
            return config
        }

        let data: Data
        do {
            data = try Data(contentsOf: configURL)
        } catch {
            throw OSCBridgeConfigError.fileNotFound(configURL.path)
        }

        let config = try parse(data, source: configURL.path)
        cached = config
        return config
    }

    /// Load from a YAML string (useful for testing).
    public func load(from yamlString: String) throws -> OSCBridgeConfig {
        guard let data = yamlString.data(using: .utf8) else {
            throw OSCBridgeConfigError.invalidEncoding
        }
        let config = try parse(data, source: "<string>")
        cached = config
        return config
    }

    /// Load the bundled default config from the module's resource bundle.
    /// Note: Currently returns the in-code default since no bundled resource exists.
    public func loadBundled() throws -> OSCBridgeConfig {
        let config = OSCBridgeConfig.default
        cached = config
        return config
    }

    /// Save a `OSCBridgeConfig` to a YAML file.
    /// Creates parent directories if needed.
    public func save(_ config: OSCBridgeConfig, to url: URL? = nil) async throws {
        let configURL = url ?? Self.defaultConfigURL

        let encoder = YAMLEncoder()
        let yamlString: String
        do {
            yamlString = try encoder.encode(config)
        } catch {
            throw OSCBridgeConfigError.writeError("YAML encoding failed: \(error.localizedDescription)")
        }

        let dir = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        guard let data = yamlString.data(using: .utf8) else {
            throw OSCBridgeConfigError.invalidEncoding
        }

        do {
            try data.write(to: configURL, options: .atomic)
        } catch {
            throw OSCBridgeConfigError.writeError("Failed to write \(configURL.path): \(error.localizedDescription)")
        }

        cached = config
    }

    /// Return the last loaded config, or load from the default location.
    public func current() async throws -> OSCBridgeConfig {
        if let cached { return cached }
        return try await load()
    }

    // MARK: - Private

    private func parse(_ data: Data, source: String) throws -> OSCBridgeConfig {
        do {
            let decoder = YAMLDecoder()
            return try decoder.decode(OSCBridgeConfig.self, from: data)
        } catch let error as DecodingError {
            throw OSCBridgeConfigError.parseError(formatDecodingError(error, source: source))
        } catch {
            throw OSCBridgeConfigError.parseError("Failed to parse YAML from \(source): \(error.localizedDescription)")
        }
    }

    private func formatDecodingError(_ error: DecodingError, source: String) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            return "\(source): missing key '\(key.stringValue)' at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .typeMismatch(let type, let context):
            return "\(source): type mismatch for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .valueNotFound(let type, let context):
            return "\(source): missing value for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .dataCorrupted(let context):
            return "\(source): corrupted data at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        @unknown default:
            return "\(source): \(error.localizedDescription)"
        }
    }
}
