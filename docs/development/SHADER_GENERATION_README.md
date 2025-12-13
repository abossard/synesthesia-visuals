# Dynamic Shader Generation Documentation

This directory contains the complete implementation plan for adding **dynamic shader generation** to synesthesia-visuals.

## 📄 Documentation Files

### 1. [SHADER_GENERATION_IMPLEMENTATION_PLAN.md](./SHADER_GENERATION_IMPLEMENTATION_PLAN.md) (36KB)
**The master specification** - Read this first for complete details.

**Contains**:
- Complete architecture specification
- Detailed component designs with code examples
- Module-by-module implementation guide
- MCP integration strategy (Pexels, Image Downloader)
- LM Studio configuration
- File system layout
- OSC protocol extensions
- Testing strategy
- Risk assessment
- Timeline estimates (4 phases, 7-11 weeks)

**When to read**: Before starting implementation, for detailed design questions

---

### 2. [SHADER_GENERATION_QUICK_REFERENCE.md](./SHADER_GENERATION_QUICK_REFERENCE.md) (13KB)
**Developer quick lookup** - Keep this open while coding.

**Contains**:
- Module structure overview
- Key classes and functions
- OSC protocol reference
- Data model schemas
- Command reference
- Troubleshooting common issues
- Performance guidelines
- Security notes

**When to read**: During implementation, for quick reference

---

### 3. [SHADER_GENERATION_ARCHITECTURE_DIAGRAM.md](./SHADER_GENERATION_ARCHITECTURE_DIAGRAM.md) (19KB)
**Visual system design** - Understand data flow at a glance.

**Contains**:
- High-level system overview diagram
- Python module structure diagram
- Processing extension structure diagram
- Data flow sequence diagram
- Key interfaces (Python ↔ LM Studio, Python ↔ MCP, Python ↔ Processing)
- State management diagrams
- Error handling flow

**When to read**: For understanding system architecture, debugging data flow

---

### 4. [SHADER_GENERATION_SUMMARY.md](./SHADER_GENERATION_SUMMARY.md) (10KB)
**Executive summary** - Understand the "why" and high-level "what".

**Contains**:
- What this feature adds
- Architecture highlights
- Data flow overview
- Key design decisions (and rationale)
- Implementation phases summary
- Example workflows
- Performance targets
- Security & licensing
- Testing strategy
- Success criteria

**When to read**: For presentations, PRs, explaining to others

---

### 5. [SHADER_GENERATION_CHECKLIST.md](./SHADER_GENERATION_CHECKLIST.md) (12KB)
**Implementation tracker** - Track progress item by item.

**Contains**:
- Pre-implementation setup tasks (environment, MCP servers)
- Phase 1 checklist (Core Infrastructure)
- Phase 2 checklist (MCP Integration)
- Phase 3 checklist (Shader Code Generation)
- Phase 4 checklist (Integration & Polish)
- Documentation & testing checklist
- Deployment checklist
- Progress tracking table
- Notes & blockers section

**When to read**: Daily during implementation, for tracking progress

---

## 🚀 Quick Start Guide

### For Implementers

1. **Read first**: [SHADER_GENERATION_IMPLEMENTATION_PLAN.md](./SHADER_GENERATION_IMPLEMENTATION_PLAN.md) (sections 1-3)
2. **Set up environment**: Follow [SHADER_GENERATION_CHECKLIST.md](./SHADER_GENERATION_CHECKLIST.md) pre-implementation setup
3. **Reference during coding**: [SHADER_GENERATION_QUICK_REFERENCE.md](./SHADER_GENERATION_QUICK_REFERENCE.md)
4. **Track progress**: Update [SHADER_GENERATION_CHECKLIST.md](./SHADER_GENERATION_CHECKLIST.md) as you go
5. **Debug issues**: Consult [SHADER_GENERATION_ARCHITECTURE_DIAGRAM.md](./SHADER_GENERATION_ARCHITECTURE_DIAGRAM.md) data flow diagrams

### For Reviewers

1. **Understand the feature**: [SHADER_GENERATION_SUMMARY.md](./SHADER_GENERATION_SUMMARY.md)
2. **Review architecture**: [SHADER_GENERATION_ARCHITECTURE_DIAGRAM.md](./SHADER_GENERATION_ARCHITECTURE_DIAGRAM.md)
3. **Check design decisions**: [SHADER_GENERATION_IMPLEMENTATION_PLAN.md](./SHADER_GENERATION_IMPLEMENTATION_PLAN.md) sections 4-7
4. **Evaluate testing**: [SHADER_GENERATION_IMPLEMENTATION_PLAN.md](./SHADER_GENERATION_IMPLEMENTATION_PLAN.md) section 10

### For Stakeholders

1. **Executive summary**: [SHADER_GENERATION_SUMMARY.md](./SHADER_GENERATION_SUMMARY.md)
2. **Visual overview**: [SHADER_GENERATION_ARCHITECTURE_DIAGRAM.md](./SHADER_GENERATION_ARCHITECTURE_DIAGRAM.md) first section
3. **Timeline**: [SHADER_GENERATION_IMPLEMENTATION_PLAN.md](./SHADER_GENERATION_IMPLEMENTATION_PLAN.md) section 11

---

## 📊 Key Metrics

**Total Documentation**: ~90KB, 2,758 lines

**Scope**:
- 7 new Python files (~1,500 LOC)
- 1 new Processing file (~200 LOC)
- 2 modified Processing files (~20 LOC)
- 8 unit test files
- 3 integration test files

**Estimated Effort**:
- 7-11 weeks part-time (10h/week)
- 4-6 weeks full-time (40h/week)

**Dependencies**:
- LM Studio (local)
- 2 Node.js MCP servers
- Pexels API key (free tier: 200 requests/hour)

---

## 🔑 Key Concepts

### What This Feature Does

Generates **Processing P3D shaders (GLSL 150)** dynamically based on:
- Song title (required)
- Visual description (optional)
- Reference image (optional)

**Output**: Complete shader directory with `.vert`, `.frag`, textures, metadata, ready to load via OSC.

### Architecture Pattern

Follows existing **domain/adapters/orchestrators** pattern:
- **Domain models**: `ShaderSpec`, `TextureInfo`, `ShaderArtifact` (immutable)
- **Adapters**: `ShaderSpecGenerator`, `PexelsImageSearch`, `ImageDownloader` (deep modules)
- **Orchestrator**: `ShaderGenerationOrchestrator` (coordinates pipeline via dependency injection)

### Technology Stack

- **LM Studio**: Local LLM (Qwen2.5-Coder-32B)
- **MCP**: Model Context Protocol for tool calling (Pexels, Image Downloader)
- **OSC**: Communication between Python and Processing
- **Processing P3D**: Shader rendering engine (existing VJUniverse)

---

## 🎯 Implementation Phases

### Phase 1: Core Infrastructure (2-3 weeks)
Create Python module structure, domain models, basic LM Studio integration, Processing OSC handler.

### Phase 2: MCP Integration (1-2 weeks)
Deploy MCP servers, implement clients, texture search and download pipeline.

### Phase 3: Shader Code Generation (2-3 weeks)
GLSL 150 code generation, validation, Processing integration, performance testing.

### Phase 4: Integration & Polish (1-2 weeks)
VJ Console integration, CLI, status feedback, error handling, tests, documentation.

---

## 🧪 Testing Strategy

### Unit Tests
- Domain models
- LM Studio client (mocked)
- MCP clients (mocked)
- Pipeline orchestrator

### Integration Tests
- Real MCP calls (Pexels search, image download)
- OSC communication loop
- GLSL compilation in Processing

### Manual Tests
- End-to-end workflow
- Performance (60fps target)
- Audio reactivity
- Error handling

---

## 📚 Related Documentation

### Repository Documentation
- [Python VJ README](../../python-vj/README.md)
- [Processing README](../../processing-vj/README.md)
- [ISF to Synesthesia Migration](../reference/isf-to-synesthesia-migration.md)

### External References
- [LM Studio Docs](https://lmstudio.ai/docs)
- [MCP Protocol Spec](https://github.com/modelcontextprotocol/mcp)
- [Pexels API](https://www.pexels.com/api/)
- [Processing Shader Guide](https://processing.org/tutorials/pshader/)
- [GLSL 150 Reference](https://www.khronos.org/opengl/wiki/Core_Language_(GLSL))

---

## ❓ FAQ

**Q: Why LM Studio instead of OpenAI?**  
A: Local execution, no API costs, privacy, offline capability. Existing integration in `ai_services.py`.

**Q: Why MCP instead of direct APIs?**  
A: Standardized protocol, swappable sources, tool calling support. Can add Unsplash, Brave Search without code changes.

**Q: Why GLSL 150?**  
A: Processing P3D requirement, modern OpenGL core profile, better compatibility.

**Q: Can I use different LLM models?**  
A: Yes, architecture supports swapping models. Qwen2.5-Coder-32B is recommended for code quality.

**Q: What if Pexels rate limit is hit?**  
A: Fallback to cached textures or default textures. Can also use Unsplash (200 requests/hour) or Brave Search (unlimited).

**Q: How long does shader generation take?**  
A: 10-20 seconds total (spec: 2-5s, search: 1-2s, download: 3-5s, code: 3-8s, write: <1s).

**Q: What if generated shader doesn't compile?**  
A: Retry with stricter prompts, GLSL validation, fallback to reference shaders.

---

## 🛠 Troubleshooting

### Common Issues

**LM Studio not responding**
- Check if server is running: `curl http://localhost:1234/v1/models`
- Verify model is loaded in LM Studio UI
- Check logs: `~/.lmstudio/logs/`

**MCP server not found**
- Verify Node.js installed: `node --version`
- Check global packages: `npm list -g`
- Ensure server process is running: `ps aux | grep mcp`

**Shader compilation error**
- Verify GLSL version 150 (first line of `.frag`)
- Check all uniforms are declared
- Validate texture samplers (`sampler2D`)

**Textures not loading**
- Verify file paths (absolute or relative to Processing `data/`)
- Check image format (JPG, PNG supported)
- Validate image size (<2048x2048)

---

## 📝 Contributing

When contributing to this implementation:

1. **Update checklist**: Check off completed items in [SHADER_GENERATION_CHECKLIST.md](./SHADER_GENERATION_CHECKLIST.md)
2. **Follow patterns**: Use existing domain/adapters/orchestrators architecture
3. **Write tests**: Unit + integration tests for all new code
4. **Document changes**: Update relevant documentation files
5. **Performance**: Ensure 60fps target is maintained

---

## 📅 Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-01-15 | Initial implementation plan |

---

**Status**: Implementation Ready  
**Last Updated**: 2025-01-15  
**Maintainer**: @copilot

For questions or clarifications, refer to the individual documentation files or open an issue.
