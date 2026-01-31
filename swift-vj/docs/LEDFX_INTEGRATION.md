# LedFX Integration

Complete LedFX integration for SwiftVJ, enabling synchronized LED control for DJ sets and VJ performances.

## Overview

This integration provides:
- Full LedFX REST API client
- Scene generation based on track analysis (energy, valence, BPM)
- Scene lifecycle management (create, activate, deactivate, delete)
- Virtual device control
- Effect and preset management
- SwiftUI configuration panel

## Architecture

Following **Grokking Simplicity** and **A Philosophy of Software Design** principles:

```
┌────────────────────────────────────────────┐
│     LedFXConfigView (SwiftUI)              │ 
├────────────────────────────────────────────┤
│     LedFXModule (Module Protocol)          │
│     - Scene lifecycle management           │
│     - Virtual device control               │
│     - Effect management                    │
├────────────────────────────────────────────┤
│     LedFXClient (Adapter - Deep Module)    │
│     - Hides HTTP complexity                │
│     - Async/await interface                │
│     - All LedFX API endpoints              │
├────────────────────────────────────────────┤
│     SceneGenerator (Pure Functions)        │
│     - Energy/valence → effect mapping      │
│     - BPM-aware scene generation           │
│     - Preset templates                     │
├────────────────────────────────────────────┤
│     LedFXTypes (Immutable Domain Models)   │
│     - Scene, Virtual, Effect, Preset       │
│     - Codable for JSON serialization       │
└────────────────────────────────────────────┘
```

## Components

### Domain Models (`LedFXTypes.swift`)

Immutable data types representing LedFX entities:

- `LedFXScene` - Scene configuration with virtual actions
- `LedFXVirtual` - Virtual LED device
- `Effect` - Effect configuration
- `LedFXPreset` - Saved effect preset
- `VirtualAction` - Action to perform on virtual (activate, ignore, stop, forceblack)
- `EffectConfig` - Dynamic effect parameters
- `SceneActionRequest` - Scene control (activate/deactivate/rename)
- `OneshotRequest` - Temporary color flash

### Adapter (`LedFXClient.swift`)

Deep module providing simple interface to LedFX REST API:

```swift
let client = LedFXClient(baseURL: "http://127.0.0.1:8888")

// Get server info
let info = try await client.getInfo()

// List and manage scenes
let scenes = try await client.listScenes()
try await client.putScene(id: "my_scene", scene: scene)
try await client.activateScene(id: "my_scene")
try await client.deactivateScene(id: "my_scene")

// Manage virtuals
let virtuals = try await client.listVirtuals()
try await client.updateVirtual(id: "virtual-1", config: config)

// Effects
try await client.setEffect(virtualId: "virtual-1", effect: effect)
try await client.clearEffect(virtualId: "virtual-1")

// Oneshots (flashes)
try await client.triggerFlash(virtualId: "virtual-1", color: "#FF0000")
```

### Scene Generator (`SceneGenerator.swift`)

Pure functions for generating scenes:

```swift
// Generate scene from track analysis
let scene = SceneGenerator.generateScene(
    name: "High Energy Track",
    virtualIds: ["virtual-1", "virtual-2"],
    energy: 0.9,    // 0.0-1.0
    valence: 0.7,   // 0.0-1.0 (negative to positive)
    bpm: 128.0,
    tags: ["dj-set", "auto"]
)

// Generate preset scenes
let presets = SceneGenerator.generatePresetScenes(
    virtualIds: ["virtual-1"]
)
// Creates: high_energy, medium_energy, low_energy, uplifting, dark, blackout

// Generate DJ set scenes
let tracks = [
    ("Track 1", energy: 0.8, valence: 0.6, bpm: 128.0),
    ("Track 2", energy: 0.5, valence: 0.7, bpm: 120.0)
]
let scenes = SceneGenerator.generateDJSetScenes(
    virtualIds: ["virtual-1"],
    tracks: tracks
)
```

#### Energy/Valence Mapping

The scene generator maps track analysis to effect types:

| Energy | Valence | Effect Type | Description |
|--------|---------|-------------|-------------|
| High (>0.7) | Positive (>0.6) | `strobe` | Fast strobing |
| High (>0.7) | Negative (<0.6) | `energy` | Intense gradients |
| Medium (0.4-0.7) | Positive (>0.5) | `scroll` | Smooth scrolling |
| Medium (0.4-0.7) | Negative (<0.5) | `gradient` | Gradual color shifts |
| Low (<0.4) | Positive (>0.6) | `wavelength` | Gentle waves |
| Low (<0.4) | Negative (<0.6) | `fade` | Slow fades |

### Module (`LedFXModule.swift`)

Module for lifecycle management and scene sync:

```swift
let module = LedFXModule(
    baseURL: "http://127.0.0.1:8888",
    virtualIds: ["virtual-1", "virtual-2"]
)

// Start module
try await module.start()

// Scene management
let scenes = await module.getScenes()
let activeId = await module.getActiveSceneId()
try await module.activateScene(id: "my_scene")

// Generate scenes for current track
let sceneId = try await module.generateSceneForTrack(
    name: trackName,
    energy: 0.8,
    valence: 0.7,
    bpm: 128.0
)
try await module.activateScene(id: sceneId)

// Scene change callback
await module.onSceneChange { sceneId in
    print("Scene changed to: \(sceneId)")
}

// Stop module
await module.stop()
```

### UI (`LedFXConfigView.swift`)

SwiftUI configuration panel accessible from the LedFX sidebar tab:

Features:
- **Connection Settings** - Configure base URL and virtual IDs
- **Server Status** - Display server info and connection state
- **Scene Browser** - List, activate, deactivate, delete scenes
- **Virtual Controls** - Adjust brightness per virtual
- **Scene Generator** - Generate preset or custom DJ set scenes
- **Error Display** - User-friendly error messages

## Usage

### 1. Enable LedFX Integration

In the SwiftVJ app:
1. Click the **LedFX** tab in the sidebar
2. Toggle **Enable LedFX Integration**
3. Configure **Base URL** (default: `http://127.0.0.1:8888`)
4. Enter **Virtual IDs** (comma-separated, e.g., `virtual-1, virtual-2`)
5. Click **Test Connection** to verify

### 2. Generate Scenes

Click **Generate Scenes** → **Generate Standard Presets** to create:
- High Energy
- Medium Energy  
- Low Energy
- Uplifting
- Dark
- Blackout

### 3. Activate Scenes

Browse the scene list and click the **Play** button to activate a scene.

### 4. DJ Set Workflow

Integrate with pipeline for automatic scene selection:

```swift
// In PipelineModule or track change callback
if let ledfx = appState.ledfxModule {
    // Generate scene for current track
    let sceneId = try await ledfx.generateSceneForTrack(
        name: track.title,
        energy: analysis.energy,
        valence: analysis.valence,
        bpm: track.bpm
    )
    
    // Activate it
    try await ledfx.activateScene(id: sceneId)
}
```

## API Coverage

The integration covers all major LedFX REST API endpoints:

### Info
- `GET /api/info` - Server information

### Scenes
- `GET /api/scenes` - List all scenes
- `GET /api/scenes/{id}` - Get specific scene
- `POST /api/scenes` - Create scene
- `PUT /api/scenes` - Update or activate scene
- `DELETE /api/scenes/{id}` - Delete scene

### Virtuals
- `GET /api/virtuals` - List virtual devices
- `GET /api/virtuals/{id}` - Get virtual device
- `PUT /api/virtuals/{id}` - Update virtual config

### Effects
- `GET /api/virtuals/{id}/effects` - Get current effect
- `PUT /api/virtuals/{id}/effects` - Set effect
- `DELETE /api/virtuals/{id}/effects` - Clear effect

### Presets
- `GET /api/virtuals/{id}/presets` - List presets
- `PUT /api/virtuals/{id}/presets` - Activate preset

### Tools
- `PUT /api/virtuals_tools/{id}` - Trigger oneshot flash

### Schema
- `GET /api/schema` - Get all schemas
- `GET /api/schema/{type}` - Get specific schema

## Testing

### Behavior Tests (No External Dependencies)

```bash
swift test --filter SceneGeneratorTests
swift test --filter LedFXTypesTests
```

Tests pure functions and data types:
- Scene generation logic
- Energy/valence mapping
- Immutability
- JSON serialization

### E2E Tests (Requires LedFX Server)

```bash
swift test --filter LedFXClientTests
```

Tests integration with real LedFX server:
- Connection
- Scene CRUD operations
- Activation/deactivation
- Error handling

Tests skip gracefully if LedFX is unavailable.

## Configuration

### App Settings

Settings are stored in `@AppStorage`:

- `ledfx_enabled` - Enable/disable integration
- `ledfx_baseURL` - LedFX server URL
- `ledfx_virtualIds` - Comma-separated virtual IDs

### Scene Generator Settings

Scene generation is deterministic based on:
- **Energy** (0.0-1.0) - Track intensity
- **Valence** (0.0-1.0) - Mood (negative to positive)
- **BPM** - Beats per minute (optional, affects timing)

## Examples

### Simple Color Flash

```swift
try await ledfx.triggerFlash(color: "#FF0000", hold: 100, fade: 200)
```

### Custom Scene

```swift
let scene = LedFXScene(
    name: "Custom",
    virtuals: [
        "virtual-1": VirtualAction(
            action: .activate,
            type: "strobe",
            config: EffectConfig([
                "speed": .double(5.0),
                "color": .string("#00FF00")
            ])
        )
    ],
    active: false
)

try await module.saveScene(id: "custom", scene: scene)
try await module.activateScene(id: "custom")
```

### Track-Reactive Scene

```swift
// When track changes
let scene = SceneGenerator.generateScene(
    name: currentTrack.title,
    virtualIds: ["virtual-1", "virtual-2"],
    energy: currentTrack.analysis.energy,
    valence: currentTrack.analysis.valence,
    bpm: currentTrack.bpm
)

let sceneId = sanitize(currentTrack.title)
try await module.saveScene(id: sceneId, scene: scene)
try await module.activateScene(id: sceneId)
```

## Design Principles

### Grokking Simplicity

**Data (Immutable):**
- `LedFXScene`, `LedFXVirtual`, `Effect`, etc.
- All structs, no mutation
- `withActive()` style updates

**Calculations (Pure Functions):**
- `SceneGenerator` - No side effects
- Energy/valence mapping
- Color selection algorithms

**Actions (Side Effects):**
- `LedFXClient` - HTTP requests
- `LedFXModule` - Lifecycle management
- SwiftUI views - User interaction

### A Philosophy of Software Design

**Deep Module:**
- `LedFXClient` - Simple interface (10 public methods), hides HTTP complexity
- `LedFXModule` - Simple interface (15 public methods), hides state management

**Narrow Interfaces:**
- Each component exposes minimal surface area
- Clear separation of concerns

**Immutable Data:**
- All domain types are immutable
- Thread-safe by design
- Easy to reason about

## Future Enhancements

- [ ] Preset introspection and selection
- [ ] Schema-based effect configuration UI
- [ ] Real-time scene preview
- [ ] Scene templates library
- [ ] Beat-sync via MIDI clock
- [ ] Multi-zone support
- [ ] Scene transitions/crossfades
- [ ] Integration with Launchpad for manual control
