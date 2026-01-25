// RenderingViews.swift - SwiftUI views for VJ rendering preview
// Phase 6: Visual rendering system views

import SwiftUI
import Metal
import MetalKit
import AppKit
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
            textManager.beatIntensity *= 0.92
            if textManager.beatIntensity < 0.01 {
                textManager.beatIntensity = 0
                timer.invalidate()
            }
        }
    }
}

// MARK: - Rendering Tab View

/// Full rendering tab for the sidebar - ALL tiles use MTKView for 60fps
struct RenderingView: View {
    @EnvironmentObject var appState: AppState
    // Shader selection now goes through AppState (single source of truth)
    @AppStorage("lastSelectedMaskShader") private var selectedMaskShader: String = "BWcarbonlattice"
    @State private var shaderSearch: String = ""
    @State private var maskSearch: String = ""
    @State private var selectedTile: String = "shader"

    private let tileKeys: [String] = ["shader", "mask", "lyrics", "refrain", "songInfo", "image"]
    private let fontNameOptions: [String] = ["Avenir Next", "Helvetica Neue", "Futura", "Menlo", "Georgia"]

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
    @State private var karaokeAnimationSelection: TextAnimationMode = .waveDissolve

    // Use appState.renderEngine (receives OSC updates) instead of local instance
    private var renderEngine: RenderEngine? { appState.renderEngine }
    private var audioState: AudioState { appState.renderEngine?.audioManager.state ?? .silent }

    var body: some View {
        VStack(spacing: 0) {
            tileGridView

            Divider()

            registerPaneView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            Task { @MainActor in
                try? await renderEngine?.start()
            }
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

    // MARK: - Layout Helpers

    private struct AspectGridLayout: Layout {
        let columns: Int
        let spacing: CGFloat
        let aspectRatio: CGFloat

        func sizeThatFits(
            proposal: ProposedViewSize,
            subviews: Subviews,
            cache: inout ()
        ) -> CGSize {
            let count = subviews.count
            guard count > 0, columns > 0 else { return .zero }

            let rows = Int(ceil(Double(count) / Double(columns)))
            let proposedWidth = proposal.width ?? 0
            let proposedHeight = proposal.height

            guard proposedWidth > 0 else { return .zero }

            let spacingWidth = spacing * CGFloat(max(columns - 1, 0))
            let spacingHeight = spacing * CGFloat(max(rows - 1, 0))

            var cellWidth = max(0, (proposedWidth - spacingWidth) / CGFloat(columns))
            var cellHeight = cellWidth / aspectRatio

            if let height = proposedHeight {
                let totalHeight = cellHeight * CGFloat(rows) + spacingHeight
                if totalHeight > height {
                    let availableHeight = max(0, height - spacingHeight)
                    cellHeight = availableHeight / CGFloat(rows)
                    cellWidth = cellHeight * aspectRatio
                }
            }

            let totalWidth = cellWidth * CGFloat(columns) + spacingWidth
            let totalHeight = cellHeight * CGFloat(rows) + spacingHeight
            return CGSize(width: totalWidth, height: totalHeight)
        }

        func placeSubviews(
            in bounds: CGRect,
            proposal: ProposedViewSize,
            subviews: Subviews,
            cache: inout ()
        ) {
            let count = subviews.count
            guard count > 0, columns > 0 else { return }

            let rows = Int(ceil(Double(count) / Double(columns)))
            let spacingWidth = spacing * CGFloat(max(columns - 1, 0))
            let spacingHeight = spacing * CGFloat(max(rows - 1, 0))

            var cellWidth = max(0, (bounds.width - spacingWidth) / CGFloat(columns))
            var cellHeight = cellWidth / aspectRatio

            let totalHeight = cellHeight * CGFloat(rows) + spacingHeight
            if totalHeight > bounds.height {
                let availableHeight = max(0, bounds.height - spacingHeight)
                cellHeight = availableHeight / CGFloat(rows)
                cellWidth = cellHeight * aspectRatio
            }

            for index in subviews.indices {
                let row = index / columns
                let column = index % columns
                let x = bounds.minX + CGFloat(column) * (cellWidth + spacing)
                let y = bounds.minY + CGFloat(row) * (cellHeight + spacing)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: cellWidth, height: cellHeight)
                )
            }
        }
    }

    
    // MARK: - Tile Grid

    @ViewBuilder
    private var tileGridView: some View {
        let spacing: CGFloat = 12
        let columns = 3
        let rows = Int(ceil(Double(tileKeys.count) / Double(columns)))
        let tileAspect: CGFloat = 16.0 / 9.0
        let gridAspect: CGFloat = (CGFloat(columns) * tileAspect) / max(1, CGFloat(rows))
        AspectGridLayout(columns: 3, spacing: spacing, aspectRatio: 16.0 / 9.0) {
            ForEach(tileKeys, id: \.self) { key in
                tilePreviewCard(tileKey: key)
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 0)
        .aspectRatio(gridAspect, contentMode: .fit)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func tilePreviewCard(tileKey: String) -> some View {
        let server = serverName(for: tileKey)
        let label = displayName(for: tileKey)

        return ZStack(alignment: .bottom) {
            SyphonMTKView(serverName: server)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(selectedTile == tileKey ? Color.accentColor : Color.clear, lineWidth: 2)
                )
                .onTapGesture {
                    selectedTile = tileKey
                }

            Button {
                copyToClipboard(server)
            } label: {
                HStack(spacing: 6) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.primary)
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(server)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Click to copy Syphon name")
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Register Pane

    @ViewBuilder
    private var registerPaneView: some View {
        GroupBox("Register") {
            VStack(alignment: .leading, spacing: 12) {
                registerTabs
                Divider()
                registerContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var registerTabs: some View {
        HStack(spacing: 8) {
            ForEach(tileKeys, id: \.self) { key in
                Button {
                    selectedTile = key
                } label: {
                    Text(displayName(for: key))
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .tint(selectedTile == key ? .accentColor : .gray)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var registerContent: some View {
        switch selectedTile {
        case "shader":
            shaderRegisterSection
        case "mask":
            maskRegisterSection
        case "lyrics":
            lyricsRegisterSection
        case "refrain":
            refrainRegisterSection
        case "songInfo":
            songInfoRegisterSection
        case "image":
            imagesRegisterSection
        default:
            shaderRegisterSection
        }
    }

    // MARK: - Register Sections

    @ViewBuilder
    private var shaderRegisterSection: some View {
        GroupBox("Shader") {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Search shaders", text: $shaderSearch)
                        .textFieldStyle(.roundedBorder)
                    shaderListView(isMask: false)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                Divider()
                    .frame(maxHeight: .infinity)

                shaderSelectionControls(isMask: false)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var maskRegisterSection: some View {
        GroupBox("Mask") {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Search masks", text: $maskSearch)
                        .textFieldStyle(.roundedBorder)
                    shaderListView(isMask: true)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                Divider()
                    .frame(maxHeight: .infinity)

                shaderSelectionControls(isMask: true)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var lyricsRegisterSection: some View {
        GroupBox("Lyrics") {
            if let karaokeEngine = renderEngine?.karaokeEngine {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        karaokeControlsSection(karaokeEngine: karaokeEngine)
                        Divider()
                        karaokeFontSettingsView(karaokeEngine: karaokeEngine)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    Divider()
                        .frame(maxHeight: .infinity)

                    lyricsTimelineView(karaokeEngine: karaokeEngine)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Text("Karaoke engine not running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var refrainRegisterSection: some View {
        GroupBox("Refrain") {
            HStack(alignment: .top, spacing: 12) {
                refrainControlsSection
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                Divider()
                    .frame(maxHeight: .infinity)

                fontSettingsView(
                    title: "Font",
                    fontName: Binding(
                        get: { renderEngine?.textManager.refrainFontName ?? fontNameOptions[0] },
                        set: { renderEngine?.textManager.refrainFontName = $0 }
                    ),
                    fontSize: Binding(
                        get: { renderEngine?.textManager.refrainFontSize ?? 64 },
                        set: { renderEngine?.textManager.refrainFontSize = $0 }
                    ),
                    animationMode: Binding(
                        get: { renderEngine?.textManager.refrainAnimationMode ?? .fadeInOut },
                        set: { renderEngine?.textManager.refrainAnimationMode = $0 }
                    )
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var songInfoRegisterSection: some View {
        GroupBox("Song Info") {
            HStack(alignment: .top, spacing: 12) {
                songInfoControlsSection
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                Divider()
                    .frame(maxHeight: .infinity)

                fontSettingsView(
                    title: "Font",
                    fontName: Binding(
                        get: { renderEngine?.textManager.songInfoFontName ?? fontNameOptions[0] },
                        set: { renderEngine?.textManager.songInfoFontName = $0 }
                    ),
                    fontSize: Binding(
                        get: { renderEngine?.textManager.songInfoFontSize ?? 54 },
                        set: { renderEngine?.textManager.songInfoFontSize = $0 }
                    ),
                    animationMode: Binding(
                        get: { renderEngine?.textManager.songInfoAnimationMode ?? .fadeInOut },
                        set: { renderEngine?.textManager.songInfoAnimationMode = $0 }
                    )
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var imagesRegisterSection: some View {
        GroupBox("Images") {
            HStack(alignment: .top, spacing: 12) {
                imageControlsView
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                Divider()
                    .frame(maxHeight: .infinity)

                imageStatusView
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Register Helpers

    @ViewBuilder
    private func shaderListView(isMask: Bool) -> some View {
        let shaders = filteredShaders(isMask: isMask)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(shaders, id: \.name) { shader in
                    Button {
                        if isMask {
                            selectedMaskShader = shader.name
                            renderEngine?.shaderSelection.selectMask(name: shader.name)
                        } else {
                            appState.selectShader(shader.name)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(shader.name)
                                .font(.caption.monospaced())
                                .foregroundStyle(.primary)
                            Spacer()
                            if isMask {
                                if shader.name == selectedMaskShader {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.orange)
                                }
                            } else {
                                if shader.name == appState.selectedShader {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(6)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func filteredShaders(isMask: Bool) -> [ShaderInfo] {
        let query = (isMask ? maskSearch : shaderSearch).trimmingCharacters(in: .whitespacesAndNewlines)
        let repository = renderEngine?.shaderRepository
        let baseShaders = isMask ? (repository?.masks ?? []) : (repository?.regularShaders ?? [])
        guard !query.isEmpty, let repository = repository else { return baseShaders }
        let results = repository.search(query: query)
        return results.filter { $0.isMask == isMask }
    }

    @ViewBuilder
    private func shaderSelectionControls(isMask: Bool) -> some View {
        let repository = renderEngine?.shaderRepository
        let shaders = isMask ? (repository?.masks ?? []) : (repository?.regularShaders ?? [])
        let selected = isMask ? selectedMaskShader : (appState.selectedShader ?? "")

        VStack(alignment: .leading, spacing: 8) {
            Text("Selected")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(selected.isEmpty ? "None" : selected)
                .font(.caption.monospaced())
                .lineLimit(2)

            HStack(spacing: 6) {
                Button {
                    guard let idx = shaders.firstIndex(where: { $0.name == selected }) else { return }
                    let prev = (idx - 1 + shaders.count) % shaders.count
                    selectShader(name: shaders[prev].name, isMask: isMask)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)

                Button {
                    guard let idx = shaders.firstIndex(where: { $0.name == selected }) else { return }
                    let next = (idx + 1) % shaders.count
                    selectShader(name: shaders[next].name, isMask: isMask)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)

                Button("Random") {
                    if let random = shaders.randomElement() {
                        selectShader(name: random.name, isMask: isMask)
                    }
                }
                .buttonStyle(.bordered)
            }

            Text("Total: \(shaders.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func selectShader(name: String, isMask: Bool) {
        if isMask {
            selectedMaskShader = name
            renderEngine?.shaderSelection.selectMask(name: name)
        } else {
            appState.selectShader(name)
        }
    }

    @ViewBuilder
    private func lyricsTimelineView(karaokeEngine: KaraokeEngine) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Position")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(timeString(appState.playbackPosition))
                    .font(.caption.monospacedDigit())
                Text("•")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Line \(max(0, karaokeEngine.activeLineIndex + 1))/\(max(1, karaokeEngine.allLines.count))")
                    .font(.caption.monospacedDigit())
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(karaokeEngine.allLines.enumerated()), id: \.offset) { index, line in
                        HStack(spacing: 8) {
                            Text(timeString(Double(line.timeSec)))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .trailing)
                            Text(line.text)
                                .font(.caption)
                                .foregroundStyle(index == karaokeEngine.activeLineIndex ? .primary : .secondary)
                            Spacer()
                        }
                        .padding(.vertical, 2)
                        .background(index == karaokeEngine.activeLineIndex ? Color.accentColor.opacity(0.12) : Color.clear)
                        .cornerRadius(4)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func karaokeFontSettingsView(karaokeEngine: KaraokeEngine) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Typography")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("Design")
                    .frame(width: 70, alignment: .leading)
                Picker("", selection: Binding(
                    get: { karaokeEngine.configuration.fontDesign },
                    set: { karaokeEngine.configuration = karaokeEngine.configuration.withFontDesign($0) }
                )) {
                    Text("Default").tag(Font.Design.default)
                    Text("Rounded").tag(Font.Design.rounded)
                    Text("Serif").tag(Font.Design.serif)
                    Text("Mono").tag(Font.Design.monospaced)
                }
                .labelsHidden()
            }

            HStack {
                Text("Weight")
                    .frame(width: 70, alignment: .leading)
                Picker("", selection: Binding(
                    get: { karaokeEngine.configuration.fontWeight },
                    set: { karaokeEngine.configuration = karaokeEngine.configuration.withFontWeight($0) }
                )) {
                    Text("Regular").tag(Font.Weight.regular)
                    Text("Medium").tag(Font.Weight.medium)
                    Text("Semibold").tag(Font.Weight.semibold)
                    Text("Bold").tag(Font.Weight.bold)
                    Text("Heavy").tag(Font.Weight.heavy)
                }
                .labelsHidden()
            }
        }
    }

    @ViewBuilder
    private func fontSettingsView(
        title: String,
        fontName: Binding<String>,
        fontSize: Binding<CGFloat>,
        animationMode: Binding<TextAnimationMode>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text("Font")
                    .frame(width: 50, alignment: .leading)
                Picker("", selection: fontName) {
                    ForEach(fontNameOptions, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
            }
            HStack {
                Text("Size")
                    .frame(width: 50, alignment: .leading)
                Slider(value: fontSize, in: 24...120)
                Text("\(Int(fontSize.wrappedValue))pt")
                    .font(.caption.monospacedDigit())
                    .frame(width: 50)
            }
            HStack {
                Text("Anim")
                    .frame(width: 50, alignment: .leading)
                Picker("", selection: animationMode) {
                    ForEach(TextAnimationMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .labelsHidden()
            }
        }
    }

    @ViewBuilder
    private var imageStatusView: some View {
        let state = renderEngine?.imageManager.state ?? .empty
        VStack(alignment: .leading, spacing: 6) {
            Text("Current: \(state.currentImageURL?.lastPathComponent ?? "None")")
                .font(.caption)
            Text("Next: \(state.nextImageURL?.lastPathComponent ?? "None")")
                .font(.caption)
            HStack {
                Text("Crossfade")
                    .font(.caption)
                Spacer()
                Text(String(format: "%.0f%%", state.crossfadeProgress * 100))
                    .font(.caption.monospacedDigit())
            }
            HStack {
                Text("Mode")
                    .font(.caption)
                Spacer()
                Text(state.coverMode ? "Cover" : "Contain")
                    .font(.caption)
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func timeString(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", mins, secs, ms)
    }
    
    // MARK: - Text Controls (Karaoke + Song Info + Refrain)

    @ViewBuilder
    private var textControlsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Karaoke Engine Controls (main feature)
                if let karaokeEngine = renderEngine?.karaokeEngine {
                    karaokeControlsSection(karaokeEngine: karaokeEngine)
                } else {
                    Text("Render engine not running")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                }

                Divider()

                // Song Info Controls (minimal)
                songInfoControlsSection

                Divider()

                // Refrain Controls (minimal)
                refrainControlsSection
            }
            .padding()
        }
    }

    // MARK: - Karaoke Controls Section

    @ViewBuilder
    private func karaokeControlsSection(karaokeEngine: KaraokeEngine) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Karaoke Engine")
                .font(.headline)

            // Test controls (preview is in main tile view above - select "Lyrics" tile)
            HStack(spacing: 8) {
                Button("Load Test") {
                    karaokeEngine.loadTestLyrics()
                }
                Button("Prev") {
                    karaokeEngine.previousLine()
                }
                Button("Next") {
                    karaokeEngine.nextLine()
                }
                Spacer()
                if karaokeEngine.displayState.hasLyrics {
                    Text(karaokeEngine.displayState.progressText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            // Configuration
            GroupBox("Settings") {
                VStack(spacing: 10) {
                    // Animation mode
                    HStack {
                        Text("Animation")
                            .frame(width: 80, alignment: .leading)
                        Picker("", selection: $karaokeAnimationSelection) {
                            ForEach(TextAnimationMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .onAppear {
                            karaokeAnimationSelection = karaokeEngine.configuration.animationMode
                        }
                        .onChange(of: karaokeAnimationSelection) { _, newValue in
                            karaokeEngine.configuration = karaokeEngine.configuration.withAnimationMode(newValue)
                        }
                        .onChange(of: karaokeEngine.configuration.animationMode) { _, newValue in
                            karaokeAnimationSelection = newValue
                        }
                    }

                    // Transition duration
                    HStack {
                        Text("Duration")
                            .frame(width: 80, alignment: .leading)
                        Slider(
                            value: Binding(
                                get: { karaokeEngine.configuration.transitionDuration },
                                set: { karaokeEngine.configuration.transitionDuration = $0 }
                            ),
                            in: 0.2...1.5
                        )
                        Text(String(format: "%.1fs", karaokeEngine.configuration.transitionDuration))
                            .font(.caption.monospacedDigit())
                            .frame(width: 40)
                    }

                    // Next line opacity
                    HStack {
                        Text("Dim Level")
                            .frame(width: 80, alignment: .leading)
                        Slider(
                            value: Binding(
                                get: { karaokeEngine.configuration.nextLineOpacity },
                                set: { karaokeEngine.configuration.nextLineOpacity = $0 }
                            ),
                            in: 0.1...0.7
                        )
                        Text(String(format: "%.0f%%", karaokeEngine.configuration.nextLineOpacity * 100))
                            .font(.caption.monospacedDigit())
                            .frame(width: 40)
                    }

                    // Font sizes
                    HStack {
                        Text("Font Size")
                            .frame(width: 80, alignment: .leading)
                        Slider(
                            value: Binding(
                                get: { karaokeEngine.configuration.currentFontSize },
                                set: { karaokeEngine.configuration.currentFontSize = $0 }
                            ),
                            in: 48...120
                        )
                        Text(String(format: "%.0fpt", karaokeEngine.configuration.currentFontSize))
                            .font(.caption.monospacedDigit())
                            .frame(width: 45)
                    }

                    // Presets
                    HStack(spacing: 6) {
                        Text("Presets")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Default") { karaokeEngine.configuration = .default }
                        Button("Compact") { karaokeEngine.configuration = .compact }
                        Button("Dramatic") { karaokeEngine.configuration = .dramatic }
                        Button("Subtle") { karaokeEngine.configuration = .subtle }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
        }
    }

    // MARK: - Song Info Controls Section

    @ViewBuilder
    private var songInfoControlsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Song Info")
                    .font(.headline)
                Spacer()
                Button("Show") {
                    showTestSongInfo()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Artist", text: $demoArtist)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    TextField("Title", text: $demoTitle)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                }
                Toggle("Sticky", isOn: Binding(
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
                    }
                ))
                .toggleStyle(.switch)
            }
        }
    }

    private func showTestSongInfo() {
        demoSongInfo = SongInfoDisplayState(
            artist: demoArtist,
            title: demoTitle,
            album: demoAlbum,
            opacity: 255,
            displayTime: 0,
            active: true,
            lastChangeTime: Date(),
            stayVisible: demoSongInfo.stayVisible
        )
        renderEngine?.textManager.songInfoState = demoSongInfo
    }

    // MARK: - Refrain Controls Section

    @ViewBuilder
    private var refrainControlsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Refrain")
                    .font(.headline)
                Spacer()
                Button(demoRefrain.active ? "Hide" : "Show") {
                    toggleRefrain()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack {
                TextField("Refrain text", text: $demoRefrainText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }
        }
    }

    private func toggleRefrain() {
        let newActive = !demoRefrain.active
        demoRefrain = RefrainDisplayState(
            text: demoRefrainText,
            opacity: 255,
            active: newActive,
            lastChangeTime: Date()
        )
        renderEngine?.textManager.refrainState = demoRefrain
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
