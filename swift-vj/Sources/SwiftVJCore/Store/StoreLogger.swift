// StoreLogger.swift - Efficient action logging for UDF debugging
// Zero overhead when disabled, minimal impact when enabled

import Foundation

// MARK: - Compile-Time Flag

/// Set to false in release builds to completely eliminate logging overhead
#if DEBUG
public let STORE_LOGGING_ENABLED = true
#else
public let STORE_LOGGING_ENABLED = false
#endif

// MARK: - Log Entry (Lightweight)

/// Minimal log entry - diffs computed lazily only when displayed
public struct ActionLogEntry: Identifiable, Sendable {
    public let id: UInt64
    public let timestamp: Double  // TimeInterval since reference date (cheaper than Date)
    public let actionType: String // Just the action name, not full description
    public let actionDetail: String // Parameters (computed lazily by caller)
    public let stateChanged: Bool
    public let reducerDurationNs: UInt64 // Nanoseconds for precision without Date overhead

    public var date: Date {
        Date(timeIntervalSinceReferenceDate: timestamp)
    }

    public var durationMs: Double {
        Double(reducerDurationNs) / 1_000_000.0
    }
}

// MARK: - Action Classifier

/// Fast action classification without full string conversion
public enum ActionCategory: String, Sendable {
    case playback, pipeline, render, launchpad, audio, ui, lifecycle, persistence
}

/// Extract action category from action (fast path)
@inlinable
public func classifyAction<Action>(_ action: Action) -> ActionCategory {
    let typeName = String(describing: type(of: action))
    if typeName.contains("Playback") { return .playback }
    if typeName.contains("Pipeline") { return .pipeline }
    if typeName.contains("Render") { return .render }
    if typeName.contains("Launchpad") { return .launchpad }
    if typeName.contains("Audio") { return .audio }
    if typeName.contains("UI") { return .ui }
    return .lifecycle
}

// MARK: - Ring Buffer

/// Fixed-size ring buffer for log entries - no allocations after init
public struct RingBuffer<T>: Sendable where T: Sendable {
    private var storage: [T?]
    private var writeIndex: Int = 0
    private var _count: Int = 0

    public var count: Int { _count }
    public var capacity: Int { storage.count }

    public init(capacity: Int) {
        self.storage = Array(repeating: nil, count: capacity)
    }

    public mutating func append(_ element: T) {
        storage[writeIndex] = element
        writeIndex = (writeIndex + 1) % storage.count
        _count = min(_count + 1, storage.count)
    }

    public mutating func clear() {
        storage = Array(repeating: nil, count: storage.count)
        writeIndex = 0
        _count = 0
    }

    /// Get entries in chronological order
    public var entries: [T] {
        guard _count > 0 else { return [] }

        var result: [T] = []
        result.reserveCapacity(_count)

        if _count < storage.count {
            // Not wrapped yet
            for i in 0..<_count {
                if let entry = storage[i] {
                    result.append(entry)
                }
            }
        } else {
            // Wrapped - start from writeIndex
            for i in 0..<storage.count {
                let idx = (writeIndex + i) % storage.count
                if let entry = storage[idx] {
                    result.append(entry)
                }
            }
        }
        return result
    }
}

// MARK: - Store Logger (Efficient)

/// High-performance logger that wraps a reducer
/// - Zero overhead when disabled (compile-time check)
/// - Minimal overhead when enabled (no reflection, ring buffer)
/// - Follows UDF: wraps reducer as middleware, doesn't mutate state
@MainActor
public final class StoreLogger<State: Equatable, Action>: ObservableObject {

    // MARK: - Published (for UI binding)

    @Published public private(set) var entryCount: Int = 0
    @Published public var isEnabled: Bool = true
    @Published public var filter: String = ""

    // MARK: - Storage

    private var buffer: RingBuffer<ActionLogEntry>
    private var nextId: UInt64 = 0

    // MARK: - Configuration

    /// Categories to exclude from logging
    public var excludedCategories: Set<ActionCategory> = [.audio]

    /// Custom filter (return false to exclude)
    public var customFilter: ((Action) -> Bool)?

    /// Print to console (async to avoid blocking)
    public var printToConsole: Bool = true

    /// Console output queue
    private let consoleQueue = DispatchQueue(label: "store.logger.console", qos: .utility)

    // MARK: - Init

    public init(capacity: Int = 500) {
        self.buffer = RingBuffer(capacity: capacity)
    }

    // MARK: - Public API

    /// Get all entries (computed property, not stored)
    public var entries: [ActionLogEntry] {
        buffer.entries
    }

    /// Get filtered entries
    public var filteredEntries: [ActionLogEntry] {
        guard !filter.isEmpty else { return entries }
        let lowercasedFilter = filter.lowercased()
        return entries.filter {
            $0.actionType.lowercased().contains(lowercasedFilter) ||
            $0.actionDetail.lowercased().contains(lowercasedFilter)
        }
    }

    /// Clear log
    public func clear() {
        buffer.clear()
        entryCount = 0
    }

    // MARK: - Reducer Wrapper

    /// Wrap a reducer with logging - the UDF way
    /// Returns a new reducer that logs actions and state changes
    @inlinable
    public func wrap(
        reducer: @escaping (inout State, Action) -> Effect<Action>
    ) -> (inout State, Action) -> Effect<Action> {
        // Compile-time elimination in release builds
        guard STORE_LOGGING_ENABLED else { return reducer }

        return { [weak self] state, action in
            guard let self = self, self.isEnabled else {
                return reducer(&state, action)
            }

            // Fast path: check category filter before any work
            let category = classifyAction(action)
            if self.excludedCategories.contains(category) {
                return reducer(&state, action)
            }

            // Custom filter check
            if let customFilter = self.customFilter, !customFilter(action) {
                return reducer(&state, action)
            }

            // Capture state hash for cheap equality check
            let oldState = state

            // Time the reducer (using ContinuousClock for precision)
            let startTime = DispatchTime.now().uptimeNanoseconds

            let effect = reducer(&state, action)

            let endTime = DispatchTime.now().uptimeNanoseconds
            let durationNs = endTime - startTime

            // Check if state changed (uses Equatable, very fast)
            let stateChanged = oldState != state

            // Extract action info (lazy, only string ops we need)
            let (actionType, actionDetail) = self.extractActionInfo(action)

            // Create entry
            let entry = ActionLogEntry(
                id: self.nextId,
                timestamp: Date.timeIntervalSinceReferenceDate,
                actionType: actionType,
                actionDetail: actionDetail,
                stateChanged: stateChanged,
                reducerDurationNs: durationNs
            )
            self.nextId += 1

            // Store entry (ring buffer, no allocation)
            self.buffer.append(entry)
            self.entryCount = self.buffer.count

            // Console output (async, non-blocking)
            if self.printToConsole {
                self.consoleQueue.async {
                    self.printEntry(entry, category: category)
                }
            }

            return effect
        }
    }

    // MARK: - Private

    /// Extract action type and detail efficiently
    private func extractActionInfo(_ action: Action) -> (type: String, detail: String) {
        let fullDesc = String(describing: action)

        // Parse "category(subAction(params))" format
        if let parenIndex = fullDesc.firstIndex(of: "(") {
            let type = String(fullDesc[..<parenIndex])
            let detail = String(fullDesc[parenIndex...])
            return (type, detail)
        }

        return (fullDesc, "")
    }

    /// Print entry to console (called on background queue)
    private nonisolated func printEntry(_ entry: ActionLogEntry, category: ActionCategory) {
        let timeStr = formatTime(entry.timestamp)
        let durationStr = String(format: "%.2fms", entry.durationMs)
        let changeIndicator = entry.stateChanged ? "Δ" : "○"

        print("\(timeStr) \(changeIndicator) \(entry.actionType)\(entry.actionDetail) [\(durationStr)]")
    }

    /// Format timestamp efficiently
    private nonisolated func formatTime(_ timestamp: Double) -> String {
        let date = Date(timeIntervalSinceReferenceDate: timestamp)
        let components = Calendar.current.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let ms = (components.nanosecond ?? 0) / 1_000_000
        return String(format: "%02d:%02d:%02d.%03d",
                      components.hour ?? 0,
                      components.minute ?? 0,
                      components.second ?? 0,
                      ms)
    }
}

// MARK: - Convenience

extension StoreLogger {
    /// Quick setup for typical use
    public func configureDefaults() {
        excludedCategories = [.audio] // Audio is too noisy
        printToConsole = true
    }

    /// Exclude high-frequency actions
    public func filterHighFrequency() {
        customFilter = { action in
            let desc = String(describing: action)
            // These fire many times per second
            if desc.contains("positionUpdated") { return false }
            if desc.contains("levelUpdated") { return false }
            if desc.contains("beatPhaseUpdated") { return false }
            return true
        }
    }
}

// MARK: - State Diff (On-Demand Only)

/// Compute state diff - call this only when user expands a log entry
/// This is expensive, so we don't do it automatically
public func computeStateDiff<State>(_ old: State, _ new: State) -> [String] where State: Equatable {
    guard old != new else { return [] }

    var diffs: [String] = []
    let oldMirror = Mirror(reflecting: old)
    let newMirror = Mirror(reflecting: new)

    var oldChildren: [String: Any] = [:]
    var newChildren: [String: Any] = [:]

    for child in oldMirror.children {
        if let label = child.label { oldChildren[label] = child.value }
    }
    for child in newMirror.children {
        if let label = child.label { newChildren[label] = child.value }
    }

    for (label, oldValue) in oldChildren {
        guard let newValue = newChildren[label] else { continue }
        let oldStr = String(describing: oldValue).prefix(50)
        let newStr = String(describing: newValue).prefix(50)
        if oldStr != newStr {
            diffs.append("\(label): \(oldStr) → \(newStr)")
        }
    }

    return diffs
}
