// PipelineModule - Orchestrates full track processing
// Following A Philosophy of Software Design: deep module hiding complexity

import Foundation

/// Pipeline step definition
public enum PipelineStep: String, CaseIterable, Sendable {
    case lyrics = "lyrics"
    case ai = "ai"
    case shaders = "shaders"
    case images = "images"
    case osc = "osc"
}

/// Pipeline module - orchestrates track analysis workflow
///
/// Deep module interface:
/// - `start()` / `stop()` - lifecycle
/// - `process(track:)` - run full pipeline
/// - `onStepStart/Complete` - progress callbacks
/// - `onComplete` - result callback
///
/// Hides: step ordering, parallel execution, caching, error recovery
public actor PipelineModule: Module {
    
    // MARK: - State
    
    public private(set) var isStarted: Bool = false
    private var isProcessing: Bool = false
    private var lastResult: PipelineResult?
    private var currentTrackKey: String?
    
    // Dependencies
    private let lyricsModule: LyricsModule
    private let aiModule: AIModule
    private let shadersModule: ShadersModule?
    private let imagesModule: ImagesModule?
    private let oscHub: OSCHub?
    
    // Cache
    private var resultCache: [String: PipelineResult] = [:]
    private let cacheTTL: TimeInterval = 3600 * 24 * 7  // 7 days
    
    // Callbacks
    private var stepStartCallbacks: [PipelineStepStartCallback] = []
    private var stepCompleteCallbacks: [PipelineStepCompleteCallback] = []
    private var completeCallbacks: [PipelineCompleteCallback] = []
    
    // MARK: - Init
    
    public init(
        lyricsModule: LyricsModule,
        aiModule: AIModule,
        shadersModule: ShadersModule? = nil,
        imagesModule: ImagesModule? = nil,
        oscHub: OSCHub? = nil
    ) {
        self.lyricsModule = lyricsModule
        self.aiModule = aiModule
        self.shadersModule = shadersModule
        self.imagesModule = imagesModule
        self.oscHub = oscHub
    }
    
    // MARK: - Module Protocol
    
    public func start() async throws {
        guard !isStarted else { throw ModuleError.alreadyStarted }
        
        // Start dependencies
        try await lyricsModule.start()
        try await aiModule.start()
        
        if let shadersModule = shadersModule {
            try await shadersModule.start()
        }
        
        if let imagesModule = imagesModule {
            try await imagesModule.start()
        }
        
        isStarted = true
        print("[Pipeline] Started")
    }
    
    public func stop() async {
        await lyricsModule.stop()
        await aiModule.stop()
        
        if let shadersModule = shadersModule {
            await shadersModule.stop()
        }
        
        if let imagesModule = imagesModule {
            await imagesModule.stop()
        }
        
        isStarted = false
        isProcessing = false
        print("[Pipeline] Stopped")
    }
    
    public func getStatus() -> [String: Any] {
        var status: [String: Any] = [
            "started": isStarted,
            "processing": isProcessing,
            "cache_size": resultCache.count
        ]
        
        if let result = lastResult {
            status["last_track"] = "\(result.artist) - \(result.title)"
            status["last_success"] = result.success
        }
        
        return status
    }
    
    // MARK: - Public API
    
    /// Process a track through the full pipeline
    public func process(track: Track) async -> PipelineResult {
        let startTime = Date()
        currentTrackKey = track.key
        isProcessing = true
        
        defer { isProcessing = false }
        
        // Check cache
        if let cached = resultCache[track.key] {
            print("[Pipeline] Cache hit: \(track.artist) - \(track.title)")
            lastResult = cached
            await fireComplete(cached)
            return cached
        }
        
        var stepsCompleted: [String] = []
        var stepsSkipped: [String] = []
        var stepTimings: [String: Int] = [:]
        
        // === STEP 1: Lyrics ===
        await fireStepStart(.lyrics)
        let lyricsStart = Date()
        
        let lines = await lyricsModule.loadLyrics(for: track)
        let lyricsFound = !lines.isEmpty
        let refrainLines = await lyricsModule.refrainLines.map { $0.text }
        let keywords = await lyricsModule.keywords
        let plainLyrics = lines.map { $0.text }.joined(separator: "\n")
        
        stepTimings["lyrics"] = Int(Date().timeIntervalSince(lyricsStart) * 1000)
        
        if lyricsFound {
            stepsCompleted.append("lyrics")
            await fireStepComplete(.lyrics, ["line_count": lines.count])
        } else {
            stepsSkipped.append("lyrics")
            await fireStepComplete(.lyrics, ["skipped": true])
        }
        
        // === STEP 2: AI Analysis ===
        await fireStepStart(.ai)
        let aiStart = Date()
        
        var analysis: SongAnalysis?
        if lyricsFound {
            analysis = await aiModule.analyze(track: track, lyrics: plainLyrics)
            stepsCompleted.append("ai")
        } else {
            // Run basic categorization without lyrics
            let _ = await aiModule.categorize(track: track, lyrics: nil)
            analysis = await aiModule.currentAnalysis
            if analysis != nil {
                stepsCompleted.append("ai")
            } else {
                stepsSkipped.append("ai")
            }
        }
        
        stepTimings["ai"] = Int(Date().timeIntervalSince(aiStart) * 1000)
        await fireStepComplete(.ai, ["mood": analysis?.mood ?? "unknown"])
        
        // === STEP 3: Shaders (parallel with images) ===
        var shaderMatch: ShaderMatchResult?
        var imageResult: ImageResult?
        
        await withTaskGroup(of: Void.self) { group in
            // Shader matching
            if let shadersModule = shadersModule, analysis != nil {
                group.addTask {
                    await self.fireStepStart(.shaders)
                    let shaderStart = Date()
                    
                    shaderMatch = await shadersModule.selectForSong(
                        categories: nil,
                        energy: analysis?.energy ?? 0.5,
                        valence: analysis?.valence ?? 0.0
                    )
                    
                    stepTimings["shaders"] = Int(Date().timeIntervalSince(shaderStart) * 1000)
                    
                    if shaderMatch != nil {
                        stepsCompleted.append("shaders")
                        await self.fireStepComplete(.shaders, ["shader": shaderMatch?.name ?? ""])
                    } else {
                        stepsSkipped.append("shaders")
                        await self.fireStepComplete(.shaders, ["skipped": true])
                    }
                }
            }
            
            // Image fetching
            if let imagesModule = imagesModule, analysis != nil {
                group.addTask {
                    await self.fireStepStart(.images)
                    let imagesStart = Date()
                    
                    imageResult = await imagesModule.fetchImages(
                        for: track,
                        visualAdjectives: analysis?.visualAdjectives ?? [],
                        themes: analysis?.themes ?? [],
                        mood: analysis?.mood ?? "unknown"
                    )
                    
                    stepTimings["images"] = Int(Date().timeIntervalSince(imagesStart) * 1000)
                    
                    if imageResult != nil {
                        stepsCompleted.append("images")
                        await self.fireStepComplete(.images, ["count": imageResult?.totalImages ?? 0])
                    } else {
                        stepsSkipped.append("images")
                        await self.fireStepComplete(.images, ["skipped": true])
                    }
                }
            }
        }
        
        // === STEP 4: OSC Broadcast ===
        await fireStepStart(.osc)
        let oscStart = Date()
        
        if let hub = oscHub {
            await sendToOSC(hub: hub, track: track, lines: lines, analysis: analysis, shader: shaderMatch, images: imageResult)
            stepsCompleted.append("osc")
        } else {
            stepsSkipped.append("osc")
        }
        
        stepTimings["osc"] = Int(Date().timeIntervalSince(oscStart) * 1000)
        await fireStepComplete(.osc, [:])
        
        // Build result
        let totalTimeMs = Int(Date().timeIntervalSince(startTime) * 1000)
        
        let result = PipelineResult(
            artist: track.artist,
            title: track.title,
            album: track.album,
            success: lyricsFound || analysis != nil,
            lyricsFound: lyricsFound,
            lyricsLineCount: lines.count,
            lyricsLines: lines,
            refrainLines: refrainLines,
            lyricsKeywords: keywords,
            metadataFound: analysis != nil,
            plainLyrics: plainLyrics,
            keywords: analysis?.keywords ?? [],
            themes: analysis?.themes ?? [],
            visualAdjectives: analysis?.visualAdjectives ?? [],
            aiAvailable: analysis != nil,
            mood: analysis?.mood ?? "unknown",
            energy: analysis?.energy ?? 0.5,
            valence: analysis?.valence ?? 0.0,
            categories: analysis?.categories ?? [:],
            shaderMatched: shaderMatch != nil,
            shaderName: shaderMatch?.name ?? "",
            shaderScore: shaderMatch?.score ?? 0.0,
            imagesFound: imageResult != nil,
            imagesFolder: imageResult?.folder.path ?? "",
            imagesCount: imageResult?.totalImages ?? 0,
            stepsCompleted: stepsCompleted,
            totalTimeMs: totalTimeMs
        )
        
        // Cache result
        resultCache[track.key] = result
        lastResult = result
        
        print("[Pipeline] Complete: \(track.title) in \(totalTimeMs)ms (\(stepsCompleted.count) steps)")
        await fireComplete(result)
        
        return result
    }
    
    /// Get last pipeline result
    public var currentResult: PipelineResult? {
        lastResult
    }
    
    /// Check if currently processing
    public var processing: Bool {
        isProcessing
    }
    
    /// Register step start callback
    public func onStepStart(_ callback: @escaping PipelineStepStartCallback) {
        stepStartCallbacks.append(callback)
    }
    
    /// Register step complete callback
    public func onStepComplete(_ callback: @escaping PipelineStepCompleteCallback) {
        stepCompleteCallbacks.append(callback)
    }
    
    /// Register complete callback
    public func onComplete(_ callback: @escaping PipelineCompleteCallback) {
        completeCallbacks.append(callback)
    }
    
    /// Clear cache
    public func clearCache() {
        resultCache.removeAll()
    }
    
    // MARK: - Private
    
    private func sendToOSC(hub: OSCHub, track: Track, lines: [LyricLine], analysis: SongAnalysis?, shader: ShaderMatchResult?, images: ImageResult?) async {
        // Send track info: /textler/track [active, source, artist, title, album, duration, has_lyrics]
        try? hub.sendToProcessing(
            "/textler/track",
            values: [
                Int32(1),  // active
                "pipeline",
                track.artist,
                track.title,
                track.album,
                Float32(track.duration),
                Int32(lines.isEmpty ? 0 : 1)
            ]
        )
        
        // Send lyrics reset: /textler/lyrics/reset
        try? hub.sendToProcessing("/textler/lyrics/reset")
        
        // Send each line: /textler/lyrics/line [index, time, text]
        for (index, line) in lines.enumerated() {
            try? hub.sendToProcessing(
                "/textler/lyrics/line",
                values: [Int32(index), Float32(line.timeSec), line.text]
            )
        }
        
        // Send refrain reset: /textler/refrain/reset
        try? hub.sendToProcessing("/textler/refrain/reset")
        
        // Send refrain lines: /textler/refrain/line [index, time, text]
        let refrainLines = lines.filter { $0.isRefrain }
        for (index, line) in refrainLines.enumerated() {
            try? hub.sendToProcessing(
                "/textler/refrain/line",
                values: [Int32(index), Float32(line.timeSec), line.text]
            )
        }
        
        // Send analysis if available
        if let analysis = analysis {
            try? hub.sendToProcessing(
                "/ai/analysis",
                values: [
                    analysis.mood,
                    Float32(analysis.energy),
                    Float32(analysis.valence)
                ]
            )
        }
        
        // Send shader if matched: /shader/load [name, energy, valence]
        if let shader = shader {
            try? hub.sendToProcessing(
                "/shader/load",
                values: [
                    shader.name,
                    Float32(shader.energyScore),
                    Float32(shader.moodValence)
                ]
            )
        }
        
        // Send image folder if available
        if let images = images {
            // Send fit mode first: /image/fit [mode]
            try? hub.sendToProcessing(
                "/image/fit",
                values: ["cover"]
            )
            // Send folder path: /image/folder [path]
            try? hub.sendToProcessing(
                "/image/folder",
                values: [images.folder.path]
            )
        }
    }
    
    private func fireStepStart(_ step: PipelineStep) async {
        for callback in stepStartCallbacks {
            await callback(step.rawValue)
        }
    }
    
    private func fireStepComplete(_ step: PipelineStep, _ info: [String: Any]) async {
        for callback in stepCompleteCallbacks {
            await callback(step.rawValue, info)
        }
    }
    
    private func fireComplete(_ result: PipelineResult) async {
        for callback in completeCallbacks {
            await callback(result)
        }
    }
}
