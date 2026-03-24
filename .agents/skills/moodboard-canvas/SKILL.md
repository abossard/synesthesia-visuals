# Moodboard Canvas Skill

## Purpose
Guide development of the moodboard visual node-graph feature in Swift-VJ. Covers canvas rendering, node/edge interactions, state management, and performance.

## When to Use
- Editing any file under `Sources/SwiftVJApp/Moodboard/`
- Modifying `MoodboardSubState`, `MoodboardAction`, or `moodboardReducer`
- Touching `MoodboardTypes.swift` or moodboard persistence in `SongStore`
- Writing or updating `MoodboardReducerTests`

## Architecture

### Data Flow (UDF)
```
User gesture → MoodboardAction → moodboardReducer → MoodboardSubState → View
```
- Views dispatch actions via `appState.send(.moodboard(...))`
- Reducer is pure: mutates `inout MoodboardSubState`, returns `Effect`
- Side effects (persistence) run via `EffectEnvironment` closures

### Key Types (SwiftVJCore/Domain/MoodboardTypes.swift)
- `MoodboardNode` — song, tag, or container node with position
- `MoodboardEdge` — typed, weighted, undirected edge between nodes
- `MoodboardBoard` — named snapshot for save/load
- `ViewportState` — canvas offset + zoom
- `TagCategory` — genre, phase, mood, topic, custom
- `EdgeType` — similarity, transition, remix, custom, tagMembership

### Grid System
- All node positions snap to a 20pt grid via `snapToGrid()`
- Grid constant: `moodboardGridSize = 20`
- Canvas shows dot grid aligned to viewport

### State (MoodboardSubState)
Key fields: `nodes`, `edges`, `viewport`, `selectedNodeIds`, `selectedEdgeIds`, `isDrawingEdge`, `drawingEdgeSourceId`, `tagManagerPanelOpen`, `currentBoardName`, `savedBoards`

## Canvas Performance Rules

### DO
- Use `@State` for live gesture feedback (pan offset, zoom scale, drag offset)
- Commit to store only on gesture `.onEnded`
- Use `effectivePositionMap()` in edges layer so edges follow dragged nodes
- Use `.drawingGroup()` on the edges layer to rasterize via Metal
- Use `Canvas` (SwiftUI) for the grid background — it's imperative and fast
- Keep node views stateless except `@State var isHovered`

### DON'T
- Put `.animation()` on views that use `.position()` — causes layout jitter
- Use `.scaleEffect()` with implicit animation on positioned views
- Rebuild dictionaries in every computed property access — cache in local lets
- Dispatch store actions on `.onChanged` — only on `.onEnded`
- Use `@EnvironmentObject` reads in tight loops

### Pan/Zoom Pattern
```swift
// @State for live feedback
@State private var livePanOffset: CGSize = .zero
@State private var liveZoomScale: CGFloat = 1.0

// Effective viewport combines store + live gesture
private var viewport: ViewportState {
    ViewportState(
        offset: CGPoint(
            x: storeViewport.offset.x + livePanOffset.width / effectiveZoom,
            y: storeViewport.offset.y + livePanOffset.height / effectiveZoom
        ),
        zoom: effectiveZoom
    )
}
```

### Edge Drawing Pattern
1. Handle `DragGesture(coordinateSpace: .global)` on `NodeHandleView`
2. Convert global → local via `canvasFrame`
3. Hit-test nodes via `hitTestNode(at:excluding:)`
4. Target node glows (shadow/scale, no `.animation()`)
5. On drop: `finishDrawingEdge(targetId:)` — reducer creates edge
6. On miss: `cancelDrawingEdge`

## File Map
| File | Purpose |
|------|---------|
| `MoodboardCanvasView.swift` | Main canvas: grid, edges, nodes, gestures |
| `SongNodeView.swift` | Song node tile (artwork, title, play button) |
| `TagNodeView.swift` | Tag/genre/mood/phase node tile |
| `NodeHandleView.swift` | 4 circular drag handles for edge drawing |
| `MoodboardView.swift` | Container: toolbar, preview bar, panels, keyboard |
| `MoodboardLibraryPanel.swift` | Left sidebar: song browser with drag source |
| `MoodboardDetailPanel.swift` | Right sidebar: song detail, tags, connections |
| `TagManagerPanel.swift` | Right sidebar: tag list, merge, rename, focus |
| `PhaseFlowBarView.swift` | Phase flow visualization bar |
| `PreviewBarView.swift` | Audio preview timeline and controls |
| `GraphLayout.swift` (Core) | 3 pure layout algorithms: force-directed, hierarchical, grouped |

## Edge Directionality Rules
| Source → Target | Directed? | Visual |
|---|---|---|
| Song → Song | Yes | Arrow at target |
| Tag → Tag | Yes | Arrow at target |
| Song ↔ Tag | No | No arrows |
| Bidirectional pair (A→B + B→A) | Both directed | Offset curves, separate arrows |

Use `edgeIsDirected(sourceKind:targetKind:)` for determination.

## Auto-Layout Algorithms
- **Auto (force-directed)** — spring-electric model, organic clustering
- **Flow (hierarchical)** — Sugiyama-style left→right layering for succession chains
- **Grouped (bipartite)** — tags in columns left, songs right, clustered by connection

All are pure functions in `GraphLayout.swift`: `(nodes, edges) → [id: CGPoint]`.
Reducer applies via `applyLayout(LayoutMode)` + `computeViewportToFit()`.

## Testing
- All reducer logic tested in `MoodboardReducerTests.swift`
- Pure helper functions (`snapToGrid`, `connectedSongNodeIds`, `computeViewportToFit`, `collectTagEntries`, `edgeIsDirected`) have dedicated tests
- Layout algorithms tested for: returns all positions, snap-to-grid, correct ordering
- Test pattern: create state → apply action → assert state changes
- No mocking needed — reducer is pure
