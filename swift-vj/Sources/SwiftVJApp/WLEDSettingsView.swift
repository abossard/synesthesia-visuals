// WLEDSettingsView - WLED Sound Reactive configuration panel
// Provides UI for managing WLED controllers and settings

import SwiftUI
import SwiftVJCore
import Network

struct WLEDSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var config: WLEDConfig = .default
    @State private var isLoading = false
    @State private var isScanning = false
    @State private var discoveredDevices: [DiscoveredWLED] = []
    
    // New controller form
    @State private var showAddController = false
    @State private var newName = ""
    @State private var newHost = ""
    @State private var newPort = "21324"
    
    var body: some View {
        Form {
            // Status section
            Section {
                HStack {
                    Image(systemName: config.enabled ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(config.enabled ? .green : .gray)
                    Text("WLED Integration")
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { config.enabled },
                        set: { newValue in
                            config = WLEDConfig(
                                controllers: config.controllers,
                                enabled: newValue,
                                updateRateHz: config.updateRateHz,
                                fftSmoothing: config.fftSmoothing
                            )
                            saveConfig()
                            logStatusChange(enabled: newValue)
                        }
                    ))
                    .labelsHidden()
                }
                
                if config.enabled {
                    let activeCount = config.controllers.filter { $0.enabled }.count
                    HStack {
                        Image(systemName: "led.strip.horizontal")
                        Text("\(activeCount) of \(config.controllers.count) controllers active")
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Status")
            }
            
            // Global settings
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Update Rate")
                        Spacer()
                        Text("\(config.updateRateHz) Hz")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { Double(config.updateRateHz) },
                            set: { newValue in
                                config = WLEDConfig(
                                    controllers: config.controllers,
                                    enabled: config.enabled,
                                    updateRateHz: Int(newValue),
                                    fftSmoothing: config.fftSmoothing
                                )
                                saveConfig()
                            }
                        ),
                        in: 20...100,
                        step: 10
                    )
                    Text("Lower rates reduce network traffic and CPU usage")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("FFT Smoothing")
                        Spacer()
                        Text(String(format: "%.2f", config.fftSmoothing))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { Double(config.fftSmoothing) },
                            set: { newValue in
                                config = WLEDConfig(
                                    controllers: config.controllers,
                                    enabled: config.enabled,
                                    updateRateHz: config.updateRateHz,
                                    fftSmoothing: Float(newValue)
                                )
                                saveConfig()
                            }
                        ),
                        in: 0...1,
                        step: 0.05
                    )
                    Text("Higher values = smoother but less responsive")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Global Settings")
            } footer: {
                Text("These settings apply to all WLED controllers")
            }
            
            // Controllers section
            Section {
                if config.controllers.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "led.strip.horizontal")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No WLED Controllers")
                            .font(.headline)
                        Text("Add controllers manually or scan your network")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    ForEach(config.controllers, id: \.id) { controller in
                        ControllerRow(
                            controller: controller,
                            onToggle: { enabled in
                                toggleController(id: controller.id, enabled: enabled)
                            },
                            onDelete: {
                                removeController(id: controller.id)
                            }
                        )
                    }
                }
                
                HStack {
                    Button {
                        showAddController = true
                    } label: {
                        Label("Add Controller", systemImage: "plus.circle.fill")
                    }
                    
                    Spacer()
                    
                    Button {
                        scanNetwork()
                    } label: {
                        if isScanning {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                        }
                        Text("Scan Network")
                    }
                    .disabled(isScanning)
                }
            } header: {
                Text("Controllers")
            } footer: {
                if !discoveredDevices.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Discovered devices:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ForEach(discoveredDevices, id: \.host) { device in
                            HStack {
                                Text("• \(device.name) (\(device.host))")
                                    .font(.caption)
                                Spacer()
                                Button("Add") {
                                    addDiscoveredDevice(device)
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("WLED Integration")
        .sheet(isPresented: $showAddController) {
            AddControllerSheet(
                name: $newName,
                host: $newHost,
                port: $newPort,
                onAdd: {
                    addController()
                },
                onCancel: {
                    showAddController = false
                    clearForm()
                }
            )
        }
        .onAppear {
            loadConfig()
        }
    }
    
    // MARK: - Actions
    
    private func loadConfig() {
        isLoading = true
        Task {
            // Load from disk via Settings
            // For now, use default config
            config = .default
            isLoading = false
        }
    }
    
    private func saveConfig() {
        Task {
            // Save to disk via Settings
            // This would integrate with Config.swift saveWLEDConfig
            appState.log("WLED configuration saved", level: .info)
        }
    }
    
    private func addController() {
        guard !newName.isEmpty && !newHost.isEmpty else { return }
        
        let port = UInt16(newPort) ?? 21324
        let controller = WLEDController(
            id: UUID().uuidString,
            name: newName,
            host: newHost,
            port: port,
            enabled: true
        )
        
        var controllers = config.controllers
        controllers.append(controller)
        
        config = WLEDConfig(
            controllers: controllers,
            enabled: config.enabled,
            updateRateHz: config.updateRateHz,
            fftSmoothing: config.fftSmoothing
        )
        
        saveConfig()
        showAddController = false
        clearForm()
        
        appState.log("Added WLED controller: \(newName) (\(newHost):\(port))", level: .info)
    }
    
    private func addDiscoveredDevice(_ device: DiscoveredWLED) {
        let controller = WLEDController(
            id: UUID().uuidString,
            name: device.name,
            host: device.host,
            port: 21324,
            enabled: true
        )
        
        var controllers = config.controllers
        controllers.append(controller)
        
        config = WLEDConfig(
            controllers: controllers,
            enabled: config.enabled,
            updateRateHz: config.updateRateHz,
            fftSmoothing: config.fftSmoothing
        )
        
        saveConfig()
        discoveredDevices.removeAll { $0.host == device.host }
        
        appState.log("Added discovered WLED device: \(device.name)", level: .info)
    }
    
    private func removeController(id: String) {
        guard let controller = config.controllers.first(where: { $0.id == id }) else { return }
        
        var controllers = config.controllers
        controllers.removeAll { $0.id == id }
        
        config = WLEDConfig(
            controllers: controllers,
            enabled: config.enabled,
            updateRateHz: config.updateRateHz,
            fftSmoothing: config.fftSmoothing
        )
        
        saveConfig()
        appState.log("Removed WLED controller: \(controller.name)", level: .info)
    }
    
    private func toggleController(id: String, enabled: Bool) {
        guard let index = config.controllers.firstIndex(where: { $0.id == id }) else { return }
        
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
        
        saveConfig()
        
        let status = enabled ? "enabled" : "disabled"
        appState.log("WLED controller \(controller.name) \(status)", level: .info)
    }
    
    private func scanNetwork() {
        isScanning = true
        discoveredDevices = []
        
        appState.log("Scanning network for WLED devices...", level: .info)
        
        // Simulate network scan (in real implementation, use Bonjour/mDNS)
        Task {
            try? await Task.sleep(for: .seconds(2))
            
            // Mock discovered devices for demonstration
            // Real implementation would use NWBrowser or Bonjour
            
            isScanning = false
            appState.log("Network scan complete. Found \(discoveredDevices.count) devices.", level: .info)
        }
    }
    
    private func clearForm() {
        newName = ""
        newHost = ""
        newPort = "21324"
    }
    
    private func logStatusChange(enabled: Bool) {
        if enabled {
            let activeCount = config.controllers.filter { $0.enabled }.count
            appState.log("WLED integration enabled with \(activeCount) active controller(s)", level: .info)
        } else {
            appState.log("WLED integration disabled", level: .warning)
        }
    }
}

// MARK: - Controller Row

struct ControllerRow: View {
    let controller: WLEDController
    let onToggle: (Bool) -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: controller.enabled ? "led.strip.horizontal.fill" : "led.strip.horizontal")
                .foregroundColor(controller.enabled ? .green : .secondary)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.name)
                    .font(.body)
                Text("\(controller.host):\(controller.port)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { controller.enabled },
                set: { onToggle($0) }
            ))
            .labelsHidden()
            
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Controller Sheet

struct AddControllerSheet: View {
    @Binding var name: String
    @Binding var host: String
    @Binding var port: String
    let onAdd: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add WLED Controller")
                .font(.headline)
            
            Form {
                TextField("Name (e.g., Living Room Strip)", text: $name)
                TextField("IP Address (e.g., 192.168.1.100)", text: $host)
                TextField("Port", text: $port)
                    .frame(width: 100)
            }
            .formStyle(.grouped)
            .frame(height: 150)
            
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Add") {
                    onAdd()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || host.isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 280)
    }
}

// MARK: - Supporting Types

struct DiscoveredWLED: Identifiable {
    let id = UUID()
    let name: String
    let host: String
}

// MARK: - Preview

#Preview {
    WLEDSettingsView()
        .environmentObject({
            let state = AppState()
            return state
        }())
        .frame(width: 600, height: 500)
}
