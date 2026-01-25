// PipelineModule - Orchestrates full track processing
// Following A Philosophy of Software Design: deep module hiding complexity
// Unidirectional Data Flow: dispatches actions instead of callbacks

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
/// - `dispatch` - action dispatcher for unidirectional data flow
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

    // MARK: - Action Dispatcher (Unidirectional Data Flow)

    /// Action dispatcher - set this to integrate with Store
    public var dispatch: (@Sendable (AppAction) async -> Void)?
    
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
    }
    
    public func getStatus() -> ModuleStatus {
        var status = ModuleStatus([
            "started": .bool(isStarted),
            "processing": .bool(isProcessing),
            "cache_size": .int(resultCache.count)
        ])

        if let result = lastResult {
            status["last_track"] = .string("\(result.artist) - \(result.title)")
            status["last_success"] = .bool(result.success)
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
            lastResult = cached
            await fireComplete(cached)
            return cached
        }
        
        var stepsCompleted: [String] = []
        var stepsSkipped: [String] = []
        var stepTimings: [String: Int] = [:]
        
        // === STEP 1: Lyrics (LRC from LRCLIB) ===
        await fireStepStart(.lyrics)
        let lyricsStart = Date()
        
        let lines = await lyricsModule.loadLyrics(for: track)
        let lrcLyricsFound = !lines.isEmpty
        var refrainLines = await lyricsModule.refrainLines.map { $0.text }
        var keywords = await lyricsModule.keywords
        let plainLyrics = lines.map { $0.text }.joined(separator: "\n")
        
        stepTimings["lyrics"] = Int(Date().timeIntervalSince(lyricsStart) * 1000)
        
        if lrcLyricsFound {
            stepsCompleted.append("lyrics")
            let refrainCount = lines.filter { $0.isRefrain }.count
            let kwCount = lines.filter { !$0.keywords.isEmpty }.count
            await fireStepComplete(.lyrics, .lyrics(lineCount: lines.count, refrainCount: refrainCount, keywordCount: kwCount))
        }
        // If no LRC lyrics, leave step in "pending" state - AI step will update it
        
        // === STEP 2: AI Analysis (always runs) ===
        await fireStepStart(.ai)
        let aiStart = Date()
        
        let analysis = await aiModule.analyze(track: track, lyrics: plainLyrics)
        
        // If LRC didn't have lyrics but LLM found some, update data and step status
        if !lrcLyricsFound {
            if !analysis.keywords.isEmpty {
                keywords = analysis.keywords.flatMap { $0.split(separator: " ").map(String.init) }
            }
            if !analysis.refrainLines.isEmpty {
                refrainLines = analysis.refrainLines
            }
            if !analysis.keywords.isEmpty || !analysis.themes.isEmpty {
                stepsCompleted.append("lyrics")
                // Update lyrics step to show LLM provided the data
                await fireStepComplete(.lyrics, .lyrics(
                    lineCount: 0,
                    refrainCount: analysis.refrainLines.count,
                    keywordCount: analysis.keywords.count
                ))
            } else {
                stepsSkipped.append("lyrics")
                await fireStepComplete(.lyrics, .skipped(reason: "No lyrics found"))
            }
        }
        
        stepsCompleted.append("ai")
        stepTimings["ai"] = Int(Date().timeIntervalSince(aiStart) * 1000)
        await fireStepComplete(.ai, .ai(
            mood: analysis.mood,
            energy: analysis.energy,
            valence: analysis.valence,
            keywords: analysis.keywords,
            themes: analysis.themes
        ))
        
        // === STEP 3 & 4: Shaders + Images (parallel) ===
        var shaderMatch: ShaderMatchResult?
        var imageResult: ImageResult?

        enum ParallelStepResult: Sendable {
            case shaders(match: ShaderMatchResult?, timingMs: Int, completed: Bool)
            case images(result: ImageResult?, timingMs: Int, completed: Bool)
        }

        await withTaskGroup(of: ParallelStepResult.self) { group in
            // Shader matching
            if let shadersModule = shadersModule {
                group.addTask {
                    await self.fireStepStart(.shaders)
                    let shaderStart = Date()

                    let currentPhase = await EffectEnvironment.shared.currentPhaseProvider?()
                    
                    let match = await shadersModule.selectForSong(
                        categories: nil,
                        energy: analysis.energy,
                        valence: analysis.valence,
                        phase: currentPhase
                    )
                    let timingMs = Int(Date().timeIntervalSince(shaderStart) * 1000)

                    if let match = match {
                        await self.fireStepComplete(.shaders, .shaders(name: match.name, score: match.score))
                        return .shaders(match: match, timingMs: timingMs, completed: true)
                    }

                    await self.fireStepComplete(.shaders, .skipped(reason: "No match"))
                    return .shaders(match: nil, timingMs: timingMs, completed: false)
                }
            } else {
                stepsSkipped.append("shaders")
            }
            
            // Image fetching
            if let imagesModule = imagesModule {
                group.addTask {
                    await self.fireStepStart(.images)
                    let imagesStart = Date()

                    let result = await imagesModule.fetchImages(
                        for: track,
                        visualAdjectives: analysis.visualAdjectives,
                        themes: analysis.themes,
                        mood: analysis.mood
                    )
                    let timingMs = Int(Date().timeIntervalSince(imagesStart) * 1000)

                    if let result = result {
                        await self.fireStepComplete(.images, .images(
                            count: result.totalImages,
                            folder: result.folder.path,
                            source: result.source,
                            cached: result.cached
                        ))
                        return .images(result: result, timingMs: timingMs, completed: true)
                    }

                    await self.fireStepComplete(.images, .skipped(reason: "No images"))
                    return .images(result: nil, timingMs: timingMs, completed: false)
                }
            } else {
                stepsSkipped.append("images")
            }

            for await result in group {
                switch result {
                case .shaders(let match, let timingMs, let completed):
                    shaderMatch = match
                    stepTimings["shaders"] = timingMs
                    if completed {
                        stepsCompleted.append("shaders")
                    } else {
                        stepsSkipped.append("shaders")
                    }
                case .images(let result, let timingMs, let completed):
                    imageResult = result
                    stepTimings["images"] = timingMs
                    if completed {
                        stepsCompleted.append("images")
                    } else {
                        stepsSkipped.append("images")
                    }
                }
            }
        }

        // Ensure we always have a shader selection; fallback to random if needed
        if shaderMatch == nil, let shadersModule = shadersModule, let random = await shadersModule.randomShader() {
            shaderMatch = ShaderMatchResult(
                name: random.name,
                path: random.path,
                score: 0,
                energyScore: random.energyScore,
                moodValence: random.moodValence,
                mood: random.mood
            )
            stepsCompleted.append("shaders")
            await self.fireStepComplete(.shaders, .shaders(name: random.name, score: 0))
        }
        
        // === STEP 5: OSC Broadcast ===
        await fireStepStart(.osc)
        let oscStart = Date()
        
        if let hub = oscHub {
            await sendToOSC(hub: hub, track: track, lines: lines, analysis: analysis, shader: shaderMatch, images: imageResult)
            stepsCompleted.append("osc")
            stepTimings["osc"] = Int(Date().timeIntervalSince(oscStart) * 1000)
            await fireStepComplete(.osc, .osc(sent: true))
        } else {
            stepsSkipped.append("osc")
            stepTimings["osc"] = Int(Date().timeIntervalSince(oscStart) * 1000)
            await fireStepComplete(.osc, .osc(sent: false))
        }
        
        // Build result
        let totalTimeMs = Int(Date().timeIntervalSince(startTime) * 1000)
        
        // Lyrics found only counts when we have timecoded LRC lyrics
        let lyricsFound = lrcLyricsFound
        
        let result = PipelineResult(
            artist: track.artist,
            title: track.title,
            album: track.album,
            success: true,
            lyricsFound: lyricsFound,
            lyricsLineCount: lines.count,
            lyricsLines: lines,
            refrainLines: refrainLines,
            lyricsKeywords: keywords,
            metadataFound: true,
            plainLyrics: plainLyrics,
            keywords: analysis.keywords,
            themes: analysis.themes,
            visualAdjectives: analysis.visualAdjectives,
            aiAvailable: true,
            mood: analysis.mood,
            energy: analysis.energy,
            valence: analysis.valence,
            categories: analysis.categories,
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
    
    /// Set action dispatcher for Store integration
    public func setDispatch(_ dispatch: @escaping @Sendable (AppAction) async -> Void) {
        self.dispatch = dispatch
    }
    
    /// Clear cache
    public func clearCache() {
        resultCache.removeAll()
        try? FileManager.default.removeItem(at: cacheFile)
    }
    
    /// Clear cache for a specific song
    public func clearCacheForSong(artist: String, title: String) {
        let key = "\(artist)::\(title)"
        resultCache.removeValue(forKey: key)
        saveCacheToDisk()
    }
    
    /// Save cache to disk
    public func saveCache() {
        saveCacheToDisk()
    }
    
    // MARK: - Cache Serialization
    
    private func loadCacheFromDisk() {
        guard FileManager.default.fileExists(atPath: cacheFile.path) else {
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
        } catch {
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
        } catch {
            // Cache save error - silent
        }
    }
    
    // MARK: - Private
    
    private func sendToOSC(hub: OSCHub, track: Track, lines: [LyricLine], analysis: SongAnalysis, shader: ShaderMatchResult?, images: ImageResult?) async {
        // Send track info: /textler/track [active, source, artist, title, album, duration, has_lyrics]
        try? hub.sendToMagic(
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
        try? hub.sendToMagic("/textler/lyrics/reset")
        
        // Send each line: /textler/lyrics/line [index, time, text]
        for (index, line) in lines.enumerated() {
            try? hub.sendToMagic(
                "/textler/lyrics/line",
                values: [Int32(index), Float32(line.timeSec), line.text]
            )
        }
        
        // Send refrain reset: /textler/refrain/reset
        try? hub.sendToMagic("/textler/refrain/reset")
        
        // Send refrain lines: /textler/refrain/line [index, time, text]
        let refrainLines = lines.filter { $0.isRefrain }
        for (index, line) in refrainLines.enumerated() {
            try? hub.sendToMagic(
                "/textler/refrain/line",
                values: [Int32(index), Float32(line.timeSec), line.text]
            )
        }
        
        // Send keywords reset: /textler/keywords/reset
        try? hub.sendToMagic("/textler/keywords/reset")
        
        // Send keywords per line: /textler/keywords/line [index, time, keywords]
        for (index, line) in lines.enumerated() {
            if !line.keywords.isEmpty {
                try? hub.sendToMagic(
                    "/textler/keywords/line",
                    values: [Int32(index), Float32(line.timeSec), line.keywords]
                )
            }
        }
        
        // Send metadata from LLM analysis (always available now)
        // Keywords: /textler/metadata/keywords [comma-separated]
        let keywordsJoined = analysis.keywords.joined(separator: ",")
        if !keywordsJoined.isEmpty {
            try? hub.sendToMagic("/textler/metadata/keywords", values: [keywordsJoined])
        }
        
        // Themes: /textler/metadata/themes [comma-separated]
        let themesJoined = analysis.themes.joined(separator: ",")
        if !themesJoined.isEmpty {
            try? hub.sendToMagic("/textler/metadata/themes", values: [themesJoined])
        }
        
        // Visual adjectives for VJ: /textler/metadata/visuals [comma-separated]
        let visualsJoined = analysis.visualAdjectives.joined(separator: ",")
        if !visualsJoined.isEmpty {
            try? hub.sendToMagic("/textler/metadata/visuals", values: [visualsJoined])
        }
        
        // Mood: /textler/metadata/mood [string]
        if !analysis.mood.isEmpty {
            try? hub.sendToMagic("/textler/metadata/mood", values: [analysis.mood])
        }
        
        // AI analysis summary: /ai/analysis [mood, energy, valence]
        try? hub.sendToMagic(
            "/ai/analysis",
            values: [
                analysis.mood,
                Float32(analysis.energy),
                Float32(analysis.valence)
            ]
        )
        
        // Send shader if matched: /shader/load [name, energy, valence]
        if let shader = shader {
            try? hub.sendToMagic(
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
            try? hub.sendToMagic(
                "/image/fit",
                values: ["cover"]
            )
            // Send folder path: /image/folder [path]
            try? hub.sendToMagic(
                "/image/folder",
                values: [images.folder.path]
            )
        }
    }
    
    private func fireStepStart(_ step: PipelineStep) async {
        await dispatch?(.pipeline(.stepStarted(step.rawValue)))
    }

    private func fireStepComplete(_ step: PipelineStep, _ status: PipelineStepStatus) async {
        await dispatch?(.pipeline(.stepCompleted(step.rawValue, status)))
    }

    private func fireComplete(_ result: PipelineResult) async {
        await dispatch?(.pipeline(.processingCompleted(result)))
    }
}
