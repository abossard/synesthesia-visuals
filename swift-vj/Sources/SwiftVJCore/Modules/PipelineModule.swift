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
    private let cacheDir: URL
    private let cacheFile: URL
    
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
        oscHub: OSCHub? = nil,
        cacheDir: URL? = nil
    ) {
        self.lyricsModule = lyricsModule
        self.aiModule = aiModule
        self.shadersModule = shadersModule
        self.imagesModule = imagesModule
        self.oscHub = oscHub
        
        // Cache directory setup
        let dir = cacheDir ?? Config.cacheDirectory.appendingPathComponent("pipeline")
        self.cacheDir = dir
        self.cacheFile = dir.appendingPathComponent("pipeline_cache.json")
        
        // Create cache directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    
    // MARK: - Module Protocol
    
    public func start() async throws {
        guard !isStarted else { throw ModuleError.alreadyStarted }
        
        // Load cached results from disk
        loadCacheFromDisk()
        
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
        print("[Pipeline] Started (cache: \(resultCache.count) entries)")
    }
    
    public func stop() async {
        // Save cache to disk before stopping
        saveCacheToDisk()
        
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
        print("[Pipeline] ▶ Step 1/5: LYRICS - Fetching lyrics for \(track.artist) - \(track.title)")
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
            print("[Pipeline] ✓ Step 1/5: LYRICS - Found \(lines.count) lines, \(refrainLines.count) refrain (\(stepTimings["lyrics"] ?? 0)ms)")
            await fireStepComplete(.lyrics, ["line_count": lines.count, "status": "complete"])
        } else {
            stepsSkipped.append("lyrics")
            print("[Pipeline] ○ Step 1/5: LYRICS - No lyrics found (\(stepTimings["lyrics"] ?? 0)ms)")
            await fireStepComplete(.lyrics, ["skipped": true, "status": "skipped"])
        }
        
        // === STEP 2: AI Analysis ===
        print("[Pipeline] ▶ Step 2/5: AI - Analyzing song...")
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
        
        if let a = analysis {
            print("[Pipeline] ✓ Step 2/5: AI - mood=\(a.mood), energy=\(String(format: "%.2f", a.energy)), valence=\(String(format: "%.2f", a.valence)) (\(stepTimings["ai"] ?? 0)ms)")
            await fireStepComplete(.ai, ["mood": a.mood, "status": "complete"])
        } else {
            print("[Pipeline] ○ Step 2/5: AI - No analysis available (\(stepTimings["ai"] ?? 0)ms)")
            await fireStepComplete(.ai, ["skipped": true, "status": "skipped"])
        }
        
        // === STEP 3 & 4: Shaders + Images (parallel) ===
        var shaderMatch: ShaderMatchResult?
        var imageResult: ImageResult?
        
        print("[Pipeline] ▶ Steps 3-4: SHADERS+IMAGES (parallel)...")
        
        await withTaskGroup(of: Void.self) { group in
            // Shader matching
            if let shadersModule = shadersModule {
                group.addTask {
                    await self.fireStepStart(.shaders)
                    let shaderStart = Date()
                    
                    let energy = analysis?.energy ?? 0.5
                    let valence = analysis?.valence ?? 0.0
                    print("[Pipeline] ▶ Step 3/5: SHADERS - Matching (energy=\(String(format: "%.2f", energy)), valence=\(String(format: "%.2f", valence)))")
                    
                    shaderMatch = await shadersModule.selectForSong(
                        categories: nil,
                        energy: energy,
                        valence: valence
                    )
                    
                    stepTimings["shaders"] = Int(Date().timeIntervalSince(shaderStart) * 1000)
                    
                    if let match = shaderMatch {
                        stepsCompleted.append("shaders")
                        print("[Pipeline] ✓ Step 3/5: SHADERS - Matched '\(match.name)' (score=\(String(format: "%.2f", match.score))) (\(stepTimings["shaders"] ?? 0)ms)")
                        await self.fireStepComplete(.shaders, ["shader": match.name, "status": "complete"])
                    } else {
                        stepsSkipped.append("shaders")
                        print("[Pipeline] ○ Step 3/5: SHADERS - No match found (\(stepTimings["shaders"] ?? 0)ms)")
                        await self.fireStepComplete(.shaders, ["skipped": true, "status": "skipped"])
                    }
                }
            } else {
                print("[Pipeline] ○ Step 3/5: SHADERS - Module not configured")
                stepsSkipped.append("shaders")
            }
            
            // Image fetching
            if let imagesModule = imagesModule {
                group.addTask {
                    await self.fireStepStart(.images)
                    let imagesStart = Date()
                    
                    let visuals = analysis?.visualAdjectives ?? []
                    let themes = analysis?.themes ?? []
                    let mood = analysis?.mood ?? "unknown"
                    print("[Pipeline] ▶ Step 4/5: IMAGES - Fetching (visuals=\(visuals.prefix(3)), themes=\(themes.prefix(3)))")
                    
                    imageResult = await imagesModule.fetchImages(
                        for: track,
                        visualAdjectives: visuals,
                        themes: themes,
                        mood: mood
                    )
                    
                    stepTimings["images"] = Int(Date().timeIntervalSince(imagesStart) * 1000)
                    
                    if let result = imageResult {
                        stepsCompleted.append("images")
                        print("[Pipeline] ✓ Step 4/5: IMAGES - Fetched \(result.totalImages) images to \(result.folder.lastPathComponent) (\(stepTimings["images"] ?? 0)ms)")
                        await self.fireStepComplete(.images, ["count": result.totalImages, "status": "complete"])
                    } else {
                        stepsSkipped.append("images")
                        print("[Pipeline] ○ Step 4/5: IMAGES - No images fetched (\(stepTimings["images"] ?? 0)ms)")
                        await self.fireStepComplete(.images, ["skipped": true, "status": "skipped"])
                    }
                }
            } else {
                print("[Pipeline] ○ Step 4/5: IMAGES - Module not configured")
                stepsSkipped.append("images")
            }
        }
        
        // === STEP 5: OSC Broadcast ===
        print("[Pipeline] ▶ Step 5/5: OSC - Broadcasting results...")
        await fireStepStart(.osc)
        let oscStart = Date()
        
        if let hub = oscHub {
            await sendToOSC(hub: hub, track: track, lines: lines, analysis: analysis, shader: shaderMatch, images: imageResult)
            stepsCompleted.append("osc")
            stepTimings["osc"] = Int(Date().timeIntervalSince(oscStart) * 1000)
            print("[Pipeline] ✓ Step 5/5: OSC - Sent track, \(lines.count) lines, shader=\(shaderMatch?.name ?? "none") (\(stepTimings["osc"] ?? 0)ms)")
            await fireStepComplete(.osc, ["status": "complete"])
        } else {
            stepsSkipped.append("osc")
            stepTimings["osc"] = Int(Date().timeIntervalSince(oscStart) * 1000)
            print("[Pipeline] ○ Step 5/5: OSC - Hub not configured (\(stepTimings["osc"] ?? 0)ms)")
            await fireStepComplete(.osc, ["skipped": true, "status": "skipped"])
        }
        
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
        try? FileManager.default.removeItem(at: cacheFile)
    }
    
    /// Save cache to disk
    public func saveCache() {
        saveCacheToDisk()
    }
    
    // MARK: - Cache Serialization
    
    private func loadCacheFromDisk() {
        guard FileManager.default.fileExists(atPath: cacheFile.path) else {
            print("[Pipeline] No cache file found")
            return
        }
        
        do {
            let data = try Data(contentsOf: cacheFile)
            let decoder = JSONDecoder()
            let cacheData = try decoder.decode(PipelineCacheData.self, from: data)
            
            // Filter out expired entries
            let now = Date()
            var validCount = 0
            for entry in cacheData.entries {
                if now.timeIntervalSince(entry.cachedAt) < cacheTTL {
                    resultCache[entry.key] = entry.result
                    validCount += 1
                }
            }
            
            print("[Pipeline] Loaded \(validCount) cached results (filtered \(cacheData.entries.count - validCount) expired)")
        } catch {
            print("[Pipeline] Cache load error: \(error.localizedDescription)")
        }
    }
    
    private func saveCacheToDisk() {
        let entries = resultCache.map { key, result in
            CacheEntry(key: key, result: result, cachedAt: Date())
        }
        
        let cacheData = PipelineCacheData(entries: entries, savedAt: Date())
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(cacheData)
            try data.write(to: cacheFile)
            print("[Pipeline] Saved \(entries.count) cache entries to disk")
        } catch {
            print("[Pipeline] Cache save error: \(error.localizedDescription)")
        }
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
        
        // Send keywords reset: /textler/keywords/reset
        try? hub.sendToProcessing("/textler/keywords/reset")
        
        // Send keywords per line: /textler/keywords/line [index, time, keywords]
        for (index, line) in lines.enumerated() {
            if !line.keywords.isEmpty {
                try? hub.sendToProcessing(
                    "/textler/keywords/line",
                    values: [Int32(index), Float32(line.timeSec), line.keywords]
                )
            }
        }
        
        // Send metadata if available (from LLM analysis)
        if let analysis = analysis {
            // Keywords: /textler/metadata/keywords [comma-separated]
            let keywordsJoined = analysis.keywords.joined(separator: ",")
            if !keywordsJoined.isEmpty {
                try? hub.sendToProcessing("/textler/metadata/keywords", values: [keywordsJoined])
            }
            
            // Themes: /textler/metadata/themes [comma-separated]
            let themesJoined = analysis.themes.joined(separator: ",")
            if !themesJoined.isEmpty {
                try? hub.sendToProcessing("/textler/metadata/themes", values: [themesJoined])
            }
            
            // Visual adjectives for VJ: /textler/metadata/visuals [comma-separated]
            let visualsJoined = analysis.visualAdjectives.joined(separator: ",")
            if !visualsJoined.isEmpty {
                try? hub.sendToProcessing("/textler/metadata/visuals", values: [visualsJoined])
            }
            
            // Mood: /textler/metadata/mood [string]
            if !analysis.mood.isEmpty {
                try? hub.sendToProcessing("/textler/metadata/mood", values: [analysis.mood])
            }
            
            // AI analysis summary: /ai/analysis [mood, energy, valence]
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
