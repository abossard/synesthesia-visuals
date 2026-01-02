# Dynamic Shader Generation - Implementation Plan

## Executive Summary

This document outlines the implementation plan for adding **dynamic shader generation** to the synesthesia-visuals project. The system will use **LM Studio** with **MCP (Model Context Protocol)** servers to generate **Processing P3D PShader** code (GLSL 150) and download web textures based on song metadata, visual descriptions, and optional reference images.

**Target**: Generate shaders that can be hot-loaded into the existing VJUniverse Processing sketch via OSC.

---

## Current System Architecture

### Existing Components (Leveraged)

1. **Python VJ Console** (`python-vj/`)
   - Domain-driven design: `domain.py` (immutable models), `adapters.py` (external services), `orchestrators.py` (coordinators)
   - **LM Studio integration already exists**: `ai_services.py` has `LLMAnalyzer` class with LM Studio support
   - **OSC communication**: `osc_manager.py` provides centralized OSC messaging
   - Architecture pattern: Deep modules with dependency injection

2. **Processing VJUniverse** (`processing-vj/src/VJUniverse/`)
   - P3D renderer with dynamic shader loading
   - OSC input on port 9000
   - `ShaderManager.pde`: Dynamic GLSL shader loading with auto-detection
   - Supports GLSL 150 (`#version 150`) with `in/out` syntax
   - Existing uniform injection: `time`, `mouse`, `resolution`, `speed`, audio reactivity uniforms

3. **OSC Protocol** (established patterns in `osc_manager.py`)
   - Flat arrays only (no nested structures)
   - Examples: `/karaoke/track`, `/audio/levels`

---

## System Architecture

### High-Level Data Flow

```
User Input → Python Orchestrator → LM Studio (Qwen2.5-Coder) → Shader Spec JSON
                    ↓
            MCP Image Search (Pexels/Brave/Unsplash)
                    ↓
            Image Selection & Download (MCP Image Downloader)
                    ↓
            Shader Code Generation (GLSL 150 vert + frag)
                    ↓
            Write Files (assets/shaders/generated/)
                    ↓
            OSC Message → Processing VJUniverse
                    ↓
            Hot-Load Shader + Textures
                    ↓
            OSC Status Response
```

### Component Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     Python Orchestrator                      │
│  (New: python-vj/shadergen/pipeline.py)                     │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │ LM Studio    │  │ MCP Clients  │  │ OSC Sender   │     │
│  │ Client       │  │ (Pexels,     │  │ (existing)   │     │
│  │ (existing)   │  │  Downloader) │  │              │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
└─────────────────────────────────────────────────────────────┘
                          ↓ OSC
┌─────────────────────────────────────────────────────────────┐
│              Processing VJUniverse (P3D)                     │
│  (Extended: processing-vj/src/VJUniverse/)                  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ New OSC Handler: /shader/load [path, metadata]      │  │
│  │ Hot-load shader.vert + shader.frag                   │  │
│  │ Load PImage textures                                 │  │
│  │ Send OSC status: /shader/status [success, message]  │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## Detailed Component Specifications

### 1. Python Orchestrator

**Location**: `python-vj/shadergen/`

#### File Structure
```
python-vj/
├── shadergen/
│   ├── __init__.py
│   ├── pipeline.py           # Main orchestrator (ShaderGenerationOrchestrator)
│   ├── schema.py             # Data models (ShaderSpec, TextureRole, etc.)
│   ├── lmstudio_client.py    # LM Studio API client (extends ai_services.py)
│   ├── mcp_clients.py        # MCP server clients (Pexels, Downloader)
│   └── prompts.py            # LLM prompt templates
├── orchestrators/
│   └── shader_orchestrator.py # High-level coordinator (integrates with pipeline)
└── requirements.txt          # Add: mcp (if client lib exists)
```

#### Module: `schema.py` (Domain Models)

**Purpose**: Immutable domain models following existing `domain.py` patterns

```python
from dataclasses import dataclass, field
from typing import List, Optional, Dict, Any
from enum import Enum

class TextureRole(Enum):
    """Texture roles in shader pipeline"""
    BASE = "base"           # Primary texture
    DETAIL = "detail"       # Detail/overlay texture
    MASK = "mask"          # Masking texture
    NOISE = "noise"        # Noise/distortion texture

@dataclass(frozen=True)
class TextureInfo:
    """Texture metadata"""
    path: str                   # Local file path
    role: TextureRole
    url: str                    # Original source URL
    attribution: str            # Required attribution text
    width: int = 0
    height: int = 0

@dataclass(frozen=True)
class ShaderSpec:
    """Shader generation specification (LLM output)"""
    style: str                  # e.g., "abstract geometric", "organic flow"
    palette: List[str]          # Hex color codes
    motion_type: str            # e.g., "pulsing", "rotating", "flowing"
    texture_roles: List[TextureRole]  # Which textures to request
    uniforms: Dict[str, Any]    # Custom uniform declarations
    audio_reactive: bool = True
    complexity: str = "medium"  # "low", "medium", "high"

@dataclass(frozen=True)
class ShaderArtifact:
    """Complete shader generation output"""
    name: str                   # Unique identifier
    vert_source: str            # Vertex shader GLSL
    frag_source: str            # Fragment shader GLSL
    textures: List[TextureInfo]
    spec: ShaderSpec
    metadata: Dict[str, Any]    # Generation metadata (model, prompts, etc.)
    
    def write_to_disk(self, base_path: Path) -> Path:
        """Write all files to disk, return shader directory path"""
        # Implementation in pipeline.py
        pass
```

#### Module: `lmstudio_client.py` (LM Studio Adapter)

**Purpose**: Deep module wrapping LM Studio OpenAI-compatible API + tool calling

**Extends**: Existing `ai_services.LLMAnalyzer` patterns

```python
class ShaderSpecGenerator:
    """
    Generate shader specifications using LM Studio with tool calling.
    
    Deep module interface:
        generate_spec(song_title, description, reference_image) -> ShaderSpec
        refine_spec(spec, feedback) -> ShaderSpec
        
    Hides: LM Studio API, structured output parsing, retry logic
    """
    
    LM_STUDIO_URL = "http://localhost:1234"
    RECOMMENDED_MODEL = "qwen2.5-coder-32b-instruct"
    
    def __init__(self):
        self._client = None
        self._model = None
        self._health = ServiceHealth("ShaderSpecGenerator")
        self._init_backend()
    
    def generate_spec(
        self,
        song_title: str,
        description: Optional[str] = None,
        reference_image: Optional[Path] = None
    ) -> Optional[ShaderSpec]:
        """Generate shader specification from inputs"""
        # Build prompt from song_title, description
        # If reference_image, use VLM model (Qwen2-VL-Instruct)
        # Call LM Studio with structured output schema
        # Parse JSON response into ShaderSpec
        pass
    
    def generate_shader_code(
        self,
        spec: ShaderSpec,
        textures: List[TextureInfo]
    ) -> tuple[str, str]:
        """Generate GLSL 150 vertex + fragment shader code"""
        # Use code generation model (Qwen2.5-Coder)
        # Prompt includes: spec, texture paths, Processing requirements
        # Return (vert_source, frag_source)
        pass
```

#### Module: `mcp_clients.py` (MCP Adapters)

**Purpose**: Deep modules wrapping MCP server protocols

**Recommended MCP Servers**:
1. **Pexels MCP Server** - Photo search with license-safe downloads
2. **MCP Image Downloader** - URL download with optimization

```python
class PexelsImageSearch:
    """
    MCP client for Pexels image search.
    
    Deep module interface:
        search(query, count) -> List[ImageResult]
        download_photo(photo_id, output_path) -> TextureInfo
        
    Hides: MCP protocol, Pexels API, attribution parsing
    """
    
    def __init__(self, mcp_server_path: str):
        # Initialize MCP client connection
        # Load Pexels API key from environment
        pass
    
    def search(self, query: str, count: int = 4) -> List[Dict]:
        """Search Pexels for images matching query"""
        # Call MCP tool: pexels_search
        # Return list of image metadata (url, attribution, dimensions)
        pass
    
    def download_photo(self, url: str, output_path: Path) -> TextureInfo:
        """Download and save photo, return TextureInfo"""
        # Call MCP tool: downloadPhoto
        # Parse attribution
        # Return TextureInfo with local path
        pass

class ImageDownloader:
    """
    MCP client for generic image download with optimization.
    
    Deep module interface:
        download(url, output_path, max_size) -> TextureInfo
        
    Hides: MCP protocol, image optimization, error handling
    """
    
    def __init__(self, mcp_server_path: str):
        pass
    
    def download(
        self,
        url: str,
        output_path: Path,
        max_width: int = 2048
    ) -> TextureInfo:
        """Download and optimize image"""
        # Call MCP tool: download_image
        # Apply resize if needed (Processing texture limits)
        pass
```

#### Module: `pipeline.py` (Orchestrator)

**Purpose**: Coordinate entire shader generation pipeline

```python
class ShaderGenerationOrchestrator:
    """
    Orchestrates shader generation pipeline.
    
    Dependency Injection:
        - spec_generator: ShaderSpecGenerator
        - image_search: PexelsImageSearch
        - downloader: ImageDownloader
        - osc_sender: OSCSender (from osc_manager)
    
    Interface:
        generate(song_title, description, reference_image) -> ShaderArtifact
        send_to_processing(artifact) -> bool
    """
    
    def __init__(
        self,
        spec_generator: ShaderSpecGenerator,
        image_search: PexelsImageSearch,
        downloader: ImageDownloader,
        osc_sender: OSCSender,
        output_dir: Path
    ):
        self._spec_gen = spec_generator
        self._image_search = image_search
        self._downloader = downloader
        self._osc = osc_sender
        self._output_dir = output_dir
    
    def generate(
        self,
        song_title: str,
        description: Optional[str] = None,
        reference_image: Optional[Path] = None
    ) -> Optional[ShaderArtifact]:
        """Execute full generation pipeline"""
        
        # 1. Generate shader spec from inputs
        spec = self._spec_gen.generate_spec(
            song_title, description, reference_image
        )
        if not spec:
            return None
        
        # 2. Search for textures based on spec
        query = self._build_texture_query(spec, song_title)
        image_results = self._image_search.search(query, count=4)
        
        # 3. Let LLM select images and assign roles
        selected_images = self._spec_gen.select_textures(
            spec, image_results
        )
        
        # 4. Download textures
        textures = []
        for img_meta, role in selected_images:
            texture_path = self._output_dir / f"texture_{role.value}.jpg"
            texture_info = self._downloader.download(
                img_meta['url'], texture_path
            )
            textures.append(texture_info)
        
        # 5. Generate shader code
        vert_src, frag_src = self._spec_gen.generate_shader_code(
            spec, textures
        )
        
        # 6. Create artifact and write to disk
        artifact = ShaderArtifact(
            name=self._generate_name(song_title),
            vert_source=vert_src,
            frag_source=frag_src,
            textures=textures,
            spec=spec,
            metadata=self._build_metadata(song_title, description)
        )
        
        artifact.write_to_disk(self._output_dir)
        
        return artifact
    
    def send_to_processing(self, artifact: ShaderArtifact) -> bool:
        """Send OSC message to load shader in Processing"""
        shader_dir = self._output_dir / artifact.name
        
        # OSC message: /shader/load [shader_dir, metadata_json]
        self._osc.send(
            "/shader/load",
            [
                str(shader_dir),
                json.dumps(artifact.metadata)
            ]
        )
        
        # Wait for status response (future enhancement)
        return True
```

#### Module: `prompts.py` (LLM Prompts)

**Purpose**: Centralized prompt templates

```python
SHADER_SPEC_SYSTEM_PROMPT = """You are a GLSL shader designer for VJ performances.
Generate shader specifications for Processing P3D (GLSL 150).

Target: Audio-reactive visuals for live music performances.
Constraints:
- GLSL version 150 (use in/out, explicit fragment output)
- Processing P3D renderer
- Performance: Must run at 60fps on HD resolution
- Audio reactivity: Use uniform float bass, mid, highs, level, beat

Output JSON schema:
{
  "style": "string describing visual style",
  "palette": ["#hexcolor1", "#hexcolor2", ...],
  "motion_type": "pulsing|rotating|flowing|morphing",
  "texture_roles": ["base", "detail", "mask", "noise"],
  "uniforms": {"name": {"type": "float", "default": 0.5, "min": 0.0, "max": 1.0}},
  "complexity": "low|medium|high"
}
"""

SHADER_CODE_SYSTEM_PROMPT = """You are a GLSL shader code generator for Processing P3D.

Requirements:
- GLSL version 150 core
- Vertex shader: Transform vertices, pass UV to fragment
- Fragment shader: Implement visual effect using spec
- Use uniforms: time, resolution, mouse, speed, bass, mid, highs, level
- Textures available as: uniform sampler2D texture0, texture1, etc.
- Output: out vec4 fragColor;

Generate production-ready, optimized GLSL code.
"""

def build_shader_spec_prompt(
    song_title: str,
    description: Optional[str],
    reference_image: Optional[Path]
) -> str:
    """Build shader spec generation prompt"""
    # Construct prompt with context
    pass

def build_shader_code_prompt(
    spec: ShaderSpec,
    textures: List[TextureInfo]
) -> str:
    """Build shader code generation prompt"""
    # Construct code generation prompt
    pass
```

---

### 2. Processing VJUniverse Extensions

**Location**: `processing-vj/src/VJUniverse/`

#### New File: `DynamicShaderLoader.pde`

**Purpose**: Hot-load generated shaders via OSC

```java
/**
 * Dynamic Shader Loader for Generated Shaders
 * Handles OSC-driven shader loading from Python generation pipeline
 */

// State
String pendingShaderPath = "";
String pendingMetadata = "";
boolean shaderLoadPending = false;

void setupDynamicShaderLoader() {
  println("[DynamicLoader] Initialized");
}

void updateDynamicShaderLoader() {
  if (shaderLoadPending) {
    loadDynamicShader(pendingShaderPath, pendingMetadata);
    shaderLoadPending = false;
  }
}

void loadDynamicShader(String shaderDir, String metadataJson) {
  println("[DynamicLoader] Loading shader from: " + shaderDir);
  
  try {
    // 1. Parse metadata
    JSONObject meta = parseJSONObject(metadataJson);
    
    // 2. Load vertex shader
    String vertPath = shaderDir + "/shader.vert";
    String fragPath = shaderDir + "/shader.frag";
    
    // 3. Create PShader
    PShader dynShader = loadShader(fragPath, vertPath);
    
    // 4. Load textures
    ArrayList<PImage> textures = loadShaderTextures(shaderDir, meta);
    
    // 5. Set as active shader
    activeShader = dynShader;
    
    // 6. Send success status via OSC
    sendShaderStatus(true, "Loaded successfully: " + shaderDir);
    
    println("[DynamicLoader] Shader loaded successfully");
    
  } catch (Exception e) {
    println("[DynamicLoader] Error: " + e.getMessage());
    sendShaderStatus(false, "Load failed: " + e.getMessage());
  }
}

ArrayList<PImage> loadShaderTextures(String shaderDir, JSONObject meta) {
  ArrayList<PImage> textures = new ArrayList<PImage>();
  
  JSONArray textureList = meta.getJSONArray("textures");
  for (int i = 0; i < textureList.size(); i++) {
    JSONObject texInfo = textureList.getJSONObject(i);
    String path = shaderDir + "/" + texInfo.getString("filename");
    
    try {
      PImage tex = loadImage(path);
      textures.add(tex);
      println("[DynamicLoader] Loaded texture: " + path);
    } catch (Exception e) {
      println("[DynamicLoader] Texture load failed: " + path);
    }
  }
  
  return textures;
}

void sendShaderStatus(boolean success, String message) {
  // Send OSC: /shader/status [1/0, "message"]
  OscMessage msg = new OscMessage("/shader/status");
  msg.add(success ? 1 : 0);
  msg.add(message);
  oscP5.send(msg, new NetAddress("127.0.0.1", 9001)); // Back to Python
}
```

#### Modified: `VJUniverse.pde` (OSC Handler)

**Add to `oscEvent()` function**:

```java
void oscEvent(OscMessage msg) {
  // ... existing handlers ...
  
  // NEW: Dynamic shader loading
  if (msg.checkAddrPattern("/shader/load")) {
    if (msg.checkTypetag("ss")) {
      pendingShaderPath = msg.get(0).stringValue();
      pendingMetadata = msg.get(1).stringValue();
      shaderLoadPending = true;
      println("[OSC] Shader load requested: " + pendingShaderPath);
    }
  }
  
  // ... rest of handlers ...
}
```

#### Modified: `draw()` function

**Add to main loop**:

```java
void draw() {
  // ... existing code ...
  
  updateDynamicShaderLoader(); // Check for pending shader loads
  
  // ... rest of draw ...
}
```

---

### 3. OSC Protocol Extensions

#### New Messages (Python → Processing)

```
/shader/load [shader_dir: string, metadata: json_string]
  - shader_dir: Absolute path to shader directory (contains .vert, .frag, textures)
  - metadata: JSON with shader info, texture list, attribution
```

#### New Messages (Processing → Python)

```
/shader/status [success: int, message: string]
  - success: 1 = success, 0 = failure
  - message: Human-readable status message
```

---

### 4. File System Layout

**Output Directory**: `processing-vj/src/VJUniverse/data/shaders/generated/`

**Per-Shader Structure**:
```
shaders/generated/
├── <shader_name>/
│   ├── shader.vert          # Vertex shader (GLSL 150)
│   ├── shader.frag          # Fragment shader (GLSL 150)
│   ├── texture_base.jpg     # Primary texture
│   ├── texture_detail.jpg   # Detail texture (optional)
│   ├── texture_noise.jpg    # Noise texture (optional)
│   ├── meta.json            # Complete metadata
│   └── uniforms.json        # Runtime parameter schema
```

**meta.json Schema**:
```json
{
  "name": "shader_name",
  "song_title": "Song Title",
  "description": "User description",
  "generated_at": "2025-01-15T12:00:00Z",
  "model": "qwen2.5-coder-32b-instruct",
  "prompts": {
    "spec": "...",
    "code": "..."
  },
  "spec": {
    "style": "abstract geometric",
    "palette": ["#ff0000", "#00ff00"],
    "motion_type": "rotating",
    "texture_roles": ["base", "detail"],
    "complexity": "medium"
  },
  "textures": [
    {
      "filename": "texture_base.jpg",
      "role": "base",
      "url": "https://...",
      "attribution": "Photo by X on Pexels",
      "width": 2048,
      "height": 1536
    }
  ]
}
```

**uniforms.json Schema** (for future UI controls):
```json
{
  "speed_mult": {
    "type": "float",
    "default": 1.0,
    "min": 0.0,
    "max": 2.0,
    "label": "Speed Multiplier"
  },
  "color_intensity": {
    "type": "float",
    "default": 0.5,
    "min": 0.0,
    "max": 1.0,
    "label": "Color Intensity"
  }
}
```

---

## MCP Integration Strategy

### MCP Servers to Deploy

1. **Pexels MCP Server**
   - Repository: https://github.com/CaullenOmdahl/pexels-mcp-server
   - Setup: Install Node.js package, configure Pexels API key
   - Tools: `pexels_search`, `downloadPhoto`

2. **MCP Image Downloader**
   - Repository: https://github.com/qpd-v/mcp-image-downloader
   - Setup: Install Node.js package
   - Tools: `download_image` (with resize/optimize)

### MCP Client Implementation

**Option A: Use official MCP SDK** (if available for Python)
```python
from mcp import Client

client = Client(server_path="path/to/pexels-mcp-server")
result = client.call_tool("pexels_search", {"query": "abstract", "count": 4})
```

**Option B: Direct stdio communication** (fallback)
```python
import subprocess
import json

def call_mcp_tool(server_path: str, tool: str, params: dict) -> dict:
    """Call MCP tool via subprocess"""
    proc = subprocess.Popen(
        [server_path],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    
    request = {
        "jsonrpc": "2.0",
        "method": f"tools/{tool}",
        "params": params,
        "id": 1
    }
    
    stdout, stderr = proc.communicate(json.dumps(request).encode())
    return json.loads(stdout)
```

### LM Studio Configuration

**Model Requirements**:
- **Code Generation**: Qwen2.5-Coder-32B-Instruct (GGUF, 8-bit quantization)
- **VLM (optional)**: Qwen2-VL-Instruct (for reference image analysis)

**LM Studio Settings**:
- Enable OpenAI-compatible API server (port 1234)
- Enable tool calling / function calling
- Temperature: 0.3 (deterministic code generation)
- Max tokens: 4096 (sufficient for shader code)

**API Endpoint**:
```
POST http://localhost:1234/v1/chat/completions
```

---

## Implementation Phases

### Phase 1: Core Infrastructure (Foundation)

**Goal**: Establish basic pipeline without MCP

**Tasks**:
1. Create `python-vj/shadergen/` module structure
2. Implement `schema.py` (domain models)
3. Extend `ai_services.py` with `ShaderSpecGenerator` (basic LM Studio integration)
4. Implement `pipeline.py` (orchestrator skeleton)
5. Add OSC handler in VJUniverse for `/shader/load`
6. Create `DynamicShaderLoader.pde`

**Deliverable**: Can generate simple shader spec JSON via LM Studio, send via OSC to Processing

**Test**: Manual LLM call → generate spec → write dummy shader files → OSC load

### Phase 2: MCP Integration (Image Pipeline)

**Goal**: Add texture search and download via MCP

**Tasks**:
1. Deploy Pexels MCP server (Node.js)
2. Deploy Image Downloader MCP server
3. Implement `mcp_clients.py` (PexelsImageSearch, ImageDownloader)
4. Integrate MCP clients into `pipeline.py`
5. Test texture download workflow

**Deliverable**: Full pipeline from song title → texture download → file writing

**Test**: Generate shader request → search Pexels → download 2-4 images → save locally

### Phase 3: Shader Code Generation (GLSL 150)

**Goal**: Generate functional Processing shaders

**Tasks**:
1. Implement `prompts.py` (code generation templates)
2. Extend `ShaderSpecGenerator.generate_shader_code()`
3. Create reference GLSL 150 examples for LLM context
4. Add GLSL validation (syntax checking)
5. Test shader loading in VJUniverse

**Deliverable**: LLM generates GLSL 150 vert + frag shaders that compile in Processing

**Test**: Generate complete shader → load in Processing → renders without errors

### Phase 4: Integration & Polish

**Goal**: Connect to VJ Console, add user interface

**Tasks**:
1. Add shader generation to VJ Console UI (new screen or command)
2. Implement status feedback (Processing → Python OSC)
3. Add shader gallery/history view
4. Create command-line interface (`python shadergen_cli.py generate "Song Title"`)
5. Add error handling and retry logic
6. Write integration tests

**Deliverable**: End-to-end user workflow from VJ Console

**Test**: User enters song title → shader generates → auto-loads → displays in VJUniverse

### Phase 5: Advanced Features (Optional)

**Goal**: Reference images, refinement, caching

**Tasks**:
1. Add reference image support (VLM integration)
2. Implement shader refinement (iterate on existing shader)
3. Add shader caching (avoid regenerating)
4. Add batch generation mode

**Deliverable**: Advanced generation features

---

## Testing Strategy

### Unit Tests

**Location**: `python-vj/tests/test_shadergen/`

```python
# test_schema.py
def test_shader_spec_creation():
    spec = ShaderSpec(
        style="abstract",
        palette=["#ff0000"],
        motion_type="pulsing",
        texture_roles=[TextureRole.BASE],
        uniforms={}
    )
    assert spec.style == "abstract"

# test_lmstudio_client.py
def test_generate_spec(mock_lm_studio):
    generator = ShaderSpecGenerator()
    spec = generator.generate_spec("Test Song")
    assert spec is not None
    assert isinstance(spec, ShaderSpec)

# test_pipeline.py
def test_full_pipeline(mock_all_services):
    orchestrator = ShaderGenerationOrchestrator(...)
    artifact = orchestrator.generate("Test Song")
    assert artifact is not None
    assert artifact.vert_source.startswith("#version 150")
```

### Integration Tests

**Location**: `python-vj/tests/integration/`

```python
# test_mcp_integration.py
def test_pexels_search_real():
    """Test real Pexels search (requires API key)"""
    client = PexelsImageSearch(...)
    results = client.search("abstract art", 4)
    assert len(results) > 0

# test_processing_osc.py
def test_shader_load_osc():
    """Test OSC communication with Processing"""
    # Start VJUniverse in headless mode
    # Send /shader/load message
    # Wait for /shader/status response
    # Assert success
```

### Manual Testing Checklist

- [ ] LM Studio running with Qwen2.5-Coder model loaded
- [ ] Pexels MCP server running with valid API key
- [ ] VJUniverse Processing sketch running
- [ ] Python pipeline generates shader spec JSON
- [ ] MCP search returns 4 texture candidates
- [ ] LLM selects textures and assigns roles
- [ ] Images download successfully
- [ ] GLSL code generation produces valid GLSL 150
- [ ] Vertex shader compiles in Processing
- [ ] Fragment shader compiles in Processing
- [ ] OSC message sends shader path to Processing
- [ ] Processing loads shader and textures
- [ ] Shader renders at 60fps in HD
- [ ] Audio reactivity uniforms work
- [ ] Status message returns to Python
- [ ] Error handling works (bad shader, missing texture)

---

## Security & Attribution

### Image Licensing

**Pexels**: All photos are free to use (Pexels License)
- ✅ Commercial use allowed
- ✅ No attribution required (but recommended)
- ❌ Cannot sell unmodified photos
- ✅ Can be used in shaders/VJ performances

**Attribution Storage**: Always save in `meta.json`

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

### Code Licensing

**Generated GLSL Code**: 
- Model output is not copyrightable (generally)
- Safe for use in performances
- Consider adding: "Generated by AI (Qwen2.5-Coder)" comment

### API Key Management

**Environment Variables**:
```bash
# .env file (never commit)
PEXELS_API_KEY=your_key_here
LM_STUDIO_URL=http://localhost:1234
```

**Load in Python**:
```python
from dotenv import load_dotenv
load_dotenv()

PEXELS_API_KEY = os.getenv("PEXELS_API_KEY")
```

---

## Performance Considerations

### Shader Generation Time

**Expected Pipeline Duration**:
1. LLM spec generation: 2-5 seconds
2. Texture search: 1-2 seconds
3. Image download (4 images): 3-5 seconds
4. Code generation: 3-8 seconds
5. File writing: <1 second

**Total**: 10-20 seconds per shader

**Optimization**:
- Pre-warm LM Studio (keep model loaded)
- Parallel texture downloads (async)
- Cache texture searches (same query = same results)
- Reuse textures across shaders

### Runtime Performance

**Processing Shader Requirements**:
- Target: 60fps at 1280x720
- Max texture size: 2048x2048 (reasonable for GPU)
- Complexity limit: Avoid nested loops >100 iterations

**LLM Prompt Constraint**:
```
Generate shader code optimized for 60fps at HD resolution.
Avoid:
- Complex raymarching (limit to 20-30 steps)
- Large texture samples in tight loops
- Expensive math (pow, exp, sin/cos in every pixel)
```

---

## Future Enhancements

### Phase 6+: Advanced Features

1. **Style Transfer from Reference Images**
   - Use VLM to analyze reference image
   - Extract color palette, composition, motion patterns
   - Generate shader matching visual style

2. **Multi-Shader Sequences**
   - Generate sequence of shaders for song sections (intro, verse, chorus, outro)
   - Transition effects between shaders
   - Timeline-based shader switching

3. **Shader Evolution**
   - Genetic algorithm: mutate and crossbreed shaders
   - Automatic parameter tuning based on audience feedback

4. **Real-Time Refinement**
   - Voice commands during performance: "make it more blue", "faster motion"
   - LLM adjusts shader parameters on-the-fly
   - Hot-reload modified shader

5. **Shader Library Management**
   - Tag system (mood, genre, energy level)
   - Semantic search: "find shaders similar to X"
   - Auto-categorization via LLM analysis

6. **Collaborative Generation**
   - Multiple performers submit prompts
   - LLM combines prompts into hybrid shader
   - Vote on best generation

---

## Open Questions / Decisions Needed

1. **MCP Server Hosting**
   - Should MCP servers run as system services (systemd)?
   - Or spawn on-demand from Python?
   - Recommend: System services for reliability

2. **Model Selection UI**
   - Allow users to switch between models (Qwen, Codestral, etc.)?
   - Or hardcode recommended model?
   - Recommend: Start with single model, add UI later

3. **Shader Caching Strategy**
   - Cache by song title + description hash?
   - Or always regenerate for variety?
   - Recommend: Cache with TTL (24 hours), allow manual regen

4. **Error Handling Philosophy**
   - Fail silently and fallback to default shader?
   - Or show error message and halt?
   - Recommend: Log error, send notification, continue with last working shader

5. **Processing Integration**
   - Extend VJUniverse only?
   - Or create new standalone app?
   - Recommend: Extend VJUniverse (existing OSC infrastructure)

---

## Dependencies

### Python Requirements (Add to `requirements.txt`)

```txt
# Existing dependencies already cover:
# - openai (LM Studio OpenAI-compatible API)
# - python-osc (OSC communication)
# - requests (HTTP requests)

# New dependencies:
mcp-python-sdk>=0.1.0  # If official SDK exists (check availability)
pillow>=10.0.0         # Image validation and metadata
pydantic>=2.0.0        # Data validation for schemas
```

### Node.js MCP Servers

```bash
# Pexels MCP Server
npm install -g @pexels/mcp-server

# Image Downloader MCP Server
npm install -g mcp-image-downloader
```

### Processing Libraries (Already Installed)

- oscP5 (OSC communication)
- Syphon (video output)

---

## Documentation Updates

### New Documentation Files

1. **User Guide**: `docs/operation/SHADER_GENERATION_GUIDE.md`
   - How to generate shaders
   - Command-line usage
   - Troubleshooting

2. **Developer Guide**: `docs/development/SHADER_GENERATION_DEV.md`
   - Architecture deep dive
   - Extending the pipeline
   - Adding new MCP sources

3. **API Reference**: `docs/reference/SHADER_GENERATION_API.md`
   - Python API documentation
   - OSC protocol specification
   - Schema reference

### Updated Files

1. **README.md**: Add shader generation section
2. **python-vj/README.md**: Document new module
3. **processing-vj/README.md**: Document OSC extensions

---

## Success Criteria

### Minimum Viable Product (MVP)

- ✅ User provides song title
- ✅ System generates GLSL 150 shader (vert + frag)
- ✅ System downloads 1-2 textures from Pexels
- ✅ Shader loads in VJUniverse via OSC
- ✅ Shader compiles without errors
- ✅ Shader renders at 30+ fps
- ✅ Basic audio reactivity works (bass, mid, highs)

### Full Success

- ✅ MVP criteria met
- ✅ User provides optional visual description
- ✅ System downloads 2-4 textures with assigned roles
- ✅ Shader renders at 60fps
- ✅ Advanced audio reactivity (beat sync, envelope tracking)
- ✅ Status feedback loop (Processing → Python)
- ✅ Error handling covers all failure modes
- ✅ Integration tests pass
- ✅ Documentation complete
- ✅ Demonstrates 5+ varied shader styles

---

## Timeline Estimate

**Assuming 1 developer, part-time (10 hours/week)**

- **Phase 1 (Core Infrastructure)**: 2-3 weeks
- **Phase 2 (MCP Integration)**: 1-2 weeks
- **Phase 3 (Shader Code Gen)**: 2-3 weeks
- **Phase 4 (Integration & Polish)**: 1-2 weeks
- **Testing & Documentation**: 1 week

**Total**: 7-11 weeks (2-3 months)

**Full-time (40 hours/week)**: 4-6 weeks

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| LM Studio model quality insufficient | Medium | High | Test with multiple models, fallback to simpler templates |
| MCP servers unstable/unavailable | Medium | Medium | Implement fallback to direct API calls |
| GLSL generation produces invalid code | High | High | Add validation layer, retry with stricter prompts |
| Processing shader compilation errors | Medium | High | Extensive testing, reference shader library |
| Performance issues (fps drops) | Medium | Medium | Complexity limits in prompts, shader profiling |
| Texture downloads slow/fail | Low | Low | Async downloads, caching, fallback textures |
| OSC communication failures | Low | Medium | Robust error handling, status timeouts |

---

## Conclusion

This implementation plan provides a **comprehensive roadmap** for adding dynamic shader generation to the synesthesia-visuals project. The architecture leverages existing patterns (domain models, adapters, orchestrators) and infrastructure (LM Studio, OSC, Processing P3D) while introducing new capabilities via MCP servers and LLM-driven code generation.

**Key Design Principles**:
- **Minimal dependencies**: Reuse existing infrastructure
- **Deep modules**: Hide complexity behind simple interfaces
- **Dependency injection**: Testable, swappable components
- **Fail gracefully**: Fallback strategies for every failure mode
- **Performance first**: Target 60fps from the start

**Next Steps**:
1. Review and approve this plan
2. Set up development environment (LM Studio, MCP servers)
3. Begin Phase 1 implementation
4. Iterate based on testing feedback

---

**Document Version**: 1.0  
**Date**: 2025-01-15  
**Author**: Copilot Agent  
**Status**: Awaiting Review
