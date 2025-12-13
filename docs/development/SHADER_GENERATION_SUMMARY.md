# Dynamic Shader Generation - Implementation Summary

## What This Adds

A **complete pipeline** for dynamically generating Processing P3D shaders (GLSL 150) based on song metadata, using:

- **LM Studio** with Qwen2.5-Coder-32B for shader code generation
- **MCP (Model Context Protocol) servers** for texture search and download (Pexels, image downloader)
- **OSC hot-loading** into the existing VJUniverse Processing sketch
- **Python orchestration** following existing architecture patterns (domain/adapters/orchestrators)

## Architecture Highlights

### Existing Infrastructure (Leveraged)

✅ **Python VJ Console** - Already has LM Studio integration (`ai_services.py`)  
✅ **OSC Manager** - Centralized messaging system  
✅ **VJUniverse** - P3D shader engine with dynamic loading  
✅ **Domain-driven design** - Immutable models, deep modules, dependency injection

### New Components

**Python Module**: `python-vj/shadergen/`
- `pipeline.py` - Main orchestrator
- `schema.py` - Domain models (ShaderSpec, TextureInfo, ShaderArtifact)
- `lmstudio_client.py` - LM Studio adapter for shader generation
- `mcp_clients.py` - MCP server clients (Pexels, Image Downloader)
- `prompts.py` - LLM prompt templates

**Processing Extension**: `processing-vj/src/VJUniverse/`
- `DynamicShaderLoader.pde` - OSC handler + hot-loader for generated shaders

**OSC Protocol**:
- `/shader/load [shader_dir, metadata_json]` - Python → Processing
- `/shader/status [success, message]` - Processing → Python

## Data Flow

```
Song Title + Description + Reference Image (optional)
    ↓
LM Studio (Qwen2.5-Coder) → Shader Spec JSON
    ↓
MCP Pexels Search → Candidate Textures
    ↓
LLM Selects + Assigns Roles (base, detail, mask, noise)
    ↓
MCP Image Downloader → Save Textures
    ↓
LM Studio → Generate GLSL 150 (.vert + .frag)
    ↓
Write to disk: shaders/generated/<name>/
    ↓
OSC → VJUniverse Hot-Load
    ↓
Render at 60fps with Audio Reactivity
```

## Key Design Decisions

### 1. GLSL Version: 150 Core
- **Why**: Processing P3D target, modern OpenGL
- **Syntax**: `in`/`out` instead of `varying`, explicit `fragColor` output
- **Compatibility**: Works with existing VJUniverse shader infrastructure

### 2. MCP for Images (Not Direct APIs)
- **Why**: Standardized protocol, swappable sources, tool calling support
- **Servers**: Pexels (license-safe stock), Image Downloader (optimization)
- **Benefit**: Can add Unsplash, Brave Search, etc. without code changes

### 3. LM Studio (Not OpenAI)
- **Why**: Local execution, no API costs, privacy, offline capable
- **Model**: Qwen2.5-Coder-32B (best open-source code generation)
- **Existing**: Already integrated in `ai_services.py`

### 4. Dependency Injection
- **Why**: Testable, follows existing orchestrators pattern
- **Example**: `ShaderGenerationOrchestrator` accepts injected clients
- **Benefit**: Easy to mock for unit tests, swap implementations

### 5. Immutable Domain Models
- **Why**: Thread-safe, follows existing `domain.py` patterns
- **Example**: `ShaderSpec`, `TextureInfo`, `ShaderArtifact` are all `@dataclass(frozen=True)`
- **Benefit**: Predictable state, easy to reason about

## Implementation Phases

### Phase 1: Core Infrastructure (2-3 weeks)
- Create `shadergen/` module
- Implement domain models
- Basic LM Studio integration
- OSC handler in VJUniverse

### Phase 2: MCP Integration (1-2 weeks)
- Deploy Pexels MCP server
- Implement MCP clients
- Texture download workflow

### Phase 3: Shader Code Generation (2-3 weeks)
- GLSL code generation prompts
- Code validation
- Processing integration

### Phase 4: Integration & Polish (1-2 weeks)
- VJ Console integration
- Status feedback loop
- Error handling
- Tests + documentation

**Total**: 7-11 weeks part-time (10h/week), 4-6 weeks full-time

## Example Workflow (Future)

### Command Line
```bash
python -m shadergen generate "Cosmic Journey" \
    --description "Abstract flowing particles with neon colors" \
    --reference-image space.jpg
```

### VJ Console UI (Future)
```
[Shader Generation Screen]
Song: Cosmic Journey
Description: Abstract flowing particles
Reference: space.jpg
[Generate] [Cancel]

Status: Generating shader spec... ✓
Status: Searching textures... ✓
Status: Downloading images... ✓
Status: Generating GLSL code... ✓
Status: Loading in Processing... ✓

Shader loaded: cosmic_journey_2025_01_15_001
```

### Output Structure
```
processing-vj/src/VJUniverse/data/shaders/generated/
└── cosmic_journey_2025_01_15_001/
    ├── shader.vert          # GLSL 150 vertex shader
    ├── shader.frag          # GLSL 150 fragment shader
    ├── texture_base.jpg     # Primary texture (2048x1536)
    ├── texture_detail.jpg   # Detail texture (1024x768)
    ├── meta.json            # Generation metadata + attribution
    └── uniforms.json        # Runtime parameter schema
```

## Performance Targets

### Generation Time
- Spec generation: 2-5 seconds
- Texture search: 1-2 seconds
- Image download: 3-5 seconds
- Code generation: 3-8 seconds
- **Total**: 10-20 seconds per shader

### Runtime Performance
- **Target**: 60fps at 1280x720 (HD)
- **Complexity limits**: Built into LLM prompts
- **Audio reactivity**: Smooth uniform updates (bass, mid, highs, level, beat)

## Security & Licensing

### Image Sources
- **Pexels License**: Free for commercial use, no attribution required (but recommended)
- **Attribution**: Always stored in `meta.json` for proper credit
- **Safe for VJ work**: All sources are license-cleared stock photos

### Generated Code
- **LLM output**: Not copyrightable (model output)
- **Safe to use**: For performances, commercial work, etc.
- **Attribution note**: Can add "Generated by AI (Qwen2.5-Coder)" comment

### API Keys
- **Never committed**: Use `.env` file (already in `.gitignore`)
- **Required**: `PEXELS_API_KEY` (free tier: 200 requests/hour)
- **Optional**: LM Studio runs locally (no API key needed)

## Testing Strategy

### Unit Tests
- `test_schema.py` - Domain model validation
- `test_lmstudio_client.py` - Mock LLM responses
- `test_pipeline.py` - Orchestrator logic

### Integration Tests
- `test_mcp_integration.py` - Real Pexels search
- `test_processing_osc.py` - OSC communication loop
- `test_shader_compilation.py` - GLSL validation in Processing

### Manual Testing
- End-to-end workflow: song title → loaded shader
- Performance: 60fps target
- Audio reactivity: bass/mid/highs modulation
- Error handling: bad GLSL, missing textures, offline services

## Documentation

### Created Files
1. **[SHADER_GENERATION_IMPLEMENTATION_PLAN.md](./SHADER_GENERATION_IMPLEMENTATION_PLAN.md)** (35KB)
   - Complete architecture specification
   - Detailed component designs
   - Code examples for every module
   - Phase-by-phase implementation guide
   - Risk assessment and mitigation
   - Timeline estimates

2. **[SHADER_GENERATION_QUICK_REFERENCE.md](./SHADER_GENERATION_QUICK_REFERENCE.md)** (12KB)
   - Quick lookup guide
   - Command reference
   - Troubleshooting common issues
   - Performance guidelines

3. **docs/README.md** (updated)
   - Added links to new documentation
   - Quick navigation section updated

## Dependencies

### New Python Packages
```txt
mcp-python-sdk>=0.1.0  # If official SDK exists
pillow>=10.0.0         # Image validation
pydantic>=2.0.0        # Data validation
```

### New Node.js MCP Servers
```bash
npm install -g @pexels/mcp-server
npm install -g mcp-image-downloader
```

### Existing (Already Available)
- `openai` - LM Studio uses OpenAI-compatible API
- `python-osc` - OSC communication
- `requests` - HTTP requests

## Next Steps

1. **Review & Approve**: Review implementation plan
2. **Environment Setup**: Install LM Studio, MCP servers, Pexels API key
3. **Phase 1 Start**: Create `shadergen/` module structure
4. **Iterative Development**: Implement phases 1-4 sequentially
5. **Testing**: Unit + integration tests at each phase
6. **Documentation**: User guide + developer guide

## Success Criteria

### MVP (Minimum Viable Product)
- ✅ User provides song title
- ✅ System generates GLSL 150 shader
- ✅ System downloads 1-2 textures
- ✅ Shader loads in VJUniverse
- ✅ Shader renders at 30+ fps
- ✅ Basic audio reactivity works

### Full Success
- ✅ Optional visual description + reference image support
- ✅ 2-4 textures with assigned roles
- ✅ 60fps rendering
- ✅ Advanced audio reactivity
- ✅ Status feedback loop
- ✅ Error handling covers all failure modes
- ✅ Tests pass, documentation complete

## Why This Approach?

### Architectural Consistency
- **Follows existing patterns**: Domain models, adapters, orchestrators
- **Reuses infrastructure**: LM Studio, OSC, Processing
- **Minimal new dependencies**: MCP clients, image validation

### Future-Proof
- **Swappable LLMs**: Can add GPT-4, Claude, Codestral without architecture changes
- **Swappable image sources**: MCP protocol allows adding Unsplash, Pixabay, etc.
- **Extensible**: Easy to add reference image VLM, shader refinement, style transfer

### VJ-Focused
- **Performance first**: 60fps target built into prompts
- **Audio reactivity**: Core requirement, not afterthought
- **Live workflow**: Hot-loading, status feedback, error recovery
- **Attribution**: Proper credit for stock images

---

**Status**: Implementation plan ready for review  
**Estimated Effort**: 7-11 weeks part-time, 4-6 weeks full-time  
**Risk Level**: Medium (depends on LLM code quality, mitigated by validation)  
**Value**: High (unique feature, creative enabler, performance tool)
