// StoreLogger.swift - Action logging and state change insights
// Lightweight observability for unidirectional data flow debugging

import Foundation

// MARK: - State Diff

/// Represents a change in state
public struct StateDiff: CustomStringConvertible, Sendable {
    public let path: String
    public let oldValue: String
    public let newValue: String

    public var description: String {
        "\(path): \(oldValue) → \(newValue)"
    }
}

/// Compute differences between two states using Mirror reflection
public func computeStateDiff<State>(_ old: State, _ new: State, path: String = "") -> [StateDiff] {
    var diffs: [StateDiff] = []

    let oldMirror = Mirror(reflecting: old)
    let newMirror = Mirror(reflecting: new)

    // Build dictionaries for comparison
    var oldChildren: [String: Any] = [:]
    var newChildren: [String: Any] = [:]

    for child in oldMirror.children {
        if let label = child.label {
            oldChildren[label] = child.value
        }
    }

    for child in newMirror.children {
        if let label = child.label {
            newChildren[label] = child.value
        }
    }

    // Compare each property
    for (label, oldValue) in oldChildren {
        let currentPath = path.isEmpty ? label : "\(path).\(label)"

        guard let newValue = newChildren[label] else {
            diffs.append(StateDiff(path: currentPath, oldValue: describe(oldValue), newValue: "nil"))
            continue
        }

        let oldDesc = describe(oldValue)
        let newDesc = describe(newValue)

        if oldDesc != newDesc {
            // Check if we should recurse into nested structs
            let oldMirror = Mirror(reflecting: oldValue)
            let newMirror = Mirror(reflecting: newValue)

            if oldMirror.displayStyle == .struct && !oldMirror.children.isEmpty {
                // Recurse into struct
                let nestedDiffs = computeStateDiff(oldValue, newValue, path: currentPath)
                diffs.append(contentsOf: nestedDiffs)
            } else {
                diffs.append(StateDiff(path: currentPath, oldValue: oldDesc, newValue: newDesc))
            }
        }
    }

    return diffs
}

/// Describe a value concisely
private func describe(_ value: Any) -> String {
    let mirror = Mirror(reflecting: value)

    // Handle optionals
    if mirror.displayStyle == .optional {
        if let child = mirror.children.first {
            return describe(child.value)
        }
        return "nil"
    }

    // Handle collections
    if mirror.displayStyle == .collection {
        return "[\(mirror.children.count) items]"
    }

    if mirror.displayStyle == .dictionary {
        return "{\(mirror.children.count) entries}"
    }

    // Handle primitives and simple types
    let desc = String(describing: value)
    if desc.count > 50 {
        return String(desc.prefix(47)) + "..."
    }
    return desc
}

// MARK: - Action Log Entry

/// A logged action with timestamp and state diff
public struct ActionLogEntry: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let action: String
    public let diffs: [StateDiff]
    public let duration: TimeInterval?

    public init(action: String, diffs: [StateDiff], duration: TimeInterval? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.action = action
        self.diffs = diffs
        self.duration = duration
    }

    /// Formatted log output
    public var formatted: String {
        let df = Self.dateFormatter
        var lines = ["\(df.string(from: timestamp)) ▶ \(action)"]

        if let duration = duration {
            lines[0] += " (\(String(format: "%.1f", duration * 1000))ms)"
        }

        for diff in diffs {
            lines.append("  ├─ \(diff)")
        }

        return lines.joined(separator: "\n")
    }

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()
}

// MARK: - Store Logger

/// Logger that wraps a reducer to log actions and state changes
@MainActor
public final class StoreLogger<State, Action>: ObservableObject {

    // MARK: - Published

    @Published public private(set) var entries: [ActionLogEntry] = []
    @Published public var isEnabled: Bool = true
    @Published public var filter: String = ""

    // MARK: - Configuration

    public var maxEntries: Int = 500
    public var actionFilter: ((Action) -> Bool)?
    public var printToConsole: Bool = true

    // MARK: - Computed

    public var filteredEntries: [ActionLogEntry] {
        guard !filter.isEmpty else { return entries }
        return entries.filter { $0.action.localizedCaseInsensitiveContains(filter) }
    }

    // MARK: - Public API

    /// Log an action and its state changes
    public func log(action: Action, oldState: State, newState: State, duration: TimeInterval? = nil) {
        guard isEnabled else { return }

        // Check filter
        if let filter = actionFilter, !filter(action) {
            return
        }

        let actionDesc = String(describing: action)
        let diffs = computeStateDiff(oldState, newState)

        let entry = ActionLogEntry(action: actionDesc, diffs: diffs, duration: duration)
        entries.append(entry)

        // Trim if needed
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }

        // Console output
        if printToConsole {
            print(entry.formatted)
        }
    }

    /// Clear all entries
    public func clear() {
        entries.removeAll()
    }

    /// Create a logging reducer wrapper
    public func wrap(
        reducer: @escaping (inout State, Action) -> Effect<Action>
    ) -> (inout State, Action) -> Effect<Action> {
        return { [weak self] state, action in
            let oldState = state
            let start = Date()

            let effect = reducer(&state, action)

            let duration = Date().timeIntervalSince(start)
            self?.log(action: action, oldState: oldState, newState: state, duration: duration)

            return effect
        }
    }
}

// MARK: - Convenience Extensions

extension StoreLogger {
    /// Filter out high-frequency actions (audio updates, position updates)
    public func filterHighFrequency() {
        actionFilter = { action in
            let desc = String(describing: action)
            let highFreq = ["levelUpdated", "beatPhaseUpdated", "positionUpdated"]
            return !highFreq.contains { desc.contains($0) }
        }
    }
}

// MARK: - Store Extension for Logging

extension Store {
    /// Create a store with logging enabled
    @MainActor
    public static func withLogging(
        initialState: State,
        reducer: @escaping (inout State, Action) -> Effect<Action>,
        logger: StoreLogger<State, Action>
    ) -> Store<State, Action> {
        Store(
            initialState: initialState,
            reducer: logger.wrap(reducer: reducer)
        )
    }
}
