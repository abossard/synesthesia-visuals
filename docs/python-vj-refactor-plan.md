# python-vj Refactor Plan

## Objectives

- Hard boundaries between pure data ([python-vj/domain.py](python-vj/domain.py)), configuration/state ([python-vj/infrastructure.py](python-vj/infrastructure.py)), external services, orchestration, and UI so each module has one responsibility.
- Robust, fault-tolerant runtime where health/backoff policies, OSC emission, and analyzer watchdogs are centralized and share diagnostics.
- Lean modules that let hosts import only the slices they need (headless analyzer engine, lyrics/AI pipeline, full Textual console shell) without dragging along unused dependencies.
- Easier onboarding via dedicated architecture documentation and smoke tests covering audio, AI, and OSC pipelines.

## Current Layer Recap

- **Domain**: immutable dataclasses and helpers already isolated in [python-vj/domain.py](python-vj/domain.py).
- **Infrastructure**: settings/backoff/pipeline state in [python-vj/infrastructure.py](python-vj/infrastructure.py) bridging `.env`, macOS defaults, and telemetry.
- **Adapters & Services**: third-party integrations concentrated in [python-vj/adapters.py](python-vj/adapters.py) and [python-vj/ai_services.py](python-vj/ai_services.py).
- **Audio Stack**: Essentia analyzer, watchdog, and diagnostics in [python-vj/audio_analyzer.py](python-vj/audio_analyzer.py) plus system setup helpers in [python-vj/audio_setup.py](python-vj/audio_setup.py).
- **Orchestration**: lyric/AI pipelines in [python-vj/orchestrators.py](python-vj/orchestrators.py) and coordination glue in [python-vj/karaoke_engine.py](python-vj/karaoke_engine.py).
- **Runtime Shells**: OSC transport ([python-vj/osc_manager.py](python-vj/osc_manager.py)), Processing supervisor ([python-vj/process_manager.py](python-vj/process_manager.py)), and the Textual UI ([python-vj/vj_console.py](python-vj/vj_console.py)).

## Layer Boundary Implementation Details

- **Domain (Pure Data)**
  - Restrict imports to stdlib only; no service or infrastructure references allowed.
  - Keep immutable dataclasses plus pure helper functions for formatting, parsing, comparison, or validation. Any stateful defaults or I/O must be lifted into infrastructure.
  - Introduce mypy-enforced protocols for entities that other layers depend on (e.g., `TrackMetadata`, `LyricSegment`) so boundaries stay explicit.
- **Infrastructure (Configuration & State)**
  - Sole owner of `.env` parsing, platform detection, feature flags, retry/backoff constants, and persistent caches on disk.
  - Expose typed config objects (e.g., `SpotifyConfig`, `AnalyzerConfig`) that service modules receive via constructor dependency injection; forbid direct access to `os.environ` elsewhere.
  - Provide a `HealthRegistry` and `BackoffPolicy` APIs that other layers consume without duplicating logic.
- **External Services**
  - Live inside `python_vj/services/` and `python_vj/ai/`; each module exports a single interface plus factory.
  - Services may depend on domain and infrastructure types but never on orchestration or UI. Communication back to higher layers happens through return values or message objects, not global state.
  - Shared concerns (HTTP session management, caching, logging) go into `services/_base.py` to avoid cross-import tangles.
- **Orchestration & Pipeline**
  - Owns sequencing, queues, and multi-service coordination but never reaches into UI widgets or Textual APIs.
  - Consumes services via interfaces and emits domain objects/events; state transitions recorded through infrastructure’s registries.
  - Provide a single facade (`KaraokeEngine`) with explicit methods (`update_track`, `refresh_lyrics`, `emit_osc_frame`) called by host modules (UI shell, analyzer runner, automation scripts).
- **UI / Entry Points**
  - Import only orchestration facades plus the audio analyzer interface; no direct service calls.
  - Keep Textual widgets, key bindings, and Syphon/Processing supervision under `python_vj/ui/` and `python_vj/process_manager.py` respectively.
  - When UI needs configuration or diagnostics, request them from orchestration facades instead of reading infrastructure modules directly.
- **Enforcement Mechanisms**
  - Add `tests/test_layers.py` ensuring import graph respects `domain -> infrastructure -> services -> orchestration -> ui` order (use `import-linter` or `pytest-arch`).
  - Update code review checklist to verify new modules declare their layer and avoid upward imports.
  - Document allowed dependency arrows in the forthcoming architecture note and keep diagrams synced with the actual package layout.

## Modularization Roadmap

### Phase 0 — Documentation & Interfaces

- Publish this plan plus a concise architecture note summarizing data flow, service contracts, and OSC schema.
- Define target public APIs (interfaces/protocols) for service clients, audio analyzer, OSC bus, and pipelines before moving code.

### Phase 1 — Service Extraction

- Create `python_vj/services/` package splitting responsibilities currently in [python-vj/adapters.py](python-vj/adapters.py):
  - `spotify.py`, `virtualdj.py`, `lyrics.py`, `osc_sender.py` each with a narrow surface.
  - Shared caching, throttling, and health helpers in `services/_base.py`.
- Move AI integrations from [python-vj/ai_services.py](python-vj/ai_services.py) into `python_vj/ai/` submodules (`llm.py`, `categorizer.py`, `comfyui.py`).
- Ensure `infrastructure` exposes typed configs consumed by each service module to avoid cross-imports.

### Phase 2 — Audio Package

- Create `python_vj/audio/` with:
  - `dsp.py` for Essentia feature helpers, filters, and math utilities (pure, unit testable).
  - `analyzer.py` housing the real-time loop, OSC hooks, and watchdog/backoff logic.
  - `setup.py` dedicated to macOS diagnostics (BlackHole/Multi-Output, `SwitchAudioSource`).
- Define a clean interface (`AudioAnalyzer` protocol) used by both UI and headless entrypoints for start/stop/status.

### Phase 3 — Pipeline & Orchestration

- Introduce `python_vj/pipeline/` package encapsulating queues, background workers, and job definitions previously in [python-vj/orchestrators.py](python-vj/orchestrators.py).
- Refactor [python-vj/karaoke_engine.py](python-vj/karaoke_engine.py) into a thin coordinator that wires `domain`, `infrastructure`, `services`, and `pipeline` without internal knowledge of worker internals.
- Add unit tests for pipeline transitions (track change, lyric fetch failure, AI retries) using the new interfaces.

### Phase 4 — OSC Bus & Messaging

- Wrap [python-vj/osc_manager.py](python-vj/osc_manager.py) into `python_vj/messaging/osc_bus.py` with typed helpers (`send_levels`, `send_lyrics`, `send_categories`).
- Provide a pluggable logger/debug sink so UI and tests can capture outgoing packets without touching UDP.

### Phase 5 — UI & Entry Points

- Split [python-vj/vj_console.py](python-vj/vj_console.py) into `python_vj/ui/app.py`, `python_vj/ui/screens/*.py`, and `python_vj/ui/controllers/*.py` so layout, input handling, and service management are isolated.
- Introduce lightweight module runners (e.g., `python_vj.audio.runner`, `python_vj.lyrics.runner`) exposing `run()` helpers so host applications can embed individual slices without shipping extra executables.
- Update [python-vj/process_manager.py](python-vj/process_manager.py) to depend on new service interfaces rather than concrete classes.

## Robustness & Ease-of-Use Enhancements

- Centralize health/backoff policies in [python-vj/infrastructure.py](python-vj/infrastructure.py) with a shared status API consumed by UI, pipelines, and services.
- Adopt typed config objects (dataclasses/Pydantic) for `.env` parsing to catch misconfiguration early and simplify defaults for new contributors.
- Standardize logging/diagnostics so every module can emit structured events captured by the console or any embedding host application.
- Create smoke-test scripts (no UI) that verify Spotify polling, lyric parsing, analyzer boot, and OSC emission end-to-end.

### Unified Health, Backoff, and Diagnostics Strategy

- **Lightweight Health Registry**
  - Keep a single `HealthRegistry` singleton, but store only the latest status plus timestamp per subsystem (Spotify monitor, lyric fetcher, analyzer, OSC bus, AI categorizer, Processing supervisor).
  - Optional ring buffer (size ≤ 20) captures recent failures for UI inspection; sampling occurs only on error to avoid constant serialization.
- **Shared Backoff Policies**
  - Provide simple dataclasses (`ConstantBackoff`, `ExponentialBackoff`) that expose `next_delay()` and `reset()`; log transitions only when state changes to limit I/O.
  - Attach policies via constructor injection so services compute delays locally without registry chatter.
- **OSC & Analyzer Watchdogs**
  - Analyzer sends periodic (1–2 Hz) heartbeat objects containing last buffer duration and last OSC send time; watchdog restarts analyzer only after consecutive missed beats to prevent flapping.
  - OSC bus keeps per-channel send counters updated lazily (increment only when packets go out); watchdog warns if counters stay flat beyond threshold.
- **Crash Visibility & Auto-Recovery**
  - `GuardedWorker` wrapper captures exceptions, records a compact failure object (`component`, `error_type`, `message`, `trace_excerpt`, `first_seen`, `attempts`) and schedules restart based on supplied policy.
  - UI polls registry at low frequency (once per second) and surfaces banners like “AI categorizer restarting (3 attempts, next in 60s)”.
- **Diagnostics Surfaces**
  - Offer a diagnostics helper (`python_vj.diagnostics.snapshot()`) returning registry + backoff summary so host apps can surface the info inside their own shells, services, or dashboards without bundling extra binaries.
  - On-disk crash log rotates daily with JSON lines capped at a few kilobytes per entry to minimize file churn.
- **Why/When Reporting**
  - Standard helper `report_failure(component, action, error, context)` stamps ISO time, short action label (“poll-virtualdj”), and recommended remediation hint.
  - Nightly job (or optional script flag) aggregates failures to highlight chronic issues (“VirtualDJ poller: 5 failures in 10 min, last error missing file”).

## Lean Distribution Strategy

- Convert `python-vj` into a namespace package (`python_vj/`) so internal modules can be re-used or published.
- Add optional dependency extras in `requirements.txt` (`[ui]`, `[ai]`, `[audio]`) letting deployments install only what they need.
- Document integration recipes in [python-vj/README.md](python-vj/README.md) that show how to import the analyzer module, lyrics pipeline, or console shell independently (no standalone CLI required).

## Testing, Rollout, and Risks

- Maintain functional parity after each phase using regression tests outlined in [python-vj/test_python_vj.py](python-vj/test_python_vj.py) and new unit suites per package.
- Sequence refactors to keep active PRs small: finish a phase, merge, then proceed to the next.
- Risks: circular imports during extraction, temporary duplication of helper code, and deployment scripts expecting old paths. Mitigate by introducing new modules behind feature flags before removing legacy ones.
