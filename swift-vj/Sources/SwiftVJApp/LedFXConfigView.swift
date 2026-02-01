// LedFXConfigView.swift - SwiftUI configuration panel for LedFX integration
// Following A Philosophy of Software Design: simple UI for complex functionality

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SwiftVJCore
import OscRestBridge

struct LedFXConfigView: View {
    @EnvironmentObject var appState: AppState
    
    // Settings
    @AppStorage("ledfx_baseURL") private var baseURL = "http://127.0.0.1:8888"
    @AppStorage("ledfx_virtualIds") private var virtualIdsString = ""
    @AppStorage("ledfx_enabled") private var ledfxEnabled = false
    
    // State
    @State private var isRefreshing = false
    @State private var serverInfo: LedFXInfo?
    @State private var scenes: [String: LedFXScene] = [:]
    @State private var virtuals: [String: LedFXVirtual] = [:]
    @State private var errorMessage: String?
    @State private var showingSceneGenerator = false
    @State private var isGeneratingConfig = false
    @State private var generatedConfig: BridgeConfig?
    @State private var generatedYaml: String?
    @State private var supportedRouteGroups: [SupportedRouteGroup] = []
    @State private var playlistCount: Int = 0
    @State private var effectsCount: Int = 0
    
    private var virtualIds: [String] {
        virtualIdsString
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Connection Settings
                connectionSection
                
                // Status
                if ledfxEnabled {
                    statusSection
                }
                
                // Scene Management
                if ledfxEnabled && !scenes.isEmpty {
                    sceneSection
                }
                
                // Virtual Devices
                if ledfxEnabled && !virtuals.isEmpty {
                    virtualsSection
                }

                if ledfxEnabled {
                    configSection
                }

                if ledfxEnabled && !supportedRouteGroups.isEmpty {
                    supportedPathsSection
                }
                
                // Error Display
                if let error = errorMessage {
                    errorSection(error)
                }
            }
            .padding()
        }
        .navigationTitle("LedFX Configuration")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await refreshData() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isRefreshing || !ledfxEnabled)
            }
            
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingSceneGenerator = true }) {
                    Label("Generate Scenes", systemImage: "wand.and.stars")
                }
                .disabled(!ledfxEnabled)
            }
        }
        .sheet(isPresented: $showingSceneGenerator) {
            SceneGeneratorSheet(
                virtualIds: virtualIds,
                onGenerate: { tracks in
                    await generateScenes(tracks: tracks)
                }
            )
        }
        .task {
            if ledfxEnabled {
                await refreshData()
            }
        }
    }
    
    // MARK: - Sections
    
    private var connectionSection: some View {
        GroupBox("Connection") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable LedFX Integration", isOn: $ledfxEnabled)
                    .onChange(of: ledfxEnabled) { _, newValue in
                        Task {
                            if newValue {
                                await startLedFX()
                            } else {
                                await stopLedFX()
                            }
                        }
                    }
                
                if ledfxEnabled {
                    TextField("Base URL", text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("Virtual IDs (comma-separated)", text: $virtualIdsString)
                        .textFieldStyle(.roundedBorder)
                    
                    Text("Example: virtual-1, virtual-2")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("Test Connection") {
                        Task { await testConnection() }
                    }
                    .disabled(isRefreshing)
                }
            }
            .padding()
        }
    }
    
    private var statusSection: some View {
        GroupBox("Server Status") {
            VStack(alignment: .leading, spacing: 8) {
                if let info = serverInfo {
                    statusRow("Server", info.name)
                    statusRow("Version", info.version)
                    statusRow("URL", info.url)
                    statusRow("Scenes", "\(scenes.count)")
                    statusRow("Virtuals", "\(virtuals.count)")
                } else {
                    Text("Not connected")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
    }
    
    private var sceneSection: some View {
        GroupBox("Scenes (\(scenes.count))") {
            VStack(spacing: 8) {
                ForEach(Array(scenes.keys.sorted()), id: \.self) { sceneId in
                    if let scene = scenes[sceneId] {
                        SceneRow(
                            id: sceneId,
                            scene: scene,
                            onActivate: { await activateScene(id: sceneId) },
                            onDeactivate: { await deactivateScene(id: sceneId) },
                            onDelete: { await deleteScene(id: sceneId) }
                        )
                    }
                }
            }
            .padding()
        }
    }
    
    private var virtualsSection: some View {
        GroupBox("Virtual Devices (\(virtuals.count))") {
            VStack(spacing: 8) {
                ForEach(Array(virtuals.keys.sorted()), id: \.self) { virtualId in
                    if let virtual = virtuals[virtualId] {
                        VirtualRow(
                            id: virtualId,
                            virtual: virtual,
                            onSetBrightness: { brightness in
                                await setVirtualBrightness(id: virtualId, brightness: brightness)
                            }
                        )
                    }
                }
            }
            .padding()
        }
    }

    private var configSection: some View {
        GroupBox("OSC REST Bridge") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Button("Generate Config") {
                        Task { await generateBridgeConfig() }
                    }
                    .disabled(isGeneratingConfig)

                    Button("Save As…") {
                        saveConfigAs()
                    }
                    .disabled(generatedYaml == nil)

                    Button("Load This Config") {
                        Task { await loadGeneratedConfig() }
                    }
                    .disabled(generatedYaml == nil)
                }

                if isGeneratingConfig {
                    ProgressView("Generating...")
                }

                if generatedConfig != nil {
                    Text("Playlists: \(playlistCount) · Effects: \(effectsCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
    }

    private var supportedPathsSection: some View {
        GroupBox("Supported OSC Paths") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(supportedRouteGroups) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.title)
                            .font(.headline)
                        ForEach(group.paths, id: \.self) { path in
                            Text(path)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    private func errorSection(_ error: String) -> some View {
        GroupBox {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(error)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Dismiss") {
                    errorMessage = nil
                }
            }
            .padding()
        }
    }
    
    private func statusRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
    }
    
    // MARK: - Actions
    
    private func startLedFX() async {
        guard appState.ledfxModule == nil else { return }
        
        let module = LedFXModule(baseURL: baseURL, virtualIds: virtualIds)
        appState.ledfxModule = module
        
        do {
            try await module.start()
            await refreshData()
        } catch {
            errorMessage = "LedFX is enabled but unreachable: \(error.localizedDescription)"
        }
    }
    
    private func stopLedFX() async {
        guard let module = appState.ledfxModule else { return }
        await module.stop()
        appState.ledfxModule = nil
        
        serverInfo = nil
        scenes = [:]
        virtuals = [:]
    }
    
    private func testConnection() async {
        guard let module = appState.ledfxModule else { return }
        
        isRefreshing = true
        errorMessage = nil
        
        do {
            try await module.refreshScenes()
            await refreshData()
        } catch {
            errorMessage = "Connection test failed: \(error.localizedDescription)"
        }
        
        isRefreshing = false
    }
    
    private func refreshData() async {
        guard let module = appState.ledfxModule else { return }
        
        isRefreshing = true
        errorMessage = nil
        
        do {
            // Get server info from status
            let status = await module.getStatus()
            if let version = status["server_version"], case .string(let versionStr) = version {
                serverInfo = LedFXInfo(url: baseURL, name: "LedFX", version: versionStr)
            }
            
            // Refresh scenes and virtuals
            try await module.refreshScenes()
            try await module.refreshVirtuals()
            
            scenes = await module.getScenes()
            virtuals = await module.getVirtuals()
        } catch {
            errorMessage = "Failed to refresh: \(error.localizedDescription)"
        }
        
        isRefreshing = false
    }
    
    private func activateScene(id: String) async {
        guard let module = appState.ledfxModule else { return }
        
        do {
            try await module.activateScene(id: id)
            await refreshData()
        } catch {
            errorMessage = "Failed to activate scene: \(error.localizedDescription)"
        }
    }
    
    private func deactivateScene(id: String) async {
        guard let module = appState.ledfxModule else { return }
        
        do {
            try await module.deactivateScene(id: id)
            await refreshData()
        } catch {
            errorMessage = "Failed to deactivate scene: \(error.localizedDescription)"
        }
    }
    
    private func deleteScene(id: String) async {
        guard let module = appState.ledfxModule else { return }
        
        do {
            try await module.deleteScene(id: id)
            await refreshData()
        } catch {
            errorMessage = "Failed to delete scene: \(error.localizedDescription)"
        }
    }
    
    private func setVirtualBrightness(id: String, brightness: Double) async {
        guard let module = appState.ledfxModule else { return }
        
        do {
            try await module.setVirtualBrightness(id: id, brightness: brightness)
            await refreshData()
        } catch {
            errorMessage = "Failed to set brightness: \(error.localizedDescription)"
        }
    }
    
    private func generateScenes(tracks: [(name: String, energy: Double, valence: Double, bpm: Double?)]) async {
        guard let module = appState.ledfxModule else { return }
        
        do {
            try await module.generateDJSetScenes(tracks: tracks)
            await refreshData()
            showingSceneGenerator = false
        } catch {
            errorMessage = "Failed to generate scenes: \(error.localizedDescription)"
        }
    }

    private func generateBridgeConfig() async {
        let currentBaseURL = baseURL

        await MainActor.run {
            isGeneratingConfig = true
            errorMessage = nil
        }

        Task.detached(priority: .userInitiated) {
            do {
                let client = LedFXClient(baseURL: currentBaseURL)
                let playlistsResponse = try await client.listPlaylists()
                let scenesResponse = try await client.listScenes()
                let virtualsResponse = try await client.listVirtuals()
                let effectsResponse = try await client.listEffectsCatalog()

                let input = LedFXBridgeConfigGenerator.Input(
                    baseURL: currentBaseURL,
                    playlists: playlistsResponse.playlists,
                    scenes: scenesResponse,
                    virtuals: virtualsResponse,
                    effects: effectsResponse.effects
                )

                let config = try LedFXBridgeConfigGenerator.generate(input: input)
                let yaml = try ConfigLoader.export(config)
                let routes = buildSupportedRoutes(config: config)

                await MainActor.run {
                    playlistCount = playlistsResponse.playlists.count
                    effectsCount = effectsResponse.effects.count
                    generatedConfig = config
                    generatedYaml = yaml
                    supportedRouteGroups = routes
                    isGeneratingConfig = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to generate config: \(error.localizedDescription)"
                    isGeneratingConfig = false
                }
            }
        }
    }

    @MainActor
    private func saveConfigAs() {
        guard let yaml = generatedYaml else {
            errorMessage = "Generate a config before saving"
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "yaml") ?? .plainText]
        panel.nameFieldStringValue = "ledfx-bridge.yaml"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try yaml.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                errorMessage = "Failed to save config: \(error.localizedDescription)"
            }
        }
    }

    private func loadGeneratedConfig() async {
        guard let yaml = generatedYaml else {
            errorMessage = "Generate a config before loading"
            return
        }

        do {
            let bridge = ensureOscRestBridge()
            try await bridge.loadConfig(from: Data(yaml.utf8))
        } catch {
            errorMessage = "Failed to load config: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func ensureOscRestBridge() -> OscRestBridgeService {
        if let bridge = appState.oscRestBridge { return bridge }
        let bridge = OscRestBridgeService(httpClient: URLSessionHTTPClient())
        appState.oscRestBridge = bridge
        return bridge
    }

}

private struct SupportedRouteGroup: Identifiable {
    let id: String
    let title: String
    let paths: [String]
}

private func buildSupportedRoutes(config: BridgeConfig) -> [SupportedRouteGroup] {
    let slotIds = config.slots.keys.sorted()
    let sceneNames = config.scenes.keys.sorted()
    let oneshotNames = config.oneshots.keys.sorted()
    let paramNames = config.params.keys.sorted()

    let scenePaths = sceneNames.flatMap { scene in
        slotIds.map { slot in "/ledfx/scene/\(scene)/\(slot)" }
    }
    let oneshotPaths = oneshotNames.flatMap { oneshot in
        slotIds.map { slot in "/ledfx/oneshot/\(oneshot)/\(slot)" }
    }
    let paramPaths = paramNames.flatMap { param in
        slotIds.map { slot in "/ledfx/param/\(param)/\(slot)" }
    }
    let blackoutPaths = slotIds.map { slot in "/ledfx/blackout/\(slot)" }

    return [
        SupportedRouteGroup(id: "scenes", title: "Scenes", paths: scenePaths),
        SupportedRouteGroup(id: "oneshots", title: "Oneshots", paths: oneshotPaths),
        SupportedRouteGroup(id: "params", title: "Params", paths: paramPaths),
        SupportedRouteGroup(id: "blackout", title: "Blackout", paths: blackoutPaths)
    ].filter { !$0.paths.isEmpty }
}

// MARK: - Scene Row

private struct SceneRow: View {
    let id: String
    let scene: LedFXScene
    let onActivate: () async -> Void
    let onDeactivate: () async -> Void
    let onDelete: () async -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(scene.name)
                    .font(.headline)
                if let tags = scene.sceneTags {
                    Text(tags)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if scene.active {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
            
            Button(action: { Task { await onActivate() } }) {
                Label("Activate", systemImage: "play.circle")
                    .labelStyle(.iconOnly)
            }
            .disabled(scene.active)
            
            if scene.active {
                Button(action: { Task { await onDeactivate() } }) {
                    Label("Deactivate", systemImage: "stop.circle")
                        .labelStyle(.iconOnly)
                }
            }
            
            Button(role: .destructive, action: { Task { await onDelete() } }) {
                Label("Delete", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Virtual Row

private struct VirtualRow: View {
    let id: String
    let virtual: LedFXVirtual
    let onSetBrightness: (Double) async -> Void
    
    @State private var brightness: Double = 0.8
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(virtual.config?.name ?? id)
                    .font(.headline)
                Spacer()
                if let effect = virtual.effect {
                    Text(effect.type)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            
            HStack {
                Text("Brightness")
                    .font(.caption)
                Slider(value: $brightness, in: 0.0...1.0, step: 0.1)
                    .onChange(of: brightness) { _, newValue in
                        Task {
                            await onSetBrightness(newValue)
                        }
                    }
                Text("\(Int(brightness * 100))%")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 40)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            brightness = virtual.config?.brightness ?? 0.8
        }
    }
}

// MARK: - Scene Generator Sheet

private struct SceneGeneratorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let virtualIds: [String]
    let onGenerate: ([(name: String, energy: Double, valence: Double, bpm: Double?)]) async -> Void
    
    @State private var presetType: PresetType = .standard
    
    enum PresetType: String, CaseIterable {
        case standard = "Standard Presets"
        case custom = "Custom DJ Set"
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Generate LedFX Scenes")
                .font(.title)
            
            Picker("Type", selection: $presetType) {
                ForEach(PresetType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            if presetType == .standard {
                Text("This will generate standard preset scenes for common moods and energy levels.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Button("Generate Standard Presets") {
                    Task {
                        await onGenerate([
                            ("High Energy", 0.9, 0.7, nil),
                            ("Medium Energy", 0.5, 0.5, nil),
                            ("Low Energy", 0.2, 0.6, nil),
                            ("Uplifting", 0.6, 0.9, nil),
                            ("Dark", 0.7, 0.2, nil)
                        ])
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("Custom DJ set generation coming soon...")
                    .foregroundColor(.secondary)
            }
            
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
    }
}

// MARK: - Preview

#Preview {
    LedFXConfigView()
        .environmentObject(AppState())
}
