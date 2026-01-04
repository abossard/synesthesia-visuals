// ShadertoyView.swift - SwiftUI wrapper for Shadertoy renderer
// Provides NSViewRepresentable (macOS) / UIViewRepresentable (iOS) wrapper

import SwiftUI
import MetalKit

// MARK: - Shadertoy View (macOS)

#if os(macOS)
/// SwiftUI view wrapper for Shadertoy rendering on macOS
public struct ShadertoyView: NSViewRepresentable {
    /// Renderer instance
    @Binding public var renderer: ShadertoyRenderer?

    /// Current shader folder to load
    public var shaderFolder: ShaderFolder?

    /// Preferred frame rate (30, 60, 120)
    public var preferredFrameRate: Int

    /// Enable mouse interaction
    public var mouseEnabled: Bool

    /// Audio state callback
    public var audioCallback: (() -> (bass: Float, lowMid: Float, mid: Float, highs: Float,
                                       energyFast: Float, energySlow: Float, beat: Float, level: Float,
                                       kickEnv: Float, kickPulse: Float, bpm: Float, confidence: Float)?)?

    public init(
        renderer: Binding<ShadertoyRenderer?>,
        shaderFolder: ShaderFolder? = nil,
        preferredFrameRate: Int = 60,
        mouseEnabled: Bool = true,
        audioCallback: (() -> (bass: Float, lowMid: Float, mid: Float, highs: Float,
                               energyFast: Float, energySlow: Float, beat: Float, level: Float,
                               kickEnv: Float, kickPulse: Float, bpm: Float, confidence: Float)?)? = nil
    ) {
        self._renderer = renderer
        self.shaderFolder = shaderFolder
        self.preferredFrameRate = preferredFrameRate
        self.mouseEnabled = mouseEnabled
        self.audioCallback = audioCallback
    }

    public func makeNSView(context: Context) -> MTKView {
        let mtkView = ShadertoyMTKView()
        mtkView.delegate = context.coordinator
        mtkView.preferredFramesPerSecond = preferredFrameRate
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        // Set up device
        guard let device = MTLCreateSystemDefaultDevice() else {
            return mtkView
        }
        mtkView.device = device

        // Create renderer
        if let newRenderer = ShadertoyRenderer(device: device) {
            DispatchQueue.main.async {
                self.renderer = newRenderer
            }
            mtkView.delegate = newRenderer

            // Set coordinator reference
            context.coordinator.renderer = newRenderer
            context.coordinator.mtkView = mtkView
        }

        return mtkView
    }

    public func updateNSView(_ nsView: MTKView, context: Context) {
        nsView.preferredFramesPerSecond = preferredFrameRate

        // Update audio
        if let callback = audioCallback, let audio = callback() {
            renderer?.audioUniforms = audio
        }

        // Load shader if changed
        if let folder = shaderFolder, let renderer = renderer {
            let currentName = renderer.currentShader?.name
            if currentName != folder.name {
                Task {
                    try? await renderer.loadShader(from: folder)
                }
            }
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public class Coordinator: NSObject {
        var parent: ShadertoyView
        var renderer: ShadertoyRenderer?
        weak var mtkView: MTKView?

        init(_ parent: ShadertoyView) {
            self.parent = parent
        }
    }
}

/// Custom MTKView subclass for mouse handling
class ShadertoyMTKView: MTKView {
    var shadertoyRenderer: ShadertoyRenderer? {
        return delegate as? ShadertoyRenderer
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let renderer = shadertoyRenderer else { return }
        let location = convert(event.locationInWindow, from: nil)
        renderer.mousePosition = SIMD2(Float(location.x), Float(bounds.height - location.y))
        renderer.mousePressed = true
        renderer.mouseClicked = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let renderer = shadertoyRenderer else { return }
        let location = convert(event.locationInWindow, from: nil)
        renderer.mousePosition = SIMD2(Float(location.x), Float(bounds.height - location.y))
    }

    override func mouseUp(with event: NSEvent) {
        guard let renderer = shadertoyRenderer else { return }
        renderer.mousePressed = false
    }

    override func mouseMoved(with event: NSEvent) {
        guard let renderer = shadertoyRenderer else { return }
        let location = convert(event.locationInWindow, from: nil)
        renderer.mousePosition = SIMD2(Float(location.x), Float(bounds.height - location.y))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Remove existing tracking areas
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        // Add new tracking area for mouse movement
        let options: NSTrackingArea.Options = [.mouseMoved, .activeInKeyWindow, .inVisibleRect]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }
}

#endif

// MARK: - Shadertoy View (iOS)

#if os(iOS)
/// SwiftUI view wrapper for Shadertoy rendering on iOS
public struct ShadertoyView: UIViewRepresentable {
    @Binding public var renderer: ShadertoyRenderer?
    public var shaderFolder: ShaderFolder?
    public var preferredFrameRate: Int
    public var audioCallback: (() -> (bass: Float, lowMid: Float, mid: Float, highs: Float,
                                       energyFast: Float, energySlow: Float, beat: Float, level: Float,
                                       kickEnv: Float, kickPulse: Float, bpm: Float, confidence: Float)?)?

    public init(
        renderer: Binding<ShadertoyRenderer?>,
        shaderFolder: ShaderFolder? = nil,
        preferredFrameRate: Int = 60,
        audioCallback: (() -> (bass: Float, lowMid: Float, mid: Float, highs: Float,
                               energyFast: Float, energySlow: Float, beat: Float, level: Float,
                               kickEnv: Float, kickPulse: Float, bpm: Float, confidence: Float)?)? = nil
    ) {
        self._renderer = renderer
        self.shaderFolder = shaderFolder
        self.preferredFrameRate = preferredFrameRate
        self.audioCallback = audioCallback
    }

    public func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.preferredFramesPerSecond = preferredFrameRate
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let device = MTLCreateSystemDefaultDevice() else {
            return mtkView
        }
        mtkView.device = device

        if let newRenderer = ShadertoyRenderer(device: device) {
            DispatchQueue.main.async {
                self.renderer = newRenderer
            }
            mtkView.delegate = newRenderer
        }

        // Add gesture recognizer for touch
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        mtkView.addGestureRecognizer(panGesture)

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        mtkView.addGestureRecognizer(tapGesture)

        context.coordinator.mtkView = mtkView

        return mtkView
    }

    public func updateUIView(_ uiView: MTKView, context: Context) {
        uiView.preferredFramesPerSecond = preferredFrameRate

        if let callback = audioCallback, let audio = callback() {
            renderer?.audioUniforms = audio
        }

        if let folder = shaderFolder, let renderer = renderer {
            if renderer.currentShader?.name != folder.name {
                Task {
                    try? await renderer.loadShader(from: folder)
                }
            }
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public class Coordinator: NSObject {
        var parent: ShadertoyView
        weak var mtkView: MTKView?

        init(_ parent: ShadertoyView) {
            self.parent = parent
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = mtkView, let renderer = parent.renderer else { return }
            let location = gesture.location(in: view)
            renderer.mousePosition = SIMD2(Float(location.x), Float(view.bounds.height - location.y))
            renderer.mousePressed = gesture.state != .ended
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = mtkView, let renderer = parent.renderer else { return }
            let location = gesture.location(in: view)
            renderer.mousePosition = SIMD2(Float(location.x), Float(view.bounds.height - location.y))
            renderer.mouseClicked = true
        }
    }
}
#endif

// MARK: - Shader Browser View

#if os(macOS)
/// View for browsing and selecting shaders
public struct ShaderBrowserView: View {
    @State private var shaders: [ShaderFolder] = []
    @State private var selectedShader: ShaderFolder?
    @State private var searchText = ""
    @State private var renderer: ShadertoyRenderer?

    private let shadersDirectory: URL

    public init(shadersDirectory: URL) {
        self.shadersDirectory = shadersDirectory
    }

    public var body: some View {
        HSplitView {
            // Shader list
            VStack {
                TextField("Search shaders...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                List(filteredShaders, id: \.name, selection: $selectedShader) { shader in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(shader.name)
                                .font(.headline)
                            if let author = shader.metadata.global?.author {
                                Text(author)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if shader.metadata.isMultiPass {
                            Text("\(shader.metadata.passes.count) passes")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedShader = shader
                    }
                }
            }
            .frame(minWidth: 200, maxWidth: 300)

            // Shader preview
            VStack {
                if selectedShader != nil {
                    ShadertoyView(
                        renderer: $renderer,
                        shaderFolder: selectedShader,
                        preferredFrameRate: 60
                    )
                } else {
                    Text("Select a shader")
                        .foregroundColor(.secondary)
                }
            }
            .frame(minWidth: 400)
        }
        .onAppear {
            loadShaders()
        }
    }

    private var filteredShaders: [ShaderFolder] {
        if searchText.isEmpty {
            return shaders
        }
        return shaders.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func loadShaders() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: shadersDirectory, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return
        }

        shaders = contents.compactMap { url -> ShaderFolder? in
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
                return nil
            }
            return try? ShaderFolder(url: url)
        }.sorted { $0.name < $1.name }
    }
}
#endif

// MARK: - Debug Overlay View

/// Overlay showing current shader state and pass graph
public struct ShaderDebugOverlay: View {
    public let shader: ShaderInstance?

    public init(shader: ShaderInstance?) {
        self.shader = shader
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let shader = shader {
                Text(shader.name)
                    .font(.headline)

                Text("Frame: \(shader.frameCount)")
                    .font(.caption)
                Text(String(format: "Time: %.2fs", shader.uniforms.iTime))
                    .font(.caption)

                Divider()

                Text("Passes:")
                    .font(.subheadline)

                ForEach(shader.passes, id: \.passName.rawValue) { pass in
                    HStack {
                        Circle()
                            .fill(pass.pipelineState != nil ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(pass.passName.rawValue)
                            .font(.caption)
                        Spacer()
                        Text("\(pass.width)x\(pass.height)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                if shader.metadata.isMultiPass {
                    Divider()
                    Text("Pass Graph:")
                        .font(.subheadline)
                    PassGraphView(shader: shader)
                }
            } else {
                Text("No shader loaded")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
}

/// Visual representation of pass dependencies
struct PassGraphView: View {
    let shader: ShaderInstance

    var body: some View {
        HStack(spacing: 4) {
            ForEach(shader.passes, id: \.passName.rawValue) { pass in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(passColor(pass.passName))
                        .frame(width: 40, height: 30)
                        .overlay(
                            Text(passLabel(pass.passName))
                                .font(.caption2)
                                .foregroundColor(.white)
                        )

                    // Show channels
                    ForEach(0..<4, id: \.self) { i in
                        let channel = pass.config.channels[i]
                        if channel.source != .none {
                            Text("ch\(i):\(channelLabel(channel))")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if pass.passName != .image {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func passColor(_ name: PassName) -> Color {
        switch name {
        case .bufA: return .blue
        case .bufB: return .green
        case .bufC: return .orange
        case .bufD: return .purple
        case .image: return .red
        }
    }

    private func passLabel(_ name: PassName) -> String {
        switch name {
        case .bufA: return "A"
        case .bufB: return "B"
        case .bufC: return "C"
        case .bufD: return "D"
        case .image: return "Img"
        }
    }

    private func channelLabel(_ channel: ChannelConfig) -> String {
        switch channel.source {
        case .none: return "-"
        case .buffer: return channel.ref ?? "?"
        case .bufferPrev: return "prev"
        case .file: return "file"
        case .noise: return "noise"
        case .keyboard: return "kbd"
        case .video: return "vid"
        case .audioFFT: return "fft"
        }
    }
}
