# Shader Orchestrator Implementation Plan

## 🎯 Objectives
- Automate GLSL shader selection/generation for each song using local AI (Gemma-3) with RAG over existing shader metadata.
- Announce shader availability to the Processing-based VJUniverse app through OSC, including texture usage and lyric/text requirements.
- Preserve the current Python VJ stack’s structure by reusing existing utilities (OSC manager, pipeline tracker, adapters) and adding narrowly scoped modules.
- Provide an extensible filesystem layout that separates curated shaders from generated ones while keeping analysis metadata synchronized with ChromaDB.

---

## 🧭 Context & Reuse Inventory
- **Python entrypoints**: `python-vj/vj_console.py` and `python-vj/process_manager.py` already bootstrap analysis pipelines and playback monitoring.
- **Playback + metadata**: `python-vj/orchestrators.py` exposes `PlaybackCoordinator`, `LyricsOrchestrator`, and `AIOrchestrator` that already emit track metadata, keywords, and LLM outputs.
- **OSC infrastructure**: `python-vj/osc_manager.py` provides a singleton sender bound to the default broadcast port (`9000`).
- **AI tooling**: `python-vj/ai_services.py` contains LLM wrappers; hook Gemma-3 interfaces here to maintain config-driven behavior.
- **Filesystem**: `processing-vj/` is the natural home for shader assets. Create `processing-vj/shaders/base` and `processing-vj/shaders/generated` mirroring the spec.

This plan assumes Gemma-3 and ChromaDB dependencies are managed in the existing Python virtualenv (see `python-vj/requirements.txt`).

### Feasibility Notes
- `python-vj/orchestrators.py` already handles playback events and exposes `AIOrchestrator.last_llm_result`, making it straightforward to trigger the shader orchestrator without reshaping the event loop.
- `python-vj/osc_manager.py` centralizes OSC sending; adding helper wrappers preserves compatibility with current karaoke and lyric messages.
- `python-vj/ai_services.py` provides LLM abstraction points where Gemma-3 bindings can be added without affecting other features.
- `processing-vj/examples/` demonstrate shader loading via `loadShader(...)` and multiple texture bindings, confirming that Processing can swap between curated and generated shaders at runtime using the existing graphics pipeline.

---

## 🗂️ Filesystem Strategy
1. **Create shader root**: `processing-vj/shaders/`
   - `base/` → curated hand-authored shaders and metadata.
   - `generated/` → Gemma outputs (one shader + analysis JSON per track).
2. **Analysis metadata**: enforce `<shader>.analysis.json` naming and store `id`, `kind`, `tags`, `texture_channels`, etc., matching the provided schema. Generated entries are written for bookkeeping but explicitly skipped by any analyser or indexing job.
3. **Chroma persistence**: use `python-vj/.data/chroma/shaders/` as the persisted vector store path to keep it outside asset directories yet under version control (ignored by git). Only `base/` metadata is ingested into the RAG index; `generated/` stays out of the collection to avoid feedback loops.
4. **Source capture**: while scanning `base/`, read the GLSL fragment files alongside each analysis JSON. Store their contents (and optional hashed summaries) in the repository cache so downstream indexing can embed both metadata and actual shader source text during long-running analysis jobs.
5. **Generated shader template**: place a static template file under `python-vj/templates/shader_base.frag.tpl` to simplify LLM output validation and injection.

---

## 🧠 Python Shader Orchestrator Design

### Module Overview
| Module | Purpose | Key Functions |
| --- | --- | --- |
| `python-vj/shader_repository.py` | Manage filesystem scans, load analysis JSON, track shader paths | `scan_shaders()`, `load_analysis()`, `ensure_generated_dirs()` |
| `python-vj/shader_indexer.py` | Wrap ChromaDB initialization/upsert queries | `initialize_index()`, `refresh_index()`, `query_similar()` |
| `python-vj/shader_orchestrator.py` | High-level orchestrator binding playback events, LLM calls, OSC emits | `handle_track_change()`, `generate_shader_if_needed()`, `announce_shader()` |
| `python-vj/llm/shader_prompt_builder.py` | Compose prompt inputs and validate LLM output | `build_prompt()`, `validate_effect_snippet()` |
| `python-vj/osc_extensions.py` | Provide typed helpers around `/vj/shader/*` addresses (using existing OSC manager) | `send_shader_announce()`, `send_text_payload()` |

Keep module interfaces thin so they can be consumed by the existing `process_manager` loop with minimal wiring.

### Startup Lifecycle
1. **Ensure directories**: `ShaderRepository.ensure_generated_dirs()` verifies `generated/` exists.
2. **Index scan**: `ShaderIndexer.refresh_index()` walks only `base/`, loading every `.analysis.json` and calling Chroma `upsert` with the derived document text + metadata plus the associated shader source code. Generated entries are loaded into memory for reuse but deliberately excluded from the index. The long-running scan streams shader code as document chunks so later RAG queries can surface both stylistic summaries and real GLSL bodies for the LLM.
3. **Cache results**: maintain an in-memory dict keyed by shader `id` with analysis data, absolute shader paths, and cached source snippets to avoid repeated disk I/O during playback. Track folder of origin so generated shaders can be resolved quickly without triggering analysis.
4. **Warm cache**: optionally prime a `song_shader_cache` from the generated folder by deriving `song_id` from filenames while still preventing any analyzer re-processing.

### Runtime Handling
1. **Track change signal**: hook into `PlaybackCoordinator` events (already exposed within `process_manager`) to trigger `ShaderOrchestrator.handle_track_change(now_playing)`.
2. **Lookup**: compute stable shader ID using the provided `song_id_to_shader_id` helper (place in `shader_repository.py` for reuse). If the `.frag` already exists, load its analysis and skip generation.
3. **RAG query**: if missing, assemble a query string using track metadata, AI keywords (`AIOrchestrator.last_llm_result`), and/or fallback heuristics.
4. **Chroma query**: call `ShaderIndexer.query_similar(query_text, n=5)` returning top matches with metadata plus batched shader source excerpts gathered during indexing.
5. **LLM call**: compose a prompt via `ShaderPromptBuilder`, injecting:
   - Template contract (effect signature, allowed uniforms).
   - Top-k shader descriptions (analysis JSON + the cached GLSL snippets limited to effect bodies) so the LLM can reuse proven techniques via RAG.
   - Song-specific mood, genre, BPM, lyric snippet.
   - Requirement summary (text mode yes/no, texture channel assignments).
6. **Validate snippet**:
   - Ensure function header `vec4 effect(vec2 uv)` present.
   - Reject forbidden tokens (`#version`, `gl_FragColor` assignments outside template, loops beyond threshold).
   - If invalid, fall back to the top-ranked base shader and clone it into generated/ with minimal metadata tweaks.
7. **Persist outputs**:
   - Render final shader by interpolating snippet into header template.
   - Write `<shader_id>.frag` and companion `<shader_id>.analysis.json` (copying base metadata + new fields like `derived_from`, `meta.created_at`).
   - Update `ShaderRepository` cache and `ShaderIndexer` with fresh entry.
8. **OSC announcement**: broadcast `/vj/shader/announce` with `[shader_id, abs_path, text_mode, texture_channels_json, song_id, initial_text]` using helper wrappers. The additional `initial_text` string (empty when not in text mode) guarantees VJUniverse receives the first lyric payload atomically. Follow-up `/vj/shader/text_payload` calls remain available for subsequent lyric updates only when the text changes.
9. **Generated shader broadcast**: when a new shader is produced, send a second `/vj/shader/announce` immediately afterward with the generated shader’s path and a short `initial_text` snippet (2–3 word lyric fragment or summary). Reuse the same OSC address so VJUniverse can enqueue the generated option and attempt to load it as soon as the file hits disk.

### Error Handling & Resilience
- Missing LLM or indexing: log warning, degrade gracefully by selecting the best matching base shader (via Chroma query) without generating new code.
- Write failures: guard with `pathlib.Path.write_text` and log errors; leave cache unchanged on failure.
- Race conditions: protect shared caches (e.g., `song_shader_cache`) with `threading.Lock` if orchestrator runs on background threads.

---

## 🧾 analysis.json Contract Implementation
1. **Schema compliance**: use `pydantic` or dataclass validation in `shader_repository.py` to normalize optional fields and fill defaults (e.g., `meta.created_at` via `datetime.utcnow().isoformat()`).
2. **Kind inference**: `kind="generated"` when writing new files; fallback to `"base"` if absent.
3. **Texture role mapping**: enforce presence of `tex0` and `tex1` keys; include `textTex` only when `text_mode` is true.
4. **Versioning**: increment `version` when regenerating a shader for the same song; store previous version reference in `meta.previous_version_id` if needed.

---

## 🧬 ChromaDB Integration
- **Persistent path**: `python-vj/.data/chroma/shaders/`
- **Initialization**:
  ```python
  client = chromadb.PersistentClient(path=Settings.CHROMA_BASE / "shaders")
  collection = client.get_or_create_collection(name="shaders")
  ```
- **Document string**: combine `id`, `tags`, `mood`, and `llm_prompt_context` as described, optionally appending `derived_from` identifiers for richer context.
- **Metadata fields**: store absolute shader path, `kind`, `text_mode`, `texture_channels`, `meta` (author, bpm range), plus `analysis_path` to accelerate reloads.
- **Refresh strategy**: simple full rescan on startup plus targeted `upsert` after generating new shaders (base only). Optionally implement checksum-based skip (hash JSON contents) for speed.
- **Generated exclusion**: guard `ShaderIndexer.refresh_index()` with a folder allowlist so generated shaders never enter the collection, while still keeping their metadata accessible from the repository cache.

---

## 📡 OSC Protocol Additions
1. **Client reuse**: extend `OSCManager` to support secondary destinations. Options:
   - Add `send_to(address, args, host, port)` helper.
   - Or instantiate a dedicated `SimpleUDPClient` within `osc_extensions.py` configured for port `12000`.
   The second option isolates shader traffic without disturbing existing message flow.
2. **Helpers**: create typed wrappers `send_shader_announce()` and `send_text_payload()` that accept native Python types, perform JSON serialization for `texture_channels`, and append the `initial_text` string to the announce message.
3. **Integration**: `ShaderOrchestrator` depends on `send_shader_announce()` for atomic shader+text delivery. `send_text_payload()` is reserved for incremental lyric updates after the initial announce when the content changes. The orchestrator issues a minimum of two announces per song change: one for the fallback curated shader (if available) and a second for the generated shader once it is ready.

---

## 🎨 VJUniverse (Processing) Updates
1. **OSC handler**: add `/vj/shader/announce` and `/vj/shader/text_payload` branches to the existing `oscEvent`. Use minimal JSON parsing (e.g., `processing.data.JSONObject` or a tiny manual parser) to fill a `HashMap<String, String>` and extract the `initial_text` string from the announce payload.
2. **Shader lifecycle**:
   - Store `currentShader`, `currentShaderMetadata`, and `currentSongId` globals.
   - When `announce` arrives, call `loadShader(filePath)` (Processing accepts absolute paths) and set booleans for text mode.
3. **Textures**:
   - Maintain `PGraphics` buffers for `tex0`, `tex1` (existing flows) and `textTex` (new). When `text_mode` is false, skip binding `textTex` to avoid performance hits.
4. **Text rendering**:
   - Add `renderTextToTexture()` function writing onto `textTex`. Call it immediately when `initial_text` arrives via announce, during lyric payload updates, and optionally once per frame when text is active to handle fades.
5. **Debug shader selection**:
   - Expand the existing debug mode toggle (active before any OSC traffic) to cycle through three buckets: curated ISF shaders, curated GLSL shaders, and generated GLSL shaders. Each mode should display sourced examples, enabling operators to preview generated content without waiting for OSC.
6. **Announce queue & fallback logic**:
   - Maintain a small FIFO queue of incoming shader announcements. The first message that arrives is attempted immediately; if loading succeeds, mark it active. Additional announcements (e.g., the generated shader) are attempted in arrival order. On load failure, log the error and revert to the most recent successfully loaded shader without blocking the queue. This behavior mirrors the specification: use whatever shader loads, fall back gracefully if subsequent candidates fail.
7. **Fallbacks**:
   - If shader load fails, keep previous shader active and request Python to resend (optional `/vj/shader/debug`).

All Processing changes remain isolated to the OSC sketch, avoiding global rewrites.

---

## 📝 Implementation TODO Checklist
1. **Scaffold storage**
   - [ ] Create `processing-vj/shaders/{base,generated}` folders and populate base entries with analysis JSON + GLSL pairs.
   - [ ] Add template file at `python-vj/templates/shader_base.frag.tpl`.
2. **Repository + cache layer**
   - [ ] Implement `ShaderRepository` to enumerate shaders, ingest source code, and cache metadata without touching generated files during analysis.
   - [ ] Write unit tests covering JSON parsing and `song_id_to_shader_id` behavior.
3. **Chroma indexer**
   - [ ] Initialize persistent Chroma client pointed at `python-vj/.data/chroma/shaders/`.
   - [ ] Upsert only base shader metadata + source code chunks; confirm generated folder is skipped.
4. **Orchestrator integration**
   - [ ] Wire `ShaderOrchestrator` into `process_manager` to receive playback change events.
   - [ ] Implement dual announce flow (fallback curated shader then generated shader) and ensure `initial_text` is included.
5. **LLM workflow**
   - [ ] Extend `ai_services` to expose Gemma-3 inference endpoint.
   - [ ] Build `ShaderPromptBuilder` to assemble RAG payload including GLSL snippets and track metadata.
6. **OSC helpers**
   - [ ] Add typed wrappers for `/vj/shader/announce` and `/vj/shader/text_payload` with `initial_text` handling.
   - [ ] Update tests or mocks to validate payload formatting.
7. **VJUniverse updates**
   - [ ] Implement OSC queue, debug-mode tri-toggle, and text texture initialization.
   - [ ] Add safe fallback when shader fails to compile/load.
8. **Validation**
   - [ ] Run end-to-end dry run: trigger track change with simulated now-playing data, verify fallback shader loads, then confirm generated shader replaces it when ready.
   - [ ] Document operator flow in `docs/testing/shader-orchestrator-smoke.md`.

These tasks reuse existing modules, minimize churn, and can be tracked individually in the project board.

---

## 🛡️ Validation & Tooling
- **Unit tests**: add targeted tests under `python-vj/tests/` (`test_shader_repository.py`, `test_shader_indexer.py`) to validate JSON parsing, ID generation, and Chroma interactions (mock client).
- **Integration test**: simulate a track event using fixtures to confirm orchestrator writes files and emits OSC messages (mock UDP client).
- **Processing smoke test**: provide a `docs/testing/shader-orchestrator-smoke.md` checklist for manual verification (load generated shader, verify textures, confirm lyrics overlay).
- **Observability**: extend existing `PipelineTracker` to add steps like `shader_index_refresh`, `shader_llm_generate`, and `shader_osc_emit` for UI dashboards.

---

## 🗺️ Rollout Phases
1. **Phase 0 – Scaffolding**
   - Create shader directories and analysis templates.
   - Implement repository + indexer modules with CLI to refresh index.
2. **Phase 1 – Playback Hook**
   - Wire `ShaderOrchestrator` into `process_manager` to respond to track changes.
   - Verify base shader selection works without LLM (regen disabled).
3. **Phase 2 – LLM Generation**
   - Integrate Gemma-3 backend and prompt builder.
   - Add validation/fallback logic and persistence for generated shaders.
4. **Phase 3 – OSC & Processing Integration**
   - Extend OSC helpers and Processing sketch.
   - Confirm dynamic shader loading and text texture behavior.
5. **Phase 4 – Polish**
   - Add caching, failure recovery, and CLI tooling for manual shader regeneration per song.
   - Document workflow in `docs/shader-orchestrator-usage.md` (future work).

---

## ✅ Success Criteria
- New track triggers consistent shader announcement within <500 ms when shader exists; within <3 s when generating via LLM.
- Generated shaders follow the fixed template and never block the main playback loop (generation happens on worker thread).
- VJUniverse receives `announce` and `text_payload` messages without affecting existing OSC consumers.
- Analysis metadata remains synchronized across filesystem, Chroma index, and Python cache after restarts.

This plan balances the new pipeline requirements with maximal reuse of the current Python VJ infrastructure, ensuring minimal disruptive changes and a clear path for iterative development.
