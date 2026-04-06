# Copilot Instructions for synesthesia-visuals

## Project Overview
A live VJ/lighting performance toolkit combining:
- **Swift-VJ** (`swift-vj/`) — macOS VJ control app (SwiftUI + Metal rendering), optional central hub
- **QLC+** — DMX lighting control (`.qxw` workspaces in project root)
- **Magic Music Visuals** — visual engine with ISF shaders (`magic/`)
- **LedFX** — audio-reactive LED strip effects via WLED
- **sACN_ledfx_bridge** — QLC+ → LedFX scene bridge via E1.31/sACN
- **musicky** — music library tagging tool for DJ phase preparation
- **Archived** (`archive/`) — Python-VJ and Processing-VJ (deprecated, do not modify)

## Live Rig Signal Flow
```
VirtualDJ ──OS2L──► QLC+5 ──DMX──► fixtures (Hero Spot, Thunderwash, Hazer)
           ──OS2L──► SwiftVJApp (optional) ──Syphon──► Magic
                     QLC+5 ──sACN──► sACN_ledfx_bridge ──REST──► LedFX ──► WLED strips
                     Magic ──OSC(:7700)──► QLC+5 (audio-reactive lighting)
```

Key ports: OS2L `9996`/`9997`, OSC `7700`/`9010`/`11111`, LedFX REST `8888`, sACN `5568`

## Architecture Principles
This codebase follows **Grokking Simplicity** and **A Philosophy of Software Design**:
- **Domain models** are immutable structs (Swift) or frozen dataclasses (Python)
- **Adapters** are deep modules hiding protocol complexity (2-5 public methods max)
- **Pure functions** for calculations with no side effects
- **"Define errors out of existence"** — design APIs so error cases can't happen, don't add error handling
- **TDD**: Test behaviors, not implementation; no mocking; skip when prerequisites unavailable

## Build, Test, Lint

### Swift-VJ
```bash
cd swift-vj

swift build                              # Build all targets
swift test --filter BehaviorTests        # Pure function tests (no external deps)
swift test --filter BehaviorTests/StoreTests/testSelectShader  # Single test
swift test --filter E2ETests             # Integration tests (require services)
make test                                # All tests
make lint                                # SwiftLint (if installed)
swift run SwiftVJApp                     # Run the GUI app
swift run swift-vj runtime-shader --file Shaders/glsl/acidsphere.txt  # PoC: runtime shader compilation
```

### Shaders
```bash
make stats          # Shader analysis statistics
make clean-errors   # Delete .error.json files
make find-black     # Find broken shaders from screenshots
```

## Swift-VJ Architecture (UDF / Redux Pattern)

### Data Flow (strict unidirectional)
```
User/System Event → AppAction → Reducer (pure) → State → View
                                    ↓
                               Effect (async) → EffectEnvironment → side effects
```

- **Views** dispatch actions only — never call modules directly
- **Reducers** are pure: synchronous state mutations, return `Effect` for side effects
- **Effects** execute via `EffectEnvironment` dependency injection (closures set in app layer)
- **Store sends** must happen on `@MainActor`; hop to main from MIDI/OSC/background callbacks

### Module Protocol
```swift
protocol Module {
    var isStarted: Bool { get }
    func start() async throws
    func stop() async
    func getStatus() -> [String: Any]
}
```

### Key Layers
| Layer | Location | Responsibility |
|-------|----------|---------------|
| Domain | `SwiftVJCore/Domain/` | Pure data types, calculations |
| Adapters | `SwiftVJCore/Adapters/` | Deep modules hiding external services |
| Modules | `SwiftVJCore/Modules/` | Orchestration (Playback, Lyrics, AI, Shaders, Pipeline) |
| Store | `SwiftVJCore/Store/` | AppState, Actions, Reducer, Effects, EffectEnvironment |
| App | `SwiftVJApp/` | SwiftUI views, Metal rendering, Syphon, wiring |

### Runtime Shader Compilation
Shaders can compile at runtime without Xcode via `ShaderPipelineProvider`:
```
GLSL source → ShaderCompiler.compileToMSL() → glslangValidator → spirv-cross → MSL
→ device.makeLibrary(source:) → MTLRenderPipelineState
```
Requires only Homebrew tools: `brew install glslang spirv-cross`

### Rendering Pipeline
- `ShaderPipelineProvider` (actor) — single method: `pipeline(for:) async → MTLRenderPipelineState?`
  - Resolves: cache → metallib → runtime GLSL compile
- `RenderEngine` — 60fps headless timer, atomic lock state passing between MainActor and render thread
- `ShaderRenderer.setPipeline(_:name:)` — can't fail, just swaps pipeline state

### New Feature Checklist
1. Add/extend action(s) in `Actions.swift`
2. Handle in reducer (pure state mutation only)
3. Return `Effect` for side effects → implement in `EffectEnvironment`
4. Views dispatch actions only
5. Add behavior tests + stress test

## ISF Shader Conventions (`magic/**/*.fs`)

See `.github/instructions/magic-isf-shaders.instructions.md` for full rules. Critical:
- GLSL 1.20-style (OpenGL 2.1 legacy profile)
- Use `texture2D()` not `texture()`, `gl_FragColor` for output
- No `uint`, no bitwise ops, no `tanh/sinh/cosh` (add `_tanh` polyfill)
- `max()`/`min()`/`clamp()` — float overloads only, cast with `float()`
- ISF auto-declares `TIME`, `RENDERSIZE`, `PASSINDEX`, `isf_FragNormCoord` — do NOT redeclare

## OSC Communication
All OSC uses **flat arrays** (no nested structures):
```swift
oscClient.send("/karaoke/track", [1, "spotify", artist, title, album, duration, hasLyrics])
oscClient.send("/audio/levels", [subBass, bass, lowMid, mid, highMid, presence, air, rms])
```

## Key Files Reference
- [docs/setup/SHOW_CHECKLIST.md](docs/setup/SHOW_CHECKLIST.md) — Complete show setup from zero to live
- [brief/DJ_PHASE_GUIDE.md](brief/DJ_PHASE_GUIDE.md) — Phase design, fixture inventory, scene mapping
- [docs/setup/qlcplus-detailed-setup.md](docs/setup/qlcplus-detailed-setup.md) — QLC+ from scratch
- [docs/setup/magic-detailed-setup.md](docs/setup/magic-detailed-setup.md) — Magic audio FFT + OSC
- [docs/setup/sacn-ledfx-bridge-setup.md](docs/setup/sacn-ledfx-bridge-setup.md) — sACN bridge setup
- [OSC.md](OSC.md) — OSC architecture and message formats
- [AGENTS.md](AGENTS.md) — UDF architecture rules for AI agents
