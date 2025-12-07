# Processing Pipeline Planner Improvements (Future Work)

## Context

- Current pipeline status UI derives from `PipelineTracker` in `python-vj/karaoke_engine.py`.
- Steps are stored in an ordered mapping and surfaced in the Textual console via `build_pipeline_data()` and `PipelinePanel`.
- Status icons only appear when a step explicitly sets a `status` glyph (e.g., `⧗`). Optional or skipped steps may bypass the in-progress state, producing blank columns.

## Pain Points

1. **Missing icons** – steps such as `parse_lrc` or optional AI jobs may jump straight to `complete` or `skip`, leaving `status=""`.
2. **Invisible stages** – tasks like `prepare_song_assets` run but lack entries in `PipelineTracker.STEP_LABELS`, so progress never shows up.
3. **Non-planned execution** – pipeline stages fire opportunistically and do not originate from a clear "plan" set when a new song loads.

## Planner Concept

Treat the pipeline as a task planner that queues all required steps for a new song, tracks their lifecycle, and exposes consistent states to the UI.

### Desired States

| State         | Icon | Color  | Notes                                |
|---------------|------|--------|---------------------------------------|
| `queued`      | `○`  | dim    | Initial state for every planned step |
| `in_progress` | `⧗`  | yellow | Worker actively processing            |
| `complete`    | `✓`  | green  | Step succeeded                        |
| `skipped`     | `↷`  | cyan   | Deliberately bypassed                 |
| `cancelled`   | `×`  | red    | Aborted due to failure or cutoff      |

### Planner Data Model (Concept)

```python
@dataclass
class PipelinePlanItem:
    name: str
    priority: int
    prerequisites: tuple[str, ...] = ()
    optional: bool = False
```

- `PipelinePlanner` maintains a queue (`deque[PipelinePlanItem]`).
- `reset_for_track()` seeds the queue with canonical steps (detect playback → fetch lyrics → parse → analyze refrain → categorize → LLM analysis → ComfyUI → OSC).
- Optional steps (LLM, ComfyUI) are still enqueued but flagged; planner can skip automatically if prerequisites fail.

### Lifecycle Hooks

1. **Queue All Steps**

   ```python
   planner.enqueue(PipelinePlanItem("fetch_lyrics", priority=10))
   planner.enqueue(PipelinePlanItem("parse_lrc", priority=20, prerequisites=("fetch_lyrics",)))
   # etc.
   ```

2. **Start Work** – workers request the next available item (`planner.start_next()`), which:
   - Marks prior dependencies as satisfied.
   - Calls `tracker.mark_in_progress(step_name)` → UI shows yellow icon.
3. **Finish / Skip / Cancel** – workers report outcomes via dedicated planner APIs; planner updates tracker and schedules dependent steps or aborts optional branches.

## UI Changes

- `PipelinePanel` should provide fallback icons when `status` is empty:

   ```python
   icon = status or DEFAULT_ICONS.get(color, "○")
   ```

- Add legend for planner states and optionally group steps by phase (Acquisition, Analysis, Rendering).
- Display queue depth or ETA by referencing planner data (e.g., `planner.pending_count`).

## Implementation Notes

1. Extend `PipelineTracker.reset()` to seed every known step with `queued` state and default message.
2. Audit all `mark_*` calls (fetch, parse, categorize, LLM, ComfyUI) to ensure they flow through `queued → in_progress → terminal` states.
3. Integrate planner queue with existing background threads (`_prepare_song`, `ShaderSelector` worker, ComfyUI task dispatcher).
4. Update documentation (`docs/` or in-code docstrings) to reflect the new lifecycle.

## Risks / Considerations

- Planner must be thread-safe (current tracker uses a lock; planner should reuse it).
- Ensure OSC or downstream systems that consume pipeline status tolerate new states/icons.
- Provide migration path for tests or mocks (if any) that expect previous status strings.

## Next Steps

1. Prototype planner classes alongside `PipelineTracker` without disrupting current behavior.
2. Update workers to consume planner APIs, run the suite manually, and verify UI output.
3. Iterate on iconography and messaging with live sessions to fine-tune what operators see during song transitions.
