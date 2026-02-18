// LedFXConfigView.swift - SwiftUI configuration panel for LedFX integration
// Following A Philosophy of Software Design: simple UI for complex functionality

import SwiftUI
import SwiftVJCore
import OscRestBridge
import Foundation

struct LedFXConfigView: View {
    @EnvironmentObject var appState: AppState

    // UI State
    @State private var showingSceneGenerator = false
    
    private var virtualIds: [String] { appState.ledfxVirtualIds }

    private var slotIdsForPaths: [String] {
        appState.ledfxSlotIdsForPaths
    }

    private var activePlaylistId: String? {
        appState.ledfxActivePlaylistId
    }

    private var activePlaylistLabel: String {
        guard let id = activePlaylistId else { return "None" }
        return appState.ledfxPlaylists[id]?.name ?? id
    }

    private var sceneNameLookup: [String: String] {
        appState.ledfxScenes.mapValues { $0.name }
    }

    private var supportedRouteGroups: [SupportedRouteGroup] {
        guard let config = appState.ledfxGeneratedConfig else { return [] }
        return buildSupportedRoutes(config: config)
    }

    private var sceneFilterRegex: NSRegularExpression? {
        guard !appState.ledfxSceneFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return try? NSRegularExpression(pattern: appState.ledfxSceneFilter, options: [.caseInsensitive])
    }

    private var playlistFilterRegex: NSRegularExpression? {
        guard !appState.ledfxPlaylistFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return try? NSRegularExpression(pattern: appState.ledfxPlaylistFilter, options: [.caseInsensitive])
    }

    private var filteredScenes: [(id: String, scene: LedFXScene)] {
        let items = appState.ledfxScenes.keys.sorted().compactMap { id -> (id: String, scene: LedFXScene)? in
            guard let scene = appState.ledfxScenes[id] else { return nil }
            return (id: id, scene: scene)
        }
        guard let regex = sceneFilterRegex else { return items }
        return items.filter { item in
            let target = "\(item.scene.name) \(item.id)"
            let range = NSRange(target.startIndex..<target.endIndex, in: target)
            return regex.firstMatch(in: target, options: [], range: range) != nil
        }
    }

    private var filteredPlaylists: [(id: String, playlist: LedFXPlaylist)] {
        let items = appState.ledfxPlaylists.keys.sorted().compactMap { id -> (id: String, playlist: LedFXPlaylist)? in
            guard let playlist = appState.ledfxPlaylists[id] else { return nil }
            return (id: id, playlist: playlist)
        }
        guard let regex = playlistFilterRegex else { return items }
        return items.filter { item in
            let target = "\(item.playlist.name) \(item.id)"
            let range = NSRange(target.startIndex..<target.endIndex, in: target)
            return regex.firstMatch(in: target, options: [], range: range) != nil
        }
    }

    private var refreshSummary: String {
        guard let last = appState.ledfxLastHealthCheck else { return "Not refreshed yet" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: last, relativeTo: Date())
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                overviewSection
                playlistsSection

                LazyVGrid(columns: gridColumns, spacing: 16) {
                    connectionSection
                    filtersSection
                    statusSection
                    bridgeSection
                }

                if !appState.ledfxScenes.isEmpty || !appState.ledfxVirtuals.isEmpty {
                    LazyVGrid(columns: gridColumns, spacing: 16) {
                        if !appState.ledfxScenes.isEmpty {
                            sceneSection
                        }
                        if !appState.ledfxVirtuals.isEmpty {
                            virtualsSection
                        }
                    }
                }

                if !supportedRouteGroups.isEmpty {
                    supportedPathsSection
                }

                if !appState.ledfxPlaylists.isEmpty || !appState.ledfxScenes.isEmpty {
                    livePathsSection
                }

                if let error = appState.ledfxErrorMessage {
                    errorSection(error)
                }
            }
            .padding()
        }
        .navigationTitle("LedFX Configuration")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.send(.ledfx(.refresh))
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(appState.ledfxIsRefreshing)
            }
            
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingSceneGenerator = true }) {
                    Label("Generate Scenes", systemImage: "wand.and.stars")
                }
            }
        }
        .sheet(isPresented: $showingSceneGenerator) {
            SceneGeneratorSheet(
                virtualIds: virtualIds,
                onGenerate: { seeds in
                    appState.send(.ledfx(.generateScenes(seeds)))
                }
            )
        }
        .task {
            appState.send(.ledfx(.refresh))
            appState.send(.ledfx(.loadCachedConfig))
        }
    }
    
    // MARK: - Sections
    
    private var connectionSection: some View {
        GroupBox("Connection") {
            VStack(alignment: .leading, spacing: 12) {
                Text("LedFX bridge is always on. Apply & Reconnect regenerates OSC → REST routes.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Base URL", text: appState.ledfxBaseURLBinding)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Virtual IDs (comma-separated)", text: appState.ledfxVirtualIdsBinding)
                    .textFieldStyle(.roundedBorder)
                
                Text("Example: virtual-1, virtual-2")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Button("Apply & Reconnect") {
                        appState.send(.ledfx(.applySettings(
                            baseURL: appState.ledfxBaseURL,
                            virtualIds: virtualIds
                        )))
                    }
                    .disabled(appState.ledfxIsApplying)

                    Button("Test Connection") {
                        appState.send(.ledfx(.testConnection))
                    }
                    .disabled(appState.ledfxIsRefreshing)
                }
            }
            .padding()
        }
    }

    private var filtersSection: some View {
        GroupBox("Filters") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Regex filters narrow the scenes/playlists lists and their OSC paths.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Scene filter (regex)", text: appState.ledfxSceneFilterBinding)
                    .textFieldStyle(.roundedBorder)

                TextField("Playlist filter (regex)", text: appState.ledfxPlaylistFilterBinding)
                    .textFieldStyle(.roundedBorder)

                if sceneFilterRegex == nil && !appState.ledfxSceneFilter.isEmpty {
                    Text("Scene filter regex is invalid")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                if playlistFilterRegex == nil && !appState.ledfxPlaylistFilter.isEmpty {
                    Text("Playlist filter regex is invalid")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .padding()
        }
    }
    
    private var statusSection: some View {
        GroupBox("Server Status") {
            VStack(alignment: .leading, spacing: 8) {
                if let info = appState.ledfxServerInfo {
                    statusRow("Server", info.name)
                    statusRow("Version", info.version)
                    statusRow("URL", info.url)
                    statusRow("Scenes", "\(appState.ledfxScenes.count)")
                    statusRow("Playlists", "\(appState.ledfxPlaylists.count)")
                    statusRow("Virtuals", "\(appState.ledfxVirtuals.count)")
                } else {
                    Text("Not connected")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
    }

    private var playlistsSection: some View {
        GroupBox("Playlists (\(filteredPlaylists.count))") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Playlists are the primary LedFX control surface. Activating a scene will stop the current playlist.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if filteredPlaylists.isEmpty {
                    Text("No playlists available. Refresh to load playlists from LedFX.")
                        .foregroundColor(.secondary)
                } else {
                    LazyVGrid(columns: playlistColumns, spacing: 12) {
                        ForEach(filteredPlaylists, id: \.id) { item in
                            PlaylistCard(
                                id: item.id,
                                playlist: item.playlist,
                                isActive: item.id == activePlaylistId,
                                slotIds: slotIdsForPaths,
                                sceneNames: sceneNameLookup,
                                onActivate: { appState.sendLedFXAction(.activatePlaylist(item.id)) }
                            )
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    private var sceneSection: some View {
        GroupBox("Scenes (\(filteredScenes.count))") {
            VStack(spacing: 8) {
                ForEach(filteredScenes, id: \.id) { item in
                    SceneRow(
                        id: item.id,
                        scene: item.scene,
                        onActivate: { appState.sendLedFXAction(.activateScene(item.id)) },
                        onDeactivate: { appState.sendLedFXAction(.deactivateScene(item.id)) },
                        onDelete: { appState.sendLedFXAction(.deleteScene(item.id)) }
                    )
                }
            }
            .padding()
        }
    }
    
    private var virtualsSection: some View {
        GroupBox("Virtual Devices (\(appState.ledfxVirtuals.count))") {
            VStack(spacing: 8) {
                ForEach(Array(appState.ledfxVirtuals.keys.sorted()), id: \.self) { virtualId in
                    if let virtual = appState.ledfxVirtuals[virtualId] {
                        VirtualRow(
                            id: virtualId,
                            virtual: virtual,
                            onSetBrightness: { brightness in
                                appState.sendLedFXAction(.setVirtualBrightness(id: virtualId, brightness: brightness))
                            }
                        )
                    }
                }
            }
            .padding()
        }
    }

    private var bridgeSection: some View {
        GroupBox("Bridge") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Auto-configured. Refresh or Apply & Reconnect to regenerate routes.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let config = appState.ledfxGeneratedConfig {
                    Text("Slots: \(config.slots.count) · Scenes: \(config.scenes.count) · Playlists: \(config.playlists.count) · Params: \(config.params.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Config not loaded yet.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Global Controls")
                        .font(.headline)
                    Text("/ledfx/param/global_brightness/all")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("/ledfx/blackout/all")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

            }
            .padding()
        }
    }

    private var supportedPathsSection: some View {
        GroupBox("Supported OSC Paths") {
            LazyVGrid(columns: supportedColumns, spacing: 12) {
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
    }

    private var livePathsSection: some View {
        GroupBox("Live LedFX OSC Paths") {
            LazyVGrid(columns: livePathsColumns, spacing: 16) {
                if !filteredPlaylists.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Playlists")
                            .font(.headline)
                        ForEach(filteredPlaylists, id: \.id) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(item.playlist.name) (\(item.id))")
                                    .font(.subheadline)
                                ForEach(slotIdsForPaths, id: \.self) { slot in
                                    Text("/ledfx/playlist/\(item.id)/\(slot)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !filteredScenes.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Scenes")
                            .font(.headline)
                        ForEach(filteredScenes, id: \.id) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(item.scene.name) (\(item.id))")
                                    .font(.subheadline)
                                ForEach(slotIdsForPaths, id: \.self) { slot in
                                    Text("/ledfx/scene/\(item.id)/\(slot)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                    appState.send(.ledfx(.clearError))
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
}

private extension LedFXConfigView {
    var overviewSection: some View {
        LazyVGrid(columns: overviewColumns, spacing: 12) {
            MetricTile(
                title: "LedFX",
                value: appState.ledfxIsRunning ? "Online" : "Offline",
                subtitle: appState.ledfxBaseURL,
                status: appState.ledfxIsRunning ? .ok : .warning
            )

            MetricTile(
                title: "Scenes",
                value: "\(appState.ledfxScenes.count)",
                subtitle: "Filtered: \(filteredScenes.count)"
            )

            MetricTile(
                title: "Playlists",
                value: "\(appState.ledfxPlaylists.count)",
                subtitle: "Active: \(activePlaylistLabel) · Filtered: \(filteredPlaylists.count)"
            )

            MetricTile(
                title: "Virtuals",
                value: "\(appState.ledfxVirtuals.count)",
                subtitle: "Last refresh: \(refreshSummary)"
            )

            if let config = appState.ledfxGeneratedConfig {
                MetricTile(
                    title: "Routes",
                    value: "\(config.slots.count) slots",
                    subtitle: "Params: \(config.params.count)"
                )
            } else {
                MetricTile(
                    title: "Routes",
                    value: "Auto",
                    subtitle: "Config loading…"
                )
            }
        }
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
    let playlistNames = config.playlists.keys.sorted()
    let playlistControlNames = config.playlist_controls.keys.sorted()
    let oneshotNames = config.oneshots.keys.sorted()
    let paramNames = config.params.keys.sorted()

    let scenePaths = sceneNames.flatMap { scene in
        slotIds.map { slot in "/ledfx/scene/\(scene)/\(slot)" }
    }
    let playlistPaths = playlistNames.flatMap { playlist in
        slotIds.map { slot in "/ledfx/playlist/\(playlist)/\(slot)" }
    }
    let playlistControlPaths = playlistControlNames.flatMap { action in
        slotIds.map { slot in "/ledfx/playlist_control/\(action)/\(slot)" }
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
        SupportedRouteGroup(id: "playlists", title: "Playlists", paths: playlistPaths),
        SupportedRouteGroup(id: "playlist_controls", title: "Playlist Controls", paths: playlistControlPaths),
        SupportedRouteGroup(id: "oneshots", title: "Oneshots", paths: oneshotPaths),
        SupportedRouteGroup(id: "params", title: "Params", paths: paramPaths),
        SupportedRouteGroup(id: "blackout", title: "Blackout", paths: blackoutPaths)
    ].filter { !$0.paths.isEmpty }
}

// MARK: - Playlist Card

private struct PlaylistCard: View {
    let id: String
    let playlist: LedFXPlaylist
    let isActive: Bool
    let slotIds: [String]
    let sceneNames: [String: String]
    let onActivate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(playlist.name)
                        .font(.headline)
                    Text(playlist.id)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isActive {
                    Text("Active")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .foregroundColor(.green)
                        .background(Color.green.opacity(0.12))
                        .clipShape(Capsule())
                }

                Button(action: { onActivate() }) {
                    Label("Activate", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isActive)
            }

            if !playlist.items.isEmpty {
                Text("Scenes")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(Array(playlist.items.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 6) {
                        Text(sceneNames[item.sceneId] ?? item.sceneId)
                            .font(.subheadline)
                        Spacer()
                        if let duration = item.durationMs {
                            Text("\(max(1, duration / 1000))s")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            } else {
                Text("No scenes in playlist")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("OSC Paths")
                    .font(.caption)
                    .foregroundColor(.secondary)
                ForEach(slotIds, id: \.self) { slot in
                    Text("/ledfx/playlist/\(id)/\(slot)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isActive ? Color.green.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Scene Row

private struct SceneRow: View {
    let id: String
    let scene: LedFXScene
    let onActivate: () -> Void
    let onDeactivate: () -> Void
    let onDelete: () -> Void
    
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
            
            Button(action: { onActivate() }) {
                Label("Activate", systemImage: "play.circle")
                    .labelStyle(.iconOnly)
            }
            .disabled(scene.active)
            
            if scene.active {
                Button(action: { onDeactivate() }) {
                    Label("Deactivate", systemImage: "stop.circle")
                        .labelStyle(.iconOnly)
                }
            }
            
            Button(role: .destructive, action: { onDelete() }) {
                Label("Delete", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct MetricTile: View {
    enum Status {
        case ok
        case warning
        case neutral
    }

    let title: String
    let value: String
    let subtitle: String
    var status: Status = .neutral

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                LedFXStatusBadge(status: status)
            }
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct LedFXStatusBadge: View {
    let status: MetricTile.Status

    var body: some View {
        let (label, color): (String, Color) = {
            switch status {
            case .ok:
                return ("Online", .green)
            case .warning:
                return ("Offline", .orange)
            case .neutral:
                return ("", .clear)
            }
        }()

        if label.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(color)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
        }
    }
}

// MARK: - Virtual Row

private struct VirtualRow: View {
    let id: String
    let virtual: LedFXVirtual
    let onSetBrightness: (Double) -> Void
    
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
                        onSetBrightness(newValue)
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
    let onGenerate: ([LedFXSceneSeed]) -> Void
    
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
                    onGenerate([
                        LedFXSceneSeed(name: "High Energy", energy: 0.9, valence: 0.7, bpm: nil),
                        LedFXSceneSeed(name: "Medium Energy", energy: 0.5, valence: 0.5, bpm: nil),
                        LedFXSceneSeed(name: "Low Energy", energy: 0.2, valence: 0.6, bpm: nil),
                        LedFXSceneSeed(name: "Uplifting", energy: 0.6, valence: 0.9, bpm: nil),
                        LedFXSceneSeed(name: "Dark", energy: 0.7, valence: 0.2, bpm: nil)
                    ])
                    dismiss()
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

private let gridColumns = [
    GridItem(.adaptive(minimum: 320), spacing: 16)
]

private let playlistColumns = [
    GridItem(.adaptive(minimum: 280), spacing: 12)
]

private let overviewColumns = [
    GridItem(.adaptive(minimum: 200), spacing: 12)
]

private let supportedColumns = [
    GridItem(.adaptive(minimum: 240), spacing: 12)
]

private let livePathsColumns = [
    GridItem(.adaptive(minimum: 320), spacing: 16)
]
