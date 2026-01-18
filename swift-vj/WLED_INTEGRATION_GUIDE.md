# WLED Integration - Developer Guide

## How to Integrate WLED Module into Swift-VJ App

This guide shows how to wire up the WLED module into the existing Swift-VJ application.

## 1. Add to ModuleRegistry

Update `Sources/SwiftVJCore/Modules/ModuleRegistry.swift`:

```swift
public class ModuleRegistry {
    // ... existing modules ...
    public lazy var wled: WLEDModule = {
        WLEDModule(
            oscHub: osc.hub,
            config: settings.loadWLEDConfig()
        )
    }()
    
    // Update startAll() to include WLED
    public func startAll() async {
        do {
            try await osc.start()
            try await playback.start()
            try await lyrics.start()
            try await ai.start()
            try await shaders.start()
            try await pipeline.start()
            try await wled.start()  // Add this line
        } catch {
            print("Failed to start module: \(error)")
        }
    }
    
    // Update stopAll() to include WLED
    public func stopAll() async {
        await wled.stop()  // Add this line
        await pipeline.stop()
        await shaders.stop()
        await ai.stop()
        await lyrics.stop()
        await playback.stop()
        await osc.stop()
    }
}
```

## 2. Subscribe to Audio OSC in App Initialization

Update `Sources/SwiftVJApp/SwiftVJApp.swift`:

```swift
@main
struct SwiftVJApp: App {
    @StateObject private var store = Store()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onAppear {
                    Task {
                        await setupModules()
                    }
                }
        }
    }
    
    private func setupModules() async {
        // Start all modules including WLED
        await store.environment.registry.startAll()
        
        // Subscribe WLED to audio updates
        await subscribeWLEDToAudio()
    }
    
    private func subscribeWLEDToAudio() async {
        let oscHub = store.environment.registry.osc.hub
        let wledModule = store.environment.registry.wled
        
        // Subscribe to Synesthesia audio messages
        oscHub.subscribe(pattern: "/syn/*") { address, values in
            Task {
                // Parse OSC message and update WLED
                if let levels = parseAudioOSC(address: address, values: values) {
                    await wledModule.updateAudioLevels(levels)
                }
            }
        }
    }
    
    private func parseAudioOSC(address: String, values: [any OSCValue]) -> OSCAudioLevels? {
        // This should be handled by SynesthesiaAudioProcessor
        // For now, return nil (will be wired up with existing audio processor)
        return nil
    }
}
```

## 3. Add WLED Settings View

Create `Sources/SwiftVJApp/WLEDSettingsView.swift`:

```swift
import SwiftUI
import SwiftVJCore

struct WLEDSettingsView: View {
    @EnvironmentObject var store: Store
    @State private var config: WLEDConfig
    @State private var newControllerName = ""
    @State private var newControllerHost = ""
    
    init() {
        _config = State(initialValue: .default)
    }
    
    var body: some View {
        Form {
            Section("WLED Integration") {
                Toggle("Enable WLED", isOn: $config.enabled)
                
                Stepper("Update Rate: \(config.updateRateHz) Hz", 
                        value: $config.updateRateHz, in: 20...100, step: 10)
                
                Slider(value: $config.fftSmoothing, in: 0...1) {
                    Text("FFT Smoothing: \(String(format: "%.2f", config.fftSmoothing))")
                }
            }
            
            Section("Controllers") {
                ForEach(config.controllers) { controller in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(controller.name)
                                .font(.headline)
                            Text("\(controller.host):\(controller.port)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: binding(for: controller.id))
                            .labelsHidden()
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            removeController(id: controller.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                
                HStack {
                    TextField("Name", text: $newControllerName)
                    TextField("IP Address", text: $newControllerHost)
                    Button("Add") {
                        addController()
                    }
                    .disabled(newControllerName.isEmpty || newControllerHost.isEmpty)
                }
            }
            
            Section("Status") {
                if let status = getStatus() {
                    LabeledContent("Active Controllers", value: "\(status["controllersActive"] ?? 0)")
                    LabeledContent("Packets Sent", value: "\(status["packetsProcessed"] ?? 0)")
                }
            }
        }
        .navigationTitle("WLED Settings")
        .onAppear {
            loadConfig()
        }
        .onChange(of: config) { newValue in
            saveConfig(newValue)
        }
    }
    
    private func loadConfig() {
        Task {
            let settings = await store.environment.settings
            config = await settings.loadWLEDConfig()
        }
    }
    
    private func saveConfig(_ newConfig: WLEDConfig) {
        Task {
            let settings = await store.environment.settings
            await settings.saveWLEDConfig(newConfig)
            
            // Update running module
            let wled = await store.environment.registry.wled
            await wled.updateConfig(newConfig)
        }
    }
    
    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: {
                config.controllers.first { $0.id == id }?.enabled ?? false
            },
            set: { enabled in
                if let index = config.controllers.firstIndex(where: { $0.id == id }) {
                    var controllers = config.controllers
                    let controller = controllers[index]
                    controllers[index] = WLEDController(
                        id: controller.id,
                        name: controller.name,
                        host: controller.host,
                        port: controller.port,
                        enabled: enabled
                    )
                    config = WLEDConfig(
                        controllers: controllers,
                        enabled: config.enabled,
                        updateRateHz: config.updateRateHz,
                        fftSmoothing: config.fftSmoothing
                    )
                }
            }
        )
    }
    
    private func addController() {
        let newController = WLEDController(
            id: UUID().uuidString,
            name: newControllerName,
            host: newControllerHost
        )
        
        var controllers = config.controllers
        controllers.append(newController)
        config = WLEDConfig(
            controllers: controllers,
            enabled: config.enabled,
            updateRateHz: config.updateRateHz,
            fftSmoothing: config.fftSmoothing
        )
        
        newControllerName = ""
        newControllerHost = ""
    }
    
    private func removeController(id: String) {
        var controllers = config.controllers
        controllers.removeAll { $0.id == id }
        config = WLEDConfig(
            controllers: controllers,
            enabled: config.enabled,
            updateRateHz: config.updateRateHz,
            fftSmoothing: config.fftSmoothing
        )
    }
    
    private func getStatus() -> [String: Any]? {
        // This would be updated via async call to module
        nil
    }
}
```

## 4. Add to Settings Navigation

Update `Sources/SwiftVJApp/SettingsView.swift`:

```swift
struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Playback") {
                    PlaybackSettingsView()
                }
                NavigationLink("OSC") {
                    OSCSettingsView()
                }
                NavigationLink("WLED Integration") {  // Add this
                    WLEDSettingsView()
                }
                NavigationLink("Launchpad") {
                    LaunchpadSettingsView()
                }
            }
            .navigationTitle("Settings")
        }
    }
}
```

## 5. Wire Audio Processor to WLED

Update `Sources/SwiftVJCore/Adapters/SynesthesiaAudioProcessor.swift`:

```swift
public actor SynesthesiaAudioProcessor {
    // ... existing code ...
    
    private var wledModule: WLEDModule?
    
    public func setWLEDModule(_ module: WLEDModule) {
        self.wledModule = module
    }
    
    // In your OSC message handler:
    private func handleOSCMessage(_ address: String, _ values: [any OSCValue]) {
        // ... existing audio processing ...
        
        // Forward to WLED
        if let wled = wledModule {
            Task {
                await wled.updateAudioLevels(currentLevels)
            }
        }
    }
}
```

## 6. Update Store to Include WLED Config

Update `Sources/SwiftVJCore/Store/AppState.swift`:

```swift
public struct AppState: Equatable {
    // ... existing state ...
    
    public var wledConfig: WLEDConfig
    public var wledStatus: WLEDStatus
    
    public init(
        // ... existing params ...
        wledConfig: WLEDConfig = .default,
        wledStatus: WLEDStatus = WLEDStatus()
    ) {
        // ... existing init ...
        self.wledConfig = wledConfig
        self.wledStatus = wledStatus
    }
}

public struct WLEDStatus: Equatable {
    public var enabled: Bool = false
    public var controllersActive: Int = 0
    public var packetsProcessed: Int = 0
    public var lastError: String?
    
    public init() {}
}
```

## 7. Add Actions for WLED Control

Update `Sources/SwiftVJCore/Store/Actions.swift`:

```swift
public enum AppAction: Equatable {
    // ... existing actions ...
    
    // WLED actions
    case wledConfigLoaded(WLEDConfig)
    case wledConfigUpdated(WLEDConfig)
    case wledStatusUpdated(WLEDStatus)
    case wledControllerAdded(WLEDController)
    case wledControllerRemoved(String)
    case wledToggled(Bool)
}
```

## 8. Add Reducer Cases

Update `Sources/SwiftVJCore/Store/Reducer.swift`:

```swift
public func appReducer(state: inout AppState, action: AppAction) -> Effect<AppAction> {
    switch action {
    // ... existing cases ...
    
    case .wledConfigLoaded(let config):
        state.wledConfig = config
        return .none
        
    case .wledConfigUpdated(let config):
        state.wledConfig = config
        return .fireAndForget {
            // Save to disk
            let settings = Settings()
            await settings.saveWLEDConfig(config)
        }
        
    case .wledStatusUpdated(let status):
        state.wledStatus = status
        return .none
        
    case .wledControllerAdded(let controller):
        var config = state.wledConfig
        var controllers = config.controllers
        controllers.append(controller)
        state.wledConfig = WLEDConfig(
            controllers: controllers,
            enabled: config.enabled,
            updateRateHz: config.updateRateHz,
            fftSmoothing: config.fftSmoothing
        )
        return .send(.wledConfigUpdated(state.wledConfig))
        
    case .wledControllerRemoved(let id):
        var config = state.wledConfig
        var controllers = config.controllers
        controllers.removeAll { $0.id == id }
        state.wledConfig = WLEDConfig(
            controllers: controllers,
            enabled: config.enabled,
            updateRateHz: config.updateRateHz,
            fftSmoothing: config.fftSmoothing
        )
        return .send(.wledConfigUpdated(state.wledConfig))
        
    case .wledToggled(let enabled):
        var config = state.wledConfig
        state.wledConfig = WLEDConfig(
            controllers: config.controllers,
            enabled: enabled,
            updateRateHz: config.updateRateHz,
            fftSmoothing: config.fftSmoothing
        )
        return .send(.wledConfigUpdated(state.wledConfig))
    }
}
```

## 9. Testing the Integration

### Manual Test

1. Start Swift-VJ app
2. Go to Settings → WLED Integration
3. Add a WLED controller (IP address)
4. Enable WLED Integration
5. Play audio in Synesthesia
6. Check WLED web interface: Info → UDP Sound Sync should show "receiving"
7. LED effects should react to audio

### Automated Test

Create `Tests/E2ETests/WLEDIntegrationTests.swift`:

```swift
import XCTest
@testable import SwiftVJCore

final class WLEDIntegrationTests: XCTestCase {
    
    func testWLEDModuleLifecycle() async throws {
        // Skip if no WLED available
        guard ProcessInfo.processInfo.environment["WLED_TEST_HOST"] != nil else {
            throw XCTSkip("WLED_TEST_HOST not set")
        }
        
        let host = ProcessInfo.processInfo.environment["WLED_TEST_HOST"]!
        
        let config = WLEDConfig(
            controllers: [
                WLEDController(id: "test", name: "Test", host: host)
            ],
            enabled: true,
            updateRateHz: 10  // Low rate for testing
        )
        
        let module = WLEDModule(config: config)
        
        // Start module
        try await module.start()
        
        // Send some audio data
        let levels = OSCAudioLevels(
            bass: 0.8,
            lowMid: 0.6,
            mid: 0.5,
            highs: 0.4,
            level: 0.6
        )
        
        await module.updateAudioLevels(levels)
        
        // Wait for packets to be sent
        try await Task.sleep(for: .seconds(1))
        
        // Check status
        let status = await module.getStatus()
        XCTAssertTrue(status["started"] as? Bool ?? false)
        
        // Stop module
        await module.stop()
    }
}
```

Run with:
```bash
WLED_TEST_HOST=192.168.1.100 swift test --filter WLEDIntegrationTests
```

## 10. Troubleshooting Integration

### Module doesn't start

Check:
- ModuleRegistry includes WLED module
- startAll() calls wled.start()
- No errors in console logs

### No packets sent

Check:
- Config enabled = true
- At least one controller enabled
- Valid IP addresses
- Network connectivity (ping WLED IP)

### Audio data not reaching WLED

Check:
- OSC subscription is set up
- SynesthesiaAudioProcessor forwards to WLED
- Synesthesia is sending OSC messages
- Check OSC Debug view for /syn/* messages

## 11. Performance Monitoring

Add to your debug view:

```swift
struct WLEDDebugView: View {
    @EnvironmentObject var store: Store
    @State private var status: [String: Any] = [:]
    
    var body: some View {
        List {
            Section("WLED Status") {
                Text("Enabled: \(status["enabled"] as? Bool ?? false ? "Yes" : "No")")
                Text("Controllers: \(status["controllersActive"] as? Int ?? 0)")
                Text("Packets: \(status["packetsProcessed"] as? Int ?? 0)")
                Text("Update Rate: \(status["updateRateHz"] as? Int ?? 0) Hz")
            }
        }
        .onAppear {
            startMonitoring()
        }
    }
    
    private func startMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task {
                let wled = await store.environment.registry.wled
                status = await wled.getStatus()
            }
        }
    }
}
```

---

## Summary

The WLED integration is designed to plug seamlessly into Swift-VJ's existing architecture:

1. **ModuleRegistry** - Manages WLED module lifecycle
2. **Store/Reducer** - Handles state and actions
3. **Settings** - Persists configuration
4. **OSC subscription** - Feeds audio data
5. **UI** - Controls and monitors WLED

All components follow Swift-VJ's design patterns (Module protocol, TCA-style store, deep adapters) for consistency and maintainability.
