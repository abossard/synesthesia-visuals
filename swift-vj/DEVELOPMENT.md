# SwiftVJ Development Guide

## Getting Started

### Prerequisites
- macOS 13.0+ (Ventura or later)
- Xcode 15.0+ or Swift 5.9+ command line tools
- Basic understanding of Metal and Swift

### First Build
```bash
cd swift-vj
swift build
```

If build succeeds, you'll see:
```
Build complete! (X.XXs)
```

### Running Locally
```bash
swift run SwiftVJ
```

Or build and run separately:
```bash
swift build -c release
.build/release/SwiftVJ
```

## Project Structure

```
swift-vj/
├── Package.swift                    # SPM configuration
├── Sources/SwiftVJ/
│   ├── main.swift                  # Entry point
│   ├── AppDelegate.swift           # App lifecycle, window management
│   ├── MetalRenderEngine.swift     # Core rendering engine
│   ├── OSCHandler.swift            # OSC message processing
│   ├── TextRenderer.swift          # Core Text rendering to Metal textures
│   └── SwiftVJ-Bridging-Header.h   # Objective-C bridge (for Syphon)
├── Shaders/
│   └── audio_reactive_gradient.metal  # Example Metal shader
├── Tests/SwiftVJTests/
│   └── SwiftVJTests.swift          # Unit tests
├── README.md                        # User documentation
├── SYPHON_INTEGRATION.md           # Syphon setup guide
└── DEVELOPMENT.md                   # This file
```

## Development Workflow

### 1. Making Changes

#### Adding New Features
1. Create feature branch: `git checkout -b feature/my-feature`
2. Implement changes in appropriate files
3. Test locally: `swift run SwiftVJ`
4. Commit with descriptive message
5. Push and create PR

#### Code Style
- Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- Use 4 spaces for indentation
- Add documentation comments for public APIs
- Keep functions focused and single-purpose

### 2. Adding Shaders

Create new `.metal` file in `Shaders/`:

```metal
#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut vertex_main(uint vertexID [[vertex_id]]) {
    // Fullscreen quad
    VertexOut out;
    float2 positions[6] = {
        float2(-1, -1), float2(1, -1), float2(-1, 1),
        float2(-1, 1), float2(1, -1), float2(1, 1)
    };
    out.position = float4(positions[vertexID], 0, 1);
    out.texCoord = positions[vertexID] * 0.5 + 0.5;
    return out;
}

fragment float4 fragment_main(
    VertexOut in [[stage_in]],
    constant float &time [[buffer(0)]],
    constant float2 &resolution [[buffer(1)]],
    constant float &bassLevel [[buffer(2)]],
    constant float &midLevel [[buffer(3)]],
    constant float &highLevel [[buffer(4)]]
) {
    // Your shader code here
    return float4(1.0);
}
```

### 3. Testing

#### Run Unit Tests
```bash
swift test
```

#### Manual Testing
1. Start python-vj karaoke engine:
   ```bash
   cd python-vj
   python karaoke_engine.py
   ```

2. Start SwiftVJ:
   ```bash
   cd swift-vj
   swift run SwiftVJ
   ```

3. Send test OSC messages:
   ```bash
   python -c "
   from pythonosc import udp_client
   client = udp_client.SimpleUDPClient('127.0.0.1', 9000)
   client.send_message('/karaoke/track', [1, 'test', 'Test Artist', 'Test Song', 'Album', 180.0, 1])
   client.send_message('/audio/levels', [0.5, 0.7, 0.3, 0.4, 0.6, 0.5, 0.2, 0.6])
   "
   ```

### 4. Debugging

#### Xcode Debugger
```bash
# Generate Xcode project
swift package generate-xcodeproj
open SwiftVJ.xcodeproj
```

Set breakpoints, use LLDB, profile with Instruments.

#### Console Logging
Check logs:
```bash
log stream --predicate 'process == "SwiftVJ"' --level debug
```

Or use Console.app and filter for "SwiftVJ".

#### Metal Debugging
1. Open Xcode project
2. Product → Scheme → Edit Scheme
3. Run → Diagnostics → Metal:
   - Enable API Validation
   - Enable Shader Validation
   - Enable GPU Frame Capture

## Architecture Deep Dive

### AppDelegate
- Creates main window
- Initializes MetalRenderEngine
- Sets up OSCHandler
- Manages app lifecycle

### MetalRenderEngine
- **MTKViewDelegate**: Handles draw loop
- **Shader Management**: Compiles and manages Metal shaders
- **Texture Management**: Creates offscreen render targets
- **Uniform Management**: Passes time, resolution, audio levels to shaders
- **Syphon Integration**: Publishes textures to Syphon servers

### OSCHandler
- **SwiftOSC Server**: Listens on port 9000
- **Message Routing**: Dispatches to appropriate handlers
- **Protocol Matching**: Implements python-vj OSC protocol exactly

### TextRenderer
- **Core Text**: High-quality text rendering
- **Metal Textures**: Converts bitmap to GPU textures
- **Word Wrapping**: Multi-line text support
- **Styling**: Font, size, color, alignment

## Common Tasks

### Adding New OSC Message Handler
Edit `OSCHandler.swift`:

```swift
server.setHandler("/my/message") { [weak self] message in
    guard let args = message.arguments else { return }
    // Process message
    self?.engine?.someMethod()
}
```

### Adding New Uniform to Shader
1. Update shader `.metal` file with new buffer:
   ```metal
   constant float &myUniform [[buffer(5)]]
   ```

2. Update `MetalRenderEngine.swift` to set uniform:
   ```swift
   var myValue: Float = 0.5
   renderEncoder.setFragmentBytes(&myValue, length: MemoryLayout<Float>.stride, index: 5)
   ```

### Converting GLSL to Metal Shading Language

GLSL to MSL common conversions:

| GLSL | MSL |
|------|-----|
| `uniform float time;` | `constant float &time [[buffer(0)]]` |
| `uniform vec2 resolution;` | `constant float2 &resolution [[buffer(1)]]` |
| `varying vec2 vTexCoord;` | `VertexOut.texCoord` (passed from vertex) |
| `gl_FragCoord` | `in.position` (with [[position]] attribute) |
| `gl_FragColor = ...` | `return float4(...)` |
| `vec2, vec3, vec4` | `float2, float3, float4` |
| `mix(a, b, t)` | `mix(a, b, t)` (same) |
| `fract(x)` | `fract(x)` (same) |
| `mod(x, y)` | `fmod(x, y)` |
| `texture2D(sampler, uv)` | `sampler.sample(sampler, uv)` |

### Optimizing Performance

1. **Reuse Pipeline States**: Compile shaders once, cache states
2. **Batch Rendering**: Minimize render passes
3. **Texture Pooling**: Reuse texture allocations
4. **Efficient Uniforms**: Use constant buffers, not per-frame allocations
5. **Profile**: Use Metal System Trace in Instruments

## CI/CD

### GitHub Actions
Workflow: `.github/workflows/swift-build.yml`

Triggers:
- Push to main/master
- PRs to main/master
- Changes to `swift-vj/**` or workflow file

Builds:
- macOS 13 (Intel)
- macOS 14 (Apple Silicon)

Artifacts:
- Uploaded binaries for both architectures
- Retention: 30 days

### Running CI Locally
Use [act](https://github.com/nektos/act):
```bash
brew install act
act -W .github/workflows/swift-build.yml
```

## Troubleshooting

### Build Fails with "Cannot find 'SwiftOSC'"
```bash
swift package resolve
swift package update
```

### Metal Validation Errors
Enable Metal validation in Xcode scheme, check Console.app for details.

### OSC Messages Not Received
```bash
# Check if port is in use
lsof -i :9000

# Test with simple OSC client
pip install python-osc
python test_osc.py  # Send test messages
```

### Syphon Not Working
See [SYPHON_INTEGRATION.md](SYPHON_INTEGRATION.md) for detailed setup.

## Resources

### Documentation
- [Swift Language Guide](https://docs.swift.org/swift-book/)
- [Metal Programming Guide](https://developer.apple.com/metal/)
- [Metal Shading Language Spec](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf)
- [SwiftOSC GitHub](https://github.com/ExistentialAudio/SwiftOSC)

### Tools
- [RenderDoc](https://renderdoc.org/) - Graphics debugger
- [Instruments](https://developer.apple.com/instruments/) - Profiling
- [Metal Debugger](https://developer.apple.com/documentation/metal/debugging_metal) - Xcode built-in

### Examples
- [Metal by Example](https://metalbyexample.com/)
- [Syphon Swift Example](https://github.com/pixlwave/Syphon-Swift-Example)

## Contributing

1. Fork the repository
2. Create feature branch
3. Make changes with tests
4. Ensure CI passes
5. Submit PR with description

### PR Checklist
- [ ] Code builds without warnings
- [ ] Tests pass locally
- [ ] Documentation updated
- [ ] Commit messages are descriptive
- [ ] Changes are minimal and focused

## Future Roadmap

- [ ] Complete Syphon integration
- [ ] GLSL to MSL automatic conversion
- [ ] Shader browser UI
- [ ] Hot-reload file watcher
- [ ] Compute shader support
- [ ] Multi-pass pipeline
- [ ] MIDI control
- [ ] Preset system

## Questions?

Open an issue or check existing documentation:
- [README.md](README.md) - User guide
- [SYPHON_INTEGRATION.md](SYPHON_INTEGRATION.md) - Syphon setup
- [python-vj/README.md](../python-vj/README.md) - Python VJ tools

Happy coding! 🎨✨
