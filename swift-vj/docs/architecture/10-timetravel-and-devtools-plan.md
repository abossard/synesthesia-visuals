# Time Travel Debugging & DevTools Plan

## Current UDF Implementation Status

### What's Done (Store Infrastructure)

```
swift-vj/Sources/SwiftVJCore/Store/
├── Store.swift       ✓ Generic Store<State, Action> with effect execution
├── Effect.swift      ✓ Effect<Action> (.none, .run, .merge, .concatenate)
├── AppState.swift    ✓ Immutable state structs (Equatable, Sendable)
├── Actions.swift     ✓ Action enum hierarchy
├── Reducer.swift     ✓ Pure reducer functions
└── Effects/          ✓ Effect implementations for all domains
```

### What's NOT Done (Module Integration Gap)

The Store exists, but **modules still use callbacks instead of dispatching actions**:

| Module | Current Pattern | Needed Pattern |
|--------|-----------------|----------------|
| PlaybackModule | `onTrackChange` callback | `store.send(.playback(.trackChanged(track)))` |
| LyricsModule | `onActiveLine` callback | `store.send(.ui(.lyricsLineChanged(line)))` |
| PipelineModule | `onStepStart/Complete` callbacks | `store.send(.pipeline(.stepStarted(name)))` |
| LaunchpadModule | `onConnectionChange` callback | `store.send(.launchpad(.connected(device)))` |

**SwiftVJApp.swift** creates a Store but doesn't use it - it still wires up callbacks manually.

---

## Part 1: Time Travel Debugging

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    TimeTravel Store                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐    ┌──────────────────────────────────┐   │
│  │   History   │    │         Store<State,Action>      │   │
│  │   Buffer    │◄───│                                  │   │
│  │             │    │  state ──► @Published            │   │
│  │  [S0,A0]    │    │                                  │   │
│  │  [S1,A1]    │    └──────────────────────────────────┘   │
│  │  [S2,A2]    │                    │                      │
│  │  [S3,A3] ◄──┼────────────────────┘ (record on send)     │
│  │    ...      │                                           │
│  │  [Sn,An]    │                                           │
│  └─────────────┘                                           │
│         │                                                   │
│         ▼                                                   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Time Travel Controls                    │   │
│  │  ◄◄  ◄   ▶   ►►   │ Step 42/100 │  [Export JSON]   │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Implementation: TimeTravelStore.swift

```swift
// TimeTravelStore.swift - Store wrapper with history recording

import Foundation

/// A state-action pair for history
public struct StateSnapshot<State, Action>: Identifiable {
    public let id: UUID
    public let state: State
    public let action: Action?  // nil for initial state
    public let timestamp: Date
    public let effectDescription: String?

    public init(state: State, action: Action?, effectDescription: String? = nil) {
        self.id = UUID()
        self.state = state
        self.action = action
        self.timestamp = Date()
        self.effectDescription = effectDescription
    }
}

/// Time travel enabled store
@MainActor
public final class TimeTravelStore<State: Equatable, Action>: ObservableObject {

    // MARK: - Published State

    @Published public private(set) var state: State
    @Published public private(set) var history: [StateSnapshot<State, Action>] = []
    @Published public private(set) var currentIndex: Int = 0
    @Published public var isTimeTraveling: Bool = false
    @Published public var isRecording: Bool = true

    // MARK: - Configuration

    public var maxHistorySize: Int = 1000
    public var actionFilter: ((Action) -> Bool)?  // Filter high-frequency actions

    // MARK: - Private

    private let reducer: (inout State, Action) -> Effect<Action>
    private var effectTasks: [UUID: Task<Void, Never>] = [:]
    private var effectCancellables: [AnyHashable: UUID] = [:]

    // MARK: - Init

    public init(
        initialState: State,
        reducer: @escaping (inout State, Action) -> Effect<Action>
    ) {
        self.state = initialState
        self.reducer = reducer

        // Record initial state
        let snapshot = StateSnapshot<State, Action>(state: initialState, action: nil)
        history.append(snapshot)
    }

    // MARK: - Public API

    /// Send an action (records to history if recording)
    public func send(_ action: Action) {
        // If time traveling, jump back to present first
        if isTimeTraveling {
            jumpToPresent()
        }

        let effect = reducer(&state, action)

        // Record to history
        if isRecording && shouldRecord(action) {
            recordSnapshot(state: state, action: action)
        }

        executeEffect(effect)
    }

    // MARK: - Time Travel Controls

    /// Jump to a specific point in history
    public func jumpTo(index: Int) {
        guard index >= 0 && index < history.count else { return }
        isTimeTraveling = true
        currentIndex = index
        state = history[index].state
    }

    /// Step backward one action
    public func stepBack() {
        jumpTo(index: currentIndex - 1)
    }

    /// Step forward one action
    public func stepForward() {
        jumpTo(index: currentIndex + 1)
    }

    /// Jump to the beginning
    public func jumpToStart() {
        jumpTo(index: 0)
    }

    /// Jump to the present (most recent state)
    public func jumpToPresent() {
        isTimeTraveling = false
        currentIndex = history.count - 1
        state = history[currentIndex].state
    }

    /// Clear history (keeps current state as new initial)
    public func clearHistory() {
        let current = StateSnapshot<State, Action>(state: state, action: nil)
        history = [current]
        currentIndex = 0
        isTimeTraveling = false
    }

    /// Fork from current time travel position (discard future)
    public func forkFromCurrent() {
        guard isTimeTraveling else { return }
        history = Array(history.prefix(currentIndex + 1))
        isTimeTraveling = false
    }

    // MARK: - Export

    /// Export history as JSON (requires Codable conformance)
    public func exportHistory() -> Data? where State: Codable, Action: Codable {
        let exportable = history.map { snapshot in
            ExportableSnapshot(
                state: snapshot.state,
                action: snapshot.action,
                timestamp: snapshot.timestamp
            )
        }
        return try? JSONEncoder().encode(exportable)
    }

    /// Import history from JSON
    public func importHistory(from data: Data) throws where State: Codable, Action: Codable {
        let snapshots: [ExportableSnapshot<State, Action>] = try JSONDecoder().decode([ExportableSnapshot].self, from: data)
        history = snapshots.map { StateSnapshot(state: $0.state, action: $0.action) }
        currentIndex = history.count - 1
        state = history[currentIndex].state
    }

    // MARK: - Private

    private func shouldRecord(_ action: Action) -> Bool {
        if let filter = actionFilter {
            return filter(action)
        }
        return true
    }

    private func recordSnapshot(state: State, action: Action) {
        let snapshot = StateSnapshot(state: state, action: action)
        history.append(snapshot)
        currentIndex = history.count - 1

        // Trim if over limit
        if history.count > maxHistorySize {
            history.removeFirst(history.count - maxHistorySize)
            currentIndex = history.count - 1
        }
    }

    // ... effect execution same as Store.swift ...
}

struct ExportableSnapshot<State: Codable, Action: Codable>: Codable {
    let state: State
    let action: Action?
    let timestamp: Date
}
```

### Time Travel UI Component

```swift
// TimeTravelControlsView.swift

import SwiftUI

struct TimeTravelControlsView<State: Equatable, Action>: View {
    @ObservedObject var store: TimeTravelStore<State, Action>

    var body: some View {
        VStack(spacing: 8) {
            // Timeline scrubber
            Slider(
                value: Binding(
                    get: { Double(store.currentIndex) },
                    set: { store.jumpTo(index: Int($0)) }
                ),
                in: 0...Double(max(0, store.history.count - 1)),
                step: 1
            )
            .disabled(store.history.count <= 1)

            HStack(spacing: 16) {
                // Controls
                Button(action: store.jumpToStart) {
                    Image(systemName: "backward.end.fill")
                }
                .disabled(store.currentIndex == 0)

                Button(action: store.stepBack) {
                    Image(systemName: "backward.frame.fill")
                }
                .disabled(store.currentIndex == 0)

                Button(action: store.stepForward) {
                    Image(systemName: "forward.frame.fill")
                }
                .disabled(store.currentIndex >= store.history.count - 1)

                Button(action: store.jumpToPresent) {
                    Image(systemName: "forward.end.fill")
                }
                .disabled(!store.isTimeTraveling)

                Spacer()

                // Status
                Text("\(store.currentIndex + 1) / \(store.history.count)")
                    .font(.caption.monospacedDigit())

                // Recording toggle
                Toggle("Record", isOn: $store.isRecording)
                    .toggleStyle(.switch)
                    .labelsHidden()

                Image(systemName: store.isRecording ? "record.circle" : "record.circle.fill")
                    .foregroundColor(store.isRecording ? .red : .gray)
            }

            if store.isTimeTraveling {
                HStack {
                    Text("TIME TRAVELING")
                        .font(.caption.bold())
                        .foregroundColor(.orange)

                    Spacer()

                    Button("Fork Here") {
                        store.forkFromCurrent()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
}
```

---

## Part 2: State Inspector / DevTools

### Architecture

```
┌───────────────────────────────────────────────────────────────────────┐
│                         DevTools Window                                │
├───────────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │
│  │   State     │  │   Actions   │  │  Effects    │  │   Export    │  │
│  │  Inspector  │  │    Log      │  │   Monitor   │  │             │  │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘  │
├───────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  STATE TREE                                                     │  │
│  │  ▼ AppState                                                     │  │
│  │    ▼ playback                                                   │  │
│  │      • currentTrack: Track?                                     │  │
│  │        └─ artist: "Daft Punk"                                   │  │
│  │        └─ title: "Around the World"                             │  │
│  │      • position: 142.5                                          │  │
│  │      • isPlaying: true                                          │  │
│  │    ▶ pipeline (collapsed)                                       │  │
│  │    ▼ render                                                     │  │
│  │      • selectedShader: "cosmic_flow"                            │  │
│  │      • currentPhase: .drop                                      │  │
│  │    ▶ launchpad                                                  │  │
│  │    ▶ audio                                                      │  │
│  │    ▶ ui                                                         │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                       │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  ACTION LOG                                     [Filter: ___]  │  │
│  │  ──────────────────────────────────────────────────────────────│  │
│  │  12:34:56.123  playback.trackChanged(Track(...))               │  │
│  │  12:34:56.124  pipeline.started("Around the World")            │  │
│  │  12:34:56.200  pipeline.stepCompleted("lyrics")                │  │
│  │  12:34:56.850  pipeline.stepCompleted("ai")                    │  │
│  │  12:34:57.100  render.shaderSelected("cosmic_flow")            │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘
```

### Implementation: StateInspector.swift

```swift
// StateInspector.swift - Generic state reflection and display

import Foundation

/// A node in the state tree for display
public struct StateTreeNode: Identifiable {
    public let id: UUID
    public let label: String
    public let value: String?
    public let type: String
    public let children: [StateTreeNode]
    public let isExpandable: Bool

    public init(
        label: String,
        value: String? = nil,
        type: String = "",
        children: [StateTreeNode] = []
    ) {
        self.id = UUID()
        self.label = label
        self.value = value
        self.type = type
        self.children = children
        self.isExpandable = !children.isEmpty
    }
}

/// Protocol for states that can be inspected
public protocol Inspectable {
    func toTreeNode(label: String) -> StateTreeNode
}

/// Default implementation using Mirror
extension Inspectable {
    public func toTreeNode(label: String) -> StateTreeNode {
        let mirror = Mirror(reflecting: self)
        let typeName = String(describing: type(of: self))

        let children = mirror.children.compactMap { child -> StateTreeNode? in
            guard let childLabel = child.label else { return nil }
            return inspectValue(child.value, label: childLabel)
        }

        return StateTreeNode(
            label: label,
            type: typeName,
            children: children
        )
    }
}

/// Inspect any value using reflection
public func inspectValue(_ value: Any, label: String) -> StateTreeNode {
    let mirror = Mirror(reflecting: value)
    let typeName = String(describing: type(of: value))

    // Handle optionals
    if mirror.displayStyle == .optional {
        if let child = mirror.children.first {
            return inspectValue(child.value, label: label)
        } else {
            return StateTreeNode(label: label, value: "nil", type: "\(typeName)")
        }
    }

    // Handle primitives
    if mirror.children.isEmpty {
        return StateTreeNode(label: label, value: String(describing: value), type: typeName)
    }

    // Handle collections
    if mirror.displayStyle == .collection || mirror.displayStyle == .set {
        let children = mirror.children.enumerated().map { index, child in
            inspectValue(child.value, label: "[\(index)]")
        }
        return StateTreeNode(
            label: label,
            value: "(\(children.count) items)",
            type: typeName,
            children: children
        )
    }

    // Handle dictionaries
    if mirror.displayStyle == .dictionary {
        let children = mirror.children.map { child in
            if let (key, val) = child.value as? (AnyHashable, Any) {
                return inspectValue(val, label: String(describing: key))
            }
            return inspectValue(child.value, label: child.label ?? "?")
        }
        return StateTreeNode(
            label: label,
            value: "(\(children.count) entries)",
            type: typeName,
            children: children
        )
    }

    // Handle structs/classes
    let children = mirror.children.compactMap { child -> StateTreeNode? in
        guard let childLabel = child.label else { return nil }
        return inspectValue(child.value, label: childLabel)
    }

    return StateTreeNode(
        label: label,
        type: typeName,
        children: children
    )
}

/// Action logger with filtering
@MainActor
public final class ActionLogger<Action>: ObservableObject {

    public struct LogEntry: Identifiable {
        public let id: UUID
        public let timestamp: Date
        public let action: Action
        public let description: String
        public let stateDiff: String?

        public init(action: Action, description: String, stateDiff: String? = nil) {
            self.id = UUID()
            self.timestamp = Date()
            self.action = action
            self.description = description
            self.stateDiff = stateDiff
        }
    }

    @Published public var entries: [LogEntry] = []
    @Published public var filter: String = ""
    @Published public var isEnabled: Bool = true

    public var maxEntries: Int = 500

    public var filteredEntries: [LogEntry] {
        guard !filter.isEmpty else { return entries }
        return entries.filter { $0.description.localizedCaseInsensitiveContains(filter) }
    }

    public func log(_ action: Action, stateDiff: String? = nil) {
        guard isEnabled else { return }

        let description = String(describing: action)
        let entry = LogEntry(action: action, description: description, stateDiff: stateDiff)
        entries.append(entry)

        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    public func clear() {
        entries.removeAll()
    }
}
```

### DevTools Window View

```swift
// DevToolsView.swift

import SwiftUI

struct DevToolsView<State: Equatable, Action>: View {
    @ObservedObject var store: TimeTravelStore<State, Action>
    @ObservedObject var actionLogger: ActionLogger<Action>
    @State private var selectedTab: DevToolsTab = .state

    enum DevToolsTab: String, CaseIterable {
        case state = "State"
        case actions = "Actions"
        case timeTravel = "Time Travel"
        case export = "Export"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            Picker("Tab", selection: $selectedTab) {
                ForEach(DevToolsTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            // Content
            switch selectedTab {
            case .state:
                StateTreeView(state: store.state)
            case .actions:
                ActionLogView(logger: actionLogger)
            case .timeTravel:
                TimeTravelView(store: store)
            case .export:
                ExportView(store: store)
            }
        }
        .frame(minWidth: 400, minHeight: 500)
    }
}

struct StateTreeView<State>: View {
    let state: State
    @State private var expandedNodes: Set<UUID> = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                let root = inspectValue(state, label: "AppState")
                TreeNodeView(node: root, expandedNodes: $expandedNodes, depth: 0)
            }
            .padding()
        }
    }
}

struct TreeNodeView: View {
    let node: StateTreeNode
    @Binding var expandedNodes: Set<UUID>
    let depth: Int

    var isExpanded: Bool {
        expandedNodes.contains(node.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                // Indentation
                ForEach(0..<depth, id: \.self) { _ in
                    Rectangle()
                        .fill(.clear)
                        .frame(width: 16)
                }

                // Expand/collapse
                if node.isExpandable {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .frame(width: 12)
                        .foregroundColor(.secondary)
                        .onTapGesture {
                            if isExpanded {
                                expandedNodes.remove(node.id)
                            } else {
                                expandedNodes.insert(node.id)
                            }
                        }
                } else {
                    Spacer().frame(width: 12)
                }

                // Label
                Text(node.label)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                // Type
                if !node.type.isEmpty {
                    Text(node.type)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Value
                if let value = node.value {
                    Text(value)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.blue)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .onTapGesture {
                if node.isExpandable {
                    if isExpanded {
                        expandedNodes.remove(node.id)
                    } else {
                        expandedNodes.insert(node.id)
                    }
                }
            }

            // Children
            if isExpanded {
                ForEach(node.children) { child in
                    TreeNodeView(node: child, expandedNodes: $expandedNodes, depth: depth + 1)
                }
            }
        }
    }
}

struct ActionLogView<Action>: View {
    @ObservedObject var logger: ActionLogger<Action>

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Filter actions...", text: $logger.filter)
                    .textFieldStyle(.plain)

                Toggle("Logging", isOn: $logger.isEnabled)
                    .toggleStyle(.switch)

                Button("Clear") {
                    logger.clear()
                }
            }
            .padding()

            Divider()

            // Log entries
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(logger.filteredEntries) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(dateFormatter.string(from: entry.timestamp))
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)

                                Text(entry.description)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(nil)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 2)
                            .id(entry.id)
                        }
                    }
                }
                .onChange(of: logger.entries.count) { _ in
                    if let last = logger.entries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}
```

---

## Part 3: Integration with Current Store

### Adding DevTools to Existing Store

```swift
// StoreWithDevTools.swift - Factory for creating instrumented stores

import Foundation

public enum StoreFactory {

    /// Create a store without dev tools (production)
    public static func create<State: Equatable, Action>(
        initialState: State,
        reducer: @escaping (inout State, Action) -> Effect<Action>
    ) -> Store<State, Action> {
        Store(initialState: initialState, reducer: reducer)
    }

    /// Create a store with time travel and logging (development)
    @MainActor
    public static func createWithDevTools<State: Equatable, Action>(
        initialState: State,
        reducer: @escaping (inout State, Action) -> Effect<Action>,
        actionFilter: ((Action) -> Bool)? = nil
    ) -> (store: TimeTravelStore<State, Action>, logger: ActionLogger<Action>) {

        let logger = ActionLogger<Action>()

        // Wrap reducer to log actions
        let loggingReducer: (inout State, Action) -> Effect<Action> = { state, action in
            let oldState = state
            let effect = reducer(&state, action)

            // Log with state diff
            let diff = stateDiff(old: oldState, new: state)
            logger.log(action, stateDiff: diff)

            return effect
        }

        let store = TimeTravelStore(
            initialState: initialState,
            reducer: loggingReducer
        )
        store.actionFilter = actionFilter

        return (store, logger)
    }

    /// Compute a simple state diff description
    private static func stateDiff<State>(old: State, new: State) -> String? {
        // Simple implementation - could be enhanced with Mirror
        let oldDesc = String(describing: old)
        let newDesc = String(describing: new)
        return oldDesc == newDesc ? nil : "State changed"
    }
}
```

### Usage in SwiftVJApp

```swift
// In SwiftVJApp.swift

#if DEBUG
// Development mode with devtools
let (store, actionLogger) = StoreFactory.createWithDevTools(
    initialState: SwiftVJCore.AppState(),
    reducer: appReducer,
    actionFilter: { action in
        // Filter out high-frequency audio updates
        if case .audio(.levelUpdated) = action { return false }
        if case .audio(.beatPhaseUpdated) = action { return false }
        return true
    }
)
#else
// Production mode
let store = StoreFactory.create(
    initialState: SwiftVJCore.AppState(),
    reducer: appReducer
)
#endif
```

---

## Part 4: What's Needed to Complete Full Integration

### Phase 1: Module Refactoring (Required First)

Before time travel will work properly, modules need to dispatch actions:

```swift
// BEFORE (current PlaybackModule)
private func fireTrackChange(_ track: Track) async {
    for callback in trackChangeCallbacks {
        await callback(track)
    }
}

// AFTER (Store-integrated)
private func fireTrackChange(_ track: Track) async {
    await store?.send(.playback(.trackChanged(track)))
}
```

**Files to modify:**
- [ ] `PlaybackModule.swift` - Replace callbacks with store dispatch
- [ ] `LyricsModule.swift` - Replace callbacks with store dispatch
- [ ] `PipelineModule.swift` - Replace callbacks with store dispatch
- [ ] `LaunchpadModule.swift` - Replace callbacks with store dispatch
- [ ] `SwiftVJApp.swift` - Remove callback wiring, use store observation

### Phase 2: E2E Tests Update

Update E2E tests to use Store:

```swift
// BEFORE
await monitor.onTrackChange { track in
    // test assertion
}

// AFTER
let store = TestStore(initialState: AppState(), reducer: appReducer)
store.send(.playback(.trackChanged(mockTrack)))
XCTAssertEqual(store.state.playback.currentTrack, mockTrack)
```

### Phase 3: DevTools Files to Create

- [ ] `TimeTravelStore.swift` - Store with history
- [ ] `StateInspector.swift` - State tree reflection
- [ ] `ActionLogger.swift` - Action logging
- [ ] `DevToolsView.swift` - DevTools window
- [ ] `TimeTravelControlsView.swift` - Time travel UI
- [ ] `StateTreeView.swift` - State tree UI

---

## Summary: Effort Estimate

| Task | Complexity | Files |
|------|------------|-------|
| Module Store Integration | Medium | 4 files |
| TimeTravelStore | Low | 1 file (~200 lines) |
| StateInspector | Low | 1 file (~150 lines) |
| DevTools UI | Medium | 3 files (~400 lines) |
| E2E Test Updates | Medium | 4 test files |
| **Total** | | ~10 files, ~1000 lines |

The Store infrastructure is solid. The main work is:
1. **Module integration** - Make modules dispatch actions instead of callbacks
2. **DevTools** - Add time travel and state inspection

Both are additive and won't break existing functionality.
