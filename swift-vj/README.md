# Swift-VJ

macOS VJ Control Application - Swift rewrite of python-vj with WLED Sound Reactive support.

## Status: Planning & Foundation

This is a TDD-first rewrite of the Python-based VJ control system. See [REWRITE_PLAN.md](./REWRITE_PLAN.md) for the complete plan.

## Features

- **Audio-reactive visuals**: Real-time audio analysis from Synesthesia via OSC
- **WLED Sound Reactive**: Send audio data to WLED LED controllers (UDP Sound Sync v2)
- **Multi-source playback**: VirtualDJ, Spotify support
- **Lyrics integration**: Fetch and display synchronized lyrics
- **Shader matching**: AI-powered shader selection based on song mood
- **Launchpad control**: MIDI controller integration

## Requirements

- macOS 14+ (Sonoma)
- Xcode 15+ / Swift 5.9+

## Quick Start

```bash
# Build the CLI
swift build

# Run tests (behavior tests - no external deps)
swift test --filter BehaviorTests

# Run E2E tests (requires external services)
swift test --filter E2ETests

# Run the CLI
swift run swift-vj lyrics --artist "Queen" --title "Bohemian Rhapsody" --local
```

## Project Structure

```text
swift-vj/
├── Package.swift              # Swift package manifest
├── REWRITE_PLAN.md            # Complete rewrite plan
├── Sources/
│   ├── SwiftVJ/               # CLI executable
│   │   └── main.swift
│   └── SwiftVJCore/           # Core library
│       ├── Domain/
│       │   ├── Types.swift    # Immutable data types
│       │   └── Functions.swift # Pure functions
│       ├── Infrastructure/
│       │   └── Config.swift   # Settings, config
│       └── Modules/
│           └── Module.swift   # Module protocol
└── Tests/
    ├── BehaviorTests/         # Pure function tests
    └── E2ETests/              # Integration tests
```

## Design Principles

### Grokking Simplicity

- **Data**: Immutable structs (LyricLine, Track, etc.)
- **Calculations**: Pure functions (parseLRC, detectRefrains)
- **Actions**: Isolated side effects (network, file I/O)

### A Philosophy of Software Design

- **Deep Modules**: Simple interfaces hiding complexity
- Each module exposes 2-5 public methods max

### TDD Philosophy

- Test end-to-end behaviors, not implementation details
- No mocking - tests run against real services
- Tests skip gracefully when prerequisites unavailable

## Documentation

- [WLED Sound Reactive Integration](./docs/WLED_INTEGRATION.md) - Complete guide for LED controller support
- [REWRITE_PLAN.md](./REWRITE_PLAN.md) - Architecture and implementation plan
- [CODE_EXAMPLES.md](./CODE_EXAMPLES.md) - Design patterns and examples

## Testing

### Behavior Tests

Pure function tests that require no external dependencies:

```bash
swift test --filter BehaviorTests
```

### E2E Tests

Integration tests that require external services:

```bash
# Check prerequisites
swift test --filter LyricsE2ETests

# Tests skip automatically if services unavailable
```

## Implementation Phases

1. **Foundation** (Current): Domain types, pure functions, config
2. **Adapters**: LyricsFetcher, OSCClient, VDJMonitor
3. **Modules**: OSC, Playback, Lyrics, AI, Shaders, Pipeline
4. **UI**: SwiftUI application shell
5. **MIDI**: Launchpad controller support (optional)

See [REWRITE_PLAN.md](./REWRITE_PLAN.md) for detailed implementation notes.
