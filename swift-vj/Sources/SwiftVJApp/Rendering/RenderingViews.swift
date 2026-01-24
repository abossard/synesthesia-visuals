// RenderingViews.swift - SwiftUI views for VJ rendering preview
// Phase 6: Visual rendering system views

import SwiftUI
import Metal
import MetalKit
import SwiftVJCore

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
        // Reduced to 1Hz - preview is just for debug, reduces main thread load
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
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

/// Controls for the render engine (always running)
struct RenderControlsView: View {
    @ObservedObject var renderEngine: RenderEngine
    @State private var showAnimationSettings: Bool = false

    var body: some View {
        HStack(spacing: 16) {
            // Status indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(renderEngine.isRunning ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(renderEngine.isRunning ? "Rendering" : "Starting...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Text Animation Mode Picker
            Picker("Text FX", selection: $renderEngine.textManager.animationMode) {
                ForEach(TextAnimationMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)
            .help(renderEngine.textManager.animationMode.description)
            
            // Animation Settings Button
            Button {
                showAnimationSettings.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .help("Animation Test Controls")
            .popover(isPresented: $showAnimationSettings, arrowEdge: .bottom) {
                TextAnimationTestPanel(textManager: renderEngine.textManager)
                    .frame(width: 320)
                    .padding()
            }

            Spacer()

            // Shader controls
            if renderEngine.isRunning {
                HStack(spacing: 8) {
                    Button {
                        renderEngine.shaderSelection.prevMain()
                    } label: {
                        Image(systemName: "chevron.left")
                    }

                    Text(renderEngine.shaderSelection.mainState.current?.name ?? "No Shader")
                        .font(.caption)
                        .frame(minWidth: 100)

                    Button {
                        renderEngine.shaderSelection.nextMain()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                }
            }
        }
    }
}

// MARK: - Text Animation Test Panel

/// Panel for testing and parameterizing glyph animations
struct TextAnimationTestPanel: View {
    @ObservedObject var textManager: TextStateManager
    @State private var testText: String = "Hello World!"
    @State private var isAnimating: Bool = false
    @State private var animationTimer: Timer?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("Text Animation Test")
                .font(.headline)
            
            Divider()
            
            // Animation Mode
            VStack(alignment: .leading, spacing: 4) {
                Text("Animation Mode")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("Mode", selection: $textManager.animationMode) {
                    ForEach(TextAnimationMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                
                Text(textManager.animationMode.description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Transition Progress Slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Transition Progress")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.2f", textManager.transitionProgress))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                
                Slider(value: $textManager.transitionProgress, in: 0...1)
                
                HStack {
                    Text("0 = Start")
                        .font(.caption2)
                    Spacer()
                    Text("1 = Complete")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }
            
            // Beat Intensity Slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Beat Intensity")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.2f", textManager.beatIntensity))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                
                Slider(value: $textManager.beatIntensity, in: 0...1)
                
                Text("Used by Glow Pulse and beat-synced effects")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Test Text Input
            VStack(alignment: .leading, spacing: 4) {
                Text("Test Lyrics")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextField("Enter test text...", text: $testText)
                    .textFieldStyle(.roundedBorder)
                
                Button("Apply Test Lyrics") {
                    applyTestLyrics()
                }
                .buttonStyle(.borderedProminent)
            }
            
            Divider()
            
            // Animation Controls
            HStack(spacing: 12) {
                Button {
                    toggleAnimation()
                } label: {
                    Label(isAnimating ? "Stop" : "Animate", 
                          systemImage: isAnimating ? "stop.fill" : "play.fill")
                }
                .buttonStyle(.bordered)
                
                Button("Reset") {
                    textManager.transitionProgress = 0
                    textManager.beatIntensity = 0
                }
                .buttonStyle(.bordered)
                
                Button("Beat!") {
                    simulateBeat()
                }
                .buttonStyle(.bordered)
            }
            
            // Quick Presets
            VStack(alignment: .leading, spacing: 4) {
                Text("Quick Presets")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    Button("Karaoke") {
                        textManager.animationMode = .waveDissolve
                        applyTestLyrics()
                        startAnimation()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button("EDM Drop") {
                        textManager.animationMode = .blurPop
                        textManager.beatIntensity = 1.0
                        applyTestLyrics()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button("Typewriter") {
                        textManager.animationMode = .typewriter
                        textManager.transitionProgress = 0
                        applyTestLyrics()
                        startAnimation()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .onDisappear {
            stopAnimation()
        }
    }
    
    private func applyTestLyrics() {
        // Create test lyrics with 3 lines
        let lines = [
            DisplayLyricLine(timeSec: 0, text: "Previous line faded"),
            DisplayLyricLine(timeSec: 1, text: testText),
            DisplayLyricLine(timeSec: 2, text: "Next line preview")
        ]
        textManager.setLyrics(lines)
        textManager.setActiveLine(1)  // Make middle line active
    }
    
    private func toggleAnimation() {
        if isAnimating {
            stopAnimation()
        } else {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        isAnimating = true
        textManager.transitionProgress = 0
        
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1/60, repeats: true) { _ in
            Task { @MainActor in
                textManager.transitionProgress += 0.01
                if textManager.transitionProgress >= 1.0 {
                    textManager.transitionProgress = 0
                }
            }
        }
    }
    
    private func stopAnimation() {
        isAnimating = false
        animationTimer?.invalidate()
        animationTimer = nil
    }
    
    private func simulateBeat() {
        textManager.beatIntensity = 1.0
        
        // Decay beat intensity over 0.5 seconds
        Timer.scheduledTimer(withTimeInterval: 1/60, repeats: true) { timer in
            Task { @MainActor in
                textManager.beatIntensity *= 0.92
                if textManager.beatIntensity < 0.01 {
                    textManager.beatIntensity = 0
                    timer.invalidate()
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
    // Shader selection now goes through AppState (single source of truth)
    @AppStorage("lastSelectedMaskShader") private var selectedMaskShader: String = "BWcarbonlattice"
    @State private var selectedTile: String = "shader"

    private let tileKeys: [String] = ["shader", "mask", "lyrics", "refrain", "songInfo", "image"]

    private func displayName(for key: String) -> String {
        switch key {
        case "songInfo": return "Song Info"
        case "mask": return "Mask"
        default: return key.capitalized
        }
    }

    private func serverName(for key: String) -> String {
        switch key {
        case "songInfo": return "SongInfo"
        case "mask": return "Mask"
        case "lyrics": return "Lyrics"
        case "refrain": return "Refrain"
        case "image": return "Image"
        case "shader": return "Shader"
        default: return key.capitalized
        }
    }

    /// Binding to appState.selectedShader for UI controls
    private var selectedShaderBinding: Binding<String> {
        Binding(
            get: { appState.selectedShader ?? "3isacrowd" },
            set: { newValue in
                appState.selectShader(newValue)
            }
        )
    }
    
    // Demo text state for preview (shown until real data arrives)
    @AppStorage("useDemoText") private var useDemoText: Bool = false

    @State private var demoLyrics: LyricsDisplayState = LyricsDisplayState(
        lines: [
            DisplayLyricLine(id: 0, timeSec: 0, text: "♪ Previous line fades away"),
            DisplayLyricLine(id: 1, timeSec: 1, text: "Current line is bright and clear"),
            DisplayLyricLine(id: 2, timeSec: 2, text: "Next line waits in shadow ♪")
        ],
        activeIndex: 1, textOpacity: 255, fadeDelayMs: 5000, fadeDurationMs: 1000, lastChangeTime: Date()
    )
    @State private var demoRefrain = RefrainDisplayState(text: "♪ This is the chorus! ♪", opacity: 255, active: true, lastChangeTime: Date())
    @State private var demoSongInfo = SongInfoDisplayState(artist: "SwiftVJ", title: "Ready for music...", album: "Waiting for track", opacity: 255, displayTime: 0, active: true, lastChangeTime: Date(), stayVisible: true)

    // Derived demo text editors
    @State private var demoLyricsText: String = "♪ Previous line fades away\nCurrent line is bright and clear\nNext line waits in shadow ♪"
    @State private var demoRefrainText: String = "♪ This is the chorus! ♪"
    @State private var demoArtist: String = "SwiftVJ"
    @State private var demoTitle: String = "Ready for music..."
    @State private var demoAlbum: String = "Waiting for track"

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

                // Shader browser (using repository for data, selection for state)
                if let repository = renderEngine?.shaderRepository,
                   let selection = renderEngine?.shaderSelection {
                    GroupBox("Shader Library") {
                        ShaderListView(repository: repository, selection: selection)
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
            // Mask uses selection manager
            renderEngine?.shaderSelection.selectMask(name: selectedMaskShader)
            // Shader is handled by AppState (single source of truth)
            if useDemoText { applyDemoText() }
        }
        // NOTE: Removed onDisappear stop() - render engine should keep running
        // when switching tabs. It only stops when app quits.
        .onChange(of: selectedMaskShader) { _, newValue in
            renderEngine?.shaderSelection.selectMask(name: newValue)
        }
    }
    
    // MARK: - MTKView Tiles Grid
    
    @ViewBuilder
    private var mtkViewTiles: some View {
        VStack(spacing: 16) {
            // Tile selector tabs
            HStack(spacing: 12) {
                ForEach(tileKeys, id: \.self) { tile in
                    Button {
                        selectedTile = tile
                    } label: {
                        Text(displayName(for: tile))
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
            GroupBox(displayName(for: selectedTile)) {
                selectedTileView
                    .aspectRatio(16/9, contentMode: .fit)
                    .frame(minHeight: 360)
                    .background(Color.black)
                    .cornerRadius(8)
            }
            
            // Shader selector (when shader or mask tile selected)
            if selectedTile == "shader" {
                shaderControlsView(title: "Shader", binding: selectedShaderBinding)
            }
            if selectedTile == "mask" {
                shaderControlsView(title: "Mask", binding: $selectedMaskShader)
            }
            
            // Image controls (when image tile selected)
            if selectedTile == "image" {
                imageControlsView
            }
            
            // Tile selector grid with Syphon client previews (60fps MTKView)
            GroupBox("Tiles → Syphon") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(tileKeys, id: \.self) { tileKey in
                        let server = serverName(for: tileKey)
                        VStack(spacing: 4) {
                            SyphonMTKView(serverName: server)
                                .aspectRatio(16/9, contentMode: .fit)
                                .frame(height: 60)
                                .cornerRadius(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(selectedTile == tileKey ? Color.blue : Color.clear, lineWidth: 2)
                                )
                                .onTapGesture { selectedTile = tileKey }

                            Text(displayName(for: tileKey)).font(.caption2)
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
        // UI displays via MTKView for 60fps GPU-direct rendering (no CPU readback)
        // Server names are simple: "Shader", "Mask", "Lyrics", etc.
        SyphonMTKView(serverName: serverName(for: selectedTile))
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
                    guard let shaders = renderEngine?.shaderRepository.regularShaders else { return }
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
                    guard let shaders = renderEngine?.shaderRepository.regularShaders else { return }
                    if let current = shaders.firstIndex(where: { $0.name == binding.wrappedValue }) {
                        let next = (current + 1) % shaders.count
                        binding.wrappedValue = shaders[next].name
                    }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)
                
                Button("Random") {
                    guard let shaders = renderEngine?.shaderRepository.regularShaders else { return }
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
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Use Demo Text", isOn: $useDemoText)
                .onChange(of: useDemoText) { _, enabled in
                    if enabled { applyDemoText() }
                }

            GroupBox("Lyrics Demo") {
                VStack(alignment: .leading, spacing: 8) {
                    // Animation controls
                    HStack {
                        Text("Animation:")
                            .font(.caption)
                        Picker("", selection: Binding(
                            get: { renderEngine?.textManager.animationMode ?? .waveDissolve },
                            set: { renderEngine?.textManager.animationMode = $0 }
                        )) {
                            ForEach(TextAnimationMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .frame(width: 140)
                        
                        Spacer()
                        
                        Text("Duration:")
                            .font(.caption)
                        Picker("", selection: Binding(
                            get: { renderEngine?.textManager.transitionDuration ?? 1.0 },
                            set: { renderEngine?.textManager.transitionDuration = $0 }
                        )) {
                            Text("0.5s").tag(0.5)
                            Text("1.0s").tag(1.0)
                            Text("1.5s").tag(1.5)
                            Text("2.0s").tag(2.0)
                        }
                        .frame(width: 80)
                    }
                    
                    Divider()
                    
                    // Line navigation
                    HStack {
                        Text("Active line: \(demoLyrics.activeIndex + 1)/\(max(1, demoLyrics.lines.count))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Prev") { shiftDemoLyrics(by: -1) }
                        Button("Next") { shiftDemoLyrics(by: 1) }
                    }
                    TextEditor(text: $demoLyricsText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 80)
                        .onChange(of: demoLyricsText) { _, _ in updateDemoLyricsFromText() }
                }
            }

            GroupBox("Refrain Demo") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Active", isOn: Binding(
                        get: { demoRefrain.active },
                        set: { active in
                            demoRefrain = RefrainDisplayState(
                                text: demoRefrain.text,
                                opacity: active ? 255 : 0,
                                active: active,
                                lastChangeTime: Date()
                            )
                            pushDemoIfNeeded()
                        }
                    ))
                    TextField("Refrain", text: $demoRefrainText)
                        .onChange(of: demoRefrainText) { _, newValue in
                            demoRefrain = RefrainDisplayState(text: newValue, opacity: demoRefrain.active ? 255 : 0, active: demoRefrain.active, lastChangeTime: Date())
                            pushDemoIfNeeded()
                        }
                }
            }

            GroupBox("Song Info Demo") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Sticky Song Info", isOn: Binding(
                        get: { demoSongInfo.stayVisible },
                        set: { val in
                            demoSongInfo = SongInfoDisplayState(
                                artist: demoSongInfo.artist,
                                title: demoSongInfo.title,
                                album: demoSongInfo.album,
                                opacity: demoSongInfo.opacity,
                                displayTime: demoSongInfo.displayTime,
                                active: demoSongInfo.active,
                                lastChangeTime: Date(),
                                stayVisible: val
                            )
                            pushDemoIfNeeded()
                        }
                    ))
                    TextField("Artist", text: $demoArtist)
                        .onChange(of: demoArtist) { _, val in updateDemoSongInfo(artist: val, title: demoTitle, album: demoAlbum) }
                    TextField("Title", text: $demoTitle)
                        .onChange(of: demoTitle) { _, val in updateDemoSongInfo(artist: demoArtist, title: val, album: demoAlbum) }
                    TextField("Album", text: $demoAlbum)
                        .onChange(of: demoAlbum) { _, val in updateDemoSongInfo(artist: demoArtist, title: demoTitle, album: val) }
                }
            }

            Button("Apply Demo → Tiles") {
                applyDemoText()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: Demo Helpers

    private func shiftDemoLyrics(by delta: Int) {
        let newIndex = min(max(0, demoLyrics.activeIndex + delta), demoLyrics.lines.count - 1)
        demoLyrics = LyricsDisplayState(
            lines: demoLyrics.lines,
            activeIndex: newIndex,
            textOpacity: 255,
            fadeDelayMs: demoLyrics.fadeDelayMs,
            fadeDurationMs: demoLyrics.fadeDurationMs,
            lastChangeTime: Date()
        )
        pushDemoIfNeeded()
        // Animation now auto-triggers via lyricsState didSet
    }

    private func updateDemoLyricsFromText() {
        let lines = demoLyricsText.split(separator: "\n").map { String($0) }
        demoLyrics = LyricsDisplayState(
            lines: lines.enumerated().map { DisplayLyricLine(id: $0.offset, timeSec: Float($0.offset), text: $0.element) },
            activeIndex: min(demoLyrics.activeIndex, max(0, lines.count - 1)),
            textOpacity: 255,
            fadeDelayMs: 5000,
            fadeDurationMs: 1000,
            lastChangeTime: Date()
        )
        pushDemoIfNeeded()
    }

    private func updateDemoSongInfo(artist: String, title: String, album: String) {
        demoSongInfo = SongInfoDisplayState(
            artist: artist,
            title: title,
            album: album,
            opacity: 255,
            displayTime: 0,
            active: true,
            lastChangeTime: Date(),
            stayVisible: demoSongInfo.stayVisible
        )
        pushDemoIfNeeded()
    }

    private func applyDemoText() {
        guard let engine = renderEngine else { return }
        Task { @MainActor in
            engine.textManager.lyricsState = demoLyrics
            engine.textManager.refrainState = demoRefrain
            engine.textManager.songInfoState = demoSongInfo
        }
    }

    private func pushDemoIfNeeded() {
        if useDemoText { applyDemoText() }
    }
    
    // MARK: - Image Controls
    
    @ViewBuilder
    private var imageControlsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Navigation
            HStack {
                Text("Image:")

                Button {
                    appState.prevImage()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)

                Text("\(appState.imageIndex + 1)/\(appState.imageCount)")
                    .font(.caption.monospaced())
                    .frame(minWidth: 80)
                    .padding(.horizontal, 8)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)

                Button {
                    appState.nextImage()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)
            }
            
            // Beat cycling
            HStack {
                Text("Auto-switch:")

                ForEach([("Manual", 0), ("4 beats", 4), ("8 beats", 8), ("16 beats", 16)], id: \.0) { label, beats in
                    Button {
                        if let imageManager = renderEngine?.imageManager {
                            let state = imageManager.state
                            imageManager.state = ImageDisplayState(
                                currentImageURL: state.currentImageURL,
                                nextImageURL: state.nextImageURL,
                                crossfadeProgress: state.crossfadeProgress,
                                isFading: state.isFading,
                                coverMode: state.coverMode,
                                folderImages: state.folderImages,
                                folderIndex: state.folderIndex,
                                beatsPerChange: beats
                            )
                            if beats == 0 {
                                appState.log("[Images] Auto-cycle: Manual", level: .info)
                            } else {
                                appState.log("[Images] Auto-cycle: \(beats) beats", level: .info)
                            }
                        }
                    } label: {
                        Text(label)
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint((renderEngine?.imageManager.state.beatsPerChange ?? 0) == beats ? .blue : .gray)
                }
            }
            
            // Load folder button
            HStack {
                Text("Source:")
                
                Button("Load Folder") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    
                    if panel.runModal() == .OK, let url = panel.url {
                        loadImagesFromFolder(url)
                    }
                }
                .buttonStyle(.bordered)
                
                if let state = renderEngine?.imageManager.state,
                   !state.folderImages.isEmpty {
                    Text("\(state.folderImages.count) images loaded")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }

    private func loadImagesFromFolder(_ url: URL) {
        appState.log("[Images] Loading from folder: \(url.lastPathComponent)", level: .info)
        appState.log("[Images]   Path: \(url.path)", level: .debug)

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        ) else {
            appState.log("[Images] Failed to read directory", level: .error)
            return
        }

        let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff"]
        let imageFiles = files.filter { file in
            imageExtensions.contains(file.pathExtension.lowercased())
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        appState.log("[Images] Found \(imageFiles.count) image files", level: .info)

        guard !imageFiles.isEmpty else {
            appState.log("[Images] No images found in folder", level: .warning)
            return
        }

        // Log first few filenames
        let preview = imageFiles.prefix(5).map { $0.lastPathComponent }.joined(separator: ", ")
        appState.log("[Images]   Files: \(preview)\(imageFiles.count > 5 ? "..." : "")", level: .debug)

        if let imageManager = renderEngine?.imageManager {
            let currentCoverMode = imageManager.state.coverMode
            imageManager.state = ImageDisplayState(
                currentImageURL: imageFiles.first,
                nextImageURL: imageFiles.count > 1 ? imageFiles[1] : nil,
                crossfadeProgress: 0.0,
                isFading: false,
                coverMode: currentCoverMode,
                folderImages: imageFiles,
                folderIndex: 0,
                beatsPerChange: 8
            )
            appState.log("[Images] Loaded with 8-beat auto-cycle", level: .info)
        } else {
            appState.log("[Images] ImageManager not available", level: .error)
        }
    }
}

// MARK: - Shader List View

struct ShaderListView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var repository: ObservableShaderRepository
    @ObservedObject var selection: ShaderSelectionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Navigation buttons - go through AppState for shader selection
                Button {
                    selection.prevMain()
                    if let name = selection.mainShaderName {
                        appState.selectShader(name)
                    }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)
                .disabled(repository.regularShaders.isEmpty)

                Button {
                    selection.nextMain()
                    if let name = selection.mainShaderName {
                        appState.selectShader(name)
                    }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)
                .disabled(repository.regularShaders.isEmpty)
                
                Text("\(selection.mainIndex + 1)/\(repository.regularShaders.count)")
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
                        Task {
                            await repository.setShadersDirectory(url)
                        }
                    }
                }
                .font(.caption)
            }

            if !repository.regularShaders.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(repository.regularShaders) { shader in
                            ShaderChip(
                                name: shader.name,
                                isSelected: appState.selectedShader == shader.name
                            ) {
                                // All shader selection goes through AppState
                                appState.selectShader(shader.name)
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
