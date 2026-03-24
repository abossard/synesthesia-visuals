# UI Testing Approaches for SwiftUI macOS Apps (SPM)

> Research report for the Swift-VJ project — a macOS VJ control application built with SwiftUI, Metal rendering, and a unidirectional data flow (UDF) architecture, packaged exclusively with Swift Package Manager.

---

## Table of Contents

1. [ViewInspector (Currently Used)](#1-viewinspector-currently-used)
2. [XCUITest (Apple's UI Automation)](#2-xcuitest-apples-ui-automation)
3. [Snapshot/Screenshot Testing](#3-snapshotscreenshot-testing-swift-snapshot-testing)
4. [State-Driven Testing (Reducer + AppState)](#4-state-driven-testing-reducer--appstate)
5. [Manual Visual Testing](#5-manual-visual-testing)
6. [Recommendation for This Project](#6-recommendation-for-this-project)

---

## 1. ViewInspector (Currently Used)

### What It Is

[ViewInspector](https://github.com/nalexn/ViewInspector) is a third-party open-source library for unit-testing SwiftUI views. It lets you write XCTest assertions against the SwiftUI view hierarchy without launching a running application or rendering pixels.

### How It Works

ViewInspector uses Swift's runtime reflection (`Mirror`) to traverse the internal tree that SwiftUI builds when a `body` property is evaluated. It exposes a type-safe inspection API that lets you locate views by type, index, or accessibility identifier, then read their properties, trigger actions, and verify bindings.

The view is instantiated in-process — no window, no run loop, no rendering pipeline. This makes tests extremely fast (millisecond-range).

### Strengths

| Strength | Why It Matters for Swift-VJ |
|---|---|
| **Works with SPM** | No `.xcodeproj` required — runs via `swift test` |
| **Fast** | Sub-second per test; fits in CI without macOS UI session |
| **Tests view structure** | Verify that `MoodboardCanvasView`, `MoodboardLibraryPanel`, etc. appear under expected conditions |
| **Accessibility ID verification** | Ensures `A11yID` constants are wired to the correct views |
| **State binding validation** | Can read `@Binding`, `@State`, `@EnvironmentObject` values |
| **Action dispatch verification** | Can tap buttons and verify the resulting action dispatch |

### Limitations

| Limitation | Impact |
|---|---|
| Cannot test visual rendering | Won't catch Metal shader issues, color mismatches, layout overflow |
| No gesture simulation | Can't test drag-to-create-edge, pinch-to-zoom on the Moodboard canvas |
| No animation testing | Can't verify phase transitions or beat-synced animations |
| No real user interaction flow | Can't simulate tabbing between fields, menu bar actions, keyboard shortcuts via `NSEvent` |
| Reflection-based | May break with new SwiftUI releases (though the maintainer tracks betas actively) |

### Best For

- Verifying view hierarchy composition (e.g., "library panel is visible when `libraryPanelOpen == true`")
- Confirming accessibility identifiers are attached
- Testing button presence and tap-action wiring
- Validating conditional rendering logic

### Example: Testing MoodboardView Structure

This example mirrors the patterns already used in `SwiftVJAppUITests.swift`:

```swift
import XCTest
import ViewInspector
@testable import SwiftVJApp
@testable import SwiftVJCore

@MainActor
final class MoodboardViewInspectorTests: XCTestCase {

    private func makeAppState(
        libraryOpen: Bool = true,
        detailSongId: SongID? = nil
    ) -> Store<AppState, AppAction> {
        var state = AppState()
        state.moodboard.libraryPanelOpen = libraryOpen
        state.moodboard.detailPanelSongId = detailSongId
        return Store(initialState: state, reducer: appReducer)
    }

    // MARK: - Structural Tests

    func testMoodboardShowsCanvasAlways() throws {
        let store = makeAppState()
        let view = MoodboardView().environmentObject(store)
        let inspector = try view.inspect()

        // Canvas should always be present
        XCTAssertNoThrow(
            try inspector.find(MoodboardCanvasView.self)
        )
    }

    func testLibraryPanelVisibleWhenOpen() throws {
        let store = makeAppState(libraryOpen: true)
        let view = MoodboardView().environmentObject(store)
        let inspector = try view.inspect()

        XCTAssertNoThrow(
            try inspector.find(MoodboardLibraryPanel.self)
        )
    }

    func testLibraryPanelHiddenWhenClosed() throws {
        let store = makeAppState(libraryOpen: false)
        let view = MoodboardView().environmentObject(store)
        let inspector = try view.inspect()

        XCTAssertThrowsError(
            try inspector.find(MoodboardLibraryPanel.self)
        )
    }

    // MARK: - Accessibility ID Tests

    func testToolbarHasExpectedAccessibilityIDs() throws {
        let store = makeAppState()
        let view = MoodboardView().environmentObject(store)
        let inspector = try view.inspect()

        let buttonIds = inspector.findAll(ViewType.Button.self).compactMap {
            try? $0.accessibilityIdentifier()
        }

        // Verify key toolbar buttons are present and identifiable
        XCTAssertTrue(buttonIds.contains("moodboard.toolbar.newBoard"))
        XCTAssertTrue(buttonIds.contains("moodboard.toolbar.toggleLibrary"))
    }
}
```

### Integration with This Project

ViewInspector is already declared in `Package.swift` as a dependency of `SwiftVJAppTests`:

```swift
.package(url: "https://github.com/nalexn/ViewInspector", from: "0.9.10"),
```

Run existing tests:

```bash
swift test --filter SwiftVJAppTests
```

---

## 2. XCUITest (Apple's UI Automation)

### What It Is

XCUITest is Apple's first-party UI testing framework, part of the XCTest family. It launches the application as a separate process and drives it through the accessibility tree — the same tree that VoiceOver uses.

### How It Works

1. Xcode builds a **UI test runner** bundle.
2. The runner launches the **target application** as a child process.
3. Tests interact with the app via `XCUIApplication`, `XCUIElement`, and `XCUIElementQuery`.
4. All interaction goes through the accessibility hierarchy — buttons, text fields, sliders, etc.
5. Assertions check element existence, values, labels, and enabled state.

### Requirements

| Requirement | Detail |
|---|---|
| Build system | Needs `.xcodeproj` or `.xcworkspace` with a UI Testing target |
| App target | Must have an actual application target (not just a library) |
| macOS session | Requires a logged-in GUI session (or a CI agent with screen access) |
| Cannot run from `swift test` | XCUITest bundles are only runable via `xcodebuild test` or Xcode IDE |

### SPM Workaround

Since Swift-VJ is SPM-only, XCUITest requires a manual bridge:

```bash
# 1. Open Package.swift in Xcode
open swift-vj/Package.swift

# 2. In Xcode: File → New → Target → macOS → UI Testing Bundle
#    Set the "Target to be Tested" to SwiftVJApp

# 3. Xcode creates a .xcodeproj wrapper automatically
#    The UI test target lives inside this wrapper

# 4. Run tests via xcodebuild
xcodebuild test \
  -scheme SwiftVJApp \
  -destination 'platform=macOS' \
  -only-testing:SwiftVJAppUITests
```

> **Note:** This creates an Xcode project dependency. The SPM `Package.swift` remains the source of truth for production code, but UI tests live in the `.xcodeproj`.

### Strengths

| Strength | Detail |
|---|---|
| **Real interaction** | Taps, clicks, drags, keyboard input, menu bar navigation |
| **Screenshot capture** | `XCTAttachment` captures screenshots at any point during the test |
| **Cross-process** | Tests are isolated from the app — crashes don't kill the test runner |
| **Apple-supported** | First-party framework with Xcode integration and CI support |
| **Accessibility validation** | If XCUITest can't find an element, your app has an accessibility gap |

### Limitations

| Limitation | Impact on Swift-VJ |
|---|---|
| **Slow** | Each test launches the app from scratch (2-5 seconds per test) |
| **Fragile** | Tests break when accessibility hierarchy changes |
| **No `swift test`** | Can't run from the SPM-native test command |
| **GUI session required** | CI needs a macOS agent with display access (or `xcrun simctl`) |
| **Limited Metal inspection** | Can't verify shader output or Metal texture content |
| **Requires Xcode project** | Adds `.xcodeproj` maintenance burden to an SPM-only project |

### Example: XCUITest for Moodboard

```swift
import XCTest

final class MoodboardUITests: XCTestCase {

    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launch()
    }

    func testMoodboardTabNavigation() throws {
        // Navigate to Moodboard tab via sidebar
        let sidebar = app.scrollViews["sidebarList"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))

        let moodboardTab = sidebar.buttons["sidebarTab.Moodboard"]
        XCTAssertTrue(moodboardTab.exists)
        moodboardTab.click()

        // Verify canvas appears
        let canvas = app.groups["moodboard.canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 3))
    }

    func testToggleLibraryPanel() throws {
        // Navigate to Moodboard
        app.scrollViews["sidebarList"].buttons["sidebarTab.Moodboard"].click()

        // Toggle library panel
        let toggleButton = app.buttons["moodboard.toolbar.toggleLibrary"]
        XCTAssertTrue(toggleButton.waitForExistence(timeout: 3))
        toggleButton.click()

        // Library panel should appear/disappear
        let libraryPanel = app.groups["moodboard.libraryPanel"]
        // State depends on initial visibility — assert based on expected toggle behavior
    }

    func testAddNodeViaDragFromLibrary() throws {
        app.scrollViews["sidebarList"].buttons["sidebarTab.Moodboard"].click()

        let libraryItem = app.cells["moodboard.library.song.0"]
        let canvas = app.groups["moodboard.canvas"]

        guard libraryItem.waitForExistence(timeout: 5),
              canvas.waitForExistence(timeout: 3) else {
            XCTFail("Required elements not found")
            return
        }

        // Drag song from library to canvas
        libraryItem.click(forDuration: 0.5, thenDragTo: canvas)

        // Verify node appears on canvas
        let nodeCount = canvas.groups.matching(
            identifier: "moodboard.node"
        ).count
        XCTAssertGreaterThan(nodeCount, 0)
    }

    func testScreenshotCapture() throws {
        app.scrollViews["sidebarList"].buttons["sidebarTab.Moodboard"].click()

        let canvas = app.groups["moodboard.canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // Capture screenshot for visual reference
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Moodboard-Canvas"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
```

### Verdict for Swift-VJ

XCUITest is **not recommended as a primary strategy** for this project because:

1. The project is SPM-only — adding `.xcodeproj` introduces maintenance overhead.
2. Tests can't run via `swift test`, breaking the existing CI workflow.
3. Metal-rendered content (shader tiles) isn't inspectable via the accessibility tree.

However, it becomes valuable **if the project ever adds an Xcode project** for distribution (e.g., notarization, App Store). At that point, a small suite of smoke tests for critical flows (tab navigation, keyboard shortcuts) would be worthwhile.

---

## 3. Snapshot/Screenshot Testing (swift-snapshot-testing)

### What It Is

[swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) by Point-Free is a library that renders SwiftUI views (or any `NSView`/`UIView`) to an image, saves the image as a baseline, and on subsequent runs diffs the current render against the baseline. Any pixel-level differences cause the test to fail with a visual diff.

### How It Works

```
1. First run:  View → render to image → save as baseline PNG
2. Later runs: View → render to image → pixel-diff against baseline
3. If different: test fails, produces diff image showing changes
4. Developer reviews diff, updates baseline if intentional
```

### Strengths

| Strength | Detail |
|---|---|
| **Catches visual regressions** | Detects unintended layout shifts, color changes, font size changes |
| **Works with SPM** | Pure Swift package, no Xcode project needed |
| **Automated** | Runs in CI alongside unit tests via `swift test` |
| **Multiple strategies** | Can snapshot as image, text dump, or accessibility hierarchy |
| **Diffing output** | Failed tests produce before/after/diff images for easy review |

### Limitations

| Limitation | Detail |
|---|---|
| **Baseline maintenance** | Every intentional UI change requires updating baseline images |
| **Platform-specific renders** | Baselines differ between macOS versions, Retina vs non-Retina, CI vs local |
| **No interaction testing** | Snapshots are static — can't test drag, hover, or keyboard behavior |
| **Metal content** | SwiftUI snapshot rendering may not capture Metal layer content (shader tiles) |
| **Git bloat** | Baseline PNGs add to repository size (mitigated with Git LFS) |

### Best For

- Detecting unintended visual changes in layout-heavy views
- Verifying dark mode / light mode appearance
- Regression testing for complex view compositions (toolbar, panels, canvas overlays)
- Accessibility hierarchy snapshots (text-based, no image concerns)

### Setup for Swift-VJ

Add to `Package.swift`:

```swift
dependencies: [
    // ... existing dependencies
    .package(
        url: "https://github.com/pointfreeco/swift-snapshot-testing",
        from: "1.15.0"
    ),
],
```

Add to the test target:

```swift
.testTarget(
    name: "SwiftVJAppTests",
    dependencies: [
        "SwiftVJApp",
        "SwiftVJCore",
        .product(name: "ViewInspector", package: "ViewInspector"),
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
    ]),
```

### Example: Snapshot Testing Moodboard Components

```swift
import XCTest
import SnapshotTesting
import SwiftUI
@testable import SwiftVJApp
@testable import SwiftVJCore

@MainActor
final class MoodboardSnapshotTests: XCTestCase {

    // MARK: - Helpers

    private func makeStore(
        nodes: [MoodboardNode] = [],
        edges: [MoodboardEdge] = [],
        libraryOpen: Bool = true
    ) -> Store<AppState, AppAction> {
        var state = AppState()
        state.moodboard.nodes = nodes
        state.moodboard.edges = edges
        state.moodboard.libraryPanelOpen = libraryOpen
        return Store(initialState: state, reducer: appReducer)
    }

    private func hostView<V: View>(_ view: V, size: CGSize) -> NSView {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = CGRect(origin: .zero, size: size)
        return hostingView
    }

    // MARK: - Image Snapshots

    func testMoodboardToolbarAppearance() {
        let store = makeStore()
        let view = MoodboardToolbar()
            .environmentObject(store)
            .frame(width: 800, height: 44)

        let hosted = hostView(view, size: CGSize(width: 800, height: 44))

        // First run: creates __Snapshots__/MoodboardToolbar.png
        // Subsequent runs: diffs against baseline
        assertSnapshot(of: hosted, as: .image)
    }

    func testMoodboardLibraryPanelWithSongs() {
        let store = makeStore(libraryOpen: true)
        // Add some test songs to state for a realistic snapshot
        let view = MoodboardLibraryPanel()
            .environmentObject(store)
            .frame(width: 250, height: 600)

        let hosted = hostView(view, size: CGSize(width: 250, height: 600))
        assertSnapshot(of: hosted, as: .image)
    }

    // MARK: - Accessibility Hierarchy Snapshot (text-based, cross-platform stable)

    func testMoodboardToolbarAccessibilityTree() {
        let store = makeStore()
        let view = MoodboardToolbar()
            .environmentObject(store)
            .frame(width: 800, height: 44)

        let hosted = hostView(view, size: CGSize(width: 800, height: 44))

        // Text-based snapshot of the accessibility tree
        // More stable across OS versions than pixel comparisons
        assertSnapshot(of: hosted, as: .recursiveDescription)
    }

    // MARK: - Recording Mode

    func testRecordNewBaselines() {
        // Set record = true to capture new baselines after intentional UI changes
        // Then set back to false and commit the updated PNGs
        // isRecording = true  // Uncomment to record

        let store = makeStore()
        let view = MoodboardView()
            .environmentObject(store)
            .frame(width: 1200, height: 800)

        let hosted = hostView(view, size: CGSize(width: 1200, height: 800))
        assertSnapshot(of: hosted, as: .image)
    }
}
```

### Baseline Management Strategy

```
Tests/
  SwiftVJAppTests/
    __Snapshots__/
      MoodboardSnapshotTests/
        testMoodboardToolbarAppearance.png
        testMoodboardLibraryPanelWithSongs.png
        testMoodboardToolbarAccessibilityTree.txt
```

**Git strategy:**

- Commit baseline images alongside tests.
- Use `.gitattributes` to mark PNGs as binary: `*.png binary`
- Consider Git LFS if baseline count grows large (> 50 images).
- Use `isRecording = true` when intentionally changing UI, then switch back.

### CI Considerations

- Pin CI runner macOS version to match local development.
- Use tolerance parameter for minor anti-aliasing differences:

```swift
assertSnapshot(of: hosted, as: .image(precision: 0.98))
```

---

## 4. State-Driven Testing (Reducer + AppState)

### What It Is

State-driven testing verifies UI behavior by testing the **state transformations** that drive the UI, rather than the UI itself. In a UDF architecture, this means dispatching actions through the reducer and asserting the resulting state.

Since SwiftUI views are pure functions of state (`View = f(State)`), proving the state is correct implies the view renders correctly — assuming view bindings are wired correctly (which ViewInspector can verify).

### How It Works in Swift-VJ

The project already follows this pattern extensively:

```
Action → Reducer(inout State, Action) → New State + Effects
```

Tests call the reducer directly with a known initial state and action, then assert the resulting state.

### Strengths

| Strength | Detail |
|---|---|
| **Fastest tests** | Pure function calls — no view instantiation, no rendering |
| **Deterministic** | No timing, no async, no external dependencies |
| **Complete coverage** | Every state transition can be tested exhaustively |
| **Refactor-safe** | Tests survive view restructuring since they test state, not UI |
| **Already established** | 36+ reducer tests across 10 test files |

### Limitations

| Limitation | Detail |
|---|---|
| **No rendering verification** | Won't catch a missing `if` branch in a view's `body` |
| **No binding verification** | Won't catch a view reading `state.foo` instead of `state.bar` |
| **Assumes correct view wiring** | The "view = f(state)" contract must be verified separately |

### Already Used: MoodboardReducerTests

The project has comprehensive Moodboard reducer tests:

```swift
// From Tests/BehaviorTests/ReducerTests/MoodboardReducerTests.swift

final class MoodboardReducerTests: XCTestCase {

    private func apply(
        _ action: MoodboardAction,
        to state: inout MoodboardSubState
    ) -> Effect<MoodboardAction> {
        moodboardReducer(state: &state, action: action)
    }

    // --- Node Management ---

    func testAddSongNodeToEmptyState() {
        var state = MoodboardSubState()
        let songId = makeSongID("Song1")

        _ = apply(.addSongNode(songId, position: CGPoint(x: 10, y: 20)), to: &state)

        XCTAssertEqual(state.nodes.count, 1)
        XCTAssertEqual(state.nodes[0].songId, songId)
        XCTAssertEqual(state.nodes[0].position, CGPoint(x: 10, y: 20))
        XCTAssertEqual(state.nodes[0].kind, .song)
    }

    // --- Edge Removal Cascading ---

    func testRemoveNodeRemovesNodeAndConnectedEdges() {
        let nodeA = makeSongNode("A", at: .zero)
        let nodeB = makeSongNode("B", at: CGPoint(x: 10, y: 10))
        let edgeAB = makeEdge(sourceId: nodeA.id, targetId: nodeB.id)

        var state = MoodboardSubState(
            nodes: [nodeA, nodeB],
            edges: [edgeAB],
            selectedNodeIds: [nodeB.id]
        )

        _ = apply(.removeNode(nodeB.id), to: &state)

        XCTAssertEqual(state.nodes.count, 1)
        XCTAssertTrue(state.edges.isEmpty)
        XCTAssertFalse(state.selectedNodeIds.contains(nodeB.id))
    }

    // --- Selection ---

    func testSelectNodesReplacesSelection() {
        var state = MoodboardSubState()
        state.selectedNodeIds = [UUID()]

        let newIds: Set<MoodboardNodeID> = [UUID(), UUID()]
        _ = apply(.selectNodes(newIds), to: &state)

        XCTAssertEqual(state.selectedNodeIds, newIds)
    }

    // --- Multi-action Sequences ---

    func testFullWorkflow_AddNodes_Connect_Delete() {
        var state = MoodboardSubState()

        // Add two nodes
        _ = apply(.addSongNode(makeSongID("A"), position: .zero), to: &state)
        _ = apply(.addSongNode(makeSongID("B"), position: CGPoint(x: 100, y: 100)), to: &state)
        XCTAssertEqual(state.nodes.count, 2)

        // Connect them
        let idA = state.nodes[0].id
        let idB = state.nodes[1].id
        _ = apply(.addEdge(sourceId: idA, targetId: idB), to: &state)
        XCTAssertEqual(state.edges.count, 1)

        // Delete source node — edge should cascade
        _ = apply(.removeNode(idA), to: &state)
        XCTAssertEqual(state.nodes.count, 1)
        XCTAssertTrue(state.edges.isEmpty)
    }
}
```

### Extending State-Driven Tests: Integration Sequences

Beyond individual reducer tests, you can test full action sequences through the composed `appReducer` to verify cross-substate interactions:

```swift
final class MoodboardIntegrationTests: XCTestCase {

    @MainActor
    func testMoodboardLoadTriggersCorrectStateFlow() {
        var state = AppState()
        state.songs.library = [
            Song(id: "song1", artist: "Artist A", title: "Track 1"),
            Song(id: "song2", artist: "Artist B", title: "Track 2"),
        ]

        // Simulate the action that MoodboardView dispatches on appear
        let effect = appReducer(state: &state, action: .moodboard(.loadFromSongs))

        // Verify moodboard state reflects loaded songs
        XCTAssertFalse(state.moodboard.nodes.isEmpty)
        // Verify no unintended side effects on other substates
        XCTAssertTrue(state.playback.currentTrack == nil)
        XCTAssertEqual(state.ui.logEntries.count, 0)
    }
}
```

---

## 5. Manual Visual Testing

### When To Use

Manual testing is necessary when automated tools cannot verify the behavior:

| Scenario | Why Automation Falls Short |
|---|---|
| **Drag-to-draw-edge** on Moodboard canvas | Requires precise gesture simulation with intermediate positions |
| **Node repositioning** with momentum | Physics-based animation can't be pixel-verified deterministically |
| **Keyboard shortcut flows** | `NSEvent`-level key handling via `MoodboardKeyHandler` bypasses SwiftUI's responder chain |
| **Metal shader rendering** | Shader tile output is GPU-rendered; not accessible to view inspection |
| **Overall UX feel** | Responsiveness, visual rhythm, and "does this feel right" require human judgment |
| **Audio-reactive visuals** | Real-time audio-driven rendering requires live observation |

### Structured Testing Checklist

Use this checklist when doing manual testing of the Moodboard feature:

```markdown
## Moodboard Manual Test Checklist

### Navigation
- [ ] Click "Moodboard" in sidebar → canvas loads
- [ ] Library panel toggles via toolbar button
- [ ] Detail panel opens when a node is selected
- [ ] Tag manager panel toggles correctly

### Node Operations
- [ ] Add node: drag song from library to canvas
- [ ] Move node: drag existing node to new position
- [ ] Select node: single-click highlights, shows detail panel
- [ ] Multi-select: Shift+click adds to selection
- [ ] Select all: Cmd+A selects all nodes
- [ ] Delete: Backspace/Delete removes selected nodes
- [ ] Delete cascades: connected edges removed with node

### Edge Operations
- [ ] Draw edge: drag from node connector to target node
- [ ] Edge renders as visible line between nodes
- [ ] Edge follows node repositioning
- [ ] Delete edge: select and delete, or delete connected node

### Keyboard Shortcuts (via MoodboardKeyHandler)
- [ ] Space: play/pause preview
- [ ] Cmd+A: select all nodes
- [ ] Shift+Left/Right: seek ±15 seconds
- [ ] Delete/Backspace: remove selected nodes
- [ ] Escape: clear selection

### Board Management
- [ ] New board: toolbar button creates empty board
- [ ] Save board: saves current layout with name
- [ ] Load board: restores layout from saved boards
- [ ] Delete board: removes saved board from list

### Visual Quality
- [ ] Nodes render with correct song metadata (title, artist)
- [ ] Selected nodes have visible highlight
- [ ] Edges render with correct color and line style
- [ ] Canvas panning/zooming works smoothly
- [ ] Dark mode renders correctly
- [ ] Light mode renders correctly

### Performance
- [ ] 50+ nodes: canvas remains responsive
- [ ] Rapid node selection: no UI lag
- [ ] Window resize: layout adapts correctly
```

### Tools

| Tool | Use |
|---|---|
| **Cmd+Shift+4** | Region screenshot with crosshair selection |
| **Cmd+Shift+5** | Screen recording (captures interactions) |
| **QuickTime Player** | Screen recording with audio for demo videos |
| **Xcode Instruments** | Profile rendering performance (Metal System Trace) |

### Documentation Process

1. Run through checklist on each release candidate.
2. Capture screenshots for any visual regressions.
3. File issues with screenshot attachments for failures.
4. Store reference screenshots in `swift-vj/docs/screenshots/` for comparison.

---

## 6. Recommendation for This Project

### Context

Swift-VJ is an SPM-only macOS application with:

- **UDF architecture** (`AppAction → Reducer → AppState → View`)
- **36+ reducer tests** across 10 test files (BehaviorTests)
- **ViewInspector tests** for view hierarchy and accessibility (SwiftVJAppTests)
- **E2E tests** for integration with external services
- **No Xcode project** — all builds and tests run via `swift build` / `swift test`
- **Metal rendering** for shader tiles (not testable via view inspection)
- **Complex gestures** (drag-to-draw-edge, node repositioning) in the Moodboard

### Recommended Layered Approach

```
┌─────────────────────────────────────────────────────────┐
│  Layer 4: Manual Visual Testing                         │
│  • Structured checklists for gestures, animation, UX    │
│  • Screenshot documentation                             │
│  • Metal shader visual verification                     │
├─────────────────────────────────────────────────────────┤
│  Layer 3: State-Driven Integration Tests                │
│  • Full action sequences through appReducer             │
│  • Cross-substate interaction verification              │
│  • Effect emission validation                           │
├─────────────────────────────────────────────────────────┤
│  Layer 2: ViewInspector Tests                           │
│  • View hierarchy structure                             │
│  • Accessibility ID verification                        │
│  • Conditional rendering (panel visibility)             │
│  • Button/control presence                              │
├─────────────────────────────────────────────────────────┤
│  Layer 1: Reducer Tests (Already have 36+)              │
│  • Individual action → state transition                 │
│  • Edge cases and error states                          │
│  • Effect return value verification                     │
│  • Pure, fast, deterministic                            │
└─────────────────────────────────────────────────────────┘
```

### Layer Details

#### Layer 1: Reducer Tests ✅ Already Established

**Status:** 36+ tests across 10 files, including comprehensive Moodboard coverage.

**Action items:** Continue expanding as new actions and state transitions are added. Every new `MoodboardAction` variant should have a corresponding test.

**Run:** `swift test --filter BehaviorTests`

#### Layer 2: ViewInspector Tests ✅ Already Established

**Status:** `SwiftVJAppUITests.swift` tests `ContentView` and `KaraokeLyricsPanel`.

**Action items:**
- Add tests for `MoodboardView` conditional panel rendering.
- Add tests for `MoodboardToolbar` button presence and accessibility IDs.
- Verify `MoodboardDetailPanel` shows correct song metadata from state.

**Run:** `swift test --filter SwiftVJAppTests`

#### Layer 3: State-Driven Integration Tests 🔲 New

**What to test:**
- Full Moodboard workflows: load → add nodes → connect → save → reload.
- Cross-substate actions: Moodboard song preview triggering playback state changes.
- Action sequence invariants: no orphan edges after any sequence of add/remove operations.

**Where:** Add to `Tests/BehaviorTests/ReducerTests/` or a new `IntegrationTests/` group.

**Run:** `swift test --filter BehaviorTests`

#### Layer 4: Manual Visual Testing 🔲 New

**What to test:** Gesture interactions, Metal rendering, animation smoothness, overall UX.

**Action items:**
- Create the checklist above as a living document.
- Capture reference screenshots after major UI changes.
- Run checklist before releases.

### Future Enhancements

#### Snapshot Testing (Medium Priority)

Add `swift-snapshot-testing` for visual regression detection:

```swift
// Package.swift
.package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.15.0"),
```

**When to add:** After the Moodboard UI stabilizes and visual changes become less frequent. Snapshot tests are most valuable when the UI is mature enough that changes should be intentional.

**Recommended approach:** Start with accessibility hierarchy snapshots (text-based, platform-stable) before adding image-based snapshots.

#### XCUITest (Low Priority)

Consider only if:
- The project adds a `.xcodeproj` for distribution (notarization, App Store).
- Complex end-to-end flows need automated regression testing.
- CI infrastructure supports macOS GUI sessions.

**Not recommended now** because the SPM-only setup and the overhead of maintaining an Xcode project wrapper outweigh the benefits for the current team size and release cadence.

### Testing Decision Matrix

| What You Want To Verify | Use This Layer |
|---|---|
| Action X produces correct state Y | Layer 1: Reducer test |
| View shows component Z when state is W | Layer 2: ViewInspector |
| Full user workflow produces correct final state | Layer 3: Integration test |
| Drag gesture works, animation looks right | Layer 4: Manual checklist |
| UI didn't accidentally change visually | Future: Snapshot testing |
| Real click-through of the full app | Future: XCUITest |

### Test Count Targets

| Layer | Current | Target (Short-term) | Target (Long-term) |
|---|---|---|---|
| Reducer tests | 36+ | 50+ | 80+ |
| ViewInspector tests | 3 | 10+ | 20+ |
| Integration tests | 0 | 5+ | 15+ |
| Manual checklist items | 0 | 25+ | 40+ |
| Snapshot tests | 0 | — | 10+ |

---

## References

- [ViewInspector GitHub](https://github.com/nalexn/ViewInspector) — SwiftUI view inspection
- [swift-snapshot-testing GitHub](https://github.com/pointfreeco/swift-snapshot-testing) — Snapshot testing
- [Apple XCUITest Documentation](https://developer.apple.com/documentation/xctest/user_interface_tests) — UI automation
- [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture) — TCA testing patterns (similar to Swift-VJ's UDF)
- [swift-vj Architecture Docs](../architecture/08-data-flow.md) — Data flow diagrams
- [swift-vj UDF Refactor Plan](../architecture/09-unidirectional-data-flow-refactor-plan.md) — UDF architecture rationale
