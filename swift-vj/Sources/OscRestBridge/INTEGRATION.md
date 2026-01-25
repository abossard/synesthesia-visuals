# OscRestBridge Integration Guide for SwiftVJ

This guide shows how to integrate the OscRestBridge module into SwiftVJ.

**Important**: The bridge uses SwiftVJ's existing OSCHub for receiving messages. It does not create its own OSC listener.

## 1. Add the Module to AppState

The bridge is already integrated into AppState. In `Sources/SwiftVJApp/SwiftVJApp.swift`:

```swift
import OscRestBridge

public final class AppState: ObservableObject {
    // ...
    public var oscRestBridge: OscRestBridgeService?
    
    private func setupModules() {
        // ...
        
        // Initialize OSC Rest Bridge
        oscRestBridge = createDefaultBridgeService()
    }
}
```

## 2. Subscribe to OSCHub

In the `startOSCHub()` method, the bridge subscribes to `/ledfx/*` messages:

```swift
private func startOSCHub() {
    do {
        try oscHub.start()
        
        // ... other subscriptions ...
        
        // Subscribe OSC Rest Bridge to /ledfx/* messages
        oscHub.subscribe(pattern: "/ledfx/*") { [weak self] address, values in
            guard let self = self, let bridge = self.oscRestBridge else { return }
            Task {
                await bridge.handleOSCMessage(path: address, values: values)
            }
        }
    } catch {
        log("Failed to start OSC hub: \(error)", level: .error)
    }
}
```

## 3. Load Configuration on Startup

You can load the bundled LedFX config or a custom one:

```swift
@main
struct SwiftVJApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .task {
            do {
                // Load bridge config
                if let configURL = Bundle.main.url(forResource: "config-ledfx", withExtension: "yaml") {
                    try await appState.oscRestBridge?.loadConfig(from: configURL)
                    try await appState.oscRestBridge?.start()
                }
            } catch {
                print("Failed to start OSC Rest Bridge: \(error)")
            }
        }
    }
}
```

## 4. Create Custom Configuration

Create your own YAML config in `Resources/my-bridge-config.yaml`:

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
      virtual_ids: ["my-device-1"]
    blackout:
      scene: "off"
      restore_previous_scene: true

scenes:
  my_scene:
    id: "my_scene"
    on_activate:
      request:
        method: "PUT"
        path: "/api/my/endpoint"
        body:
          scene: "${scene.id}"
          state: "active"
    on_deactivate:
      enabled: true
      request:
        method: "PUT"
        path: "/api/my/endpoint"
        body:
          scene: "${scene.id}"
          state: "inactive"

oneshots: {}
params: {}
```

Then add it to your `Package.swift` resources:

```swift
.executableTarget(
    name: "SwiftVJApp",
    dependencies: [
        "SwiftVJCore",
        "OscRestBridge",  // Add dependency
    ],
    resources: [
        .copy("Resources/my-bridge-config.yaml"),  // Add config
    ]
)
```

## 4. Standalone Debug App

You can also create a standalone app for testing:

```swift
// Sources/OscRestBridgeApp/main.swift
import SwiftUI
import OscRestBridge

@main
struct OscRestBridgeApp: App {
    @State private var service = createDefaultBridgeService()
    
    var body: some Scene {
        WindowGroup {
            OscRestBridgeDebugView(service: service)
                .frame(minWidth: 800, minHeight: 600)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Load Config...") {
                    // TODO: Show file picker
                }
                .keyboardShortcut("o", modifiers: [.command])
                
                Divider()
                
                Button("Start Service") {
                    Task {
                        try? await service.start()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
                
                Button("Stop Service") {
                    Task {
                        await service.stop()
                    }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
    }
}
```

## 5. Testing with OSC

Use an OSC sender to test the bridge. Examples using Python with `python-osc`:

```python
from pythonosc import udp_client

# Create client
client = udp_client.SimpleUDPClient("127.0.0.1", 9000)

# Test scene activation
client.send_message("/ledfx/scene/strobe/0", 1.0)

# Test oneshot
client.send_message("/ledfx/oneshot/whiteflash/0", 1.0)

# Test parameter
client.send_message("/ledfx/param/strobe_speed/0", 63.5)

# Test blackout
client.send_message("/ledfx/blackout/0", 1.0)
```

Or use TouchOSC, Max/MSP, Pure Data, or any OSC tool.

## 6. Monitoring and Debugging

The debug UI provides 5 tabs:

1. **Config**: Load/reload YAML, view validation errors
2. **OSC**: Live OSC message stream with parsed routes
3. **REST**: HTTP requests with status codes and bodies
4. **Stats**: Counters and rates
5. **State**: Slot states, dry-run toggle, clear actions

## 7. Production Deployment

For production, disable dry-run and handle errors:

```swift
@main
struct SwiftVJApp: App {
    @State private var oscRestBridge = createDefaultBridgeService()
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .alert("OSC Rest Bridge Error", isPresented: $showError) {
                    Button("OK") { }
                } message: {
                    Text(errorMessage)
                }
        }
        .task {
            do {
                // Load config
                let configURL = URL(fileURLWithPath: "/path/to/production-config.yaml")
                try await oscRestBridge.loadConfig(from: configURL)
                
                // Ensure dry-run is off
                await oscRestBridge.setDryRun(false)
                
                // Start
                try await oscRestBridge.start()
                
                // Monitor events
                Task {
                    for await event in oscRestBridge.events {
                        if case .restFailure(_, _, let error) = event {
                            print("REST failure: \(error)")
                        }
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}
```

## 8. Custom HTTP Client

For special requirements (authentication, retry logic, etc.), implement `HTTPClient`:

```swift
import Foundation
import OscRestBridge

final class CustomHTTPClient: HTTPClient {
    func execute(
        method: String,
        url: String,
        headers: [String: String],
        body: Data?,
        timeoutMs: Int
    ) async throws -> (statusCode: Int, body: Data) {
        // Custom logic: add auth header
        var customHeaders = headers
        customHeaders["Authorization"] = "Bearer \(getToken())"
        
        // Use URLSession with retry
        // ...
        
        return (200, Data())
    }
    
    private func getToken() -> String {
        // Your auth logic
        return "token"
    }
}

// Use custom client
let service = OscRestBridgeService(
    oscTransport: OSCKitTransport(),
    httpClient: CustomHTTPClient(),
    clock: SystemClock()
)
```

## 9. LedFX-Specific Setup

For LedFX:

1. Install LedFX: https://www.ledfx.app/
2. Start LedFX server (default port 8888)
3. Configure virtual devices in LedFX
4. Use the bundled `config-ledfx.yaml`
5. Send OSC from your controller (MIDI, Launchpad, etc.)

Example LedFX workflow:

```
Controller (MIDI) → SwiftVJ (MIDI→OSC) → OscRestBridge (OSC→REST) → LedFX
```

## Troubleshooting

**Config validation errors**: Check YAML syntax and required fields
**OSC messages not received**: Verify port 9000 is not in use
**HTTP failures**: Check LedFX is running and base_url is correct
**Unknown routes**: Verify scene/oneshot/param names match config
**Dry-run stuck**: Check State tab, ensure dry-run is off

## Example: Full Integration

```swift
// Sources/SwiftVJApp/SwiftVJApp.swift
import SwiftUI
import SwiftVJCore
import OscRestBridge

@main
struct SwiftVJApp: App {
    @State private var oscRestBridge = createDefaultBridgeService()
    @State private var registry = ModuleRegistry()
    
    var body: some Scene {
        // Main window
        WindowGroup {
            MasterControlView()
        }
        
        // OSC Rest Bridge window
        WindowGroup("OSC → REST Bridge") {
            OscRestBridgeDebugView(service: oscRestBridge)
                .frame(minWidth: 800, minHeight: 600)
        }
        .defaultSize(width: 900, height: 700)
    }
    
    init() {
        Task {
            do {
                // Load LedFX config
                if let url = Bundle.main.url(forResource: "config-ledfx", withExtension: "yaml") {
                    try await oscRestBridge.loadConfig(from: url)
                    try await oscRestBridge.start()
                    print("OSC Rest Bridge started on port 9000")
                }
            } catch {
                print("OSC Rest Bridge error: \(error)")
            }
        }
    }
}
```

## Next Steps

- Customize YAML config for your hardware
- Map MIDI/Launchpad to OSC messages
- Monitor debug UI during performance
- Create presets for different shows
- Add custom scenes and parameters
