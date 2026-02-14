# Interaction Remediation Plan

## Scope

- Streamline timing-adjustment support out of the app.
- Fix rendering interaction issues (shader cell hit area, mask list population, image orientation).
- Prefer simplification and code removal over compatibility shims.

## Checklist

- [x] Master timing-adjustment support removed end-to-end
  - [x] Implemented
  - [x] Tested
- [x] Rendering shader selection accepts clicks on full row cell
  - [x] Implemented
  - [ ] Tested
- [x] Rendering masks list populated correctly
  - [x] Implemented
  - [ ] Tested
- [x] Rendering image preview orientation corrected (not upside down)
  - [x] Implemented
  - [ ] Tested

## Test Log

- [x] `swift test --filter PlaybackReducerTests`
- [x] `swift test --filter SettingsTests`
- [x] `swift test --filter InfrastructureTests`
- [x] `swift test --filter SwiftVJAppTests`

## Manual Verification Pending

- Verify shader and mask row click target covers the full cell in Rendering tab.
- Verify mask list is populated from `Shaders/masks` at startup.
- Verify image tile preview is no longer vertically inverted.

## Trace Reassessment (Post-Fix)

- Captured fresh trace: `docs/perf-traces/post-fixes-20260213-110651.trace` (20s Time Profiler).
- Parsed metrics: `docs/perf-traces/post-fixes-20260213-110651-metrics.json`.
- Result summary:
  - Main-thread sample share: `57.45%` (`1218/2120` rows).
  - Potential hangs: `1` (main-thread, `~790.7ms`, around `5.19s` after start).
  - No hang-risk log entries.
  - During the hang window, top main-thread work is dominated by file IO and image resampling (`__open`, `read`, CoreGraphics resample), with app frames in shader load/analysis paths (`Shaders.loadAll`, `Shaders.loadAnalysis`).
- Interpretation:
  - Interaction-specific hit-testing pressure is not evident in this startup-focused trace.
  - The largest remaining efficiency issue is startup-phase synchronous shader loading/analysis and image conversion on the main actor.

## Trace Reassessment (After Off-Main Shader Reload)

- Captured follow-up trace: `docs/perf-traces/post-fixes-bgload-20260213-112932.trace` (20s Time Profiler).
- Parsed metrics: `docs/perf-traces/post-fixes-bgload-20260213-112932-metrics.json`.
- Result summary:
  - Potential hangs: `0` (previous startup trace had one `~790ms` main-thread hang).
  - Main-thread sample share: `52.09%` (`1246/2392` rows).
  - Top app hotspots are now mostly steady-state rendering and Spotify AppleScript polling; shader loading still appears but with reduced dominance.
