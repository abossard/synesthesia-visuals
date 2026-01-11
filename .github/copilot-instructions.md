# Copilot Instructions for synesthesia-visuals

## Project Overview
A VJ performance toolkit combining:
- **Swift-VJ** (`swift-vj/`) - macOS native VJ control application (SwiftUI + Metal rendering)
- **Synesthesia shaders** (`synesthesia-shaders/`) - `.synScene` directories with GLSL + JSON + JS
- **Archived legacy systems** (`archive/`) - Python-VJ and Processing-VJ (deprecated)

## Architecture Principles
This codebase follows **Grokking Simplicity** and **A Philosophy of Software Design** patterns:
- **Domain models** are immutable structs (Swift) or frozen dataclasses (Python)
- **Adapters** are deep modules hiding protocol complexity (2-5 public methods max)
- **Modules** coordinate via dependency injection and protocol-based architecture
- **Pure functions** for calculations with no side effects
- **TDD**: Test behaviors, not implementation; no mocking; skip when prerequisites unavailable

## Repository Structure
\`\`\`
swift-vj/                # macOS VJ control application (current)
  ├── Sources/
  │   ├── SwiftVJApp/    # SwiftUI application + Metal rendering
  │   │   ├── Rendering/ # ShaderTile, TextTiles, Syphon output
  │   │   └── Views/     # Master control, OSC debug, shader browser
  │   ├── SwiftVJCore/   # Core library
  │   │   ├── Domain/    # Pure data types and functions
  │   │   ├── Adapters/  # LyricsFetcher, VDJMonitor, SpotifyMonitor, etc.
  │   │   ├── Modules/   # Playback, Lyrics, AI, Shaders, Pipeline, Launchpad
  │   │   └── Launchpad/ # MIDI controller support
  │   └── SwiftVJ/       # CLI executable (main.swift)
  └── Tests/
      ├── BehaviorTests/ # Pure function tests (no external deps)
      └── E2ETests/      # Integration tests (require services)
synesthesia-shaders/     # SSF scenes (main.glsl, scene.json, script.js)
archive/                 # Deprecated components
  ├── python-vj/         # Legacy Python TUI (archived)
  └── processing-vj/     # Legacy Processing sketches (archived)
\`\`\`

## Swift-VJ Patterns

### Module Protocol (protocol-based architecture)
\`\`\`swift
protocol Module {
    var isStarted: Bool { get }
    func start() async throws
    func stop() async
    func getStatus() -> [String: Any]
}
\`\`\`

### Domain Models (immutable structs)
\`\`\`swift
struct LyricLine: Codable {
    let timeSec: Double
    let text: String
    let isRefrain: Bool
    
    func withRefrain(_ isRefrain: Bool) -> LyricLine {
        LyricLine(timeSec: timeSec, text: text, isRefrain: isRefrain)
    }
}
\`\`\`

### Adapter Pattern (deep modules)
Each adapter hides one external service behind a simple interface:
- \`SpotifyMonitor.getPlayback() async -> PlaybackState?\` - hides AppleScript complexity
- \`VDJMonitor.getPlayback() async -> PlaybackState?\` - hides OSC message parsing
- \`LyricsFetcher.fetch(artist:title:) async -> String?\` - hides LRCLIB + LLM fallback

### OSC Communication
All OSC uses **flat arrays** (no nested structures):
\`\`\`swift
oscClient.send("/karaoke/track", [1, "spotify", artist, title, album, duration, hasLyrics])
oscClient.send("/audio/levels", [subBass, bass, lowMid, mid, highMid, presence, air, rms])
\`\`\`

## Synesthesia Shader (SSF) Conventions

### Key Uniforms (auto-injected, DO NOT declare)
\`\`\`glsl
TIME, RENDERSIZE, PASSINDEX, FRAMECOUNT
_xy (pixel coords), _uv (normalized 0-1), _uvc (aspect-correct)
syn_BassLevel, syn_MidLevel, syn_HighLevel, syn_Level
syn_BassHits, syn_HighHits, syn_BeatTime, syn_BPM
syn_Spectrum (sampler1D), syn_LevelTrail (sampler1D)
\`\`\`

### Control Mapping (scene.json → uniform)
\`\`\`json
{"NAME": "warp_amount", "TYPE": "slider", "MIN": 0.0, "MAX": 1.0, "DEFAULT": 0.3}
\`\`\`

### Audio Reactivity Pattern
\`\`\`glsl
float baseTime = TIME * 0.3;                    // always-moving base
float audioTime = syn_Time * 0.5;               // audio-driven boost
float bassActive = smoothstep(0.3, 0.4, syn_BassHits);  // threshold trigger
\`\`\`

## Processing Game Conventions

> **Note**: Processing-VJ has been archived. These conventions are kept for reference only.
> For new visual rendering, use Swift-VJ's Metal-based shader system.

### Archived Features (see `archive/processing-vj/`)
- VJ games (WhackAMole, CrowdBattle, BuildupRelease)
- VJUniverse shader engine (replaced by Swift-VJ Metal rendering)
- KaraokeOverlay (replaced by Swift-VJ TextTiles)
- Launchpad MIDI control (replaced by Swift-VJ LaunchpadModule)

## Development Workflows

### Swift-VJ Quick Start
\`\`\`bash
cd swift-vj

# Build the application
swift build

# Run behavior tests (no external deps)
swift test --filter BehaviorTests

# Run E2E tests (requires external services)
swift test --filter E2ETests

# Run all tests
make test

# Run the CLI
swift run swift-vj lyrics --artist "Queen" --title "Bohemian Rhapsody" --local

# Build and run the app
swift run SwiftVJApp
# or
make run
\`\`\`

### Code Standards
- **Build**: Run \`make build\` or \`swift build\` before committing
- **Test**: Run \`make test\` or \`swift test\` to run test suite
- **Lint**: Run \`make lint\` (if swiftlint is installed) for code style
- Follow Swift naming conventions (camelCase for variables/functions, PascalCase for types)
- Use \`async/await\` for asynchronous operations, not completion handlers
- Write behavior tests for new functionality (BehaviorTests for pure logic, E2ETests for integration)

### Shader Development
\`\`\`bash
# Show shader analysis statistics
make stats

# Delete .error.json files (allows re-analysis)
make clean-errors

# Find black/broken shaders from screenshots
make find-black
\`\`\`

### Testing Shaders
1. Copy \`.synScene/\` to Synesthesia custom library folder
2. Reload library in Synesthesia
3. Use Stats overlay to verify performance

### Live Rig Audio Routing (macOS)
- Install BlackHole for audio loopback
- Create Multi-Output Device (speakers + BlackHole)
- Set Synesthesia audio input to BlackHole
- Swift-VJ receives OSC from Synesthesia on port 9999

## Key Files Reference
- [swift-vj/README.md](../swift-vj/README.md) - Swift-VJ documentation and quick start
- [swift-vj/REWRITE_PLAN.md](../swift-vj/REWRITE_PLAN.md) - Complete architecture and feature inventory
- [swift-vj/CODE_EXAMPLES.md](../swift-vj/CODE_EXAMPLES.md) - Design patterns and code samples
- [PYTHON_PROCESSING_TO_SWIFT_MIGRATION.md](../PYTHON_PROCESSING_TO_SWIFT_MIGRATION.md) - Migration guide and feature parity
- [docs/reference/isf-to-synesthesia-migration.md](../docs/reference/isf-to-synesthesia-migration.md) - Shader conversion guide
- [docs/setup/live-vj-setup-guide.md](../docs/setup/live-vj-setup-guide.md) - Full Syphon/Magic pipeline
- [OSC.md](../OSC.md) - OSC architecture and message formats
- [OSC_FUTURE_PLAN.md](../OSC_FUTURE_PLAN.md) - Planned OSC evolution
