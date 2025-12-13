# Dynamic Shader Generation - Implementation Checklist

This checklist tracks the implementation of the dynamic shader generation feature. Check off items as they are completed.

**See**: [SHADER_GENERATION_IMPLEMENTATION_PLAN.md](./SHADER_GENERATION_IMPLEMENTATION_PLAN.md) for detailed specifications.

---

## Pre-Implementation Setup

### Environment Setup
- [ ] Install LM Studio (https://lmstudio.ai)
- [ ] Download Qwen2.5-Coder-32B-Instruct model (GGUF, Q8_0 or Q4_K_M)
- [ ] Configure LM Studio to start OpenAI-compatible server on port 1234
- [ ] Test LM Studio API: `curl http://localhost:1234/v1/models`

### MCP Servers Setup
- [ ] Install Node.js (if not already installed)
- [ ] Install Pexels MCP Server: `npm install -g @pexels/mcp-server`
- [ ] Install Image Downloader MCP Server: `npm install -g mcp-image-downloader`
- [ ] Create Pexels account and get API key (https://www.pexels.com/api/)
- [ ] Set environment variable: `export PEXELS_API_KEY=your_key_here`
- [ ] Add to `.env` file: `PEXELS_API_KEY=your_key_here`

### Repository Setup
- [ ] Create feature branch: `git checkout -b feature/shader-generation`
- [ ] Verify Python environment: `cd python-vj && pip install -r requirements.txt`
- [ ] Verify Processing runs: Open `processing-vj/src/VJUniverse/VJUniverse.pde`

---

## Phase 1: Core Infrastructure (2-3 weeks)

### Python Module Structure
- [ ] Create directory: `python-vj/shadergen/`
- [ ] Create `python-vj/shadergen/__init__.py`
- [ ] Create `python-vj/shadergen/schema.py`
- [ ] Create `python-vj/shadergen/lmstudio_client.py`
- [ ] Create `python-vj/shadergen/mcp_clients.py`
- [ ] Create `python-vj/shadergen/prompts.py`
- [ ] Create `python-vj/shadergen/pipeline.py`

### Domain Models (schema.py)
- [ ] Implement `TextureRole` enum (BASE, DETAIL, MASK, NOISE)
- [ ] Implement `TextureInfo` dataclass (frozen=True)
- [ ] Implement `ShaderSpec` dataclass (frozen=True)
- [ ] Implement `ShaderArtifact` dataclass (frozen=True)
- [ ] Add `ShaderArtifact.write_to_disk()` method
- [ ] Write unit tests: `python-vj/tests/test_shadergen/test_schema.py`

### LM Studio Client (lmstudio_client.py)
- [ ] Implement `ShaderSpecGenerator` class
- [ ] Implement `__init__()` method (connection setup)
- [ ] Implement `_init_backend()` method (detect LM Studio)
- [ ] Implement `generate_spec()` method (spec generation)
- [ ] Implement `generate_shader_code()` method (GLSL generation)
- [ ] Implement `select_textures()` method (image selection)
- [ ] Add error handling (connection failures, invalid JSON)
- [ ] Write unit tests: `python-vj/tests/test_shadergen/test_lmstudio_client.py`

### Prompts (prompts.py)
- [ ] Define `SHADER_SPEC_SYSTEM_PROMPT` constant
- [ ] Define `SHADER_CODE_SYSTEM_PROMPT` constant
- [ ] Implement `build_shader_spec_prompt()` function
- [ ] Implement `build_shader_code_prompt()` function
- [ ] Add reference GLSL 150 examples in prompts

### Processing Extension
- [ ] Create `processing-vj/src/VJUniverse/DynamicShaderLoader.pde`
- [ ] Implement `setupDynamicShaderLoader()` function
- [ ] Implement `updateDynamicShaderLoader()` function
- [ ] Implement `loadDynamicShader()` function
- [ ] Implement `loadShaderTextures()` function
- [ ] Implement `sendShaderStatus()` function
- [ ] Add OSC handler in `VJUniverse.pde`: `/shader/load`
- [ ] Add `updateDynamicShaderLoader()` call in `draw()`

### Testing Phase 1
- [ ] Unit test: Domain model creation and validation
- [ ] Unit test: LM Studio connection (mock)
- [ ] Manual test: LM Studio generates shader spec JSON
- [ ] Manual test: OSC `/shader/load` message received by Processing
- [ ] Manual test: Write dummy shader files and load via OSC

---

## Phase 2: MCP Integration (1-2 weeks)

### MCP Clients (mcp_clients.py)
- [ ] Implement `PexelsImageSearch` class
- [ ] Implement `PexelsImageSearch.__init__()` (MCP connection)
- [ ] Implement `PexelsImageSearch.search()` method
- [ ] Implement `PexelsImageSearch.download_photo()` method
- [ ] Implement `ImageDownloader` class
- [ ] Implement `ImageDownloader.__init__()` (MCP connection)
- [ ] Implement `ImageDownloader.download()` method
- [ ] Add error handling (MCP server offline, API rate limits)
- [ ] Write unit tests: `python-vj/tests/test_shadergen/test_mcp_clients.py`

### Pipeline Integration
- [ ] Create `python-vj/shadergen/pipeline.py`
- [ ] Implement `ShaderGenerationOrchestrator` class
- [ ] Implement `__init__()` with dependency injection
- [ ] Implement `generate()` method (full pipeline)
- [ ] Implement `send_to_processing()` method (OSC sender)
- [ ] Implement `_build_texture_query()` helper
- [ ] Implement `_generate_name()` helper
- [ ] Implement `_build_metadata()` helper
- [ ] Add error handling and logging
- [ ] Write unit tests: `python-vj/tests/test_shadergen/test_pipeline.py`

### Testing Phase 2
- [ ] Integration test: Pexels search returns results
- [ ] Integration test: Images download successfully
- [ ] Integration test: Files written to disk (shader_dir/)
- [ ] Manual test: Full pipeline from song title to downloaded textures

---

## Phase 3: Shader Code Generation (2-3 weeks)

### GLSL Generation
- [ ] Create reference GLSL 150 examples (vertex + fragment)
- [ ] Test LLM generates valid GLSL 150 syntax
- [ ] Test LLM includes Processing uniforms (time, resolution, mouse)
- [ ] Test LLM includes audio uniforms (bass, mid, highs, level, beat)
- [ ] Test LLM includes texture samplers (texture0, texture1, etc.)
- [ ] Add GLSL validation (syntax checking with regex or parser)
- [ ] Add retry logic for invalid GLSL

### Processing Integration
- [ ] Test `loadShader()` with generated GLSL 150
- [ ] Test vertex shader compiles in Processing
- [ ] Test fragment shader compiles in Processing
- [ ] Test textures bind correctly
- [ ] Test shader renders without errors
- [ ] Test audio uniforms update correctly
- [ ] Verify 60fps performance at 1280x720

### File Output
- [ ] Create output directory: `processing-vj/src/VJUniverse/data/shaders/generated/`
- [ ] Implement `meta.json` writing
- [ ] Implement `uniforms.json` writing
- [ ] Test file structure matches specification

### Testing Phase 3
- [ ] Integration test: Generate complete shader artifact
- [ ] Integration test: Load shader in Processing via OSC
- [ ] Manual test: Shader renders at 60fps
- [ ] Manual test: Audio reactivity works (bass modulates visuals)
- [ ] Manual test: Textures display correctly

---

## Phase 4: Integration & Polish (1-2 weeks)

### VJ Console Integration
- [ ] Add shader generation command to VJ Console
- [ ] Create UI screen for shader generation (optional)
- [ ] Add status display (generation progress)
- [ ] Add error display (generation failures)
- [ ] Add shader gallery/history view (optional)

### Command-Line Interface
- [ ] Create `python-vj/shadergen_cli.py`
- [ ] Implement `generate` command
- [ ] Implement `list` command (show generated shaders)
- [ ] Implement `reload` command (re-load shader in Processing)
- [ ] Add argument parsing (song title, description, reference image)
- [ ] Add help text

### Status Feedback Loop
- [ ] Implement OSC receiver in Python for `/shader/status`
- [ ] Log status messages
- [ ] Update UI with status
- [ ] Handle errors gracefully (shader load failures)

### Error Handling
- [ ] Handle LM Studio offline gracefully
- [ ] Handle MCP server offline gracefully
- [ ] Handle Pexels API rate limits
- [ ] Handle invalid GLSL (retry or fallback)
- [ ] Handle missing textures (use fallback)
- [ ] Handle Processing shader compilation errors

### Testing Phase 4
- [ ] Integration test: Full end-to-end workflow
- [ ] Integration test: OSC status feedback works
- [ ] Integration test: Error handling covers all scenarios
- [ ] Manual test: CLI generates shader successfully
- [ ] Manual test: VJ Console integration works (if implemented)

---

## Documentation & Testing

### Unit Tests
- [ ] Write `tests/test_shadergen/test_schema.py` (domain models)
- [ ] Write `tests/test_shadergen/test_lmstudio_client.py` (LLM client)
- [ ] Write `tests/test_shadergen/test_mcp_clients.py` (MCP clients)
- [ ] Write `tests/test_shadergen/test_pipeline.py` (orchestrator)
- [ ] All unit tests pass: `pytest python-vj/tests/test_shadergen/ -v`

### Integration Tests
- [ ] Write `tests/integration/test_mcp_integration.py` (real MCP calls)
- [ ] Write `tests/integration/test_processing_osc.py` (OSC loop)
- [ ] Write `tests/integration/test_shader_compilation.py` (GLSL validation)
- [ ] All integration tests pass: `pytest python-vj/tests/integration/ -v`

### Manual Testing
- [ ] Test: LM Studio running with model loaded
- [ ] Test: Pexels MCP server running with API key
- [ ] Test: VJUniverse Processing sketch running
- [ ] Test: Generate shader from song title only
- [ ] Test: Generate shader with description
- [ ] Test: Generate shader with reference image (VLM)
- [ ] Test: Shader renders at 60fps
- [ ] Test: Audio reactivity works
- [ ] Test: Error handling (offline services, bad GLSL, etc.)

### Documentation
- [ ] Update `python-vj/README.md` (document new module)
- [ ] Update `processing-vj/README.md` (document OSC extensions)
- [ ] Create user guide: `docs/operation/SHADER_GENERATION_GUIDE.md`
- [ ] Create developer guide: `docs/development/SHADER_GENERATION_DEV.md`
- [ ] Create API reference: `docs/reference/SHADER_GENERATION_API.md`
- [ ] Update main `README.md` (add shader generation section)

---

## Deployment & Release

### Pre-Release Checks
- [ ] All unit tests pass
- [ ] All integration tests pass
- [ ] Manual testing complete (all scenarios)
- [ ] Documentation complete
- [ ] Code review complete
- [ ] Security review (API keys, attribution)
- [ ] Performance profiling (generation time, runtime fps)

### Release Preparation
- [ ] Update `CHANGELOG.md` (add shader generation feature)
- [ ] Tag release: `git tag v1.0.0-shader-gen`
- [ ] Create release notes
- [ ] Update installation instructions
- [ ] Create demo video (optional)
- [ ] Create example shaders (showcase)

### Post-Release
- [ ] Monitor for issues
- [ ] Gather user feedback
- [ ] Plan Phase 5+ enhancements (see implementation plan)

---

## Optional Enhancements (Phase 5+)

### Reference Image Support (VLM)
- [ ] Install Qwen2-VL-Instruct model in LM Studio
- [ ] Implement image-to-spec analysis
- [ ] Test with reference images
- [ ] Document workflow

### Shader Refinement
- [ ] Add `refine_shader()` method (iterate on existing shader)
- [ ] UI for refinement (tweak parameters)
- [ ] Test refinement workflow

### Shader Caching
- [ ] Implement cache key (song title + description hash)
- [ ] Check cache before generating
- [ ] Add TTL (24 hours)
- [ ] Manual cache clear command

### Shader Rating System
- [ ] Track which shaders perform well (fps, user ratings)
- [ ] Use ratings to improve prompts
- [ ] Auto-select best shaders for similar songs

### Batch Generation
- [ ] Generate multiple shader variations
- [ ] Let user select best one
- [ ] Compare side-by-side in Processing

---

## Progress Tracking

**Status Key**: ⬜ Not started | 🔄 In progress | ✅ Complete | ❌ Blocked

| Phase | Status | Estimated Time | Actual Time | Notes |
|-------|--------|---------------|-------------|-------|
| Pre-Implementation Setup | ⬜ | 1-2 days | - | |
| Phase 1: Core Infrastructure | ⬜ | 2-3 weeks | - | |
| Phase 2: MCP Integration | ⬜ | 1-2 weeks | - | |
| Phase 3: Shader Code Generation | ⬜ | 2-3 weeks | - | |
| Phase 4: Integration & Polish | ⬜ | 1-2 weeks | - | |
| Documentation & Testing | ⬜ | Ongoing | - | |
| Deployment & Release | ⬜ | 1 week | - | |

**Overall Progress**: 0% (0 / 200+ items)

---

## Notes & Blockers

*Use this section to track issues, blockers, and important decisions during implementation.*

### Blockers
- None yet

### Important Decisions
- None yet

### Issues
- None yet

### Questions
- None yet

---

**Last Updated**: 2025-01-15  
**Implementation Start Date**: TBD  
**Target Completion Date**: TBD

**See Also**:
- [SHADER_GENERATION_IMPLEMENTATION_PLAN.md](./SHADER_GENERATION_IMPLEMENTATION_PLAN.md)
- [SHADER_GENERATION_QUICK_REFERENCE.md](./SHADER_GENERATION_QUICK_REFERENCE.md)
- [SHADER_GENERATION_ARCHITECTURE_DIAGRAM.md](./SHADER_GENERATION_ARCHITECTURE_DIAGRAM.md)
