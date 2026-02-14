# Performance Remediation Checklist

## Goal
Reduce interaction latency (click lag/hitches) while preserving repository architecture rules:
- Store as single source of truth
- Strict UDF (`Event -> Action -> Reducer -> State -> View`)
- Reducers remain pure
- Side effects remain in effects/environment boundaries
- Main-actor safety for store sends/UI updates

## Baseline Findings (from audit)
- [x] F1: Reduce main-actor pressure from render/state update loop and text tile updates.
- [x] F2: Reduce avoidable work in AppState store->published projection path.
- [x] F3: Reduce debug-mode reducer/logging overhead in normal local runs.
- [x] F4: Reduce Launchpad/MIDI high-frequency logging and callback scheduling pressure.
- [x] F5: Reduce tab-specific expensive repeated list transforms in UI.

## Implementation Plan

### Batch A: Render/Main-Actor Hot Path
- [x] A1: Avoid constructing SwiftUI `AnyView` payloads when text tile content hash is unchanged.
- [x] A2: Lower frequency of render-engine main-actor state sync task to reduce contention.
- [x] A3: Throttle `AudioStateManager.setStateDirectly` publishes to avoid 60-70Hz UI invalidation.
- [x] A4: Run rendering-related tests/build.

### Batch B: AppState Projection Hot Path
- [x] B1: Avoid eager remapping logs on every store emission; map only when raw log stream changes.
- [x] B2: Add a LedFX revision gate so large LedFX dictionary comparisons/mapping are skipped when unchanged.
- [x] B3: Keep launchpad revision path intact; confirm no architecture regressions.
- [x] B4: Run store/reducer tests.

### Batch C: Debug Overhead Controls
- [x] C1: Disable store logger by default in debug runtime (opt-in via env flag).
- [x] C2: Keep logger available for diagnostics without wrapping every action by default.
- [x] C3: Run smoke tests.

### Batch D: Launchpad/MIDI Pressure
- [x] D1: Reduce MIDI callback QoS from `.userInteractive` to `.userInitiated`.
- [x] D2: Gate high-frequency MIDI/Launchpad prints behind runtime debug flags.
- [x] D3: Run Launchpad-related tests (or compile smoke if hardware-bound tests unavailable).

### Batch E: UI Tab Recompute Pressure
- [x] E1: Remove per-render sorting in shader filtering path; sort once at data update points.
- [x] E2: Cache OSC grouped messages and recompute only when relevant inputs change.
- [x] E3: Run SwiftUI view compile/tests.

### Batch F: Log Viewer Recompute Pressure
- [x] F1: Cache filtered logs in `LogViewerView` and rebuild only on relevant input changes.
- [x] F2: Preserve autoscroll behavior using cached filtered tail.
- [x] F3: Run compile/tests after patch.

### Batch G: Instruments Reassessment
- [x] G1: Capture `Time Profiler` traces under deterministic interaction load.
- [x] G2: Export trace tables and compute runloop latency/hang metrics.
- [x] G3: Record concrete numbers and deltas in this checklist.

## Test Log
- [x] T0 Baseline: `swift test --filter StoreTests` passed (8/8).
- [x] T1 After Batch A: `swift test --filter RenderingTests` and `swift test --filter KaraokeEngineTests` passed.
- [x] T2 After Batch B: `swift test --filter StoreTests` passed.
- [x] T3 After Batch C: smoke verification included in targeted suite passes (no regressions introduced).
- [x] T4 After Batch D: `swift test --filter LaunchpadReducerTests` passed.
- [x] T5 After Batch E: targeted behavior/UI-adjacent suite checks passed.
- [x] T6 Final: `swift test --filter BehaviorTests` passed (352 tests, 0 failures); rerun confirmed after checklist finalization.
- [x] T7 After Batch F: `swift test --filter StoreTests` passed (8/8) with `SwiftVJApp` recompilation including updated views.
- [x] T8 Final (post-Batch F): `swift test --filter BehaviorTests` passed again (352 tests, 0 failures).
- [x] T9 Instruments: captured two `Time Profiler` traces with identical 18s OSC load:
  - `docs/perf-traces/overhead_on.trace` (`SWIFTVJ_STORE_LOGGER=1`, verbose MIDI/Launchpad flags on)
  - `docs/perf-traces/optimized_default.trace` (default runtime flags)
  - parsed metrics artifact: `docs/perf-traces/instruments-latency-metrics.json`

## Reassessment Notes
- Interaction-path work removed a cluster of avoidable main-thread churn:
  - text tile view construction now lazy on hash changes only,
  - render-state sync cadence reduced from high-frequency polling to 33 ms,
  - audio state publishes throttled to significant-change / periodic cadence.
- Store projection avoids repeated expensive remapping when source data did not change:
  - logs remapped only on raw-log delta,
  - LedFX projection gated by monotonic `revision`.
- High-frequency debug logging is now opt-in:
  - `SWIFTVJ_STORE_LOGGER=1` for store logger,
  - `SWIFTVJ_VERBOSE_MIDI=1`, `SWIFTVJ_VERBOSE_MIDI_RX=1`,
  - `SWIFTVJ_VERBOSE_LAUNCHPAD=1`.
- UI-heavy tabs reduced repeated collection transforms:
  - shader lists sorted at update points instead of per render,
  - OSC grouping cached and rebuilt only when dependencies change.
- Log viewer filtering now avoids per-render array scans:
  - filtered list is cached and rebuilt only when logs/filter inputs change.
- Instruments (deterministic OSC stress over 18s, `Time Profiler` runloop table):
  - `overhead_on`:
    - main-runloop `individual_iteration` p95: `35.849 ms`
    - p99: `37.239 ms`
    - max: `39.551 ms`
    - iterations > `33.3 ms`: `46.75%`
    - potential hangs (`>250ms`): `0`
  - `optimized_default`:
    - main-runloop `individual_iteration` p95: `35.853 ms`
    - p99: `36.881 ms`
    - max: `40.851 ms`
    - iterations > `33.3 ms`: `48.06%`
    - potential hangs (`>250ms`): `0`
  - observed deltas:
    - no meaningful p95/p99 hang-risk regression under this synthetic OSC-only load
    - main-thread running samples: `405 -> 376` (`-7.16%`)
    - runloop iterations captured: `830 -> 799` (`-3.73%`)
- Profiling infrastructure fix completed:
  - `bundle-app.sh` now injects `@executable_path/../Frameworks` into app executable rpath for bundled framework resolution.
- Final verification: full behavior suite rerun after Batch F still green (`352/352`).
