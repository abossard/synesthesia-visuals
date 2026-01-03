// SwiftVJApp - SwiftUI macOS Application
// Phase 4: SwiftUI Shell for VJ Control
// Phase 6: Rendering Integration

import SwiftUI
import SwiftVJCore
import Metal
import AppKit

@main
struct SwiftVJApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
        
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

// MARK: - App Delegate for Window Management

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure window is visible and app is active
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        // Make the first window key and front
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let window = NSApplication.shared.windows.first {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

// MARK: - App State (Observable)

@MainActor
final class AppState: ObservableObject {
    // Modules
    let oscHub = OSCHub()
    let settings = Settings()
    var playbackModule: PlaybackModule?
    var lyricsModule: LyricsModule?
    var aiModule: AIModule?
    var shadersModule: ShadersModule?
    var pipelineModule: PipelineModule?

    // Rendering Engine (Phase 6)
    @Published var renderEngine: RenderEngine?

    // UI State
    @Published var isRunning = false
    @Published var currentTrack: Track?
    @Published var playbackSource: String = "vdj"
    @Published var timingOffsetMs: Int = 0

    // Pipeline State
    @Published var pipelineSteps: [PipelineStep] = []
    @Published var pipelineResult: PipelineResult?

    // OSC State
    @Published var oscMessages: [OSCLogEntry] = []
    @Published var oscMessageCount: Int = 0

    // Shader State
    @Published var shaderCount: Int = 0
    @Published var selectedShader: String?

    // Log State
    @Published var logEntries: [LogEntry] = []
    private let maxLogEntries = 500

    init() {
        setupModules()
        setupRenderEngine()
    }

    private func setupRenderEngine() {
        // Create render engine for VJUniverse visual output
        renderEngine = RenderEngine()
    }
    
    private func setupModules() {
        // Create adapters
        let lyricsFetcher = LyricsFetcher()
        let shaderMatcher = ShaderMatcher()
        let imageScraper = ImageScraper()
        let llmClient = LLMClient()
        
        // Create modules - pass OSCHub to PlaybackModule for VDJ subscription
        playbackModule = PlaybackModule(oscHub: oscHub)
        lyricsModule = LyricsModule(fetcher: lyricsFetcher)
        aiModule = AIModule(llmClient: llmClient)
        shadersModule = ShadersModule(matcher: shaderMatcher)
        let imagesModule = ImagesModule(scraper: imageScraper)
        
        // Pipeline
        pipelineModule = PipelineModule(
            lyricsModule: lyricsModule!,
            aiModule: aiModule!,
            shadersModule: shadersModule,
            imagesModule: imagesModule,
            oscHub: oscHub
        )
        
        // Track changes via playback module (registered in start())
    }
    
    func start() async throws {
        // Start playback module first
        try await playbackModule?.start()
        
        // Set initial source
        await playbackModule?.setSource(playbackSource == "vdj" ? .vdj : .spotify)
        
        // Capture references for Sendable closure (avoid capturing self)
        let pipeline = pipelineModule
        
        // Register track change callback - triggers pipeline processing
        // Use explicit Sendable closure to satisfy Swift 6 concurrency
        await playbackModule?.onTrackChange { @Sendable [weak self] track in
            guard let self = self else { return }
            
            // Update UI state on main thread
            await MainActor.run { [weak self] in
                self?.currentTrack = track
                self?.log("Track: \(track.artist) - \(track.title)", level: .info)
            }
            
            // Process through pipeline
            if let pipeline = pipeline {
                let result = await pipeline.process(track: track)
                await MainActor.run { [weak self] in
                    self?.pipelineResult = result
                    self?.updatePipelineSteps(from: result)
                }
            }
        }
        
        try await pipelineModule?.start()
        isRunning = true
        log("Pipeline started", level: .info)
        
        // Update shader count
        if let count = await shadersModule?.shaderCount {
            shaderCount = count
        }
    }
    
    private func updatePipelineSteps(from result: PipelineResult) {
        // Update pipeline steps from result
        pipelineSteps = [
            PipelineStep(name: "lyrics", status: result.lyricsFound ? "✓ \(result.lyricsLineCount) lines" : "skipped", timestamp: Date()),
            PipelineStep(name: "ai", status: result.aiAvailable ? "✓ \(result.mood)" : "skipped", timestamp: Date()),
            PipelineStep(name: "shaders", status: result.shaderMatched ? "✓ \(result.shaderName)" : "skipped", timestamp: Date()),
            PipelineStep(name: "images", status: result.imagesFound ? "✓ \(result.imagesCount) images" : "skipped", timestamp: Date()),
            PipelineStep(name: "osc", status: result.stepsCompleted.contains("osc") ? "✓" : "skipped", timestamp: Date())
        ]
    }
    
    func stop() async {
        await playbackModule?.stop()
        await pipelineModule?.stop()
        isRunning = false
        log("Pipeline stopped", level: .info)
    }
    
    func setPlaybackSource(_ source: String) async {
        playbackSource = source
        let sourceType: PlaybackSourceType = source == "vdj" ? .vdj : .spotify
        await playbackModule?.setSource(sourceType)
        log("Playback source: \(source)", level: .info)
    }
    
    func adjustTiming(_ deltaMs: Int) {
        timingOffsetMs += deltaMs
        Task {
            _ = await settings.adjustTiming(by: deltaMs)
        }
        log("Timing offset: \(timingOffsetMs)ms", level: .info)
    }
    
    func selectShader(_ name: String) async {
        selectedShader = name
        // Send shader load command via OSC
        do {
            try oscHub.sendToProcessing("/shader/load", values: [name, Float(0.5), Float(0.0)])
            log("Selected shader: \(name)", level: .info)
        } catch {
            log("Failed to send shader: \(error)", level: .error)
        }
    }
    
    // MARK: - Private
    
    private func updatePipelineStep(_ step: String, status: String) {
        if let index = pipelineSteps.firstIndex(where: { $0.name == step }) {
            pipelineSteps[index].status = status
            pipelineSteps[index].timestamp = Date()
        } else {
            pipelineSteps.append(PipelineStep(name: step, status: status, timestamp: Date()))
        }
    }
    
    func log(_ message: String, level: LogLevel = .info) {
        let entry = LogEntry(message: message, level: level, timestamp: Date())
        logEntries.append(entry)
        if logEntries.count > maxLogEntries {
            logEntries.removeFirst(logEntries.count - maxLogEntries)
        }
    }
    
    func recordOSCMessage(_ address: String, args: [String]) {
        let entry = OSCLogEntry(address: address, args: args, timestamp: Date())
        oscMessages.append(entry)
        oscMessageCount += 1
        if oscMessages.count > 200 {
            oscMessages.removeFirst(oscMessages.count - 200)
        }
    }
}

// MARK: - Supporting Types

struct PipelineStep: Identifiable {
    let id = UUID()
    let name: String
    var status: String
    var timestamp: Date
}

struct LogEntry: Identifiable {
    let id = UUID()
    let message: String
    let level: LogLevel
    let timestamp: Date
}

enum LogLevel: String, CaseIterable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
    
    var color: Color {
        switch self {
        case .debug: return .gray
        case .info: return .primary
        case .warning: return .orange
        case .error: return .red
        }
    }
}

struct OSCLogEntry: Identifiable {
    let id = UUID()
    let address: String
    let args: [String]
    let timestamp: Date
}
