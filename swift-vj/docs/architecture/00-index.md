# SwiftVJ Architecture Documentation - Index

## Overview

This directory contains comprehensive architecture and design documentation for the SwiftVJ project. The documentation is based on factual analysis of the codebase (~20,000 lines of Swift code) and includes improvement recommendations for each area.

**Project:** SwiftVJ - macOS VJ Control Application  
**Language:** Swift 5.9+ (async/await, actors)  
**Platform:** macOS 14.0+ (Sonoma)  
**Architecture:** Functional Core / Imperative Shell, Deep Modules, Actor-Based Concurrency

---

## Documentation Files

### 01. Module Structure
**File:** [01-module-structure.md](./01-module-structure.md)

**Contents:**
- 9 SPM targets (3 executables, 4 libraries, 2 test suites)
- ~70 Swift files organized by layer
- Directory structure and file organization
- Platform requirements and design patterns

**Key Stats:**
- SwiftVJCore: ~13,283 lines (core business logic)
- 6 library targets, 3 executable targets
- BehaviorTests (unit) + E2ETests (integration)

**Who Should Read:** Anyone new to the project, developers planning refactors

---

### 02. Module Dependencies
**File:** [02-module-dependencies.md](./02-module-dependencies.md)

**Contents:**
- SPM target dependency graph (mermaid diagram)
- SwiftVJCore internal module dependencies
- External package dependencies (OSCKit, ArgumentParser, Yams)
- Circular dependency analysis (none found)
- Critical paths and coupling points

**Key Insights:**
- Clear unidirectional dependency flow (domain → adapters → modules → app)
- OSCHub is a shared dependency (potential coupling point)
- 3 external packages, minimal dependencies
- Dependency injection via ModuleRegistry

**Who Should Read:** Architects, developers working on module boundaries

---

### 03. Domain Entities
**File:** [03-domain-entities.md](./03-domain-entities.md)

**Contents:**
- 10+ immutable domain types (`Track`, `LyricLine`, `PlaybackState`, etc.)
- Pure functions (`parseLRC`, `detectRefrains`, `extractKeywords`)
- Entity lifecycle and validation
- Supporting types (rendering state, audio state)

**Key Principles:**
- Immutability (all `struct` with `let` properties)
- `Sendable` conformance for thread safety
- No side effects (functional core)
- Rich type safety (enums with associated values)

**Who Should Read:** All developers, especially those adding domain types

---

### 04. Adapters and Repositories
**File:** [04-adapters-repositories.md](./04-adapters-repositories.md)

**Contents:**
- 9 adapters (~4,047 lines total)
- Deep module pattern implementation
- Error handling strategies
- Service integration (LRCLIB, LM Studio, DuckDuckGo, VDJ, Synesthesia)

**Key Adapters:**
- `OSCHub` - OSC communication (445 lines)
- `LLMClient` - AI analysis (897 lines)
- `ImageScraper` - Image search/cache (733 lines)
- `ShaderMatcher` - Shader selection (646 lines)
- `VDJMonitor` - VDJ OSC parsing (442 lines)

**Who Should Read:** Developers integrating external services, testers

---

### 05. External Dependencies
**File:** [05-external-dependencies.md](./05-external-dependencies.md)

**Contents:**
- 3 SPM packages (OSCKit, ArgumentParser, Yams)
- 12 Apple frameworks (Metal, CoreMIDI, SwiftUI, etc.)
- 1 binary framework (Syphon.xcframework)
- 5 runtime services (LRCLIB, LM Studio, DuckDuckGo, VDJ, Synesthesia)

**Dependency Graph:** Complete mermaid diagram showing all dependencies

**Security:** Recommendations for vulnerability scanning and updates

**Who Should Read:** DevOps, security auditors, deployment engineers

---

### 06. OSC Message Catalog
**File:** [06-osc-messages.md](./06-osc-messages.md)

**Contents:**
- Complete OSC message catalog (sent/received)
- 4 ports: 9999 (receive), 7777 (Synesthesia), 9009 (VDJ), 11111 (Magic)
- Message flow diagrams
- Pattern matching system (PrefixTrie)
- Common OSC workflows

**Message Categories:**
- VDJ playback monitoring (subscriptions + queries)
- Synesthesia commands (shader, image, scene)
- Synesthesia feedback (audio reactive, scene state)
- Launchpad OSC effects
- Magic/Textler metadata

**Who Should Read:** VJ software integrators, OSC protocol users

---

### 07. Architecture Overview
**File:** [07-architecture-overview.md](./07-architecture-overview.md)

**Contents:**
- Architectural layers (domain → adapters → modules → app)
- Core patterns (Functional Core, Deep Modules, Actors, DI)
- Key subsystems (pipeline, Launchpad, OSC, rendering)
- Performance characteristics
- Major improvement recommendations

**Key Patterns:**
- Functional Core / Imperative Shell
- Deep Modules (simple interface, complex implementation)
- Actor-Based Concurrency (thread-safe by design)
- Dependency Injection (ModuleRegistry)
- Repository Pattern (data access abstraction)

**Who Should Read:** Architects, senior developers, technical leads

---

### 08. Data Flow
**File:** [08-data-flow.md](./08-data-flow.md)

**Contents:**
- 6 primary data flows with sequence diagrams
- Data transformations at each step
- Performance characteristics and bottlenecks
- State management patterns
- Cache data flow

**Flows Documented:**
1. Track change detection → Pipeline processing
2. Launchpad button press → Visual effect
3. Audio reactive rendering (60 fps)
4. Manual shader selection
5. VDJ playback position polling
6. Image auto-advance (beat-sync)

**Who Should Read:** Developers debugging issues, performance engineers

---

## Quick Reference

### For New Developers

**Start Here:**
1. [01-module-structure.md](./01-module-structure.md) - Understand the codebase layout
2. [03-domain-entities.md](./03-domain-entities.md) - Learn the domain model
3. [07-architecture-overview.md](./07-architecture-overview.md) - Grasp the big picture

**Then:**
- [02-module-dependencies.md](./02-module-dependencies.md) - Understand module relationships
- [08-data-flow.md](./08-data-flow.md) - Follow a track through the system

---

### For Integrators

**External Service Integration:**
1. [04-adapters-repositories.md](./04-adapters-repositories.md) - Adapter pattern
2. [05-external-dependencies.md](./05-external-dependencies.md) - Service contracts
3. [06-osc-messages.md](./06-osc-messages.md) - OSC protocol details

---

### For Architects

**Architecture Decisions:**
1. [07-architecture-overview.md](./07-architecture-overview.md) - Overall architecture
2. [02-module-dependencies.md](./02-module-dependencies.md) - Coupling analysis
3. All improvement sections in each document

---

### For Testers

**Testing Strategy:**
1. [01-module-structure.md](./01-module-structure.md) - Test targets (BehaviorTests, E2ETests)
2. [03-domain-entities.md](./03-domain-entities.md) - Pure functions to test
3. [04-adapters-repositories.md](./04-adapters-repositories.md) - Adapter testing approach

---

## Documentation Statistics

| Metric | Value |
|--------|-------|
| Total Documents | 9 files (including this index) |
| Total Words | ~80,000+ words |
| Mermaid Diagrams | 8 diagrams |
| Code References | 300+ specific file/function/class names |
| Lines Documented | ~20,000 lines of Swift code |
| Improvement Recommendations | 50+ actionable suggestions |

---

## How to Read This Documentation

### Sequential Reading

**Recommended Order:**
1. **Module Structure** - Get oriented
2. **Domain Entities** - Understand the data model
3. **Architecture Overview** - See the big picture
4. **Module Dependencies** - Understand relationships
5. **Data Flow** - Follow end-to-end flows
6. **Adapters & Repositories** - Dive into external integration
7. **External Dependencies** - Understand the ecosystem
8. **OSC Messages** - Learn the communication protocol

**Time Required:** ~3-4 hours for complete read

---

### Reference Reading

**By Role:**

**Backend Developer:**
- Domain Entities → Adapters → Module Dependencies

**UI Developer:**
- Module Structure → Architecture Overview → Data Flow

**DevOps Engineer:**
- External Dependencies → Module Structure → OSC Messages

**Security Auditor:**
- External Dependencies → Adapters → OSC Messages

---

## Key Architectural Principles

### 1. Functional Core / Imperative Shell

**Functional Core (Domain):**
- Immutable data structures
- Pure functions (no side effects)
- No dependencies

**Imperative Shell (Adapters + Modules):**
- All I/O operations (network, files, OSC, MIDI)
- Actor-based concurrency
- Error handling

**Reference:** [03-domain-entities.md](./03-domain-entities.md), [07-architecture-overview.md](./07-architecture-overview.md)

---

### 2. Deep Modules

**Principle:** Simple public interface, complex hidden implementation

**Examples:**
- `PipelineModule.process(track:)` - Hides 5-step orchestration
- `OSCHub.subscribe(pattern:handler:)` - Hides PrefixTrie routing
- `LyricsFetcher.fetch(artist:title:)` - Hides HTTP + LLM fallback

**Reference:** [04-adapters-repositories.md](./04-adapters-repositories.md), [07-architecture-overview.md](./07-architecture-overview.md)

---

### 3. Actor-Based Concurrency

**All modules and adapters are Swift actors:**
- Thread-safe state management
- Compiler-enforced synchronization
- No manual locks (except OSCHub for OSCKit callbacks)

**Reference:** [02-module-dependencies.md](./02-module-dependencies.md), [07-architecture-overview.md](./07-architecture-overview.md)

---

### 4. No Mocking Philosophy

**Testing Approach:**
- **BehaviorTests:** Pure functions, no external deps
- **E2ETests:** Real services with graceful skipping
- **No Mocks:** Test against actual implementations

**Reference:** [01-module-structure.md](./01-module-structure.md), [04-adapters-repositories.md](./04-adapters-repositories.md)

---

## Major Improvement Recommendations

### Cross-Cutting Concerns

**1. State Management (High Priority)**

**Current:** Callback-based state synchronization, multiple state representations

**Recommended:**
- Adopt unidirectional data flow (TCA-like architecture)
- Single immutable AppState as source of truth
- Actions → Reducer → New State pattern

**Impact:** Easier debugging, time-travel debugging, predictable state transitions

**Documents:** [07-architecture-overview.md](./07-architecture-overview.md), [08-data-flow.md](./08-data-flow.md)

---

**2. OSCHub Refactoring (Medium Priority)**

**Current:** 445-line "god object" with multiple responsibilities

**Recommended:**
- Split into `OSCReceiver`, `OSCSender`, `OSCRouter`
- Protocol-based design for testability
- Separate concerns (lifecycle, routing, forwarding, monitoring)

**Impact:** Testable, smaller focused components, swappable transports

**Documents:** [04-adapters-repositories.md](./04-adapters-repositories.md), [06-osc-messages.md](./06-osc-messages.md)

---

**3. Rendering Engine Extraction (Medium Priority)**

**Current:** RenderEngine tightly coupled to SwiftVJApp

**Recommended:**
- Extract `RenderingKit` SPM library target
- Protocol-based injection
- Support multiple UIs (macOS, iOS, CLI)

**Impact:** Reusable rendering, testable, headless rendering for CLI

**Documents:** [01-module-structure.md](./01-module-structure.md), [07-architecture-overview.md](./07-architecture-overview.md)

---

### Component-Specific

See "Conclusion and Improvement Opportunities" section in each document for detailed, component-specific recommendations.

---

## Contributing to Documentation

### When to Update

**Update documentation when:**
- Adding new modules or targets
- Changing module dependencies
- Adding new domain entities
- Integrating new external services
- Modifying OSC protocol
- Major architectural refactors

---

### Documentation Format

**Each document follows:**
1. **Overview** - High-level summary
2. **Detailed Content** - Core information with code references
3. **Diagrams** - Mermaid diagrams for visual understanding
4. **Conclusion** - Strengths + Improvement opportunities

**Style:**
- 100% factual (based on actual code)
- Reference specific files/functions/classes
- No source code listing (only references)
- Actionable improvement recommendations

---

## Related Documentation

**In This Repository:**
- `/swift-vj/README.md` - Quick start guide
- `/swift-vj/REWRITE_PLAN.md` - Migration plan from Python
- `/swift-vj/docs/LAUNCHPAD_CONFIG_SPEC.md` - Launchpad YAML format
- `/swift-vj/docs/LAUNCHPAD_OSC_LIB_SPEC.md` - Launchpad OSC library
- `/swift-vj/docs/syphon-integration.md` - Syphon setup guide

**Parent Project:**
- `/README.md` - Repository overview
- `/QUICKSTART.md` - Quick start for entire project
- `/OSC.md` - OSC protocol overview
- `/docs/` - Additional documentation

---

## Glossary

**Key Terms:**

- **Actor** - Swift concurrency primitive for thread-safe state management
- **Adapter** - Wrapper for external service (hides protocol details)
- **Deep Module** - Simple interface hiding complex implementation
- **Domain Entity** - Immutable data structure (functional core)
- **Functional Core** - Pure functions with no side effects
- **Imperative Shell** - I/O operations and side effects
- **Module** - High-level orchestrator (implements `Module` protocol)
- **OSC** - Open Sound Control (real-time music/visual protocol)
- **Pipeline** - Track processing workflow (lyrics → AI → shaders → images)
- **Sendable** - Swift protocol for thread-safe types
- **Syphon** - macOS inter-application video sharing
- **VJ** - Video Jockey (visual performance artist)

---

## Change Log

**Version 1.0 (January 2026):**
- Initial comprehensive architecture documentation
- 8 core documents + index
- ~80,000 words, 8 mermaid diagrams
- Based on SwiftVJ codebase as of January 2026
- 100% factual analysis with improvement recommendations

---

## Contact & Feedback

**Documentation Maintainer:** Generated as part of architecture analysis

**Feedback:** Open issues on GitHub for documentation improvements

**Updates:** Documentation should be updated whenever major architectural changes occur

---

## License

This documentation is part of the SwiftVJ project and follows the same license.
