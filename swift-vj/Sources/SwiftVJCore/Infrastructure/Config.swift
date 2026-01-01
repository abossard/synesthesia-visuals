// Configuration - Smart defaults for macOS VJ setups
// Infrastructure layer: cross-cutting concerns

import Foundation

// MARK: - Config

/// Application configuration with smart defaults
public struct Config {
    // OSC defaults
    public static let defaultOSCHost = "127.0.0.1"
    public static let oscReceivePort: UInt16 = 9999
    public static let oscVJUniversePort: UInt16 = 10000
    public static let oscMagicPort: UInt16 = 11111
    public static let oscVDJPort: UInt16 = 9009
    public static let oscSynesthesiaPort: UInt16 = 7777

    // Timing
    public static let timingStepMs: Int = 200
    public static let lyricsCacheTTLSeconds: TimeInterval = 86400 * 7 // 7 days

    // Playback
    public static let playbackPollIntervalMs: Int = 500

    /// Get application data directory (creates if needed)
    public static var dataDirectory: URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SwiftVJ")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Cache directory for lyrics, analysis, etc.
    public static var cacheDirectory: URL {
        dataDirectory.appendingPathComponent("cache")
    }

    /// Settings file path
    public static var settingsFile: URL {
        dataDirectory.appendingPathComponent("settings.json")
    }
}

// MARK: - Settings

/// Persistent user settings
public actor Settings {
    private var data: [String: Any]
    private let filePath: URL

    public init(filePath: URL? = nil) {
        self.filePath = filePath ?? Config.settingsFile
        self.data = Self.load(from: self.filePath)
    }

    // MARK: - Timing

    public var timingOffsetMs: Int {
        get { data["timing_offset_ms"] as? Int ?? 0 }
    }

    public func setTimingOffset(_ value: Int) async {
        data["timing_offset_ms"] = value
        save()
    }

    public var timingOffsetSec: Double {
        Double(timingOffsetMs) / 1000.0
    }

    public func adjustTiming(by deltaMs: Int) async -> Int {
        let newOffset = timingOffsetMs + deltaMs
        await setTimingOffset(newOffset)
        return newOffset
    }

    // MARK: - Playback Source

    public var playbackSource: String {
        get { data["playback_source"] as? String ?? "" }
    }

    public func setPlaybackSource(_ value: String) async {
        data["playback_source"] = value
        save()
    }

    public var playbackPollIntervalMs: Int {
        get {
            let value = data["playback_poll_interval_ms"] as? Int ?? 1000
            return max(1000, min(10000, value))
        }
    }

    // MARK: - App Startup Preferences

    public var startSynesthesia: Bool {
        get { data["start_synesthesia"] as? Bool ?? false }
    }

    public func setStartSynesthesia(_ value: Bool) async {
        data["start_synesthesia"] = value
        save()
    }

    public var startVJUniverse: Bool {
        get { data["start_vjuniverse"] as? Bool ?? false }
    }

    public var startLMStudio: Bool {
        get { data["start_lmstudio"] as? Bool ?? false }
    }

    // MARK: - Private

    private static func load(from path: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return json
    }

    private func save() {
        guard let data = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted)
        else { return }
        try? data.write(to: filePath)
    }
}

// MARK: - Service Health

/// Tracks service availability with reconnection management
public actor ServiceHealth {
    public let name: String
    private var isAvailable: Bool = false
    private var lastCheck: Date = .distantPast
    private var lastError: String = ""
    private var errorCount: Int = 0

    public static let reconnectInterval: TimeInterval = 30.0

    public init(name: String) {
        self.name = name
    }

    public var available: Bool {
        isAvailable
    }

    public var shouldRetry: Bool {
        Date().timeIntervalSince(lastCheck) >= Self.reconnectInterval
    }

    public func markAvailable(message: String = "") {
        let wasUnavailable = !isAvailable
        isAvailable = true
        lastCheck = Date()
        lastError = ""
        if wasUnavailable && !message.isEmpty {
            print("[\(name)] \(message)")
        }
    }

    public func markUnavailable(error: String = "") {
        let wasAvailable = isAvailable
        isAvailable = false
        lastCheck = Date()
        errorCount += 1
        if error != lastError {
            lastError = error
            if wasAvailable || errorCount == 1 {
                print("[\(name)] \(error)")
            }
        }
    }

    public func status() -> [String: Any] {
        [
            "name": name,
            "available": isAvailable,
            "error": lastError,
            "errorCount": errorCount
        ]
    }
}

// MARK: - Backoff Policy

/// Configuration for exponential backoff
public struct BackoffPolicy: Sendable {
    public let baseDelay: TimeInterval
    public let maxDelay: TimeInterval
    public let factor: Double

    public init(
        baseDelay: TimeInterval = 0.5,
        maxDelay: TimeInterval = 30.0,
        factor: Double = 2.0
    ) {
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.factor = factor
    }

    public func delay(for attempts: Int) -> TimeInterval {
        min(baseDelay * pow(factor, Double(max(0, attempts))), maxDelay)
    }
}

/// Immutable backoff tracking state
public struct BackoffState: Sendable {
    public let attempts: Int
    public let nextAllowed: Date
    public let lastError: String
    public let policy: BackoffPolicy

    public init(
        attempts: Int = 0,
        nextAllowed: Date = .distantPast,
        lastError: String = "",
        policy: BackoffPolicy = BackoffPolicy()
    ) {
        self.attempts = attempts
        self.nextAllowed = nextAllowed
        self.lastError = lastError
        self.policy = policy
    }

    public func ready(at date: Date = Date()) -> Bool {
        date >= nextAllowed
    }

    public func recordFailure(error: String, at date: Date = Date()) -> BackoffState {
        let delay = policy.delay(for: attempts)
        return BackoffState(
            attempts: attempts + 1,
            nextAllowed: date.addingTimeInterval(delay),
            lastError: error,
            policy: policy
        )
    }

    public func recordSuccess() -> BackoffState {
        BackoffState(policy: policy)
    }

    public func timeRemaining(at date: Date = Date()) -> TimeInterval {
        max(0, nextAllowed.timeIntervalSince(date))
    }
}
