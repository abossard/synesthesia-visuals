// SwiftUITextRenderer.swift - SwiftUI TextRenderer API with per-glyph animations
// Uses SwiftUI's TextRenderer protocol for karaoke-style text effects
// Captures to Metal texture via ImageRenderer for Syphon output

import SwiftUI
import Metal
import MetalKit

// MARK: - Animation Mode

/// Available text animation modes for lyrics/text tiles
enum TextAnimationMode: String, CaseIterable, Identifiable, Sendable {
    case instant = "Instant"
    case fadeInOut = "Fade In/Out"
    case waveDissolve = "Wave Dissolve"
    case blurPop = "Blur Pop"
    case springBounce = "Spring Bounce"
    case typewriter = "Typewriter"
    case glowPulse = "Glow Pulse"
    case rainbowWave = "Rainbow Wave"
    
    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .instant: return "No animation, instant text change"
        case .fadeInOut: return "Simple opacity fade"
        case .waveDissolve: return "Characters dissolve left-to-right with blur"
        case .blurPop: return "Characters blur in with scale"
        case .springBounce: return "Characters bounce in with spring physics"
        case .typewriter: return "Characters appear one by one"
        case .glowPulse: return "Pulsing glow effect synced to beat"
        case .rainbowWave: return "Hue rotation wave across text"
        }
    }
}

// MARK: - Text Attribute for Animation

/// Custom attribute to mark text for per-glyph animation
struct AnimatedTextAttribute: TextAttribute {}

// MARK: - Animated Text Renderers
// Note: Using SwiftUI.TextRenderer explicitly to avoid conflict with HeadlessRenderer.TextRenderer class

/// Wave dissolve renderer - characters fade/blur from left to right
struct WaveDissolveRenderer: SwiftUI.TextRenderer, Animatable {
    var progress: Double  // 0 = all visible, 1 = all dissolved
    var direction: Double = 1.0  // 1 = left-to-right, -1 = right-to-left
    
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for run in layout.flattenedRuns {
            let count = run.count
            let delay = 1.0 / Double(max(count, 1))
            
            for (index, slice) in run.enumerated() {
                let charProgress: Double
                if direction > 0 {
                    charProgress = max(0, min(1, (progress - Double(index) * delay) / (1.0 - Double(count - 1) * delay)))
                } else {
                    let reverseIndex = count - 1 - index
                    charProgress = max(0, min(1, (progress - Double(reverseIndex) * delay) / (1.0 - Double(count - 1) * delay)))
                }
                
                var copy = context
                copy.opacity = 1.0 - charProgress
                copy.addFilter(.blur(radius: charProgress * 10))
                copy.draw(slice)
            }
        }
    }
}

/// Blur pop renderer - characters blur in with scale effect
struct BlurPopRenderer: SwiftUI.TextRenderer, Animatable {
    var progress: Double  // 0 = hidden, 1 = fully visible
    var staggerDelay: Double = 0.05
    
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for run in layout.flattenedRuns {
            for (index, slice) in run.enumerated() {
                let delay = Double(index) * staggerDelay
                let charProgress = max(0, min(1, (progress - delay) / (1.0 - delay * 0.5)))
                
                let bounds = slice.typographicBounds.rect
                let centerX = bounds.midX
                let centerY = bounds.midY
                
                var copy = context
                let scale = 0.5 + charProgress * 0.5
                let blur = (1.0 - charProgress) * 8
                
                copy.translateBy(x: centerX, y: centerY)
                copy.scaleBy(x: scale, y: scale)
                copy.translateBy(x: -centerX, y: -centerY)
                
                copy.opacity = charProgress
                copy.addFilter(.blur(radius: blur))
                copy.draw(slice)
            }
        }
    }
}

/// Spring bounce renderer - characters bounce in with spring physics
struct SpringBounceRenderer: SwiftUI.TextRenderer, Animatable {
    var progress: Double
    var bounceHeight: Double = 20
    
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    
    private func springValue(_ t: Double) -> Double {
        // Critically damped spring approximation
        let omega: Double = 10
        let zeta: Double = 0.7
        let damping = exp(-zeta * omega * t)
        let oscillation = cos(omega * sqrt(1 - zeta * zeta) * t)
        return 1.0 - damping * oscillation
    }
    
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for run in layout.flattenedRuns {
            for (index, slice) in run.enumerated() {
                let delay = Double(index) * 0.03
                let charTime = max(0, progress - delay)
                let spring = springValue(charTime * 3)
                
                let yOffset = bounceHeight * (1.0 - spring)
                
                var copy = context
                copy.translateBy(x: 0, y: -yOffset)
                copy.opacity = min(1, charTime * 5)
                copy.draw(slice)
            }
        }
    }
}

/// Typewriter renderer - characters appear one by one
struct TypewriterRenderer: SwiftUI.TextRenderer, Animatable {
    var progress: Double  // 0-1 maps to characters revealed
    
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for run in layout.flattenedRuns {
            let count = run.count
            let charsToShow = Int(progress * Double(count))
            
            for (index, slice) in run.enumerated() {
                if index < charsToShow {
                    context.draw(slice)
                } else if index == charsToShow {
                    // Fade in the current character
                    let charProgress = (progress * Double(count)) - Double(index)
                    var copy = context
                    copy.opacity = charProgress
                    copy.draw(slice)
                }
            }
        }
    }
}

/// Rainbow wave renderer - hue rotation travels across text
struct RainbowWaveRenderer: SwiftUI.TextRenderer, Animatable {
    var phase: Double  // Animation phase 0-1
    var waveSpeed: Double = 2.0
    
    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }
    
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for run in layout.flattenedRuns {
            for (index, slice) in run.enumerated() {
                let hueOffset = (Double(index) * 0.1 + phase * waveSpeed).truncatingRemainder(dividingBy: 1.0)
                
                var copy = context
                copy.addFilter(.hueRotation(Angle(degrees: hueOffset * 360)))
                copy.draw(slice)
            }
        }
    }
}

/// Glow pulse renderer - synchronized glow effect
struct GlowPulseRenderer: SwiftUI.TextRenderer, Animatable {
    var intensity: Double  // 0-1 glow intensity
    var glowRadius: Double = 10
    var glowColor: Color = .white
    
    var animatableData: Double {
        get { intensity }
        set { intensity = newValue }
    }
    
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        // Draw glow layer first
        if intensity > 0.01 {
            var glowContext = context
            glowContext.addFilter(.blur(radius: glowRadius * intensity))
            glowContext.opacity = intensity * 0.6
            
            for run in layout.flattenedRuns {
                for slice in run {
                    glowContext.draw(slice)
                }
            }
        }
        
        // Draw main text on top
        for run in layout.flattenedRuns {
            for slice in run {
                context.draw(slice)
            }
        }
    }
}

// MARK: - Animated Lyrics View

/// SwiftUI view for animated lyrics display with karaoke-style transitions
/// - progress=0: Show current line centered, next line below (preview)
/// - progress=0→1: Current dissolves up and out with glyph effects, next slides up with glyph effects
/// - progress=1: Transition complete (caller should reset for next line)
@available(macOS 15.0, *)
struct AnimatedLyricsView: View {
    let prevLine: String
    let currentLine: String
    let nextLine: String
    let animationMode: TextAnimationMode
    let progress: Double  // 0-1 for transition animations
    let beatIntensity: Double  // 0-1 for beat-synced effects
    
    // Layout constants
    private let currentY: CGFloat = 360      // Center of 720px
    private let nextY: CGFloat = 520         // Below center
    private let prevY: CGFloat = 200         // Above center (exit position)
    private let currentFontSize: CGFloat = 72
    private let nextFontSize: CGFloat = 42
    
    var body: some View {
        ZStack {
            Color.black
            
            // Outgoing line (current → prev): dissolves up and out with glyph effects
            if !currentLine.isEmpty {
                outgoingLine
            }
            
            // Incoming line (next → current): slides up with glyph effects
            if !nextLine.isEmpty {
                incomingLine
            }
        }
        .frame(width: 1280, height: 720)
    }
    
    // MARK: - Outgoing Line (current becoming previous)
    
    @ViewBuilder
    private var outgoingLine: some View {
        let fontSize = interpolate(from: currentFontSize, to: nextFontSize * 0.8, t: progress)
        let yPos = interpolate(from: currentY, to: prevY, t: progress)
        
        // Apply glyph-level dissolve effect based on animation mode
        outgoingText(currentLine, fontSize: fontSize)
            .position(x: 640, y: yPos)
    }
    
    @ViewBuilder
    private func outgoingText(_ text: String, fontSize: CGFloat) -> some View {
        let baseText = Text(text)
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .customAttribute(AnimatedTextAttribute())
        
        switch animationMode {
        case .instant:
            baseText.opacity(progress < 0.5 ? 1.0 : 0.0)
            
        case .fadeInOut:
            baseText.opacity(1.0 - progress)
            
        case .waveDissolve:
            // Dissolve left-to-right as it exits
            baseText.textRenderer(WaveDissolveRenderer(progress: progress, direction: 1.0))
            
        case .blurPop:
            // Blur out with scale
            baseText.textRenderer(BlurPopRenderer(progress: 1.0 - progress))
            
        case .springBounce:
            // Bounce upward as it exits
            baseText.textRenderer(SpringBounceRenderer(progress: 1.0 - progress, bounceHeight: -30))
            
        case .typewriter:
            // Characters disappear one by one
            baseText.textRenderer(TypewriterRenderer(progress: 1.0 - progress))
            
        case .glowPulse:
            baseText
                .textRenderer(GlowPulseRenderer(intensity: (1.0 - progress) * 0.5))
                .opacity(1.0 - progress)
            
        case .rainbowWave:
            baseText
                .textRenderer(RainbowWaveRenderer(phase: progress * 2))
                .opacity(1.0 - progress)
        }
    }
    
    // MARK: - Incoming Line (next becoming current)
    
    @ViewBuilder
    private var incomingLine: some View {
        let fontSize = interpolate(from: nextFontSize, to: currentFontSize, t: progress)
        let yPos = interpolate(from: nextY, to: currentY, t: progress)
        
        incomingText(nextLine, fontSize: fontSize)
            .position(x: 640, y: yPos)
    }
    
    @ViewBuilder
    private func incomingText(_ text: String, fontSize: CGFloat) -> some View {
        let baseText = Text(text)
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .customAttribute(AnimatedTextAttribute())
        
        switch animationMode {
        case .instant:
            baseText.opacity(progress > 0.5 ? 1.0 : 0.5)
            
        case .fadeInOut:
            baseText.opacity(0.4 + progress * 0.6)
            
        case .waveDissolve:
            // Materialize from left-to-right as it enters
            baseText.textRenderer(WaveDissolveRenderer(progress: 1.0 - progress, direction: 1.0))
            
        case .blurPop:
            // Pop in with blur and scale
            baseText.textRenderer(BlurPopRenderer(progress: progress))
            
        case .springBounce:
            // Bounce in from below
            baseText.textRenderer(SpringBounceRenderer(progress: progress, bounceHeight: 40))
            
        case .typewriter:
            // Characters appear one by one
            baseText.textRenderer(TypewriterRenderer(progress: progress))
            
        case .glowPulse:
            baseText
                .textRenderer(GlowPulseRenderer(intensity: progress * beatIntensity.clamped(to: 0...1)))
                .opacity(0.4 + progress * 0.6)
            
        case .rainbowWave:
            baseText
                .textRenderer(RainbowWaveRenderer(phase: (1.0 - progress) * 2))
                .opacity(0.4 + progress * 0.6)
        }
    }
    
    // MARK: - Helpers
    
    private func interpolate(from: CGFloat, to: CGFloat, t: Double) -> CGFloat {
        let eased = easeOutCubic(t)
        return from + (to - from) * CGFloat(eased)
    }
    
    private func easeOutCubic(_ t: Double) -> Double {
        1.0 - pow(1.0 - t, 3)
    }
}

/// Fallback for macOS 14
struct AnimatedLyricsViewFallback: View {
    let prevLine: String
    let currentLine: String
    let nextLine: String
    let progress: Double
    
    var body: some View {
        ZStack {
            Color.black
            
            VStack(spacing: 60) {
                Text(currentLine)
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .opacity(1.0 - progress)
                
                Text(nextLine)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4 + progress * 0.6))
            }
        }
        .frame(width: 1280, height: 720)
    }
}

// MARK: - Clamped Extension

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - SwiftUI Text Tile Renderer

/// Thread-safe container for render resources (all Metal objects are thread-safe once created)
private final class RenderResources: @unchecked Sendable {
    let outputTexture: MTLTexture
    let stagingTexture: MTLTexture
    let pipelineState: MTLRenderPipelineState
    let vertexBuffer: MTLBuffer
    let samplerState: MTLSamplerState
    var hasValidContent: Bool = false
    
    init(outputTexture: MTLTexture, stagingTexture: MTLTexture, 
         pipelineState: MTLRenderPipelineState, vertexBuffer: MTLBuffer, 
         samplerState: MTLSamplerState) {
        self.outputTexture = outputTexture
        self.stagingTexture = stagingTexture
        self.pipelineState = pipelineState
        self.vertexBuffer = vertexBuffer
        self.samplerState = samplerState
    }
}

/// Headless SwiftUI text renderer - captures SwiftUI views to Metal texture
/// 
/// Architecture for thread safety:
/// - `updateContent()` runs on @MainActor when content changes
/// - `render()` runs on render thread, just blits cached texture (no main thread dependency)
/// - RenderResources holds all Metal objects which are thread-safe once created
@MainActor
final class SwiftUITextTileRenderer: TileRenderer {
    let name: String
    
    // Thread-safe render resources (accessed from render thread)
    // nonisolated(unsafe) allows render thread to read this without MainActor isolation
    // Safe because RenderResources is @unchecked Sendable and contains only thread-safe Metal objects
    nonisolated(unsafe) private var resources: RenderResources?
    
    // Expose texture for TileRenderer protocol (thread-safe read)
    nonisolated var texture: MTLTexture? {
        resources?.outputTexture
    }
    
    private let device: MTLDevice
    private let width: Int
    private let height: Int
    
    // State - updated from RenderEngine (MainActor only)
    var animationMode: TextAnimationMode = .waveDissolve
    var lyricsState: LyricsDisplayState = .empty
    var transitionProgress: Double = 0
    var beatIntensity: Double = 0
    
    // Caching - prevents redundant SwiftUI captures
    private var lastRenderedContent: String = ""
    
    init(name: String, device: MTLDevice, width: Int = 1280, height: Int = 720) {
        self.name = name
        self.device = device
        self.width = width
        self.height = height
        setupResources()
    }
    
    private func setupResources() {
        // Output texture (private storage for rendering)
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        outputDescriptor.usage = [.renderTarget, .shaderRead]
        outputDescriptor.storageMode = .private
        
        // Staging texture (managed for CPU upload)
        let stagingDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        stagingDescriptor.usage = [.shaderRead]
        stagingDescriptor.storageMode = .managed
        
        guard let outputTexture = device.makeTexture(descriptor: outputDescriptor),
              let stagingTexture = device.makeTexture(descriptor: stagingDescriptor) else {
            print("[SwiftUITextTileRenderer:\(name)] Failed to create textures")
            return
        }
        
        // Create copy pipeline
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;
        
        struct VertexOut {
            float4 position [[position]];
            float2 uv;
        };
        
        vertex VertexOut swiftUICopyVertex(uint vid [[vertex_id]],
                                            constant float4 *vertices [[buffer(0)]]) {
            float4 v = vertices[vid];
            VertexOut out;
            out.position = float4(v.xy, 0, 1);
            out.uv = v.zw;
            return out;
        }
        
        fragment float4 swiftUICopyFragment(VertexOut in [[stage_in]],
                                             texture2d<float> tex [[texture(0)]],
                                             sampler s [[sampler(0)]]) {
            return tex.sample(s, in.uv);
        }
        """
        
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            guard let vertexFunc = library.makeFunction(name: "swiftUICopyVertex"),
                  let fragmentFunc = library.makeFunction(name: "swiftUICopyFragment") else { return }
            
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunc
            pipelineDescriptor.fragmentFunction = fragmentFunc
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
            pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .one
            pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            
            let pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            
            let vertices: [Float] = [
                -1,  1, 0, 0,
                 1,  1, 1, 0,
                -1, -1, 0, 1,
                 1, -1, 1, 1,
            ]
            guard let vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Float>.stride, options: .storageModeShared) else { return }
            
            let samplerDescriptor = MTLSamplerDescriptor()
            samplerDescriptor.minFilter = .linear
            samplerDescriptor.magFilter = .linear
            guard let samplerState = device.makeSamplerState(descriptor: samplerDescriptor) else { return }
            
            resources = RenderResources(
                outputTexture: outputTexture,
                stagingTexture: stagingTexture,
                pipelineState: pipelineState,
                vertexBuffer: vertexBuffer,
                samplerState: samplerState
            )
            print("[SwiftUITextTileRenderer:\(name)] Resources initialized")
        } catch {
            print("[SwiftUITextTileRenderer:\(name)] Pipeline error: \(error)")
        }
    }
    
    // MARK: - Content Update (call from RenderEngine when lyrics change)
    
    /// Update state and trigger capture if content changed
    /// Call this from RenderEngine when lyrics state updates
    func updateContent(
        lyricsState: LyricsDisplayState,
        animationMode: TextAnimationMode,
        transitionProgress: Double = 0,
        beatIntensity: Double = 0
    ) {
        self.lyricsState = lyricsState
        self.animationMode = animationMode
        self.transitionProgress = transitionProgress
        self.beatIntensity = beatIntensity
        
        // Check if content actually changed (include progress for animation)
        let contentHash = buildContentHash()
        if contentHash != lastRenderedContent {
            captureSwiftUIView()
            lastRenderedContent = contentHash
        }
    }
    
    /// Force re-capture for animation (call repeatedly during transition)
    func forceCapture() {
        captureSwiftUIView()
    }
    
    private func buildContentHash() -> String {
        // Include progress (rounded to avoid excessive re-renders)
        let progressBucket = Int(transitionProgress * 30)  // ~30 frames of animation
        return "\(lyricsState.currentLine ?? "")-\(lyricsState.prevLine ?? "")-\(lyricsState.nextLine ?? "")-\(animationMode)-\(progressBucket)"
    }
    
    /// Capture SwiftUI view to staging texture (runs on main thread)
    private func captureSwiftUIView() {
        guard let resources = resources else { return }
        
        let cgImage: CGImage?
        
        if #available(macOS 15.0, *) {
            let view = AnimatedLyricsView(
                prevLine: lyricsState.prevLine ?? "",
                currentLine: lyricsState.currentLine ?? "",
                nextLine: lyricsState.nextLine ?? "",
                animationMode: animationMode,
                progress: transitionProgress,
                beatIntensity: beatIntensity
            )
            let swiftUIRenderer = SwiftUI.ImageRenderer(content: view)
            swiftUIRenderer.scale = 2.0
            cgImage = swiftUIRenderer.cgImage
        } else {
            let view = AnimatedLyricsViewFallback(
                prevLine: lyricsState.prevLine ?? "",
                currentLine: lyricsState.currentLine ?? "",
                nextLine: lyricsState.nextLine ?? "",
                progress: transitionProgress
            )
            let swiftUIRenderer = SwiftUI.ImageRenderer(content: view)
            swiftUIRenderer.scale = 2.0
            cgImage = swiftUIRenderer.cgImage
        }
        
        if let cgImage = cgImage {
            uploadCGImage(cgImage, to: resources.stagingTexture)
            resources.hasValidContent = true
        }
    }
    
    private func uploadCGImage(_ cgImage: CGImage, to texture: MTLTexture) {
        let bytesPerRow = width * 4
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }
        
        // Draw CGImage into context (handles scaling/format conversion)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let data = context.data else { return }
        
        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: width, height: height, depth: 1)
        )
        texture.replace(region: region, mipmapLevel: 0, withBytes: data, bytesPerRow: bytesPerRow)
    }
    
    // MARK: - TileRenderer Protocol (render thread safe)
    
    /// Blit cached staging texture to output - thread safe, no main actor dependency
    nonisolated func render(commandBuffer: MTLCommandBuffer, uniforms: ShaderUniforms) {
        guard let resources = resources, resources.hasValidContent else { return }
        
        // Blit staging to output texture
        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = resources.outputTexture
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].storeAction = .store
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
        
        encoder.setRenderPipelineState(resources.pipelineState)
        encoder.setVertexBuffer(resources.vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(resources.stagingTexture, index: 0)
        encoder.setFragmentSamplerState(resources.samplerState, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }
}

// MARK: - Text.Layout Extension

extension Text.Layout {
    var flattenedRuns: some RandomAccessCollection<Text.Layout.Run> {
        self.flatMap { line in line }
    }
}

// MARK: - Settings View

/// Settings view for text animation mode selection
struct TextAnimationSettingsView: View {
    @Binding var selectedMode: TextAnimationMode
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Text Animation")
                .font(.headline)
            
            Picker("Animation Mode", selection: $selectedMode) {
                ForEach(TextAnimationMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            
            Text(selectedMode.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

// MARK: - Preview

@available(macOS 15.0, *)
#Preview("Animation Modes") {
    VStack {
        AnimatedLyricsView(
            prevLine: "Previous line fades away",
            currentLine: "Current line is highlighted",
            nextLine: "Next line waits in shadow",
            animationMode: .waveDissolve,
            progress: 0.5,
            beatIntensity: 0.8
        )
        
        TextAnimationSettingsView(selectedMode: .constant(.waveDissolve))
    }
}
