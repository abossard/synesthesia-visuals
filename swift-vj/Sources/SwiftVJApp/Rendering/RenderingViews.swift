// RenderingViews.swift - SwiftUI views for VJ rendering preview
// Phase 6: Visual rendering system views

import SwiftUI
import Metal
import MetalKit

// MARK: - Render Preview View

/// Main view for rendering output preview
struct RenderPreviewView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var renderEngine: RenderEngine
    @State private var selectedTile: String = "shader"

    var body: some View {
        VStack(spacing: 0) {
            // Tile selector
            HStack(spacing: 12) {
                ForEach(["shader", "lyrics", "refrain", "songInfo", "image"], id: \.self) { tile in
                    Button {
                        selectedTile = tile
                    } label: {
                        Text(tile.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(selectedTile == tile ? .blue : .gray)
                }

                Spacer()

                // FPS indicator
                Text("\(Int(renderEngine.fps)) FPS")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            .padding()

            Divider()

            // Tile preview
            TilePreviewView(tileName: selectedTile, renderEngine: renderEngine)
                .aspectRatio(16/9, contentMode: .fit)
                .background(Color.black)
                .cornerRadius(8)
                .padding()

            Divider()

            // Audio visualization
            AudioVisualizerView(audioManager: renderEngine.audioManager)
                .frame(height: 60)
                .padding(.horizontal)

            Divider()

            // Controls
            RenderControlsView(renderEngine: renderEngine)
                .padding()
        }
    }
}

// MARK: - Tile Preview View

/// Metal-based preview of a single tile - displays actual rendered texture
struct TilePreviewView: View {
    let tileName: String
    @ObservedObject var renderEngine: RenderEngine
    @State private var previewImage: NSImage?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black
                
                // Actual texture preview
                if let image = previewImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
                
                // Status overlay
                VStack {
                    Text(tileName.capitalized)
                        .font(.headline)
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                    
                    if renderEngine.isRunning {
                        Text("Frame: \(renderEngine.frameCount)")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.white.opacity(0.7))
                    } else {
                        Text("Not Running")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .onAppear {
            startPreviewUpdates()
        }
        .onReceive(Timer.publish(every: 1.0/30.0, on: .main, in: .common).autoconnect()) { _ in
            updatePreview()
        }
    }
    
    private func startPreviewUpdates() {
        updatePreview()
    }
    
    private func updatePreview() {
        Task {
            guard let texture = renderEngine.getTexture(for: tileName) else { return }
            
            // Convert Metal texture to NSImage for display
            if let image = textureToNSImage(texture) {
                await MainActor.run {
                    self.previewImage = image
                }
            }
        }
    }
    
    /// Convert Metal texture to NSImage for SwiftUI display
    private func textureToNSImage(_ texture: MTLTexture) -> NSImage? {
        let width = texture.width
        let height = texture.height
        let bytesPerRow = width * 4
        
        // For private storage textures, we need to copy to a readable texture first
        var readableTexture: MTLTexture = texture
        
        if texture.storageMode == .private {
            // Create a managed texture to copy into
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: texture.pixelFormat,
                width: width,
                height: height,
                mipmapped: false
            )
            descriptor.storageMode = .managed
            descriptor.usage = .shaderRead
            
            let device = texture.device
            guard let managedTexture = device.makeTexture(descriptor: descriptor),
                  let commandQueue = device.makeCommandQueue(),
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
                return nil
            }
            
            // Copy from private to managed texture
            blitEncoder.copy(
                from: texture,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: width, height: height, depth: 1),
                to: managedTexture,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
            )
            blitEncoder.synchronize(resource: managedTexture)
            blitEncoder.endEncoding()
            
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            
            readableTexture = managedTexture
        }
        
        // Read texture data from the readable texture
        var imageBytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        readableTexture.getBytes(
            &imageBytes,
            bytesPerRow: bytesPerRow,
            from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                           size: MTLSize(width: width, height: height, depth: 1)),
            mipmapLevel: 0
        )
        
        // Create CGImage
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let context = CGContext(
            data: &imageBytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }
        
        guard let cgImage = context.makeImage() else { return nil }
        
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }
}

// MARK: - Audio Visualizer View

/// Displays audio levels as bar graph with speed debug info
struct AudioVisualizerView: View {
    @ObservedObject var audioManager: AudioStateManager
    
    private var audioState: AudioState { audioManager.state }

    // Compute approximate speed from audio state (same algorithm as tiles)
    private var estimatedSpeed: Float {
        let baseSpeedFloor: Float = 0.02
        let audioSpeedMax: Float = 1.20
        let bassBoostWeight: Float = 0.35
        
        guard audioState.level > 0.01 else { return baseSpeedFloor }
        
        let volumeDriver = audioState.level * (1.0 - bassBoostWeight) + audioState.bass * bassBoostWeight
        let targetSpeed = baseSpeedFloor + min(max(volumeDriver, 0), 1) * (audioSpeedMax - baseSpeedFloor)
        return targetSpeed
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 4) {
                // Audio bands
                AudioBar(label: "BASS", value: audioState.bass, color: .red)
                AudioBar(label: "LOW", value: audioState.lowMid, color: .orange)
                AudioBar(label: "MID", value: audioState.mid, color: .yellow)
                AudioBar(label: "HIGH", value: audioState.highs, color: .green)
                AudioBar(label: "LVL", value: audioState.level, color: .blue)

                Divider()
                    .frame(width: 1)
                    .background(Color.gray.opacity(0.3))
                    .padding(.horizontal, 4)

                // Beat/energy
                AudioBar(label: "KICK", value: audioState.kickEnv, color: .purple)
                AudioBar(label: "E-F", value: audioState.energyFast, color: .pink)
                AudioBar(label: "E-S", value: audioState.energySlow, color: .cyan)
                
                Divider()
                    .frame(width: 1)
                    .background(Color.gray.opacity(0.3))
                    .padding(.horizontal, 4)
                
                // Speed indicator (0.02-1.20 range normalized to 0-1)
                AudioBar(label: "SPD", value: (estimatedSpeed - 0.02) / 1.18, color: .white)
                
                // Speed numeric display
                VStack(spacing: 2) {
                    Text(String(format: "%.2f", estimatedSpeed))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(estimatedSpeed > 0.1 ? .green : .red)
                    Text("SPD")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .frame(width: 35)
                
                Divider()
                    .frame(width: 1)
                    .background(Color.gray.opacity(0.3))
                    .padding(.horizontal, 4)
                
                // OSC message rate display
                VStack(spacing: 2) {
                    Text("\(audioManager.oscMessageRate)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(audioManager.oscIsActive ? .green : .red)
                    Text("MSG/S")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .frame(width: 45)
            }
            .padding(.horizontal, 8)
        }
    }
}

struct AudioBar: View {
    let label: String
    let value: Float
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    // Background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))

                    // Value bar
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(height: geometry.size.height * CGFloat(min(max(value, 0), 1)))
                }
            }

            Text(label)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Render Controls View

/// Controls for the render engine
struct RenderControlsView: View {
    @ObservedObject var renderEngine: RenderEngine

    var body: some View {
        HStack(spacing: 16) {
            // Start/Stop button
            Button {
                Task {
                    if renderEngine.isRunning {
                        await renderEngine.stop()
                    } else {
                        try? await renderEngine.start()
                    }
                }
            } label: {
                Label(
                    renderEngine.isRunning ? "Stop Rendering" : "Start Rendering",
                    systemImage: renderEngine.isRunning ? "stop.fill" : "play.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(renderEngine.isRunning ? .red : .green)

            Spacer()

            // Shader controls
            if renderEngine.isRunning {
                HStack(spacing: 8) {
                    Button {
                        renderEngine.shaderManager.prevShader()
                    } label: {
                        Image(systemName: "chevron.left")
                    }

                    Text(renderEngine.shaderManager.state.current?.name ?? "No Shader")
                        .font(.caption)
                        .frame(minWidth: 100)

                    Button {
                        renderEngine.shaderManager.nextShader()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                }
            }
        }
    }
}

// MARK: - Rendering Tab View

/// Full rendering tab for the sidebar - ALL tiles use MTKView for 60fps
struct RenderingView: View {
    @EnvironmentObject var appState: AppState
    @State private var useDirectMTKView: Bool = true
    @State private var frameCount: Int = 0
    @State private var audioTime: Float = 0
    @State private var selectedShader: String = "3isacrowd"
    @State private var selectedMaskShader: String = "BWcarbonlattice"  // Independent mask shader
    @State private var selectedTile: String = "shader"
    
    // Demo text state for preview (shown until real data arrives)
    @State private var demoLyrics: LyricsDisplayState = LyricsDisplayState(
        lines: [
            LyricLine(id: 0, timeSec: 0, text: "♪ Previous line fades away"),
            LyricLine(id: 1, timeSec: 1, text: "Current line is bright and clear"),
            LyricLine(id: 2, timeSec: 2, text: "Next line waits in shadow ♪")
        ],
        activeIndex: 1, textOpacity: 255, fadeDelayMs: 5000, fadeDurationMs: 1000, lastChangeTime: Date()
    )
    @State private var demoRefrain = RefrainDisplayState(text: "♪ This is the chorus! ♪", opacity: 255, active: true, lastChangeTime: Date())
    @State private var demoSongInfo = SongInfoDisplayState(artist: "SwiftVJ", title: "Ready for music...", album: "Waiting for track", opacity: 255, displayTime: 0, active: true, lastChangeTime: Date())

    // Use appState.renderEngine (receives OSC updates) instead of local instance
    private var renderEngine: RenderEngine? { appState.renderEngine }
    private var audioState: AudioState { appState.renderEngine?.audioManager.state ?? .silent }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Audio visualization (top for visibility)
                if let audioManager = renderEngine?.audioManager {
                    GroupBox("Audio Levels") {
                        AudioVisualizerView(audioManager: audioManager)
                            .frame(height: 70)
                    }
                }
                
                // MTKView-based tiles (60fps Direct Metal)
                mtkViewTiles

                // Shader browser
                if let shaderManager = renderEngine?.shaderManager {
                    GroupBox("Shader Library") {
                        ShaderListView(shaderManager: shaderManager)
                    }
                }

                // Text controls
                GroupBox("Text Controls") {
                    textControlsView
                }
            }
            .padding()
        }
        .onAppear {
            Task { try? await renderEngine?.start() }
        }
        // NOTE: Removed onDisappear stop() - render engine should keep running
        // when switching tabs. It only stops when app quits.
        
        // Sync shader selection to state managers for HeadlessRenderer
        .onChange(of: selectedShader) { _, newValue in
            renderEngine?.shaderManager.selectShader(name: newValue)
        }
        .onChange(of: selectedMaskShader) { _, newValue in
            renderEngine?.maskManager.selectMask(name: newValue)
        }
    }
    
    // MARK: - MTKView Tiles Grid
    
    @ViewBuilder
    private var mtkViewTiles: some View {
        VStack(spacing: 16) {
            // Tile selector tabs
            HStack(spacing: 12) {
                ForEach(["shader", "mask", "lyrics", "refrain", "songInfo"], id: \.self) { tile in
                    Button {
                        selectedTile = tile
                    } label: {
                        Text(tile.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(selectedTile == tile ? .blue : .gray)
                }
                
                Spacer()
                
                // Stats
                Text("Frame: \(frameCount)")
                    .font(.caption.monospacedDigit())
                Text("Time: \(String(format: "%.1f", audioTime))s")
                    .font(.caption.monospacedDigit())
            }
            .padding(.horizontal)
            
            // Main tile preview - only render the selected tile
            GroupBox(selectedTile.capitalized) {
                selectedTileView
                    .aspectRatio(16/9, contentMode: .fit)
                    .frame(minHeight: 360)
                    .background(Color.black)
                    .cornerRadius(8)
            }
            
            // Shader selector (when shader or mask tile selected)
            if selectedTile == "shader" {
                shaderControlsView(title: "Shader", binding: $selectedShader)
            }
            if selectedTile == "mask" {
                shaderControlsView(title: "Mask", binding: $selectedMaskShader)
            }
            
            // Tile selector grid with Syphon client previews
            GroupBox("Tiles → Syphon") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(["Shader", "Mask", "Lyrics", "Refrain", "SongInfo"], id: \.self) { tile in
                        VStack(spacing: 4) {
                            SyphonThumbnailView(serverName: tile)
                                .aspectRatio(16/9, contentMode: .fit)
                                .frame(height: 60)
                                .cornerRadius(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(selectedTile == tile.lowercased() ? Color.blue : Color.clear, lineWidth: 2)
                                )
                                .onTapGesture { selectedTile = tile.lowercased() }
                            
                            Text(tile).font(.caption2)
                        }
                    }
                }
                .padding()
            }
        }
    }
    
    // MARK: - Selected Tile View (Syphon client - headless rendering only)
    
    @ViewBuilder
    private var selectedTileView: some View {
        // All rendering is done headlessly by HeadlessRenderer
        // UI only displays Syphon client previews
        // Server names are simple: "Shader", "Mask", "Lyrics", etc.
        SyphonThumbnailView(serverName: selectedTile.capitalized)
            .id(selectedTile)  // Force view recreation when tile changes
    }
    
    // MARK: - Tile Colors (for thumbnail grid)
    
    private func tileColor(for tile: String) -> Color {
        switch tile {
        case "shader": return Color.purple.opacity(0.6)
        case "mask": return Color.orange.opacity(0.6)
        case "lyrics": return Color.blue.opacity(0.6)
        case "refrain": return Color.green.opacity(0.6)
        case "songInfo": return Color.cyan.opacity(0.6)
        default: return Color.gray.opacity(0.6)
        }
    }
    
    // MARK: - Shader Controls (reusable for Shader and Mask)
    
    @ViewBuilder
    private func shaderControlsView(title: String, binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(title):")
                
                Button {
                    guard let shaders = renderEngine?.shaderManager.availableShaders else { return }
                    if let current = shaders.firstIndex(where: { $0.name == binding.wrappedValue }) {
                        let prev = (current - 1 + shaders.count) % shaders.count
                        binding.wrappedValue = shaders[prev].name
                    }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)
                
                Text(binding.wrappedValue)
                    .font(.caption.monospaced())
                    .frame(minWidth: 150)
                    .padding(.horizontal, 8)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
                
                Button {
                    guard let shaders = renderEngine?.shaderManager.availableShaders else { return }
                    if let current = shaders.firstIndex(where: { $0.name == binding.wrappedValue }) {
                        let next = (current + 1) % shaders.count
                        binding.wrappedValue = shaders[next].name
                    }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)
                
                Button("Random") {
                    guard let shaders = renderEngine?.shaderManager.availableShaders else { return }
                    if !shaders.isEmpty {
                        binding.wrappedValue = shaders.randomElement()?.name ?? binding.wrappedValue
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Text Controls
    
    @ViewBuilder
    private var textControlsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Lyrics controls
            HStack {
                Text("Lyrics line:")
                Button("Prev") {
                    let newIndex = max(0, demoLyrics.activeIndex - 1)
                    demoLyrics = LyricsDisplayState(
                        lines: demoLyrics.lines,
                        activeIndex: newIndex,
                        textOpacity: 255,
                        fadeDelayMs: 5000, fadeDurationMs: 1000, lastChangeTime: Date()
                    )
                }
                Button("Next") {
                    let newIndex = min(demoLyrics.lines.count - 1, demoLyrics.activeIndex + 1)
                    demoLyrics = LyricsDisplayState(
                        lines: demoLyrics.lines,
                        activeIndex: newIndex,
                        textOpacity: 255,
                        fadeDelayMs: 5000, fadeDurationMs: 1000, lastChangeTime: Date()
                    )
                }
                Text("(\(demoLyrics.activeIndex + 1)/\(demoLyrics.lines.count))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Refrain toggle
            HStack {
                Text("Refrain:")
                Toggle("Active", isOn: Binding(
                    get: { demoRefrain.active },
                    set: { active in
                        demoRefrain = RefrainDisplayState(
                            text: demoRefrain.text,
                            opacity: active ? 255 : 0,
                            active: active,
                            lastChangeTime: Date()
                        )
                    }
                ))
            }
            
            // Song info toggle
            HStack {
                Text("Song Info:")
                Toggle("Active", isOn: Binding(
                    get: { demoSongInfo.active },
                    set: { active in
                        demoSongInfo = SongInfoDisplayState(
                            artist: demoSongInfo.artist,
                            title: demoSongInfo.title,
                            album: demoSongInfo.album,
                            opacity: active ? 255 : 0,
                            displayTime: 0,
                            active: active,
                            lastChangeTime: Date()
                        )
                    }
                ))
            }
        }
        .padding()
    }
}

// MARK: - Shader List View

struct ShaderListView: View {
    @ObservedObject var shaderManager: ShaderStateManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Navigation buttons
                Button {
                    shaderManager.prevShader()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)
                .disabled(shaderManager.availableShaders.isEmpty)
                
                Button {
                    shaderManager.nextShader()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)
                .disabled(shaderManager.availableShaders.isEmpty)
                
                Text("\(shaderManager.currentIndex + 1)/\(shaderManager.availableShaders.count)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                    .frame(width: 60)

                Spacer()

                Button("Load Directory") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false

                    if panel.runModal() == .OK, let url = panel.url {
                        shaderManager.loadShaderDirectory(url)
                    }
                }
                .font(.caption)
            }

            if !shaderManager.availableShaders.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(shaderManager.availableShaders) { shader in
                            ShaderChip(
                                name: shader.name,
                                isSelected: shaderManager.state.current?.name == shader.name
                            ) {
                                shaderManager.selectShader(name: shader.name)
                            }
                        }
                    }
                }
            } else {
                Text("No shaders loaded")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
        .padding()
    }
}

struct ShaderChip: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Text State View

struct TextStateView: View {
    @ObservedObject var textManager: TextStateManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Song info
            HStack {
                Text("Song:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(songInfoText)
                    .font(.caption)
            }

            // Lyrics
            HStack {
                Text("Lyrics:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(lyricsText)
                    .font(.caption)
                    .lineLimit(1)
            }

            // Refrain
            HStack {
                Text("Refrain:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(textManager.refrainState.text.isEmpty ? "-" : textManager.refrainState.text)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    private var songInfoText: String {
        let state = textManager.songInfoState
        if state.artist.isEmpty && state.title.isEmpty {
            return "-"
        }
        if !state.artist.isEmpty && !state.title.isEmpty {
            return "\(state.artist) - \(state.title)"
        }
        return state.artist.isEmpty ? state.title : state.artist
    }

    private var lyricsText: String {
        let state = textManager.lyricsState
        guard state.activeIndex >= 0 else { return "-" }
        return state.currentLine ?? "-"
    }
}

// MARK: - Preview

#Preview {
    RenderingView()
        .environmentObject(AppState())
        .frame(width: 800, height: 900)
}
