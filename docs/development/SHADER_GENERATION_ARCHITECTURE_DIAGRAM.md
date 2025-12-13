# Dynamic Shader Generation - Architecture Diagram

## High-Level System Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                           USER INPUT                                  │
│                                                                       │
│  Song Title: "Cosmic Journey"                                        │
│  Description: "Abstract flowing particles with neon colors"          │
│  Reference Image: space.jpg (optional)                               │
└───────────────────────────────┬──────────────────────────────────────┘
                                │
                                ▼
┌──────────────────────────────────────────────────────────────────────┐
│                    PYTHON ORCHESTRATOR                                │
│                  (python-vj/shadergen/)                               │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  ShaderGenerationOrchestrator (pipeline.py)                  │    │
│  │  - Coordinates entire workflow                               │    │
│  │  - Dependency injection: LLM, MCP clients, OSC              │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │ LM Studio    │  │ MCP Clients  │  │ OSC Manager  │              │
│  │ Client       │  │ (Pexels +    │  │ (existing)   │              │
│  │ (extend      │  │  Downloader) │  │              │              │
│  │ ai_services) │  │ (new)        │  │              │              │
│  └──────────────┘  └──────────────┘  └──────────────┘              │
│         │                  │                  │                      │
└─────────┼──────────────────┼──────────────────┼──────────────────────┘
          │                  │                  │
          ▼                  ▼                  │
┌─────────────────┐  ┌─────────────────┐      │
│   LM STUDIO     │  │  MCP SERVERS    │      │
│   (localhost)   │  │  (Node.js)      │      │
│                 │  │                 │      │
│  Qwen2.5-Coder  │  │  - Pexels       │      │
│  32B-Instruct   │  │  - Image DL     │      │
└─────────────────┘  └─────────────────┘      │
          │                  │                  │
          │ Shader Spec      │ Images          │ OSC
          ▼                  ▼                  ▼
┌──────────────────────────────────────────────────────────────────────┐
│                    FILE SYSTEM OUTPUT                                 │
│                                                                       │
│  processing-vj/src/VJUniverse/data/shaders/generated/                │
│  └── cosmic_journey_2025_01_15_001/                                 │
│      ├── shader.vert         (GLSL 150 vertex shader)               │
│      ├── shader.frag         (GLSL 150 fragment shader)             │
│      ├── texture_base.jpg    (Downloaded from Pexels)               │
│      ├── texture_detail.jpg  (Downloaded from Pexels)               │
│      ├── meta.json           (Metadata + attribution)               │
│      └── uniforms.json       (Runtime parameters)                   │
└───────────────────────────────┬──────────────────────────────────────┘
                                │
                                │ OSC: /shader/load
                                ▼
┌──────────────────────────────────────────────────────────────────────┐
│                    PROCESSING VJUNIVERSE (P3D)                        │
│                  (processing-vj/src/VJUniverse/)                      │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  DynamicShaderLoader.pde (NEW)                               │    │
│  │  - OSC handler for /shader/load                              │    │
│  │  - Hot-load shader.vert + shader.frag                        │    │
│  │  - Load PImage textures                                      │    │
│  │  - Send status: /shader/status                               │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                       │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  ShaderManager.pde (EXISTING)                                 │   │
│  │  - Convert GLSL for Processing                                │   │
│  │  - Inject audio uniforms (bass, mid, highs, level, beat)     │   │
│  │  - Compile and activate shader                                │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                       │
│                           ┌────────────┐                             │
│                           │  RENDER    │                             │
│                           │  60fps HD  │                             │
│                           │  + Syphon  │                             │
│                           └────────────┘                             │
└───────────────────────────────┬──────────────────────────────────────┘
                                │
                                │ OSC: /shader/status [success, message]
                                ▼
┌──────────────────────────────────────────────────────────────────────┐
│                    STATUS FEEDBACK (Python)                           │
│  - Log result                                                        │
│  - Update UI (VJ Console)                                            │
│  - Handle errors gracefully                                          │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Python Module Structure

```
python-vj/
├── shadergen/                          # NEW MODULE
│   ├── __init__.py
│   ├── pipeline.py                     # Main orchestrator
│   │   └── ShaderGenerationOrchestrator
│   │       - generate(song, desc, img) → ShaderArtifact
│   │       - send_to_processing(artifact) → bool
│   │
│   ├── schema.py                       # Domain models (frozen dataclasses)
│   │   ├── ShaderSpec (style, palette, motion, textures)
│   │   ├── TextureInfo (path, role, attribution)
│   │   └── ShaderArtifact (code + textures + metadata)
│   │
│   ├── lmstudio_client.py             # LM Studio adapter
│   │   └── ShaderSpecGenerator
│   │       - generate_spec() → ShaderSpec
│   │       - generate_shader_code() → (vert, frag)
│   │       - select_textures() → List[TextureInfo]
│   │
│   ├── mcp_clients.py                 # MCP server adapters
│   │   ├── PexelsImageSearch
│   │   │   - search(query, count) → List[ImageResult]
│   │   │   - download_photo() → TextureInfo
│   │   └── ImageDownloader
│   │       - download(url, path) → TextureInfo
│   │
│   └── prompts.py                     # LLM prompt templates
│       ├── SHADER_SPEC_SYSTEM_PROMPT
│       ├── SHADER_CODE_SYSTEM_PROMPT
│       ├── build_shader_spec_prompt()
│       └── build_shader_code_prompt()
│
├── ai_services.py                     # EXTENDED
│   └── LLMAnalyzer (existing, reuse patterns)
│
├── osc_manager.py                     # EXISTING (reuse)
│   └── OSCManager.send()
│
└── orchestrators.py                   # EXISTING (add to)
    └── ShaderOrchestrator (high-level coordinator)
```

---

## Processing Extension Structure

```
processing-vj/src/VJUniverse/
├── VJUniverse.pde                      # MODIFIED
│   └── oscEvent()
│       └── if (/shader/load) → pendingShaderPath = ...
│
├── DynamicShaderLoader.pde             # NEW FILE
│   ├── loadDynamicShader(path, meta)
│   ├── loadShaderTextures(path, meta) → ArrayList<PImage>
│   └── sendShaderStatus(success, msg)
│
└── ShaderManager.pde                   # EXISTING (reuse)
    ├── loadGlslShader()
    ├── convertGlslForProcessing()
    └── generateAudioUniformDeclarations()
```

---

## Data Flow Sequence

```
1. USER
   │
   │ song_title, description, reference_image
   ▼
   
2. PYTHON: ShaderGenerationOrchestrator.generate()
   │
   ├─→ ShaderSpecGenerator.generate_spec()
   │   │
   │   └─→ LM Studio API: /v1/chat/completions
   │       │ Prompt: "Generate shader spec for 'Cosmic Journey'..."
   │       │ Response: { style: "abstract", palette: [...], ... }
   │       └─→ ShaderSpec (domain model)
   │
   ├─→ PexelsImageSearch.search("abstract cosmic particles", 4)
   │   │
   │   └─→ MCP Pexels Server: pexels_search
   │       │ Response: [{ url: "...", attribution: "...", ... }, ...]
   │       └─→ List[ImageResult]
   │
   ├─→ ShaderSpecGenerator.select_textures(spec, images)
   │   │
   │   └─→ LM Studio API: /v1/chat/completions
   │       │ Prompt: "Select 2 images for base and detail roles..."
   │       └─→ List[(ImageResult, TextureRole)]
   │
   ├─→ ImageDownloader.download(url, path) × N
   │   │
   │   └─→ MCP Image Downloader: download_image
   │       │ Response: { path: "/local/path.jpg", width: 2048, ... }
   │       └─→ List[TextureInfo]
   │
   ├─→ ShaderSpecGenerator.generate_shader_code(spec, textures)
   │   │
   │   └─→ LM Studio API: /v1/chat/completions
   │       │ Prompt: "Generate GLSL 150 shader code..."
   │       │ Response: { vert: "...", frag: "..." }
   │       └─→ (vert_source, frag_source)
   │
   ├─→ ShaderArtifact.write_to_disk(output_dir)
   │   │
   │   └─→ FILE SYSTEM
   │       ├── shader.vert
   │       ├── shader.frag
   │       ├── texture_base.jpg
   │       ├── texture_detail.jpg
   │       ├── meta.json
   │       └── uniforms.json
   │
   └─→ ShaderGenerationOrchestrator.send_to_processing(artifact)
       │
       └─→ OSC: /shader/load [shader_dir, metadata_json]
       
3. PROCESSING: oscEvent() receives /shader/load
   │
   ├─→ pendingShaderPath = shader_dir
   ├─→ pendingMetadata = metadata_json
   └─→ shaderLoadPending = true
   
4. PROCESSING: updateDynamicShaderLoader() (in draw loop)
   │
   └─→ loadDynamicShader(shader_dir, metadata_json)
       │
       ├─→ Parse JSON metadata
       │
       ├─→ loadShader(shader.frag, shader.vert)
       │   │
       │   └─→ ShaderManager.loadGlslShader()
       │       └─→ Compile GLSL → PShader
       │
       ├─→ loadShaderTextures(shader_dir, metadata)
       │   │
       │   └─→ loadImage(texture_base.jpg) → PImage
       │       loadImage(texture_detail.jpg) → PImage
       │
       ├─→ activeShader = dynShader
       │
       └─→ sendShaderStatus(true, "Loaded successfully")
           │
           └─→ OSC: /shader/status [1, "Loaded successfully"]
           
5. PROCESSING: draw() loop
   │
   ├─→ shader(activeShader)
   ├─→ Set uniforms (time, bass, mid, highs, textures)
   ├─→ Draw fullscreen quad
   └─→ 60fps @ 1280x720
   
6. PYTHON: OSC receives /shader/status
   │
   └─→ Log result, update UI
```

---

## Key Interfaces

### Python → LM Studio (OpenAI-compatible API)

**Request**:
```json
POST http://localhost:1234/v1/chat/completions

{
  "model": "qwen2.5-coder-32b-instruct",
  "messages": [
    {
      "role": "system",
      "content": "You are a GLSL shader designer..."
    },
    {
      "role": "user",
      "content": "Generate shader spec for 'Cosmic Journey'..."
    }
  ],
  "temperature": 0.3,
  "max_tokens": 4096
}
```

**Response**:
```json
{
  "choices": [
    {
      "message": {
        "content": "{\"style\": \"abstract flow\", \"palette\": [\"#0a2463\"], ...}"
      }
    }
  ]
}
```

### Python → MCP Pexels Server

**Request** (stdio):
```json
{
  "jsonrpc": "2.0",
  "method": "tools/pexels_search",
  "params": {
    "query": "abstract cosmic particles",
    "count": 4
  },
  "id": 1
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "result": [
    {
      "url": "https://images.pexels.com/...",
      "attribution": "Photo by John Doe on Pexels",
      "width": 3840,
      "height": 2160
    }
  ],
  "id": 1
}
```

### Python → Processing (OSC)

**Message**: `/shader/load`

**Arguments**:
- `[0]` (string): Shader directory path
- `[1]` (string): JSON metadata

**Example**:
```python
osc.send("/shader/load", [
    "/Users/vj/processing/VJUniverse/data/shaders/generated/cosmic_journey",
    '{"name": "cosmic_journey", "textures": [{"filename": "texture_base.jpg"}]}'
])
```

### Processing → Python (OSC)

**Message**: `/shader/status`

**Arguments**:
- `[0]` (int): Success flag (1 = success, 0 = failure)
- `[1]` (string): Status message

**Example**:
```java
OscMessage msg = new OscMessage("/shader/status");
msg.add(1);
msg.add("Loaded successfully: cosmic_journey");
oscP5.send(msg, new NetAddress("127.0.0.1", 9001));
```

---

## State Management

### Python Orchestrator State
```python
class ShaderGenerationOrchestrator:
    _spec_gen: ShaderSpecGenerator        # Stateless service
    _image_search: PexelsImageSearch      # Stateless service
    _downloader: ImageDownloader          # Stateless service
    _osc: OSCSender                       # Shared singleton
    _output_dir: Path                     # Immutable config
```

**No mutable state** - All operations are pure functions with immutable inputs/outputs

### Processing State
```java
// Pending shader load (set by OSC, consumed by draw loop)
String pendingShaderPath = "";
String pendingMetadata = "";
boolean shaderLoadPending = false;

// Active shader (set by loader, used by draw)
PShader activeShader = null;
ArrayList<PImage> activeTextures = new ArrayList<PImage>();
```

**Thread-safe** - OSC handler writes, draw loop reads, boolean flag synchronizes

---

## Error Handling

### Python Error Flow
```
try:
    artifact = orchestrator.generate(song_title, description, image)
except LMStudioConnectionError:
    → Log error
    → Notify user: "LM Studio not available"
    → Return None
except MCPServerError:
    → Log error
    → Fallback to default textures
    → Continue with shader generation
except GLSLValidationError:
    → Log error
    → Retry with stricter prompt
    → If retry fails, return None
```

### Processing Error Flow
```java
try {
    PShader shader = loadShader(fragPath, vertPath);
    activeShader = shader;
    sendShaderStatus(true, "Loaded successfully");
} catch (Exception e) {
    println("Shader load failed: " + e.getMessage());
    sendShaderStatus(false, "Load failed: " + e.getMessage());
    activeShader = null; // Keep previous shader or default
}
```

---

## Performance Considerations

### Python Pipeline
- **Parallel downloads**: Use `ThreadPoolExecutor` for texture downloads
- **LLM caching**: Reuse same model instance (keep warm)
- **Texture caching**: Store search results (TTL 24h)

### Processing Runtime
- **Target**: 60fps @ 1280x720
- **Texture size limit**: 2048x2048 (GPU friendly)
- **Complexity limit**: Enforced in LLM prompts (no 100+ iteration loops)

---

**Diagram Version**: 1.0  
**Date**: 2025-01-15  
**See Also**: [SHADER_GENERATION_IMPLEMENTATION_PLAN.md](./SHADER_GENERATION_IMPLEMENTATION_PLAN.md)
