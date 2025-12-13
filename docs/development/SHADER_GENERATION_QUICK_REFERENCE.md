# Dynamic Shader Generation - Quick Reference

**Full Plan**: See [SHADER_GENERATION_IMPLEMENTATION_PLAN.md](./SHADER_GENERATION_IMPLEMENTATION_PLAN.md)

---

## Overview

Generate **Processing P3D PShaders (GLSL 150)** + textures using:
- **LM Studio** (Qwen2.5-Coder-32B) for code generation
- **MCP servers** (Pexels, Image Downloader) for textures
- **OSC** for hot-loading into VJUniverse

**Input**: Song title + optional description + optional reference image  
**Output**: `.vert` + `.frag` + textures → loaded via OSC

---

## Architecture Summary

```
User Input → Python Orchestrator → LM Studio → Shader Spec
                    ↓
            MCP Image Search (Pexels)
                    ↓
            Download Images (MCP Downloader)
                    ↓
            Generate GLSL 150 Code (LM Studio)
                    ↓
            Write Files → OSC → VJUniverse
```

---

## File Structure

### Python Module: `python-vj/shadergen/`

```
shadergen/
├── __init__.py
├── pipeline.py           # Main orchestrator
├── schema.py             # Domain models (ShaderSpec, TextureInfo, etc.)
├── lmstudio_client.py    # LM Studio adapter
├── mcp_clients.py        # MCP server clients (Pexels, Downloader)
└── prompts.py            # LLM prompt templates
```

### Processing Extension: `processing-vj/src/VJUniverse/`

```
DynamicShaderLoader.pde   # New file: OSC handler + hot-loader
VJUniverse.pde            # Modified: Add /shader/load handler
```

### Output Directory: `processing-vj/src/VJUniverse/data/shaders/generated/`

```
<shader_name>/
├── shader.vert           # GLSL 150 vertex shader
├── shader.frag           # GLSL 150 fragment shader
├── texture_base.jpg      # Primary texture
├── texture_detail.jpg    # Detail texture (optional)
├── meta.json             # Generation metadata + attribution
└── uniforms.json         # Runtime parameter schema
```

---

## Key Components

### Python Classes

| Class | Module | Purpose |
|-------|--------|---------|
| `ShaderSpec` | `schema.py` | Immutable spec (style, palette, motion, textures) |
| `TextureInfo` | `schema.py` | Texture metadata (path, role, attribution) |
| `ShaderArtifact` | `schema.py` | Complete output (code + textures + metadata) |
| `ShaderSpecGenerator` | `lmstudio_client.py` | LM Studio adapter (spec + code generation) |
| `PexelsImageSearch` | `mcp_clients.py` | MCP client for Pexels |
| `ImageDownloader` | `mcp_clients.py` | MCP client for image downloads |
| `ShaderGenerationOrchestrator` | `pipeline.py` | Main pipeline coordinator |

### Processing Functions

| Function | File | Purpose |
|----------|------|---------|
| `loadDynamicShader()` | `DynamicShaderLoader.pde` | Load shader + textures from disk |
| `loadShaderTextures()` | `DynamicShaderLoader.pde` | Load PImage textures |
| `sendShaderStatus()` | `DynamicShaderLoader.pde` | Send OSC status back to Python |
| `oscEvent()` | `VJUniverse.pde` | Handle `/shader/load` message |

---

## OSC Protocol

### Python → Processing

```
/shader/load [shader_dir: string, metadata: json_string]
```

**Example**:
```python
osc.send("/shader/load", [
    "/path/to/shaders/generated/cosmic_waves",
    '{"name": "cosmic_waves", "textures": [...], ...}'
])
```

### Processing → Python

```
/shader/status [success: int, message: string]
```

**Example**:
```java
msg.add(1);  // 1 = success, 0 = failure
msg.add("Loaded successfully");
```

---

## Data Models

### `ShaderSpec` (Python)

```python
@dataclass(frozen=True)
class ShaderSpec:
    style: str                      # "abstract geometric"
    palette: List[str]              # ["#ff0000", "#00ff00"]
    motion_type: str                # "pulsing", "rotating", "flowing"
    texture_roles: List[TextureRole] # [TextureRole.BASE, TextureRole.DETAIL]
    uniforms: Dict[str, Any]        # Custom uniforms
    audio_reactive: bool = True
    complexity: str = "medium"      # "low", "medium", "high"
```

### `meta.json` (Output)

```json
{
  "name": "cosmic_waves",
  "song_title": "Cosmic Journey",
  "generated_at": "2025-01-15T12:00:00Z",
  "model": "qwen2.5-coder-32b-instruct",
  "spec": {
    "style": "abstract flow",
    "palette": ["#0a2463", "#fb3640"],
    "motion_type": "flowing"
  },
  "textures": [
    {
      "filename": "texture_base.jpg",
      "role": "base",
      "attribution": "Photo by John Doe on Pexels",
      "url": "https://...",
      "width": 2048,
      "height": 1536
    }
  ]
}
```

---

## MCP Servers

### Pexels MCP Server

**Repository**: https://github.com/CaullenOmdahl/pexels-mcp-server

**Setup**:
```bash
npm install -g @pexels/mcp-server
export PEXELS_API_KEY=your_key_here
```

**Tools**:
- `pexels_search(query, count)` → List of photos
- `downloadPhoto(photo_id, path)` → Download with attribution

### Image Downloader MCP Server

**Repository**: https://github.com/qpd-v/mcp-image-downloader

**Setup**:
```bash
npm install -g mcp-image-downloader
```

**Tools**:
- `download_image(url, path, max_width)` → Download + optimize

---

## LM Studio Configuration

### Recommended Models

1. **Code Generation**: Qwen2.5-Coder-32B-Instruct (GGUF, 8-bit)
   - Quantization: Q8_0 (16GB VRAM) or Q4_K_M (8GB VRAM)
   - Use for: Shader spec + GLSL code generation

2. **VLM (Optional)**: Qwen2-VL-Instruct
   - Use for: Reference image analysis

### API Settings

**Endpoint**: `http://localhost:1234/v1/chat/completions`

**Parameters**:
```json
{
  "model": "qwen2.5-coder-32b-instruct",
  "temperature": 0.3,
  "max_tokens": 4096
}
```

---

## GLSL 150 Requirements

### Vertex Shader Template

```glsl
#version 150

in vec4 position;
in vec2 texCoord;

uniform mat4 transform;

out vec2 vTexCoord;

void main() {
    vTexCoord = texCoord;
    gl_Position = transform * position;
}
```

### Fragment Shader Template

```glsl
#version 150

uniform float time;
uniform vec2 resolution;
uniform vec2 mouse;

// Audio uniforms (injected by VJUniverse)
uniform float bass;
uniform float mid;
uniform float highs;
uniform float level;
uniform float beat;

// Textures
uniform sampler2D texture0;
uniform sampler2D texture1;

in vec2 vTexCoord;

out vec4 fragColor;

void main() {
    vec2 uv = vTexCoord;
    
    // Your shader code here
    vec3 color = texture(texture0, uv).rgb;
    
    // Audio reactivity example
    color *= 1.0 + bass * 0.5;
    
    fragColor = vec4(color, 1.0);
}
```

---

## Implementation Phases

### Phase 1: Core Infrastructure (2-3 weeks)
- ✅ Create `shadergen/` module structure
- ✅ Implement domain models (`schema.py`)
- ✅ Basic LM Studio integration
- ✅ OSC handler in VJUniverse

### Phase 2: MCP Integration (1-2 weeks)
- ✅ Deploy Pexels MCP server
- ✅ Implement MCP clients
- ✅ Texture download workflow

### Phase 3: Shader Code Generation (2-3 weeks)
- ✅ GLSL code generation prompts
- ✅ Code validation
- ✅ Processing integration

### Phase 4: Integration & Polish (1-2 weeks)
- ✅ VJ Console integration
- ✅ Status feedback loop
- ✅ Error handling
- ✅ Tests + documentation

**Total Estimate**: 7-11 weeks part-time, 4-6 weeks full-time

---

## Testing Checklist

### Prerequisites
- [ ] LM Studio running with Qwen2.5-Coder loaded
- [ ] Pexels MCP server running (with API key)
- [ ] Image Downloader MCP server running
- [ ] VJUniverse Processing sketch running

### Pipeline Tests
- [ ] Generate shader spec JSON from song title
- [ ] MCP search returns 4 texture candidates
- [ ] LLM selects and assigns texture roles
- [ ] Images download successfully
- [ ] GLSL 150 code generation produces valid syntax
- [ ] Vertex shader compiles in Processing
- [ ] Fragment shader compiles in Processing

### Integration Tests
- [ ] OSC `/shader/load` message sends correctly
- [ ] Processing loads shader without errors
- [ ] Shader renders at 60fps in HD
- [ ] Audio reactivity uniforms work
- [ ] Textures display correctly
- [ ] Status message returns to Python

### Error Handling Tests
- [ ] Bad GLSL code → error message + fallback
- [ ] Missing texture → error message + fallback
- [ ] LM Studio offline → graceful degradation
- [ ] MCP server offline → graceful degradation

---

## Quick Commands

### Start Development Environment

```bash
# Terminal 1: LM Studio (GUI or CLI)
lmstudio server start

# Terminal 2: Pexels MCP Server
export PEXELS_API_KEY=your_key_here
pexels-mcp-server

# Terminal 3: Image Downloader MCP Server
image-downloader-mcp-server

# Terminal 4: Python VJ Console
cd python-vj
python vj_console.py

# Terminal 5: Processing VJUniverse
# Open in Processing IDE and run
```

### Generate Shader (Future CLI)

```bash
python -m shadergen generate "Cosmic Journey" \
    --description "Abstract flowing particles" \
    --reference-image image.jpg
```

### Test OSC Communication

```python
from osc_manager import osc

# Send test load message
osc.send("/shader/load", [
    "/path/to/shaders/generated/test_shader",
    '{"name": "test_shader", "textures": []}'
])
```

---

## Troubleshooting

### Issue: LM Studio not responding

**Check**:
- Is LM Studio running? (`http://localhost:1234/v1/models`)
- Is model loaded? (check LM Studio UI)
- Check logs: `~/.lmstudio/logs/`

**Fix**: Restart LM Studio, load model manually

### Issue: MCP server not found

**Check**:
- Is Node.js installed? (`node --version`)
- Is package installed globally? (`npm list -g`)
- Is server process running? (`ps aux | grep mcp`)

**Fix**: Install package, start server manually

### Issue: Shader compilation error in Processing

**Check**:
- Is GLSL version 150? (first line of `.frag`)
- Are all uniforms declared?
- Are texture samplers correct? (`sampler2D`)

**Fix**: Validate GLSL syntax, check Processing console errors

### Issue: Textures not loading

**Check**:
- Do texture files exist? (`ls shaders/generated/<name>/`)
- Are file paths absolute or relative to Processing `data/` folder?
- Is image format supported? (JPG, PNG)

**Fix**: Use absolute paths, convert images to JPG/PNG

---

## Performance Guidelines

### Shader Complexity Limits

| Complexity | Raymarching Steps | Texture Samples | Loop Iterations |
|------------|------------------|-----------------|-----------------|
| Low        | 10-20            | 1-2 per pixel   | <50             |
| Medium     | 20-40            | 2-4 per pixel   | 50-100          |
| High       | 40-80            | 4-8 per pixel   | 100-200         |

### Optimization Tips

1. **Avoid in fragment shader**:
   - Dynamic branching (`if` based on uniforms)
   - Complex math in tight loops (`pow`, `exp`, `sin`)
   - Large texture samples (>2048x2048)

2. **Prefer**:
   - Precalculated lookup tables
   - Simplified math (`mix`, `smoothstep`, `clamp`)
   - Shared calculations (move to vertex shader if possible)

3. **Audio Reactivity**:
   - Modulate existing motion, don't add new complexity
   - Use smoothed values (`bass` not raw FFT)
   - Scale effects, don't branch

---

## Security Notes

### API Keys

**Never commit**:
- `PEXELS_API_KEY`
- `LM_STUDIO_API_KEY` (if using remote)

**Use `.env` file**:
```bash
# .env (in .gitignore)
PEXELS_API_KEY=your_key_here
LM_STUDIO_URL=http://localhost:1234
```

### Image Attribution

**Always store** in `meta.json`:
```json
{
  "textures": [
    {
      "attribution": "Photo by John Doe on Pexels",
      "license": "Pexels License",
      "url": "https://www.pexels.com/photo/..."
    }
  ]
}
```

**Pexels License**: Free for commercial use, no attribution required (but recommended)

### Generated Code

**LLM output considerations**:
- Not copyrightable (model output)
- Safe for performances
- Add comment: "Generated by AI (Qwen2.5-Coder)"

---

## Resources

### Documentation
- [Full Implementation Plan](./SHADER_GENERATION_IMPLEMENTATION_PLAN.md)
- [ISF to Synesthesia Migration](../reference/isf-to-synesthesia-migration.md)
- [Processing Shader Guide](https://processing.org/tutorials/pshader/)

### External Links
- [LM Studio Docs](https://lmstudio.ai/docs)
- [MCP Protocol Spec](https://github.com/modelcontextprotocol/mcp)
- [Pexels API](https://www.pexels.com/api/)
- [GLSL 150 Reference](https://www.khronos.org/opengl/wiki/Core_Language_(GLSL))

### Example Shaders
- `processing-vj/src/VJUniverse/data/shaders/glsl/` (existing GLSL examples)
- `synesthesia-shaders/` (Synesthesia scenes for reference)

---

**Last Updated**: 2025-01-15  
**Status**: Implementation Ready
