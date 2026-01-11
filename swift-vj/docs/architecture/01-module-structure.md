# SwiftVJ Module Structure

## Overview

SwiftVJ is organized as a Swift Package Manager (SPM) project with multiple targets providing different executables and libraries. The package follows a layered architecture with clear separation between domain logic, infrastructure, and UI concerns.

**Package Definition:** `Package.swift`

## Targets

### Executable Targets

#### 1. SwiftVJ (CLI)
- **Path:** `Sources/SwiftVJ/`
- **Type:** Executable
- **Purpose:** Command-line interface for standalone module execution and testing
- **Entry Point:** `Sources/SwiftVJ/main.swift`
- **Dependencies:** 
  - SwiftVJCore
  - ArgumentParser
- **Key Files:**
  - `main.swift` - CLI command definitions using ArgumentParser
- **Subcommands:**
  - `lyrics` - Fetch and parse lyrics (uses `LyricsFetcher`, `parseLRC`, `analyzeLyrics`)
  - `launchpad-test` - Interactive hardware tests (uses `runLaunchpadInteractiveTests`)
  - `launchpad-e2e` - End-to-end guided tests (uses `runLaunchpadE2ETest`)

#### 2. SwiftVJApp (macOS GUI)
- **Path:** `Sources/SwiftVJApp/`
- **Type:** Executable (SwiftUI App)
- **Purpose:** Full-featured macOS VJ control application with rendering and Syphon output
- **Entry Point:** `Sources/SwiftVJApp/SwiftVJApp.swift`
- **Dependencies:**
  - SwiftVJCore
  - SyphonKit (for video output)
- **Key Components:**
  - `SwiftVJApp.swift` - App entry point and app state management (`AppState`)
  - `ContentView.swift` - Main application window
  - `MasterControlView.swift` - Master VJ control panel
  - `PipelineStatusView.swift` - Real-time pipeline monitoring
  - `LaunchpadView.swift` - Launchpad controller visualization
  - `ShaderBrowserView.swift` - Shader selection and preview
  - `OSCDebugView.swift` - OSC message monitoring
  - `LogViewerView.swift` - Application logs
  - `SettingsView.swift` - Configuration settings
  - **Rendering/** - VJ rendering engine
    - `RenderEngine.swift` - Core rendering coordinator
    - `HeadlessRenderer.swift` - Offscreen Metal rendering
    - `AudioProcessor.swift` - Audio reactive visualization
    - `StateManagers.swift` - Shader, image, and lyrics state managers
    - `SyphonOutput.swift` - Syphon video output
    - `RenderingViews.swift` - SwiftUI preview views
    - `RenderingTypes.swift` - Rendering data types

#### 3. ShaderCompile (CLI Tool)
- **Path:** `Sources/ShaderCompile/`
- **Type:** Executable
- **Purpose:** Compile GLSL shaders to Metal shader library
- **Entry Point:** `Sources/ShaderCompile/ShaderCompile.swift`
- **Dependencies:**
  - ShadertoyRuntime
  - ArgumentParser

### Library Targets

#### 4. SwiftVJCore (Core Library)
- **Path:** `Sources/SwiftVJCore/`
- **Type:** Library
- **Purpose:** Core business logic, domain models, adapters, and modules
- **Dependencies:**
  - OSCKit (OSC communication)
  - Yams (YAML parsing for config)
- **Structure:**
  - **Domain/** - Immutable domain entities and pure functions
    - `Types.swift` - Core domain types (`LyricLine`, `Track`, `PlaybackState`, `SongCategories`, `PipelineResult`, `ShaderInfo`, etc.)
    - `Functions.swift` - Pure functions (LRC parsing, refrain detection)
    - `Phase.swift` - DJ set phases (warmup, buildup, peak, breakdown, cooldown, outro)
    - `ActiveLineTracker.swift` - Karaoke line timing
    - `TextlerOrchestrator.swift` - Textler animation coordination
  - **Adapters/** - External service wrappers (deep modules)
    - `LyricsFetcher.swift` - LRCLIB API client with LLM fallback
    - `LLMClient.swift` - LM Studio integration for AI analysis
    - `SpotifyMonitor.swift` - Spotify playback monitoring
    - `VDJMonitor.swift` - VirtualDJ OSC monitoring
    - `OSCClient.swift` - OSC hub (send/receive, subscription, forwarding)
    - `ShaderRepository.swift` - Shader metadata loading
    - `ShaderMatcher.swift` - AI-powered shader selection
    - `ImageScraper.swift` - DuckDuckGo image search with caching
    - `SynesthesiaAudioProcessor.swift` - Audio reactive data from Synesthesia OSC
  - **Modules/** - High-level orchestrators (actor-based)
    - `Module.swift` - Base protocol for all modules
    - `ModuleRegistry.swift` - Dependency injection and lifecycle management
    - `PlaybackModule.swift` - Track detection with source switching
    - `LyricsModule.swift` - Lyrics fetching and parsing
    - `AIModule.swift` - Song analysis via LLM
    - `ShadersModule.swift` - Shader loading and matching
    - `ImagesModule.swift` - Image search and caching
    - `PipelineModule.swift` - Full track processing pipeline
  - **Launchpad/** - MIDI controller support
    - `LaunchpadModule.swift` - Top-level Launchpad coordinator
    - `MIDIManager.swift` - CoreMIDI integration (Launchpad Mini MK3)
    - `LaunchpadFSM.swift` - Finite state machine for button logic
    - `LaunchpadDisplay.swift` - LED visualization logic
    - `EffectExecutor.swift` - OSC effect execution
    - `LaunchpadTypes.swift` - Button IDs, colors, modes, commands
    - `LaunchpadYAMLConfig.swift` - YAML-based pad configuration
    - `LaunchpadE2ETest.swift` - End-to-end testing framework
    - `LaunchpadInteractiveTests.swift` - Interactive hardware test suite
  - **Rendering/** - Display state types (for SwiftVJApp)
    - `DisplayStates.swift` - UI state models (lyrics, refrain, song info, images, shaders)
    - `AudioState.swift` - Audio reactive data types
  - **Infrastructure/** - Configuration and utilities
    - `Config.swift` - Global settings, service health monitoring, backoff policy
    - `PrefixTrie.swift` - Efficient OSC pattern matching
- **Resources:**
  - `Resources/launchpad-config.yaml` - Default Launchpad mapping

#### 5. ShadertoyRuntime (GLSL → Metal)
- **Path:** `Sources/ShadertoyRuntime/`
- **Type:** Library
- **Purpose:** Runtime compilation and execution of GLSL Shadertoy shaders on Metal
- **Dependencies:**
  - Metal framework
  - MetalKit framework
  - CoreGraphics framework
- **Key Files:**
  - `ShadertoyRuntime.swift` - Public API
  - `GLSLWrapperGenerator.swift` - GLSL to Metal MSL conversion
  - `ShaderCompilationPipeline.swift` - Metal shader compilation
  - `ShadertoyRenderer.swift` - Metal rendering pipeline
  - `ShadertoyUniforms.swift` - Uniform buffer management
  - `ShadertoyBindings.swift` - Texture and buffer bindings
  - `ShadertoyView.swift` - SwiftUI/NSView integration
  - `ShaderMetadata.swift` - Shader metadata types
  - `ShaderDiagnostics.swift` - Compilation error handling

#### 6. SyphonKit (Video Output)
- **Path:** `Sources/SyphonKit/`
- **Type:** Library
- **Purpose:** Swift wrapper for Syphon framework (macOS inter-app video sharing)
- **Dependencies:**
  - Syphon (binary framework)
  - Metal framework
  - IOSurface framework
  - OpenGL framework
- **Key Files:**
  - `SyphonKit.swift` - Public API
  - `SyphonSender.swift` - Send Metal textures to Syphon
  - `SyphonReceiver.swift` - Receive Syphon frames

### Binary Targets

#### 7. Syphon
- **Path:** `Frameworks/Syphon.xcframework`
- **Type:** Binary xcframework
- **Purpose:** Syphon framework for inter-application video sharing on macOS

### Test Targets

#### 8. BehaviorTests
- **Path:** `Tests/BehaviorTests/`
- **Type:** Test suite
- **Purpose:** Pure function tests with no external dependencies
- **Dependencies:** SwiftVJCore, Yams
- **Test Files:**
  - `LRCParsingTests.swift` - LRC parsing validation
  - `RefrainDetectionTests.swift` - Lyrics refrain detection
  - `DomainTypesTests.swift` - Immutable domain types
  - `InfrastructureTests.swift` - Config and utilities
  - `PrefixTrieTests.swift` - OSC pattern matching
  - `ModuleTests.swift` - Module lifecycle
  - `LaunchpadConfigTests.swift` - YAML config parsing
  - `LaunchpadYAMLConfigTests.swift` - Advanced config tests
  - `ShaderMatcherTests.swift` - Shader selection algorithm
  - `ImageScraperTests.swift` - Image search and caching
  - `LLMClientTests.swift` - AI analysis (mocked)
  - `TextlerOrchestratorTests.swift` - Textler animation
  - `ActiveLineTrackerTests.swift` - Karaoke timing
  - `RenderingTests.swift` - Display state logic
  - `ShadersModuleTests.swift` - Shader loading
  - `ImagesModuleTests.swift` - Image fetching
  - `SettingsTests.swift` - Configuration persistence

#### 9. E2ETests
- **Path:** `Tests/E2ETests/`
- **Type:** Integration test suite
- **Purpose:** Tests requiring external services (skip if unavailable)
- **Dependencies:** SwiftVJCore
- **Test Files:**
  - `Prerequisites.swift` - Service availability checks
  - `LyricsE2ETests.swift` - LRCLIB API integration
  - `PlaybackE2ETests.swift` - VDJ/Spotify integration

## Module Size Metrics

**Total Swift Files:** ~70 files
**SwiftVJCore Lines of Code:** ~13,283 lines

## Directory Structure Summary

```
swift-vj/
├── Package.swift                      # SPM manifest
├── Sources/
│   ├── SwiftVJ/                       # CLI executable
│   ├── SwiftVJApp/                    # macOS GUI app
│   ├── SwiftVJCore/                   # Core business logic
│   ├── ShadertoyRuntime/              # GLSL shader runtime
│   ├── SyphonKit/                     # Syphon video wrapper
│   └── ShaderCompile/                 # Shader compilation tool
├── Tests/
│   ├── BehaviorTests/                 # Pure function tests
│   └── E2ETests/                      # Integration tests
├── Frameworks/
│   └── Syphon.xcframework             # Binary framework
└── docs/
    ├── LAUNCHPAD_CONFIG_SPEC.md
    ├── LAUNCHPAD_OSC_LIB_SPEC.md
    ├── syphon-integration.md
    └── architecture/                  # This documentation
```

## Platform Requirements

- **macOS:** 14.0+ (Sonoma)
- **iOS:** 17.0+ (required by OSCKit, though project targets macOS only)
- **Swift:** 5.9+
- **Xcode:** 15+

## Key Design Patterns

1. **Actor-Based Concurrency** - All modules are Swift actors for thread-safe state management
2. **Deep Modules** - Simple public interfaces hiding implementation complexity
3. **Immutable Domain Models** - Value types with pure functions (Grokking Simplicity)
4. **Dependency Injection** - ModuleRegistry coordinates lifecycle and dependencies
5. **No Mocking** - Tests use real services with graceful skipping when unavailable

## Conclusion and Improvement Opportunities

### Strengths
- Clear separation between CLI, GUI, and core library
- Well-defined module boundaries using SPM targets
- Consistent naming conventions
- Test isolation (behavior vs. e2e)

### Areas for Improvement

1. **Module Coupling:**
   - SwiftVJApp directly creates and manages all modules - consider extracting to a dedicated `AppCoordinator` in SwiftVJCore
   - AppState in SwiftVJApp has 900+ lines - split into smaller, focused state managers
   - RenderEngine is tightly coupled to AppState - could use protocol-based injection

2. **Single Source of Truth:**
   - Multiple state representations exist (AppState @Published vars vs Module actor state)
   - Consider using a unidirectional data flow architecture (like TCA or similar)
   - State synchronization relies on callbacks - could use Combine publishers instead

3. **Testability:**
   - RenderEngine and Rendering/ components lack dedicated tests
   - SwiftVJApp has no tests - consider extracting view models for testing
   - E2E tests could benefit from a test harness in SwiftVJCore

4. **Module Boundaries:**
   - Launchpad code is in SwiftVJCore but logically could be its own SPM target
   - ShadertoyRuntime is independent - good separation
   - Consider splitting Rendering/ into a RenderingKit library target

5. **Documentation:**
   - Most files have good header comments but lack inline documentation
   - Public APIs need DocC documentation comments
   - Missing architecture decision records (ADRs)
