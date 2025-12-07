# Development Documentation

Implementation plans, future improvements, and development roadmaps for the VJ toolkit.

## Active Development Plans

### Processing System
- **[Processing Implementation Plan](processing-implementation-plan.md)** - Iterative plan for building the complete VJ system
  - Phase 1: Core infrastructure (MIDI, state machine, level interface)
  - Phase 2: Example levels implementation
  - Phase 3: Advanced features and polish
  - Current status and completed phases

- **[Processing Syphon Idea Board](processing-syphon-idea-board.md)** - Visual concept brainstorming
  - Links to 14 modular level files
  - Design patterns and approaches
  - Technical feasibility notes

### Python VJ Stack
- **[Python VJ Refactor Plan](python-vj-refactor-plan.md)** - Architecture improvements
  - Layer boundary implementation
  - Domain/Infrastructure/Services/Orchestration/UI separation
  - Modularization roadmap
  - Testing and enforcement strategies

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
1. **Python VJ Refactor** - Improve maintainability and testability
2. **Processing Implementation** - Complete remaining levels and features
3. **Documentation Updates** - Keep guides in sync with code changes

### Medium Priority
1. **Shader Orchestrator** - Automate shader selection with AI
2. **Pipeline Planner** - Better tracking and visualization
3. **Cross-platform Support** - Windows/Linux compatibility improvements

### Low Priority
1. **Performance Optimization** - Further reduce latency and CPU usage
2. **Additional Visual Effects** - Expand Processing level library
3. **Advanced MIDI Features** - More complex routing and mapping

## Architecture Principles

### Clean Architecture
- **Domain Layer**: Pure data and business logic, no dependencies
- **Infrastructure Layer**: Configuration, state management, platform detection
- **Services Layer**: External integrations (Spotify, AI, audio)
- **Orchestration Layer**: Multi-service coordination, pipelines
- **UI Layer**: Textual console, Processing management

### Dependency Rules
- Inner layers never depend on outer layers
- Dependencies point inward: UI → Orchestration → Services → Infrastructure → Domain
- Interfaces define boundaries between layers
- Testing isolation through dependency injection

### Code Quality Standards
- Type hints for all Python code
- Comprehensive error handling
- No secrets in source code
- Security scanning with CodeQL
- Unit tests for business logic
- Integration tests for pipelines

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

### Unit Tests
- Pure functions in domain layer
- Service adapters with mocks
- Utility functions and helpers

### Integration Tests
- OSC communication pipeline
- Audio analyzer → visualizer flow
- MIDI router state management
- Lyrics fetch → parse → display

### Manual Testing
- Visual verification of Processing sketches
- Live performance scenarios
- MIDI controller interaction
- Syphon output validation

## Tools & Dependencies

### Python Stack
- **Testing**: pytest, pytest-arch for layer enforcement
- **Type Checking**: mypy with strict mode
- **Linting**: ruff for code quality
- **Security**: CodeQL, dependency scanning
- **Documentation**: Sphinx (potential future)

### Processing Stack
- **Libraries**: The MidiBus, Syphon, PixelFlow
- **Testing**: Manual visual verification
- **Build**: Processing IDE or command-line build

### Infrastructure
- **Version Control**: Git with conventional commits
- **CI/CD**: GitHub Actions (potential)
- **Deployment**: Manual for now, automated future

## Contributing Guidelines

### Code Style
- **Python**: Follow PEP 8, use type hints
- **Processing/Java**: Follow Processing conventions
- **GLSL**: Follow Synesthesia SSF patterns
- **Documentation**: Markdown with clear headings

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
2. Implement changes with tests
3. Update documentation
4. Request code review
5. Address feedback
6. Security scan passes
7. Merge to main

## Future Considerations

### Potential Features
- WebSocket support for remote control
- Advanced AI visual generation
- Multi-screen projection mapping
- DMX lighting integration
- Real-time collaboration features

### Technical Debt
- Migrate legacy Processing sketches to new architecture
- Improve test coverage (currently manual-heavy)
- Better error recovery in audio pipeline
- Cross-platform Syphon alternative (NDI?)

### Performance Optimization
- GPU shader optimization
- Reduced OSC message overhead
- Better CPU/GPU load balancing
- Optimized particle systems

## See Also

- [Setup Guides](../setup/) - Installation and configuration
- [Operation Guides](../operation/) - Using in performance
- [Reference Documentation](../reference/) - Technical details
- [Architecture](../architecture/) - System design (when created)
- [Python VJ README](../../python-vj/README.md) - Python stack details
- [Processing README](../../processing-vj/README.md) - Processing projects
