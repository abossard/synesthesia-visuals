import SwiftUI
import SwiftVJCore
import AppKit
import UniformTypeIdentifiers

private enum PlaylistDropPayload {
    static let shaderNamePrefix = "shader-name:"
    static let maskNamePrefix = "mask-name:"
    static let shaderIndexPrefix = "shader-index:"
    static let maskIndexPrefix = "mask-index:"

    static func shaderName(_ value: String) -> String { shaderNamePrefix + value }
    static func maskName(_ value: String) -> String { maskNamePrefix + value }
    static func shaderIndex(_ value: Int) -> String { shaderIndexPrefix + String(value) }
    static func maskIndex(_ value: Int) -> String { maskIndexPrefix + String(value) }

    static func parseShaderName(_ value: String) -> String? {
        guard value.hasPrefix(shaderNamePrefix) else { return nil }
        return String(value.dropFirst(shaderNamePrefix.count))
    }

    static func parseMaskName(_ value: String) -> String? {
        guard value.hasPrefix(maskNamePrefix) else { return nil }
        return String(value.dropFirst(maskNamePrefix.count))
    }

    static func parseShaderIndex(_ value: String) -> Int? {
        guard value.hasPrefix(shaderIndexPrefix) else { return nil }
        return Int(value.dropFirst(shaderIndexPrefix.count))
    }

    static func parseMaskIndex(_ value: String) -> Int? {
        guard value.hasPrefix(maskIndexPrefix) else { return nil }
        return Int(value.dropFirst(maskIndexPrefix.count))
    }
}

struct PerformanceView: View {
    @EnvironmentObject var appState: AppState
    @State private var shaderToAdd: String = ""
    @State private var maskToAdd: String = ""
    @State private var shaderDropTargeted = false
    @State private var maskDropTargeted = false

    private var activePhase: Phase? {
        appState.effectivePhase
    }

    private var regularShaders: [ShaderInfo] {
        appState.renderEngine?.shaderRepository.regularShaders ?? []
    }

    private var maskShaders: [ShaderInfo] {
        appState.renderEngine?.shaderRepository.masks ?? []
    }

    private var shaderByName: [String: ShaderInfo] {
        Dictionary(regularShaders.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var maskByName: [String: ShaderInfo] {
        Dictionary(maskShaders.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var availableShaderNames: [String] {
        regularShaders.map(\.name).sorted()
    }

    private var availableMaskNames: [String] {
        maskShaders.map(\.name).sorted()
    }

    private var playlistGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 12, alignment: .top)]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                phaseBar
                if let phase = activePhase {
                    HStack(alignment: .top, spacing: 12) {
                        shaderPlaylistSection(phase: phase)
                        maskPlaylistSection(phase: phase)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    phaseMissingHint
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { syncAddSelections() }
        .onChange(of: availableShaderNames) { _, _ in syncAddSelections() }
        .onChange(of: availableMaskNames) { _, _ in syncAddSelections() }
    }

    private var header: some View {
        HStack {
            if let track = appState.currentTrack {
                Image(systemName: "music.note")
                    .foregroundColor(.blue)
                Text("\(track.artist) - \(track.title)")
                    .font(.headline)
            } else {
                Text("No active track")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let result = appState.pipelineResult {
                Text("Pipeline \(result.totalTimeMs)ms")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary)
                    .cornerRadius(6)
            }
        }
        .padding()
    }

    private var phaseBar: some View {
        GroupBox("Performance") {
            HStack(spacing: 12) {
                Label("Phase", systemImage: "waveform.path.ecg")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(activePhase?.displayName ?? "None")
                    .font(.headline)
                Spacer()
                Toggle("Shader Auto Next", isOn: Binding(
                    get: { appState.shaderAutoAdvanceOnSongChange },
                    set: { appState.setShaderAutoAdvanceOnSongChange($0) }
                ))
                .toggleStyle(.switch)
                Toggle("Mask Auto Next", isOn: Binding(
                    get: { appState.maskAutoAdvanceOnSongChange },
                    set: { appState.setMaskAutoAdvanceOnSongChange($0) }
                ))
                .toggleStyle(.switch)
            }
        }
    }

    private var phaseMissingHint: some View {
        GroupBox("Performance Playlists") {
            Text("Select a DJ phase in the toolbar to edit and run phase playlists.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func shaderPlaylistSection(phase: Phase) -> some View {
        let playlist = appState.shaderPlaylist(for: phase)
        let currentIndex = appState.shaderPlaylistCurrentIndex(for: phase)

        return GroupBox("Shaders • \(phase.displayName)") {
            VStack(alignment: .leading, spacing: 8) {
                if let ai = appState.aiSuggestedShaderName, !ai.isEmpty {
                    aiSuggestionCard(name: ai, phase: phase)
                }

                HStack(spacing: 8) {
                    Picker("Add Shader", selection: $shaderToAdd) {
                        ForEach(availableShaderNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                    Button("Add") {
                        guard !shaderToAdd.isEmpty else { return }
                        appState.addShaderToPhasePlaylist(phase: phase, shaderName: shaderToAdd, activate: false)
                    }
                    .buttonStyle(.bordered)
                }

                ScrollView {
                    LazyVGrid(columns: playlistGridColumns, spacing: 12) {
                        if playlist.isEmpty {
                            emptyStateCard("No shaders in this phase playlist yet.")
                        } else {
                            ForEach(Array(playlist.enumerated()), id: \.offset) { entry in
                                shaderPlaylistCard(
                                    phase: phase,
                                    index: entry.offset,
                                    name: entry.element,
                                    isActive: currentIndex == entry.offset
                                )
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .onDrop(of: [UTType.plainText.identifier], isTargeted: $shaderDropTargeted) { providers in
                    handleShaderDrop(providers, phase: phase, destinationIndex: nil)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(shaderDropTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func maskPlaylistSection(phase: Phase) -> some View {
        let playlist = appState.maskPlaylist(for: phase)
        let currentIndex = appState.maskPlaylistCurrentIndex(for: phase)

        return GroupBox("Masks • \(phase.displayName)") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Picker("Add Mask", selection: $maskToAdd) {
                        ForEach(availableMaskNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                    Button("Add") {
                        guard !maskToAdd.isEmpty else { return }
                        appState.addMaskToPhasePlaylist(phase: phase, maskName: maskToAdd, activate: false)
                    }
                    .buttonStyle(.bordered)
                }

                ScrollView {
                    LazyVGrid(columns: playlistGridColumns, spacing: 12) {
                        if playlist.isEmpty {
                            emptyStateCard("No masks in this phase playlist yet.")
                        } else {
                            ForEach(Array(playlist.enumerated()), id: \.offset) { entry in
                                maskPlaylistCard(
                                    phase: phase,
                                    index: entry.offset,
                                    name: entry.element,
                                    isActive: currentIndex == entry.offset
                                )
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .onDrop(of: [UTType.plainText.identifier], isTargeted: $maskDropTargeted) { providers in
                    handleMaskDrop(providers, phase: phase, destinationIndex: nil)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(maskDropTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func shaderPlaylistCard(
        phase: Phase,
        index: Int,
        name: String,
        isActive: Bool
    ) -> some View {
        let shader = shaderByName[name]
        return VStack(alignment: .leading, spacing: 8) {
            PlaylistThumbnailView(shader: shader, fallbackName: name, width: nil, height: 126)
            HStack(alignment: .top) {
                Text(name)
                    .font(.caption.monospaced())
                    .lineLimit(2)
                Spacer()
                if isActive {
                    Text("Active")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                }
            }
            HStack(spacing: 8) {
                Button("Activate") {
                    appState.activateShaderInPhasePlaylist(phase: phase, index: index)
                }
                .buttonStyle(.bordered)
                Button(role: .destructive) {
                    appState.removeShaderFromPhasePlaylist(phase: phase, index: index)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                Spacer()
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding(10)
        .background(isActive ? Color.accentColor.opacity(0.16) : Color(.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isActive ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isActive ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            appState.activateShaderInPhasePlaylist(phase: phase, index: index)
        }
        .onDrag {
            NSItemProvider(object: PlaylistDropPayload.shaderIndex(index) as NSString)
        }
        .onDrop(of: [UTType.plainText.identifier], isTargeted: nil) { providers in
            handleShaderDrop(providers, phase: phase, destinationIndex: index)
        }
    }

    private func maskPlaylistCard(
        phase: Phase,
        index: Int,
        name: String,
        isActive: Bool
    ) -> some View {
        let shader = maskByName[name]
        return VStack(alignment: .leading, spacing: 8) {
            PlaylistThumbnailView(shader: shader, fallbackName: name, width: nil, height: 126)
            HStack(alignment: .top) {
                Text(name)
                    .font(.caption.monospaced())
                    .lineLimit(2)
                Spacer()
                if isActive {
                    Text("Active")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                }
            }
            HStack(spacing: 8) {
                Button("Activate") {
                    appState.activateMaskInPhasePlaylist(phase: phase, index: index)
                }
                .buttonStyle(.bordered)
                Button(role: .destructive) {
                    appState.removeMaskFromPhasePlaylist(phase: phase, index: index)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                Spacer()
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding(10)
        .background(isActive ? Color.accentColor.opacity(0.16) : Color(.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isActive ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isActive ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            appState.activateMaskInPhasePlaylist(phase: phase, index: index)
        }
        .onDrag {
            NSItemProvider(object: PlaylistDropPayload.maskIndex(index) as NSString)
        }
        .onDrop(of: [UTType.plainText.identifier], isTargeted: nil) { providers in
            handleMaskDrop(providers, phase: phase, destinationIndex: index)
        }
    }

    private func aiSuggestionCard(name: String, phase: Phase) -> some View {
        HStack(spacing: 10) {
            PlaylistThumbnailView(shader: shaderByName[name], fallbackName: name, width: 220, height: 124)
            VStack(alignment: .leading, spacing: 6) {
                Text("AI selection")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(name)
                    .font(.headline)
                    .lineLimit(2)
                if let aiPhase = appState.aiSuggestedShaderPhase {
                    Text("Detected phase: \(aiPhase.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(spacing: 6) {
                Button("Add + Activate") {
                    appState.addShaderToPhasePlaylist(phase: phase, shaderName: name, activate: true)
                }
                .buttonStyle(.borderedProminent)
                Text("Drag into playlist")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.quaternary)
        .cornerRadius(10)
        .onDrag {
            NSItemProvider(object: PlaylistDropPayload.shaderName(name) as NSString)
        }
        .help("Drag this AI shader into the playlist or use Add + Activate.")
    }

    private func emptyStateCard(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
            .background(.quaternary)
            .cornerRadius(8)
    }

    private func syncAddSelections() {
        if !availableShaderNames.contains(shaderToAdd) {
            shaderToAdd = availableShaderNames.first ?? ""
        }
        if !availableMaskNames.contains(maskToAdd) {
            maskToAdd = availableMaskNames.first ?? ""
        }
    }

    private func handleShaderDrop(
        _ providers: [NSItemProvider],
        phase: Phase,
        destinationIndex: Int?
    ) -> Bool {
        readDropText(from: providers) { value in
            Task { @MainActor in
                if PlaylistDropPayload.parseMaskIndex(value) != nil || PlaylistDropPayload.parseMaskName(value) != nil {
                    return
                }

                if let sourceIndex = PlaylistDropPayload.parseShaderIndex(value) {
                    guard let destinationIndex else { return }
                    guard sourceIndex != destinationIndex else { return }
                    let toOffset = destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex
                    appState.moveShaderInPhasePlaylist(
                        phase: phase,
                        fromOffsets: IndexSet(integer: sourceIndex),
                        toOffset: toOffset
                    )
                    return
                }

                let shaderName = PlaylistDropPayload.parseShaderName(value) ?? value
                guard !shaderName.isEmpty else { return }
                appState.addShaderToPhasePlaylist(phase: phase, shaderName: shaderName, activate: false)
            }
        }
    }

    private func handleMaskDrop(
        _ providers: [NSItemProvider],
        phase: Phase,
        destinationIndex: Int?
    ) -> Bool {
        readDropText(from: providers) { value in
            Task { @MainActor in
                if PlaylistDropPayload.parseShaderIndex(value) != nil || PlaylistDropPayload.parseShaderName(value) != nil {
                    return
                }

                if let sourceIndex = PlaylistDropPayload.parseMaskIndex(value) {
                    guard let destinationIndex else { return }
                    guard sourceIndex != destinationIndex else { return }
                    let toOffset = destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex
                    appState.moveMaskInPhasePlaylist(
                        phase: phase,
                        fromOffsets: IndexSet(integer: sourceIndex),
                        toOffset: toOffset
                    )
                    return
                }

                let maskName = PlaylistDropPayload.parseMaskName(value) ?? value
                guard !maskName.isEmpty else { return }
                appState.addMaskToPhasePlaylist(phase: phase, maskName: maskName, activate: false)
            }
        }
    }

    private func readDropText(from providers: [NSItemProvider], perform: @escaping (String) -> Void) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
            return false
        }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let value = object as? String else { return }
            perform(value)
        }
        return true
    }
}

private struct PlaylistThumbnailView: View {
    let shader: ShaderInfo?
    let fallbackName: String
    let width: CGFloat?
    let height: CGFloat
    @State private var image: NSImage?

    var body: some View {
        if let width {
            previewContent
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onAppear(perform: loadImage)
                .onChange(of: shader?.path) { _, _ in loadImage() }
                .help(fallbackName)
        } else {
            previewContent
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onAppear(perform: loadImage)
                .onChange(of: shader?.path) { _, _ in loadImage() }
                .help(fallbackName)
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    )
            }
        }
    }

    private func loadImage() {
        guard let shader else {
            image = nil
            return
        }
        let shaderURL = URL(fileURLWithPath: shader.path)
        let shaderDir = shaderURL.deletingLastPathComponent()
        let baseName = shaderURL.deletingPathExtension().lastPathComponent
        let candidates = [
            shaderDir.appendingPathComponent("\(baseName).png"),
            shaderDir.appendingPathComponent("screenshot.png"),
            shaderDir.appendingPathComponent("preview.png")
        ]
        guard let screenshotURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let data = try? Data(contentsOf: screenshotURL),
              let loaded = NSImage(data: data) else {
            image = nil
            return
        }
        image = loaded
    }
}
