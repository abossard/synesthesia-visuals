# Architecture & Development Notes

Design decisions, refactoring history, and development patterns used in python-vj.

---

## Core Patterns

### Grokking Simplicity

Calculations separated from actions, immutable data structures.

**Before (mutable):**
```python
self._state.track = new_track  # Direct mutation
```

**After (immutable):**
```python
self._state = self._state.update(track=new_track)  # New instance
```

### Deep Modules (Philosophy of Software Design)

Simple interface, complex implementation hidden inside.

**Example: LyricsFetcher**
- **Public API**: `fetch(artist, title) -> Optional[str]`
- **Hidden complexity**: HTTP requests, retries, caching, TTL, error handling

**Example: LLMAnalyzer**
- **Public API**: `analyze_lyrics(lyrics, artist, title) -> Dict`
- **Hidden complexity**: Multi-backend (OpenAI/LM Studio), model detection, JSON parsing, fallback

### Stratified Design

```
┌─────────────────────────────────────────────┐
│ karaoke_engine.py (Composition)             │  ← Thin orchestration
├─────────────────────────────────────────────┤
│ orchestrators.py (Coordinators)             │  ← Business logic
├─────────────────────────────────────────────┤
│ ai_services.py | adapters.py                │  ← Deep modules
├─────────────────────────────────────────────┤
│ infrastructure.py (Cross-cutting)           │  ← Shared services
├─────────────────────────────────────────────┤
│ domain.py (Pure calculations)               │  ← No side effects
└─────────────────────────────────────────────┘
```

---

## Karaoke Engine Refactoring

**Before**: 2,703 lines in single monolithic file
**After**: ~1,100 lines across 6 focused modules

| Module | Lines | Purpose |
|--------|-------|---------|
| `domain.py` | ~210 | Pure calculations, immutable data |
| `infrastructure.py` | ~350 | Config, settings, service health |
| `adapters.py` | ~400 | External service interfaces |
| `ai_services.py` | ~450 | LLM, categorization, images |
| `orchestrators.py` | ~250 | Focused coordinators with DI |
| `karaoke_engine.py` | ~340 | Main composition |

### Dependency Injection

**Before (God Object):**
```python
def __init__(self):
    self._osc = OSCSender()
    self._lyrics = LyricsFetcher()
    self._spotify = SpotifyMonitor()
    # ... 500+ lines of orchestration
```

**After (DI):**
```python
class LyricsOrchestrator:
    def __init__(self, fetcher: LyricsFetcher, pipeline: PipelineTracker):
        self._fetcher = fetcher  # Injected - mockable for tests
```

### Testability

```python
# Test without real API calls
mock_fetcher = Mock(spec=LyricsFetcher)
mock_fetcher.fetch.return_value = "[00:10.00]Test line"

orchestrator = LyricsOrchestrator(mock_fetcher, mock_pipeline)
result = orchestrator.process_track(test_track, 0)

assert len(result) == 1
mock_pipeline.start.assert_called_with("fetch_lyrics")
```

---

## Textual Migration

Migrated from Blessed to Textual TUI framework.

**Performance improvement:**
- Old Blessed: Full redraw every 2 seconds = ~50% CPU idle
- New Textual: Partial updates on change = ~5% CPU idle

**Key benefits:**
- Reactive properties (change data → UI updates)
- CSS-based styling
- Async/await non-blocking updates
- 16.7M colors, smooth animations

```python
# Old (manual redraw)
self.state.needs_redraw = True

# New (reactive)
self.track_artist = "Daft Punk"  # Auto-updates!
```

---

## Defensive Error Handling

Widgets use fail-safe patterns:

```python
try:
    # Handle dict format (from LLM)
    if isinstance(image_prompt, dict):
        prompt_text = image_prompt.get('description', str(image_prompt))
    elif isinstance(image_prompt, str):
        prompt_text = image_prompt
    else:
        prompt_text = str(image_prompt)
except Exception as e:
    logger.exception(f"Error updating display: {e}")
    self.update(f"[red]Error[/]\n[dim]{str(e)}[/dim]")
```

### Patterns

1. **Type guards**: `isinstance()` before operations
2. **Graceful degradation**: Missing data → placeholder
3. **Granular exceptions**: Widget-level, item-level, operation-level
4. **User feedback**: Errors shown in UI, not just logs

---

## Thread Safety

### PipelineTracker

```python
def complete(self, step: str, message: str = ""):
    with self._lock:  # Thread-safe
        if step in self._steps:
            self._steps[step] = PipelineStep(  # New instance
                name=step,
                status="complete",
                message=message,
                timestamp=time.time()
            )
```

### Principles

- Immutable updates (replace, don't mutate)
- Explicit locks where needed
- No shared mutable state across threads

---

## OSC Communication

### Consolidated Pattern

**Before (20+ methods):**
```python
def send_track(self, track, has_lyrics): ...
def send_no_track(self): ...
def send_lyrics_reset(self, song_id): ...
```

**After (unified builder):**
```python
osc.send_karaoke("track", "info", {"artist": track.artist, ...})
osc.send_karaoke("lyrics", "reset", {"song_id": song_id})
```

### Message Addresses

See [Audio Analysis](features/audio-analysis.md) for complete OSC reference.

---

## File Organization

```
python-vj/
├── domain.py           # Pure calculations, immutable data
├── infrastructure.py   # Config, settings, service health
├── adapters.py         # External service interfaces
├── ai_services.py      # LLM, categorization, images
├── orchestrators.py    # Business logic coordinators
├── karaoke_engine.py   # Main composition
├── vj_console.py       # Textual TUI
├── osc_manager.py      # OSC communication
└── docs/               # Documentation (you are here)
```

---

## Future Improvements

- [ ] GPU-accelerated FFT (cuFFT)
- [ ] Machine learning beat tracking
- [ ] Key/scale detection
- [ ] Harmonic/percussive separation
- [ ] Real-time genre classification
