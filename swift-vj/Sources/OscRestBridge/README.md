# OscRestBridge

A generic OSC → REST bridge for macOS 15+ written in Swift. Translates OSC messages into REST API calls using a config-driven YAML mapping. Ships with ready-to-use LedFX configuration.

**Important**: This module integrates with SwiftVJ's existing OSCHub - it does not create its own OSC listener. All OSC messages are routed through the central OSCHub.

## Architecture

Following **Grokking Simplicity** and **A Philosophy of Software Design** principles:

- **Domain layer** (pure calculations): `OSCRouteParser`, `ParameterScaling`, `TemplateEngine`, `JSONPatcher`, `RequestBuilder`
- **Adapters** (side effects): `URLSessionHTTPClient`
- **Service** (orchestration): `OscRestBridgeService` actor
- **UI** (SwiftUI views): Consolidated debug view for monitoring and configuration
- **Integration**: Uses existing OSCHub for message receiving

## Public API

### Creating a Service

```swift
import OscRestBridge

// Default configuration
let service = createDefaultBridgeService()

// Or with custom dependencies (for testing)
let service = OscRestBridgeService(
    httpClient: URLSessionHTTPClient(),
    clock: SystemClock()
)
```

### Integrating with OSCHub

```swift
// In AppState or your app initialization:
let bridge = createDefaultBridgeService()

// Subscribe to /ledfx/* messages from the existing OSCHub
oscHub.subscribe(pattern: "/ledfx/*") { address, values in
    Task {
        await bridge.handleOSCMessage(path: address, values: values)
    }
}
```

### Loading Configuration

```swift
// From file
try await service.loadConfig(from: URL(fileURLWithPath: "/path/to/config.yaml"))

// From data
let yamlData = """
version: 1
server:
  osc_listen:
    host: "0.0.0.0"
    port: 9000
  http:
    base_url: "http://127.0.0.1:8888"
    timeout_ms: 1500
...
""".data(using: .utf8)!

try await service.loadConfig(from: yamlData)
```

### Starting and Stopping

```swift
// Start listening for OSC messages
try await service.start()

// Stop
await service.stop()

// Reload config at runtime
try await service.reloadConfig(from: configURL)
```

### Observing State and Events

```swift
// Get current state snapshot
let state = await service.getState()
print("Running: \(state.isRunning)")
print("OSC received: \(state.stats.totalOscReceived)")
print("HTTP sent: \(state.stats.totalRestSent)")

// Subscribe to events
Task {
    for await event in service.events {
        switch event {
        case .oscReceived(let timestamp, let path, let value, let parsed):
            print("OSC: \(path) = \(value)")
        case .restRequestSent(let timestamp, let plan):
            print("HTTP: \(plan.method) \(plan.url)")
        case .restFailure(let timestamp, let plan, let error):
            print("ERROR: \(error)")
        default:
            break
        }
    }
}
```

### Dry Run Mode

```swift
// Enable dry run (plans requests but doesn't execute)
await service.setDryRun(true)

// Disable
await service.setDryRun(false)
```

## OSC API

All OSC messages must carry a single numeric argument (int or float).

### Scenes

**Activate**: `/ledfx/scene/<sceneName>/<slot>` with value > 0
**Deactivate**: `/ledfx/scene/<sceneName>/<slot>` with value = 0 (only if enabled in config)

Example:
```
/ledfx/scene/strobe/0 1.0    # Activate strobe on slot 0
/ledfx/scene/strobe/0 0.0    # Deactivate (if configured)
```

### Oneshots

**Trigger**: `/ledfx/oneshot/<oneshotName>/<slot>` with value > 0

Example:
```
/ledfx/oneshot/whiteflash/0 1.0    # Trigger white flash
/ledfx/oneshot/whiteflash/0 0.0    # Ignored
```

### Blackout

**Activate**: `/ledfx/blackout/<slot>` with value > 0
**Deactivate**: `/ledfx/blackout/<slot>` with value = 0

Example:
```
/ledfx/blackout/0 1.0    # Activate blackout, optionally restore previous scene
/ledfx/blackout/0 0.0    # Deactivate blackout
```

### Parameters

**Update**: `/ledfx/param/<paramName>/<slot>` with numeric value

Example:
```
/ledfx/param/strobe_speed/0 63.5    # Set strobe speed (MIDI 0-127)
/ledfx/param/brightness/0 0.8       # Set brightness (normalized 0-1)
```

## YAML Configuration

### Structure

```yaml
version: 1

server:
  osc_listen:
    host: "0.0.0.0"
    port: 9000
  http:
    base_url: "http://127.0.0.1:8888"
    timeout_ms: 1500
    default_headers:
      Content-Type: "application/json"

slots:
  "0":
    name: "main"
    targets:
      virtual_ids: ["virtual-1"]
    blackout:
      scene: "blackout"
      restore_previous_scene: true

scenes:
  strobe:
    id: "strobe"
    on_activate:
      request:
        method: "PUT"
        path: "/api/scenes"
        body:
          id: "${scene.id}"
          action: "activate"
    on_deactivate:
      enabled: true
      request:
        method: "PUT"
        path: "/api/scenes"
        body:
          id: "${scene.id}"
          action: "deactivate"

oneshots:
  whiteflash:
    request:
      method: "PUT"
      path: "/api/virtuals_tools/${slot.targets.virtual_ids[0]}"
      body:
        tool: "oneshot"
        color: "#FFFFFF"
        brightness: 1.0

params:
  strobe_speed:
    input:
      accepted: ["midi_0_127", "normalized_0_1"]
      default_mode: "midi_0_127"
    scale:
      type: "curve"          # "linear" | "curve"
      curve: "square"        # "linear" | "square" | "sqrt" | "exp"
      in_min: 0
      in_max: 127
      out_min: 0.5
      out_max: 20.0
    request:
      method: "PUT"
      path: "/api/virtuals/${slot.targets.virtual_ids[0]}/effects"
      body_template:
        config:
          speed_hz: 1.0
      patch_ops:
        - op: "set"
          pointer: "/config/speed_hz"
          value: "${param.scaled}"
```

### Template Variables

String interpolation in paths and string values:
- `${scene.id}` - Scene ID from config
- `${slot.name}` - Slot name
- `${slot.targets.virtual_ids[0]}` - First virtual ID
- `${param.raw}` - Raw parameter value
- `${param.scaled}` - Scaled parameter value
- `${param.mode}` - Detected input mode

Numeric substitution in JSON:
- If a JSON value is **exactly** `"${param.raw}"` or `"${param.scaled}"`, it's substituted as a number, not a string.

### JSON Pointer Patching (RFC 6901)

Patch operations modify JSON bodies:

```yaml
patch_ops:
  - op: "set"                    # Set a value
    pointer: "/config/speed_hz"
    value: "${param.scaled}"
  
  - op: "merge"                  # Deep merge object
    pointer: "/config"
    value:
      brightness: 0.8
  
  - op: "delete"                 # Remove a key
    pointer: "/config/unused"
```

### Parameter Scaling

**Input modes:**
- `midi_0_127` - MIDI CC range (0-127)
- `normalized_0_1` - Normalized (0.0-1.0)

**Curves:**
- `linear` - Direct mapping
- `square` - y = x²
- `sqrt` - y = √x
- `exp` - y = (e^(4x) - 1) / (e^4 - 1)

Process:
1. Clamp to `[in_min, in_max]`
2. Normalize to 0..1
3. Apply curve
4. Map to `[out_min, out_max]`

## SwiftUI Debug Views

*(To be implemented)*

The module will provide SwiftUI views for debugging:

```swift
import SwiftUI
import OscRestBridge

struct ContentView: View {
    @State private var service = createDefaultBridgeService()
    
    var body: some View {
        OscRestBridgeDebugView(service: service)
            .task {
                try? await service.loadConfig(from: configURL)
                try? await service.start()
            }
    }
}
```

## Testing

Run tests:

```bash
cd swift-vj
swift test --filter OscRestBridgeTests
```

### Test Philosophy

- **Behavioral tests**: Test observable outcomes, not implementation
- **No mocking**: Use real OSC/HTTP test doubles that capture behavior
- **End-to-end**: Test complete flows (OSC → parse → build → HTTP)

Example:

```swift
func test_sceneActivate_sendsCorrectRequest() async throws {
    // Given: Service with config
    try await service.loadConfig(from: yaml.data(using: .utf8)!)
    try await service.start()
    
    // When: OSC scene activate
    await oscTransport.simulateMessage(path: "/ledfx/scene/strobe/0", values: [1.0])
    
    // Then: HTTP request sent with correct body
    let requests = await httpClient.requests
    XCTAssertEqual(requests[0].method, "PUT")
    XCTAssertEqual(requests[0].url, "http://127.0.0.1:8888/api/scenes")
}
```

## Example: LedFX Integration

See `Resources/config-ledfx.yaml` for a complete example with:
- 2 slots (main, secondary)
- 3 scenes (strobe, wash, blackout)
- 2 oneshots (whiteflash, redhit)
- 3 params (strobe_speed, brightness, color_hue)

## Dependencies

- **OSCKit** (0.6.0+) - OSC message parsing
- **Yams** (5.0.0+) - YAML decoding with strict validation
- **URLSession** - HTTP requests (Foundation)

## Requirements

- macOS 15.0+
- Swift 6.0+

## Integration into SwiftVJ

Add to Package.swift dependencies:

```swift
.product(name: "OscRestBridge", package: "SwiftVJ")
```

Use in your app:

```swift
import OscRestBridge

@main
struct MyApp: App {
    @State private var bridge = createDefaultBridgeService()
    
    var body: some Scene {
        WindowGroup {
            ContentView(bridge: bridge)
        }
    }
}
```

## License

Same as SwiftVJ parent project.
