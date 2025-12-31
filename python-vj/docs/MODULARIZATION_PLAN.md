# Python-VJ Modularization Plan

> **Goal:** Transform python-vj into a modular architecture where each module works standalone, following "Grokking Simplicity" (functional core, imperative shell) and "A Philosophy of Software Design" (narrow and deep modules).

---

## Architecture Vision

```
vj_console.py (Thin Shell)
    │
    ├── modules/osc_runtime.py      (standalone)
    ├── modules/playback.py         (standalone)
    ├── modules/lyrics.py           (standalone)
    ├── modules/ai_analysis.py      (standalone)
    ├── modules/shaders.py          (standalone)
    └── modules/pipeline.py         (orchestrates lyrics → ai → shaders)
```

**Principles:**
- Console is thin shell: composes modules, manages lifecycle, renders UI
- Each module has single responsibility (narrow) and hides complexity (deep)
- Modules can run standalone via CLI for testing/debugging
- No global singletons - modules are injected

---

## Testing Philosophy

**We test actual behavior, not implementation details.**

- **NO mocks** - tests run against real services
- **NO coverage requirements** - we care about behavior, not lines
- **NO whitebox tests** - we don't test internals
- **Interactive prerequisites** - tests prompt user to set up environment, then press Enter
- **High-value tests** - each test verifies meaningful user-facing behavior

### Interactive Test Flow

Tests that require external services prompt the user:

```
=== Test: Track detection from VDJ ===
Requirements:
  - VirtualDJ running
  - Music playing on Deck 1

Press Enter when ready (or 's' to skip)...
```

This ensures:
- User knows exactly what's needed
- Tests run against real, controlled conditions
- No silent failures or confusing skips

---

## Phases

| Phase | Focus | Outcome |
|-------|-------|---------|
| 0 | Foundation | Test infrastructure with prerequisite checking |
| 1 | OSC Runtime Module | Standalone OSC, no global singleton |
| 2 | Playback Module | Standalone playback with callbacks |
| 3 | Lyrics Module | Standalone fetch + sync |
| 4 | AI Analysis Module | Standalone categorization with graceful degradation |
| 5 | Shaders Module | Standalone shader matching |
| 6 | Pipeline Module | Orchestrates modules 3-5 |
| 7 | Console Refactor | Thin shell that composes modules |
| 8 | Cleanup | Remove deprecated code |

---

## Phase 0: Foundation ✅

### Tasks

- [x] Create `tests/conftest.py` with prerequisite fixtures (`requires_vdj_running`, `requires_lm_studio`, etc.)
- [x] Create `tests/test_baseline_behavior.py` with E2E tests for current system
- [x] Create `Makefile` with test targets

### E2E Tests

| Test | Prerequisites | Verifies |
|------|---------------|----------|
| OSC hub sends/receives messages | OSC ports free | Basic OSC works |
| Detect playing track from VDJ | VDJ running + playing | VDJ integration works |
| Playback monitor receives position updates | VDJ running | Position tracking works |
| Fetch lyrics for known song | Internet | LRCLIB API works |
| Full pipeline processes track | VDJ playing | End-to-end flow works |
| AI categorizes song | LM Studio running | AI integration works |

### Quality Gate

All baseline tests pass (or skip gracefully when services unavailable).

---

## Phase 1: OSC Runtime Module ✅

### Tasks

- [x] Create `modules/base.py` with `Module` base class
- [x] Create `modules/osc_runtime.py` wrapping existing `osc/hub.py`
- [x] Add configuration dataclass for ports
- [x] Add standalone CLI: `python -m modules.osc_runtime`
- [x] Console can use module (backward compatible - module available, global singleton still works)

### E2E Tests

| Test | Prerequisites | Verifies |
|------|---------------|----------|
| Module starts and stops cleanly | OSC ports free | Lifecycle works |
| Module receives VDJ responses | VDJ running | Real OSC communication |
| Module sends to VJUniverse | VJUniverse running | Sending works |

### Quality Gate

Module runs standalone and communicates with VDJ.

---

## Phase 2: Playback Module

### Tasks

- [ ] Create `modules/playback.py` wrapping `PlaybackCoordinator` + monitors
- [ ] Expose callbacks: `on_track_change`, `on_position_update`
- [ ] Support hot-swap of playback source
- [ ] Add standalone CLI: `python -m modules.playback --source vdj_osc`

### E2E Tests

| Test | Prerequisites | Verifies |
|------|---------------|----------|
| Detects playing track from VDJ | VDJ playing | Track detection works |
| Track change callback fires | VDJ playing | Callbacks work |
| Position updates while playing | VDJ playing | Position tracking works |
| Source hot-swap works | VDJ running | Can switch sources |
| Detects track from Spotify | Spotify playing | Spotify integration works |

### Quality Gate

Module detects track and position from VDJ in real-time.

---

## Phase 3: Lyrics Module

### Tasks

- [ ] Create `modules/lyrics.py` wrapping `LyricsFetcher` + sync logic
- [ ] Expose `fetch(artist, title)` and `update_position(sec)`
- [ ] Expose callback: `on_active_line`
- [ ] Add standalone CLI: `python -m modules.lyrics --artist "..." --title "..."`

### E2E Tests

| Test | Prerequisites | Verifies |
|------|---------------|----------|
| Fetches synced lyrics for popular song | Internet | LRCLIB works |
| Lyrics have valid timing | Internet | Timing parsed correctly |
| Handles song without lyrics | Internet | Graceful degradation |
| Caching works | Internet | Second fetch faster |
| Active line changes with position | Internet | Sync logic works |
| Lyrics sync to playing song | VDJ playing | Real integration |

### Quality Gate

Module fetches lyrics and syncs to playback position.

---

## Phase 4: AI Analysis Module

### Tasks

- [ ] Create `modules/ai_analysis.py` wrapping `LLMAnalyzer` + `SongCategorizer`
- [ ] Expose `is_available` property for graceful degradation
- [ ] Expose `categorize(lyrics, artist, title)` returning mood/energy/valence
- [ ] Add standalone CLI: `python -m modules.ai_analysis --artist "..." --title "..."`

### E2E Tests

| Test | Prerequisites | Verifies |
|------|---------------|----------|
| Categorizes song with lyrics | LM Studio running | AI works |
| Returns valid energy/valence scores | LM Studio running | Output format correct |
| Graceful degradation when LLM offline | None | Doesn't crash |
| CLI displays categories | LM Studio running | Standalone works |

### Quality Gate

Module categorizes songs when LM Studio available, degrades gracefully otherwise.

---

## Phase 5: Shaders Module

### Tasks

- [ ] Create `modules/shaders.py` wrapping `ShaderIndexer` + `ShaderSelector`
- [ ] Expose `find_best_match(energy, valence)`
- [ ] Expose `list_shaders()` and `get_shader(name)`
- [ ] Add standalone CLI: `python -m modules.shaders --energy 0.8 --valence 0.6`

### E2E Tests

| Test | Prerequisites | Verifies |
|------|---------------|----------|
| Lists available shaders | Shader files exist | Indexing works |
| Finds matching shader for energy/valence | Shader files exist | Matching works |
| CLI lists and searches shaders | Shader files exist | Standalone works |

### Quality Gate

Module indexes shaders and finds matches based on energy/valence.

---

## Phase 6: Pipeline Module

### Tasks

- [ ] Create `modules/pipeline.py` orchestrating lyrics → ai → shaders
- [ ] Accept module dependencies via injection
- [ ] Expose step callbacks: `on_step_start`, `on_step_complete`
- [ ] Add standalone CLI: `python -m modules.pipeline --artist "..." --title "..."`

### E2E Tests

| Test | Prerequisites | Verifies |
|------|---------------|----------|
| Pipeline runs all steps for known song | Internet + LM Studio | Full flow works |
| Step callbacks fire in order | Internet | Callbacks work |
| Pipeline completes when AI unavailable | Internet | Graceful skip |
| Pipeline matches shader | Internet + LM Studio + shaders | End-to-end works |
| CLI shows step progress | Internet | Standalone works |

### Quality Gate

Pipeline orchestrates full song processing with real services.

---

## Phase 7: Console Refactor

### Tasks

- [ ] Create `ModuleRegistry` for module lifecycle management
- [ ] Refactor `on_mount()` to compose modules
- [ ] Wire module callbacks to UI updates
- [ ] Route playback → pipeline → OSC flow through modules
- [ ] Remove direct service instantiation from console

### E2E Tests

| Test | Prerequisites | Verifies |
|------|---------------|----------|
| Console starts with all modules | All services | Startup works |
| Track detection updates UI | VDJ playing | UI integration |
| Pipeline steps show in panel | VDJ playing | Pipeline UI works |
| Lyrics sync shows active line | VDJ playing | Lyrics UI works |
| Shader loads when matched | VDJ + LM Studio | Full flow works |
| Clean shutdown | All services | No orphan threads |

### Quality Gate

Console works as before but using modular architecture.

---

## Phase 8: Cleanup

### Tasks

- [ ] Remove deprecated global singletons (`osc` in hub.py, etc.)
- [ ] Remove backward compatibility shims
- [ ] Delete unused code from `orchestrators.py`, `textler_engine.py`
- [ ] Update imports throughout codebase

### Quality Gate

No deprecated code remains. All tests pass.

---

## File Changes Summary

### New Files

```
modules/
├── __init__.py
├── base.py
├── osc_runtime.py
├── playback.py
├── lyrics.py
├── ai_analysis.py
├── shaders.py
└── pipeline.py

tests/
├── conftest.py
├── test_baseline_behavior.py
└── modules/
    ├── test_osc_runtime.py
    ├── test_playback.py
    ├── test_lyrics.py
    ├── test_ai_analysis.py
    ├── test_shaders.py
    └── test_pipeline.py
```

### Modified Files

- `vj_console.py` - Thin shell refactor
- `textler_engine.py` - May be deprecated or simplified

### Deprecated (Phase 8 removal)

- `osc/hub.py` global singleton
- `orchestrators.py` (replaced by modules)
- Direct service instantiation in console

---

## Module API Summary

Each module follows this pattern:

```
module = SomeModule(config)
module.on_event = callback        # Wire callbacks
module.start()                    # Start background processing
result = module.do_something()    # Use module
module.stop()                     # Clean shutdown
```

Modules can be run standalone:

```bash
python -m modules.osc_runtime --receive-port 9999
python -m modules.playback --source vdj_osc
python -m modules.lyrics --artist "Queen" --title "Bohemian Rhapsody"
python -m modules.ai_analysis --artist "Queen" --title "Bohemian Rhapsody"
python -m modules.shaders --energy 0.8 --valence 0.6
python -m modules.pipeline --artist "Queen" --title "Bohemian Rhapsody"
```
