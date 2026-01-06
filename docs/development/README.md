# Development Documentation

Implementation plans, future improvements, and development roadmaps for the VJ toolkit.

## Active Development Plans

### Swift-VJ System (Current)
- **[Swift-VJ Rewrite Plan](../../swift-vj/REWRITE_PLAN.md)** - Complete architecture and implementation roadmap
  - Domain types and pure functions (Phase 1 ✅)
  - Adapters for external services (Phase 2 ✅)
  - Modules layer with business logic (Phase 3 ✅)
  - SwiftUI application shell (Phase 4 ✅)
  - Launchpad MIDI controller (Phase 5 ✅)
  - Process management (Phase 6 - not started)
  - Advanced OSC features (Phase 7 - not started)
  - CLI tools (Phase 8 - not started)

- **[Swift-VJ Code Examples](../../swift-vj/CODE_EXAMPLES.md)** - Design patterns and best practices
  - Immutable data types
  - Pure functions
  - Adapter pattern
  - Module lifecycle
  - TDD approach

### Archived Development Plans

> **⚠️ ARCHIVED:** The following plans are for archived Python-VJ and Processing-VJ systems.

- **[Processing Implementation Plan](processing-implementation-plan.md)** - Archived plan for Processing VJ system
  - System completed and archived 2026-01-05
  - Replaced by Swift-VJ Metal rendering

- **[Processing Syphon Idea Board](processing-syphon-idea-board.md)** - Archived visual concepts
  - 14 modular level implementations preserved in archive
  - Reference for Swift-VJ shader tile ideas

- **[Python VJ Refactor Plan](python-vj-refactor-plan.md)** - Archived architecture improvements
  - Completed and superseded by Swift-VJ rewrite
  - Clean architecture principles carried forward to Swift-VJ

### Shader Pipeline
- **[Shader Orchestrator Implementation Plan](shader-orchestrator-implementation-plan.md)** - AI-powered shader selection
  - Local AI (Gemma-3) with RAG over shader metadata
  - OSC announcements to VJUniverse
  - ChromaDB integration
  - Filesystem strategy

### Pipeline Improvements
- **[Pipeline Planner Improvements](pipeline-planner-improvements.md)** - Future enhancements for pipeline tracking
  - Task planner concept
  - Lifecycle hooks and state management
  - UI improvements for pipeline visualization
  - Better progress tracking

## Development Priorities

### High Priority
1. **Swift-VJ Advanced Features** - Complete remaining phases (process management, advanced OSC)
2. **Metal Shader Optimization** - Performance tuning for 60+ fps
3. **Documentation Updates** - Keep guides in sync with Swift-VJ

### Medium Priority
1. **Shader Orchestrator** - Integrate with Swift-VJ shader module
2. **Cross-platform Support** - Explore Windows/Linux compatibility
3. **Additional Swift-VJ Modules** - Expand functionality

### Low Priority
1. **CLI Tools** - Swift-VJ command-line interfaces
2. **Advanced MIDI Features** - Bank system for Launchpad
3. **WebSocket Integration** - Remote control capabilities

## Architecture Principles

### Swift-VJ Clean Architecture
- **Domain Layer**: Immutable data types (structs), pure functions
- **Infrastructure Layer**: Config, Settings, ServiceHealth, Cache
- **Adapters Layer**: External service integration (LyricsFetcher, OSCHub, VDJMonitor, etc.)
- **Modules Layer**: Business logic with lifecycle (Playback, Lyrics, AI, Shaders, etc.)
- **UI Layer**: SwiftUI application and Metal rendering

### Design Patterns (from A Philosophy of Software Design)
- **Deep Modules**: Simple interfaces (2-5 public methods max)
- **Information Hiding**: Complex protocol details hidden in adapters
- **General-Purpose Design**: Reusable components, not one-off solutions

### Functional Principles (from Grokking Simplicity)
- **Data**: Immutable frozen dataclasses/structs
- **Calculations**: Pure functions with no side effects
- **Actions**: Isolated side effects (network, file I/O, OSC)

### Dependency Rules
- Inner layers never depend on outer layers
- Dependencies point inward: UI → Modules → Adapters → Infrastructure → Domain
- Actors for thread safety in modules
- AsyncStream for events instead of closures

### Code Quality Standards
- **Type Safety**: Swift's type system enforces correctness
- **Comprehensive Error Handling**: Result types and throwing functions
- **No Secrets**: Never commit credentials or API keys
- **Security Scanning**: CodeQL for vulnerability detection
- **Test Coverage**: 197 tests with TDD approach (behavior tests + E2E tests)
- **Documentation**: Inline docs and comprehensive README files

## Development Workflow

### For New Features
1. **Plan**: Create implementation plan document
2. **Design**: Identify affected layers and boundaries
3. **Implement**: Build incrementally with tests
4. **Review**: Code review and security scan
5. **Document**: Update relevant guides
6. **Integrate**: Merge to main and deploy

### For Bug Fixes
1. **Reproduce**: Create failing test case
2. **Isolate**: Identify root cause and affected layers
3. **Fix**: Minimal change to resolve issue
4. **Verify**: Ensure tests pass, no regressions
5. **Document**: Update troubleshooting guides if needed

### For Refactoring
1. **Measure**: Establish baseline (performance, complexity)
2. **Plan**: Document scope and approach
3. **Refactor**: Incremental changes with tests
4. **Verify**: No behavior changes, improved metrics
5. **Clean**: Remove dead code, update docs

## Testing Strategy

### Behavior Tests (No External Dependencies)
- Pure function tests (LRC parsing, refrain detection, keyword extraction)
- Domain type validation
- Settings and configuration
- FSM state transitions

### E2E Tests (Integration Tests)
- Lyrics fetching from LRCLIB API (skips if service unavailable)
- OSC send/receive (skips if ports unavailable)
- Playback monitoring (Spotify/VDJ - skips if not running)
- LLM client (LM Studio/OpenAI - skips if not available)
- Shader matching (requires shader analysis files)

### Manual Testing
- SwiftUI application UI/UX
- Metal shader rendering output
- Syphon integration with VJ software
- Launchpad MIDI interaction
- Live performance scenarios

## Tools & Dependencies

### Swift Stack
- **Testing**: XCTest with TDD approach, behavior tests + E2E tests
- **Type Safety**: Swift 5.9+ type system with Sendable protocol
- **Linting**: SwiftLint (potential future)
- **Security**: CodeQL, dependency scanning
- **Package Manager**: Swift Package Manager

### Rendering Stack
- **Graphics**: Metal for GPU-accelerated shader rendering
- **UI**: SwiftUI for native macOS interface
- **Frame Sharing**: Syphon for VJ software integration
- **MIDI**: CoreMIDI for device discovery and communication

### Infrastructure
- **Version Control**: Git with conventional commits
- **CI/CD**: GitHub Actions (potential)
- **Deployment**: Manual for now, automated future

## Contributing Guidelines

### Code Style
- **Swift**: Follow Swift API Design Guidelines
- **GLSL**: Follow Synesthesia SSF patterns
- **Documentation**: Markdown with clear headings
- **Comments**: Minimal, prefer self-documenting code

### Commit Messages
```
type(scope): brief description

- Detailed explanation of changes
- Why the change was necessary
- Any breaking changes or migration notes

Types: feat, fix, docs, style, refactor, test, chore
```

### Pull Request Process
1. Create feature branch from main
2. Implement changes with tests (behavior tests + E2E tests)
3. Update documentation
4. Request code review
5. Address feedback
6. Security scan passes
7. Merge to main

## Future Considerations

### Potential Features
- WebSocket support for remote control
- Advanced AI visual generation (integration with LLM for real-time shader generation)
- Multi-screen projection mapping
- DMX lighting integration via Swift-VJ
- Real-time collaboration features

### Technical Improvements
- Complete Phase 6: Process management (if needed for external tools)
- Complete Phase 7: Advanced OSC features (prefix trie, drop detection, latency monitoring)
- Complete Phase 8: CLI tools for standalone module testing
- Cross-platform support (Windows/Linux via cross-compilation)

### Performance Optimization
- Metal shader compilation caching
- Reduced OSC message overhead
- Better CPU/GPU load balancing
- Optimized texture uploads

## See Also

- [Setup Guides](../setup/) - Installation and configuration
- [Operation Guides](../operation/) - Using in performance
- [Reference Documentation](../reference/) - Technical details
- [Swift-VJ Documentation](../../swift-vj/README.md) - Swift VJ stack details
- [Migration Guide](../../PYTHON_PROCESSING_TO_SWIFT_MIGRATION.md) - Python-VJ/Processing-VJ to Swift-VJ
- [Archived Components](../../archive/README.md) - Legacy Python and Processing systems
