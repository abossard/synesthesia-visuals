# Unidirectional Data Flow Refactoring Plan

## Executive Summary

This plan outlines the migration from callback-based state management to a unidirectional data flow architecture (TCA-like) for the Swift VJ application. The refactor enables:
- Single source of truth for application state
- Predictable state transitions via Actions → Reducer → New State
- Time-travel debugging capabilities
- Simplified testing through pure reducer functions
- Elimination of callback spaghetti

---

## 1. Current Architecture Analysis

### Current State Flow (Callback-Based)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        CURRENT: CALLBACK-BASED FLOW                         │
└─────────────────────────────────────────────────────────────────────────────┘

  ┌──────────┐     ┌─────────────┐     ┌──────────────────┐
  │ VDJ OSC  │────▶│   OSCHub    │────▶│  PlaybackModule  │
  └──────────┘     └─────────────┘     └────────┬─────────┘
                                                │ callback
                                                ▼
  ┌──────────┐     ┌─────────────┐     ┌──────────────────┐
  │ SwiftUI  │◀────│  AppState   │◀────│ onTrackChange{}  │
  │  Views   │     │ (@Published)│     └──────────────────┘
  └──────────┘     └──────┬──────┘
                          │ didSet
                          ▼
                   ┌─────────────┐     ┌──────────────────┐
                   │ UserDefaults│     │  RenderEngine    │
                   └─────────────┘     │ (state managers) │
                                       └──────────────────┘

  Problems:
  ├─ 7 callback types scattered across modules
  ├─ 47 @Published properties in AppState (mixed concerns)
  ├─ State duplicated in PlaybackModule, VDJMonitor, AppState
  ├─ Side effects in didSet observers
  └─ Hard to trace state flow for debugging
```

### Current State Representations

| Location | Type | Properties | Issue |
|----------|------|------------|-------|
| `AppState` | @Published | 47 properties | Mixed UI + domain state |
| `PlaybackModule` | Private vars | currentState, callbacks[] | Duplicate of AppState |
| `PipelineModule` | Private vars | isProcessing, resultCache | Internal state hidden |
| `VDJMonitor` | Actor state | deck1State, deck2State | Duplicate track info |
| `RenderEngine` | @Published | 5 state managers | Separate from AppState |
| `UserDefaults` | Persisted | shader, phase, source | Not centralized |

### Files With Callback Registrations

| File | Callbacks |
|------|-----------|
| `SwiftVJApp.swift:389-456` | onTrackChange, onPositionUpdate, onStepStart, onStepComplete |
| `SwiftVJApp.swift:327-339` | onConnectionChange, onStateChange (Launchpad) |
| `SwiftVJApp.swift:193-255` | oscHub.subscribe (6 patterns) |
| `Module.swift:1-89` | Callback typealias definitions |

---

## 2. Target Architecture

### Unidirectional Data Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    TARGET: UNIDIRECTIONAL DATA FLOW                         │
└─────────────────────────────────────────────────────────────────────────────┘

                              ┌─────────────────┐
                              │    AppStore     │
                              │  (single actor) │
                              └────────┬────────┘
                                       │
              ┌────────────────────────┼────────────────────────┐
              │                        │                        │
              ▼                        ▼                        ▼
       ┌─────────────┐          ┌─────────────┐          ┌─────────────┐
       │   Actions   │          │   State     │          │   Effects   │
       │  (enum)     │          │ (immutable) │          │  (async)    │
       └──────┬──────┘          └──────┬──────┘          └──────┬──────┘
              │                        │                        │
              │    ┌───────────────────┘                        │
              │    │                                            │
              ▼    ▼                                            ▼
       ┌────────────────┐                               ┌─────────────┐
       │    Reducer     │                               │  Side Effect│
       │ (pure function)│◀──────────────────────────────│  Publishers │
       └───────┬────────┘                               └─────────────┘
               │ new state
               ▼
       ┌─────────────┐      ┌─────────────┐      ┌─────────────┐
       │   SwiftUI   │      │ RenderEngine│      │ Persistence │
       │   Views     │      │  Subscriber │      │  Subscriber │
       └─────────────┘      └─────────────┘      └─────────────┘

  Benefits:
  ├─ Single immutable AppState snapshot
  ├─ Pure reducer functions (testable)
  ├─ Actions are serializable (time-travel)
  ├─ Side effects isolated in Effect system
  └─ Clear unidirectional flow (easy debugging)
```

### State Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           AppState (Immutable Struct)                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐ │
│  │   PlaybackState     │  │   PipelineState     │  │    RenderState      │ │
│  ├─────────────────────┤  ├─────────────────────┤  ├─────────────────────┤ │
│  │ • currentTrack      │  │ • steps: [Step]     │  │ • selectedShader    │ │
│  │ • position          │  │ • result            │  │ • currentPhase      │ │
│  │ • isPlaying         │  │ • isProcessing      │  │ • imageIndex        │ │
│  │ • source            │  │ • error             │  │ • imageCount        │ │
│  └─────────────────────┘  └─────────────────────┘  └─────────────────────┘ │
│                                                                             │
│  ┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐ │
│  │  LaunchpadState     │  │     AudioState      │  │      UIState        │ │
│  ├─────────────────────┤  ├─────────────────────┤  ├─────────────────────┤ │
│  │ • isConnected       │  │ • level             │  │ • logEntries        │ │
│  │ • deviceName        │  │ • beatPhase         │  │ • oscMessages       │ │
│  │ • currentBank       │  │ • bpm               │  │ • selectedTab       │ │
│  │ • controllerState   │  │ • energy            │  │ • isSettingsOpen    │ │
│  └─────────────────────┘  └─────────────────────┘  └─────────────────────┘ │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Action Hierarchy

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           AppAction (enum)                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  AppAction                                                                  │
│  ├── .playback(PlaybackAction)                                             │
│  │   ├── .trackChanged(Track)                                              │
│  │   ├── .positionUpdated(Double, Bool)                                    │
│  │   ├── .sourceChanged(String)                                            │
│  │   └── .playingStateChanged(Bool)                                        │
│  │                                                                          │
│  ├── .pipeline(PipelineAction)                                             │
│  │   ├── .startProcessing(Track)                                           │
│  │   ├── .stepStarted(String)                                              │
│  │   ├── .stepCompleted(String, StepStatus)                                │
│  │   ├── .processingCompleted(PipelineResult)                              │
│  │   └── .processingFailed(Error)                                          │
│  │                                                                          │
│  ├── .render(RenderAction)                                                 │
│  │   ├── .selectShader(String)                                             │
│  │   ├── .selectPhase(Phase)                                               │
│  │   ├── .setImageIndex(Int)                                               │
│  │   └── .advanceImage                                                     │
│  │                                                                          │
│  ├── .launchpad(LaunchpadAction)                                           │
│  │   ├── .connected(String)                                                │
│  │   ├── .disconnected                                                     │
│  │   ├── .buttonPressed(Int, Int)                                          │
│  │   └── .stateUpdated(ControllerState)                                    │
│  │                                                                          │
│  ├── .audio(AudioAction)                                                   │
│  │   └── .stateUpdated(AudioState)                                         │
│  │                                                                          │
│  └── .ui(UIAction)                                                         │
│      ├── .log(String, LogLevel)                                            │
│      ├── .oscMessageReceived(String, OSCLogEntry)                          │
│      └── .clearLogs                                                        │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Effect System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Effect System                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    Effect<Action> (struct)                          │   │
│  ├─────────────────────────────────────────────────────────────────────┤   │
│  │ • none: Effect<Action>      - No side effect                        │   │
│  │ • run: (Send) async -> Void - Async operation returning actions     │   │
│  │ • merge([Effect])           - Combine multiple effects              │   │
│  │ • cancel(id)                - Cancel running effect                 │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  Effect Producers (replace callbacks):                                     │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐            │
│  │ OSCEffects      │  │ PipelineEffects │  │ LaunchpadEffects│            │
│  ├─────────────────┤  ├─────────────────┤  ├─────────────────┤            │
│  │ • subscribe()   │  │ • process(track)│  │ • connect()     │            │
│  │ • send(addr,val)│  │ • fetchLyrics() │  │ • handleButton()│            │
│  │ • startServer() │  │ • fetchImages() │  │ • updateDisplay()│           │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Migration Strategy

### Phase Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         MIGRATION PHASES                                    │
└─────────────────────────────────────────────────────────────────────────────┘

  Phase 1: Foundation        Phase 2: Core Migration       Phase 3: Effects
  ┌─────────────────┐        ┌─────────────────────┐       ┌─────────────────┐
  │ • Create Store  │        │ • Migrate AppState  │       │ • OSC Effects   │
  │ • Define State  │   ──▶  │ • Replace Callbacks │  ──▶  │ • Pipeline FX   │
  │ • Define Actions│        │ • Update Views      │       │ • Launchpad FX  │
  │ • Create Reducer│        │ • Adapt RenderEngine│       │ • Persistence   │
  └─────────────────┘        └─────────────────────┘       └─────────────────┘
          │                           │                            │
          ▼                           ▼                            ▼
  Phase 4: Testing           Phase 5: Cleanup             Phase 6: Polish
  ┌─────────────────┐        ┌─────────────────────┐       ┌─────────────────┐
  │ • Reducer Tests │        │ • Remove old code   │       │ • Time-travel   │
  │ • Effect Tests  │   ──▶  │ • Remove callbacks  │  ──▶  │ • Debug tools   │
  │ • Integration   │        │ • Update docs       │       │ • Performance   │
  └─────────────────┘        └─────────────────────┘       └─────────────────┘
```

---

## 4. Detailed Implementation Plan

### Phase 1: Foundation Layer

#### 1.1 Create Store Infrastructure

- [ ] **Create `Sources/SwiftVJCore/Store/Store.swift`**
  - Generic `Store<State, Action>` actor
  - Thread-safe state access via `@MainActor`
  - `send(_ action: Action)` method
  - `subscribe(_ handler: (State) -> Void)` for observers
  - Async effect execution with cancellation support

- [ ] **Create `Sources/SwiftVJCore/Store/Effect.swift`**
  - `Effect<Action>` struct with `none`, `run`, `merge`, `cancel`
  - `Send` typealias for action dispatch closure
  - Effect ID system for cancellation
  - Combine/AsyncSequence integration for subscriptions

#### 1.2 Define Immutable State Types

- [ ] **Create `Sources/SwiftVJCore/Store/AppState.swift`**
  - Root `AppState` struct (immutable)
  - Nested state structs:
    - `PlaybackState` (track, position, isPlaying, source)
    - `PipelineState` (steps, result, isProcessing, error)
    - `RenderState` (selectedShader, currentPhase, imageIndex, imageCount)
    - `LaunchpadState` (isConnected, deviceName, currentBank, controllerState)
    - `AudioState` (already exists in `Domain/Types.swift`)
    - `UIState` (logEntries, oscMessages, selectedTab)
  - Equatable conformance for change detection
  - Default initializer with sensible defaults

#### 1.3 Define Action Types

- [ ] **Create `Sources/SwiftVJCore/Store/Actions.swift`**
  - Root `AppAction` enum
  - Child action enums:
    - `PlaybackAction` (trackChanged, positionUpdated, sourceChanged, playingStateChanged)
    - `PipelineAction` (startProcessing, stepStarted, stepCompleted, processingCompleted, processingFailed)
    - `RenderAction` (selectShader, selectPhase, setImageIndex, advanceImage)
    - `LaunchpadAction` (connected, disconnected, buttonPressed, stateUpdated)
    - `AudioAction` (stateUpdated)
    - `UIAction` (log, oscMessageReceived, clearLogs)

#### 1.4 Create Reducer

- [ ] **Create `Sources/SwiftVJCore/Store/Reducer.swift`**
  - Root `appReducer(state: inout AppState, action: AppAction) -> Effect<AppAction>`
  - Child reducers composed via `combine`:
    - `playbackReducer`
    - `pipelineReducer`
    - `renderReducer`
    - `launchpadReducer`
    - `audioReducer`
    - `uiReducer`
  - Pure functions (no side effects in reducers)
  - Return `Effect.none` for pure state updates
  - Return `Effect.run` for async operations

---

### Phase 2: Core State Migration

#### 2.1 Migrate AppState Properties

- [ ] **Update `SwiftVJApp.swift` - Remove @Published properties**
  - Replace 47 `@Published` properties with `Store<AppState, AppAction>`
  - Create computed properties that read from store.state
  - File: `Sources/SwiftVJApp/SwiftVJApp.swift:66-150`

- [ ] **Create `AppStore` singleton**
  - Initialize with `appReducer` and initial state
  - Load persisted state (shader, phase, source) from UserDefaults
  - Expose via `@EnvironmentObject` for SwiftUI

#### 2.2 Replace Callback Registrations with Effects

- [ ] **Replace PlaybackModule callbacks**
  - Current: `SwiftVJApp.swift:389-412` (onTrackChange, onPositionUpdate)
  - Create: `Sources/SwiftVJCore/Store/Effects/PlaybackEffects.swift`
  - Effect: `subscribeToPlayback() -> Effect<AppAction>` using AsyncStream
  - Dispatches: `.playback(.trackChanged)`, `.playback(.positionUpdated)`

- [ ] **Replace PipelineModule callbacks**
  - Current: `SwiftVJApp.swift:431-456` (onStepStart, onStepComplete)
  - Create: `Sources/SwiftVJCore/Store/Effects/PipelineEffects.swift`
  - Effect: `processTrack(_ track: Track) -> Effect<AppAction>`
  - Dispatches step progress and completion actions

- [ ] **Replace Launchpad callbacks**
  - Current: `SwiftVJApp.swift:327-339` (onConnectionChange, onStateChange)
  - Create: `Sources/SwiftVJCore/Store/Effects/LaunchpadEffects.swift`
  - Effect: `subscribeToLaunchpad() -> Effect<AppAction>`

- [ ] **Replace OSC subscriptions**
  - Current: `SwiftVJApp.swift:193-255` (6 subscribe patterns)
  - Create: `Sources/SwiftVJCore/Store/Effects/OSCEffects.swift`
  - Effect: `subscribeToOSC() -> Effect<AppAction>`
  - Route OSC messages to appropriate actions

#### 2.3 Update SwiftUI Views

- [ ] **Update `ContentView.swift`**
  - Inject `Store` via environment
  - Replace direct `appState.property` with `store.state.property`
  - Replace mutations with `store.send(.action)`
  - File: `Sources/SwiftVJApp/Views/ContentView.swift`

- [ ] **Update `ControlPanelView.swift`**
  - Replace binding to appState with store dispatch
  - File: `Sources/SwiftVJApp/Views/ControlPanelView.swift`

- [ ] **Update all other views in `Sources/SwiftVJApp/Views/`**
  - Systematic replacement of appState references

#### 2.4 Adapt RenderEngine

- [ ] **Create RenderEngine state subscriber**
  - Subscribe to store state changes
  - Update state managers when relevant state changes
  - File: `Sources/SwiftVJApp/Rendering/RenderEngine.swift`
  - Maintain nonisolated audio fast path (no changes needed)

- [ ] **Update StateManagers to receive state**
  - TextStateManager, ShaderStateManager, etc.
  - Change from @Published to method-based updates
  - File: `Sources/SwiftVJApp/Rendering/StateManagers.swift`

---

### Phase 3: Effect System Implementation

#### 3.1 OSC Effects

- [ ] **Create `OSCEffects.swift`**
  - `startOSCServer() -> Effect<AppAction>` - long-running subscription
  - `sendOSC(address:values:) -> Effect<AppAction>` - fire-and-forget
  - `subscribeToPattern(pattern:) -> Effect<AppAction>` - filtered subscription
  - Reference: Current OSCHub at `Sources/SwiftVJCore/Adapters/OSCClient.swift`

#### 3.2 Pipeline Effects

- [ ] **Create `PipelineEffects.swift`**
  - `processTrack(track:) -> Effect<AppAction>`
    - Dispatches `.pipeline(.stepStarted)` for each step
    - Dispatches `.pipeline(.stepCompleted)` with status
    - Dispatches `.pipeline(.processingCompleted)` on success
    - Dispatches `.pipeline(.processingFailed)` on error
  - Reference: Current PipelineModule at `Sources/SwiftVJCore/Modules/PipelineModule.swift`

#### 3.3 Launchpad Effects

- [ ] **Create `LaunchpadEffects.swift`**
  - `connectToLaunchpad() -> Effect<AppAction>` - device connection
  - `subscribeLaunchpadEvents() -> Effect<AppAction>` - button/state events
  - `sendToLaunchpad(command:) -> Effect<AppAction>` - LED updates
  - Reference: Current LaunchpadModule at `Sources/SwiftVJCore/Launchpad/LaunchpadModule.swift`

#### 3.4 Persistence Effects

- [ ] **Create `PersistenceEffects.swift`**
  - `loadPersistedState() -> Effect<AppAction>` - startup load
  - `persistState(state:) -> Effect<AppAction>` - debounced save
  - Migrate from didSet observers in AppState
  - Keys: selectedShader, currentPhase, playbackSource

#### 3.5 Audio Effects

- [ ] **Create `AudioEffects.swift`**
  - `subscribeToAudio() -> Effect<AppAction>`
  - Maintain nonisolated fast path for high-frequency updates
  - Batch updates to reduce action dispatch overhead
  - Reference: `Sources/SwiftVJCore/Adapters/SynesthesiaAudioProcessor.swift`

---

### Phase 4: Test Refactoring

#### 4.1 Create Reducer Tests

- [ ] **Create `Tests/BehaviorTests/ReducerTests/PlaybackReducerTests.swift`**
  - Test pure state transitions
  - Test effect generation
  - No async, no mocks needed (pure functions)

- [ ] **Create `Tests/BehaviorTests/ReducerTests/PipelineReducerTests.swift`**
  - Test step state transitions
  - Test error handling paths

- [ ] **Create `Tests/BehaviorTests/ReducerTests/RenderReducerTests.swift`**
  - Test shader selection
  - Test phase changes
  - Test image index updates

- [ ] **Create `Tests/BehaviorTests/ReducerTests/LaunchpadReducerTests.swift`**
  - Test connection state
  - Test button handling

- [ ] **Create `Tests/BehaviorTests/ReducerTests/UIReducerTests.swift`**
  - Test log entry management
  - Test OSC message display

#### 4.2 Create Effect Tests

- [ ] **Create `Tests/BehaviorTests/EffectTests/OSCEffectsTests.swift`**
  - Mock OSCHub dependency
  - Test action dispatch from OSC messages
  - Test send effect generation

- [ ] **Create `Tests/BehaviorTests/EffectTests/PipelineEffectsTests.swift`**
  - Mock module dependencies
  - Test action sequence for track processing
  - Test error handling

- [ ] **Create `Tests/BehaviorTests/EffectTests/LaunchpadEffectsTests.swift`**
  - Mock MIDI dependencies
  - Test connection actions
  - Test button event translation

#### 4.3 Update Existing Tests

- [ ] **Update `Tests/BehaviorTests/ModuleTests.swift`**
  - Modules still exist, just no longer have callbacks
  - Test modules return values, effects dispatch actions
  - Reference: Lines 1-200

- [ ] **Update `Tests/E2ETests/AppIntegrationTests.swift`**
  - Use Store for state verification
  - Send actions instead of calling methods
  - Assert state changes via store.state

- [ ] **Update `Tests/E2ETests/PlaybackE2ETests.swift`**
  - Test OSC effects dispatch correct actions
  - Verify state updates through store

#### 4.4 Create Store Integration Tests

- [ ] **Create `Tests/E2ETests/StoreIntegrationTests.swift`**
  - Full store with real reducer
  - Test complete action flows
  - Test effect execution and cancellation
  - Time-travel debugging verification

---

### Phase 5: Cleanup and Removal

#### 5.1 Remove Callback Infrastructure

- [ ] **Remove callback typedefs from `Module.swift`**
  - Delete: `TrackChangeCallback`, `PositionUpdateCallback`
  - Delete: `PipelineStepStartCallback`, `PipelineStepCompleteCallback`
  - File: `Sources/SwiftVJCore/Modules/Module.swift:1-89`

- [ ] **Remove callback arrays from modules**
  - PlaybackModule: Remove `trackChangeCallbacks`, `positionUpdateCallbacks`
  - PipelineModule: Remove `stepStartCallbacks`, `stepCompleteCallbacks`
  - LaunchpadModule: Remove `onConnectionChange`, `onStateChange`

- [ ] **Remove callback registration methods**
  - Delete: `onTrackChange(_ callback:)`, `onPositionUpdate(_ callback:)`
  - Delete: `onStepStart(_ callback:)`, `onStepComplete(_ callback:)`

#### 5.2 Remove Old AppState Code

- [ ] **Remove @Published properties from SwiftVJApp.swift**
  - Delete lines 66-150 (47 @Published properties)
  - Replace with single `store: Store<AppState, AppAction>`

- [ ] **Remove didSet observers**
  - Delete UserDefaults persistence in didSet
  - Delete RenderEngine updates in didSet

- [ ] **Remove callback registration code**
  - Delete lines 389-456 (module callbacks)
  - Delete lines 327-339 (Launchpad callbacks)
  - Delete lines 193-255 (OSC subscriptions)

#### 5.3 Clean Up Modules

- [ ] **Simplify PlaybackModule**
  - Remove internal state duplication
  - Return values directly, no callbacks
  - File: `Sources/SwiftVJCore/Modules/PlaybackModule.swift`

- [ ] **Simplify PipelineModule**
  - Use AsyncSequence for step progress
  - Return PipelineResult directly
  - File: `Sources/SwiftVJCore/Modules/PipelineModule.swift`

---

### Phase 6: Polish and Documentation

#### 6.1 Add Developer Tools

- [ ] **Create `Sources/SwiftVJApp/Debug/ActionLogger.swift`**
  - Log all actions with timestamps
  - Configurable filtering by action type
  - Enable/disable via compile flag

- [ ] **Create `Sources/SwiftVJApp/Debug/StateInspector.swift`**
  - View current state in debug builds
  - State diff visualization
  - Integration with Xcode debug view

- [ ] **Create time-travel debugging support**
  - Store action history
  - Replay actions to reconstruct state
  - Add to debug menu

#### 6.2 Performance Optimization

- [ ] **Implement state change batching**
  - Batch high-frequency audio updates
  - Debounce UI state updates
  - Maintain 60fps render performance

- [ ] **Optimize effect execution**
  - Proper cancellation on superseding actions
  - Effect deduplication for idempotent operations

#### 6.3 Update Documentation

- [ ] **Update `07-architecture-overview.md`**
  - Document new Store architecture
  - Update component diagram
  - Add action flow documentation

- [ ] **Update `08-data-flow.md`**
  - Replace callback diagrams with action flow
  - Document effect patterns
  - Update sequence diagrams

- [ ] **Create `10-store-patterns.md`**
  - Effect composition patterns
  - Testing strategies
  - Performance considerations
  - Migration guide for future features

---

## 5. File Changes Summary

### New Files to Create

```
Sources/SwiftVJCore/Store/
├── Store.swift                    # Generic Store actor
├── Effect.swift                   # Effect type and utilities
├── AppState.swift                 # Root state and sub-states
├── Actions.swift                  # Action enum hierarchy
├── Reducer.swift                  # Root reducer and composition
└── Effects/
    ├── OSCEffects.swift           # OSC subscription/send effects
    ├── PipelineEffects.swift      # Track processing effects
    ├── LaunchpadEffects.swift     # MIDI device effects
    ├── PersistenceEffects.swift   # UserDefaults effects
    └── AudioEffects.swift         # Audio state effects

Sources/SwiftVJApp/Debug/
├── ActionLogger.swift             # Action logging middleware
└── StateInspector.swift           # State debug tools

Tests/BehaviorTests/ReducerTests/
├── PlaybackReducerTests.swift
├── PipelineReducerTests.swift
├── RenderReducerTests.swift
├── LaunchpadReducerTests.swift
└── UIReducerTests.swift

Tests/BehaviorTests/EffectTests/
├── OSCEffectsTests.swift
├── PipelineEffectsTests.swift
└── LaunchpadEffectsTests.swift

Tests/E2ETests/
└── StoreIntegrationTests.swift
```

### Files to Modify

```
Sources/SwiftVJApp/
├── SwiftVJApp.swift               # Major: Replace AppState class
├── Views/ContentView.swift        # Update to use Store
├── Views/ControlPanelView.swift   # Update to use Store
├── Views/*.swift                  # Update all views
└── Rendering/
    ├── RenderEngine.swift         # Add store subscription
    └── StateManagers.swift        # Change to method-based

Sources/SwiftVJCore/Modules/
├── Module.swift                   # Remove callback types
├── PlaybackModule.swift           # Remove callbacks
└── PipelineModule.swift           # Remove callbacks

Sources/SwiftVJCore/Launchpad/
└── LaunchpadModule.swift          # Remove callbacks

Tests/BehaviorTests/
└── ModuleTests.swift              # Update for new API

Tests/E2ETests/
├── AppIntegrationTests.swift      # Use Store
└── PlaybackE2ETests.swift         # Use Store
```

### Files to Delete (after migration)

```
(No files deleted - code removed from existing files)
```

---

## 6. Dependencies and Prerequisites

### External Dependencies

- **None required** - The architecture uses pure Swift
- Optional: [swift-composable-architecture](https://github.com/pointfreeco/swift-composable-architecture) for reference patterns

### Internal Prerequisites

1. All existing tests must pass before starting
2. Create feature branch for migration
3. Incremental commits for each phase

---

## 7. Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Performance regression from action dispatch | Batch high-frequency updates, profile critical paths |
| Breaking existing views | Migrate views incrementally with adapter layer |
| Test coverage gaps | Create reducer tests first (easy to test pure functions) |
| Concurrency issues | Store is single actor, effects use structured concurrency |
| Audio latency | Maintain nonisolated fast path, no change to audio architecture |

---

## 8. Success Criteria

- [ ] All 24 existing tests pass
- [ ] New reducer tests achieve >90% coverage of state transitions
- [ ] Effect tests cover all async operations
- [ ] No callback types remain in codebase
- [ ] Single `Store<AppState, AppAction>` as source of truth
- [ ] Time-travel debugging functional in debug builds
- [ ] 60fps render performance maintained
- [ ] Audio latency unchanged (<10ms)

---

## 9. Estimated Effort by Phase

| Phase | Tasks | Complexity |
|-------|-------|------------|
| Phase 1: Foundation | 4 major tasks | Medium |
| Phase 2: Core Migration | 4 major tasks | High |
| Phase 3: Effects | 5 effect systems | Medium |
| Phase 4: Testing | 4 test categories | Medium |
| Phase 5: Cleanup | 3 cleanup tasks | Low |
| Phase 6: Polish | 3 polish tasks | Low |

---

## Appendix A: Action Flow Examples

### Track Change Flow (Current vs Target)

**Current (Callback):**
```
VDJ OSC → OSCHub.receive() → PlaybackModule.handleVDJOSC()
    → fireTrackChange() → callbacks.forEach { await $0(track) }
        → AppState.onTrackChange closure
            → MainActor.run { self.currentTrack = track }
            → pipeline.process(track)
                → stepStartCallbacks.forEach { ... }
                → stepCompleteCallbacks.forEach { ... }
            → MainActor.run { self.pipelineResult = result }
```

**Target (Unidirectional):**
```
VDJ OSC → OSCEffects.subscription → store.send(.playback(.trackChanged(track)))
    → playbackReducer: state.playback.currentTrack = track
                       return PipelineEffects.process(track)
    → PipelineEffects.process()
        → store.send(.pipeline(.stepStarted("lyrics")))
        → store.send(.pipeline(.stepCompleted("lyrics", .success)))
        → store.send(.pipeline(.processingCompleted(result)))
    → pipelineReducer: state.pipeline.result = result
    → SwiftUI auto-updates from state change
```

### Shader Selection Flow (Current vs Target)

**Current (didSet):**
```
User tap → Picker.onChange → appState.selectedShader = "rainbow"
    → didSet { UserDefaults.set(...); renderEngine.shaderManager.select(...) }
```

**Target (Unidirectional):**
```
User tap → Picker.onChange → store.send(.render(.selectShader("rainbow")))
    → renderReducer: state.render.selectedShader = "rainbow"
                     return Effect.merge([
                         PersistenceEffects.save(key: "selectedShader", value: "rainbow"),
                         RenderEffects.updateShader("rainbow")
                     ])
```
