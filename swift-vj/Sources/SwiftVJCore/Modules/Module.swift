// Module Protocol - Base interface for all VJ system modules
// Following A Philosophy of Software Design: deep modules with simple interfaces

import Foundation

/// Base protocol for all VJ system modules.
///
/// Modules follow a simple lifecycle:
/// - `start()` - Begin background processing
/// - `stop()` - Clean shutdown
///
/// Each module can run standalone via CLI for testing/debugging.
public protocol Module: Actor {
    /// Whether the module has been started
    var isStarted: Bool { get }

    /// Start the module. Throws on failure.
    func start() async throws

    /// Stop the module and clean up resources.
    func stop() async

    /// Get module status for monitoring
    func getStatus() -> [String: Any]
}

/// Default implementation for common status fields
extension Module {
    public func getStatus() -> [String: Any] {
        ["started": isStarted]
    }
}

// MARK: - Module Errors

public enum ModuleError: Error, LocalizedError {
    case notStarted
    case alreadyStarted
    case startupFailed(String)
    case dependencyUnavailable(String)
    case configurationError(String)

    public var errorDescription: String? {
        switch self {
        case .notStarted:
            return "Module not started"
        case .alreadyStarted:
            return "Module already started"
        case .startupFailed(let reason):
            return "Startup failed: \(reason)"
        case .dependencyUnavailable(let name):
            return "Dependency unavailable: \(name)"
        case .configurationError(let reason):
            return "Configuration error: \(reason)"
        }
    }
}

// MARK: - Playback Source Protocol

/// Protocol for playback sources (VDJ, Spotify, etc.)
public protocol PlaybackSource: Sendable {
    /// Unique identifier for this source
    var sourceKey: String { get }

    /// Human-readable label
    var sourceLabel: String { get }

    /// Get current playback state
    func getPlayback() async throws -> PlaybackState?
}

// MARK: - Module Callbacks

/// Callback fired when track changes
public typealias TrackChangeCallback = @Sendable (Track) async -> Void

/// Callback fired when playback position updates
public typealias PositionUpdateCallback = @Sendable (Double, Bool) async -> Void

/// Callback fired when pipeline step starts
public typealias PipelineStepStartCallback = @Sendable (String) async -> Void

/// Callback fired when pipeline step completes
public typealias PipelineStepCompleteCallback = @Sendable (String, [String: Any]) async -> Void

/// Callback fired when pipeline completes
public typealias PipelineCompleteCallback = @Sendable (PipelineResult) async -> Void
