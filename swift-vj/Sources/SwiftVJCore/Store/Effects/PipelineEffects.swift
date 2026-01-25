// PipelineEffects.swift - Pipeline processing effects
// Effects for track analysis pipeline

import Foundation

/// Dependencies needed by pipeline effects
public struct PipelineEnvironment: Sendable {
    public let lyricsModule: LyricsModule
    public let aiModule: AIModule
    public let shadersModule: ShadersModule?
    public let imagesModule: ImagesModule?
    public let oscHub: OSCHub?

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
}

/// Effects for pipeline processing
public enum PipelineEffectsImpl {

    /// Process a track through the full pipeline
    public static func processTrack(
        _ track: Track,
        environment: PipelineEnvironment
    ) -> Effect<AppAction> {
        .run(cancellationId: EffectCancellationId.pipeline) { send in
            let startTime = Date()

            // Step 1: Lyrics
            await send(.pipeline(.stepStarted("lyrics")))
            let lines = await environment.lyricsModule.loadLyrics(for: track)
            let lrcLyricsFound = !lines.isEmpty
            let refrainLines = await environment.lyricsModule.refrainLines.map { $0.text }
            var keywords = await environment.lyricsModule.keywords
            let plainLyrics = lines.map { $0.text }.joined(separator: "\n")

            if lrcLyricsFound {
                let refrainCount = lines.filter { $0.isRefrain }.count
                let kwCount = lines.filter { !$0.keywords.isEmpty }.count
                await send(.pipeline(.stepCompleted("lyrics", .lyrics(
                    lineCount: lines.count,
                    refrainCount: refrainCount,
                    keywordCount: kwCount
                ))))
            } else {
                await send(.pipeline(.stepCompleted("lyrics", .skipped(reason: "pending LLM"))))
            }

            // Step 2: AI Analysis
            await send(.pipeline(.stepStarted("ai")))
            let analysis = await environment.aiModule.analyze(track: track, lyrics: plainLyrics)

            // Update keywords from AI if lyrics didn't have them
            if !lrcLyricsFound && !analysis.keywords.isEmpty {
                keywords = analysis.keywords.flatMap { $0.split(separator: " ").map(String.init) }
            }

            await send(.pipeline(.stepCompleted("ai", .ai(
                mood: analysis.mood,
                energy: analysis.energy,
                valence: analysis.valence,
                keywords: analysis.keywords,
                themes: analysis.themes
            ))))

            // Step 3 & 4: Shaders + Images (parallel)
            var shaderMatch: ShaderMatchResult?
            var imageResult: ImageResult?

            enum ParallelStepResult: Sendable {
                case shaders(ShaderMatchResult?)
                case images(ImageResult?)
            }

            await withTaskGroup(of: ParallelStepResult.self) { group in
                // Shader matching
                if let shadersModule = environment.shadersModule {
                    group.addTask {
                        await send(.pipeline(.stepStarted("shaders")))
                        let match = await shadersModule.selectForSong(
                            categories: nil,
                            energy: analysis.energy,
                            valence: analysis.valence
                        )
                        if let match = match {
                            await send(.pipeline(.stepCompleted("shaders", .shaders(
                                name: match.name,
                                score: match.score
                            ))))
                            return .shaders(match)
                        }
                        await send(.pipeline(.stepCompleted("shaders", .skipped(reason: "No match"))))
                        return .shaders(nil)
                    }
                }

                // Image fetching
                if let imagesModule = environment.imagesModule {
                    group.addTask {
                        await send(.pipeline(.stepStarted("images")))
                        let result = await imagesModule.fetchImages(
                            for: track,
                            visualAdjectives: analysis.visualAdjectives,
                            themes: analysis.themes,
                            mood: analysis.mood
                        )
                        if let result = result {
                            await send(.pipeline(.stepCompleted("images", .images(
                                count: result.totalImages,
                                folder: result.folder.path,
                                source: result.source,
                                cached: result.cached
                            ))))
                            return .images(result)
                        }
                        await send(.pipeline(.stepCompleted("images", .skipped(reason: "No images"))))
                        return .images(nil)
                    }
                }

                for await result in group {
                    switch result {
                    case .shaders(let match):
                        shaderMatch = match
                    case .images(let result):
                        imageResult = result
                    }
                }
            }

            // Step 5: OSC Broadcast
            await send(.pipeline(.stepStarted("osc")))
            if let hub = environment.oscHub {
                await sendPipelineToOSC(
                    hub: hub,
                    track: track,
                    lines: lines,
                    analysis: analysis,
                    shader: shaderMatch,
                    images: imageResult
                )
                await send(.pipeline(.stepCompleted("osc", .osc(sent: true))))
            } else {
                await send(.pipeline(.stepCompleted("osc", .osc(sent: false))))
            }

            // Build final result
            let totalTimeMs = Int(Date().timeIntervalSince(startTime) * 1000)
            let lyricsFound = lrcLyricsFound

            var stepsCompleted: [String] = ["ai"]
            if lyricsFound { stepsCompleted.insert("lyrics", at: 0) }
            if shaderMatch != nil { stepsCompleted.append("shaders") }
            if imageResult != nil { stepsCompleted.append("images") }
            if environment.oscHub != nil { stepsCompleted.append("osc") }

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

            await send(.pipeline(.processingCompleted(result)))
        }
    }

    /// Clear pipeline cache
    public static func clearCache(pipelineModule: PipelineModule?) -> Effect<AppAction> {
        .fireAndForget {
            await pipelineModule?.clearCache()
        }
    }

    // MARK: - Private

    private static func sendPipelineToOSC(
        hub: OSCHub,
        track: Track,
        lines: [LyricLine],
        analysis: SongAnalysis,
        shader: ShaderMatchResult?,
        images: ImageResult?
    ) async {
        // Send track info
        try? hub.sendToMagic(
            "/textler/track",
            values: [
                Int32(1),
                "pipeline",
                track.artist,
                track.title,
                track.album,
                Float32(track.duration),
                Int32(lines.isEmpty ? 0 : 1)
            ]
        )

        // Send lyrics
        try? hub.sendToMagic("/textler/lyrics/reset")
        for (index, line) in lines.enumerated() {
            try? hub.sendToMagic(
                "/textler/lyrics/line",
                values: [Int32(index), Float32(line.timeSec), line.text]
            )
        }

        // Send refrain
        try? hub.sendToMagic("/textler/refrain/reset")
        let refrainLines = lines.filter { $0.isRefrain }
        for (index, line) in refrainLines.enumerated() {
            try? hub.sendToMagic(
                "/textler/refrain/line",
                values: [Int32(index), Float32(line.timeSec), line.text]
            )
        }

        // Send keywords
        try? hub.sendToMagic("/textler/keywords/reset")
        for (index, line) in lines.enumerated() {
            if !line.keywords.isEmpty {
                try? hub.sendToMagic(
                    "/textler/keywords/line",
                    values: [Int32(index), Float32(line.timeSec), line.keywords]
                )
            }
        }

        // Send metadata
        let keywordsJoined = analysis.keywords.joined(separator: ",")
        if !keywordsJoined.isEmpty {
            try? hub.sendToMagic("/textler/metadata/keywords", values: [keywordsJoined])
        }

        let themesJoined = analysis.themes.joined(separator: ",")
        if !themesJoined.isEmpty {
            try? hub.sendToMagic("/textler/metadata/themes", values: [themesJoined])
        }

        let visualsJoined = analysis.visualAdjectives.joined(separator: ",")
        if !visualsJoined.isEmpty {
            try? hub.sendToMagic("/textler/metadata/visuals", values: [visualsJoined])
        }

        if !analysis.mood.isEmpty {
            try? hub.sendToMagic("/textler/metadata/mood", values: [analysis.mood])
        }

        // Send AI analysis
        try? hub.sendToMagic(
            "/ai/analysis",
            values: [analysis.mood, Float32(analysis.energy), Float32(analysis.valence)]
        )

        // Send shader
        if let shader = shader {
            try? hub.sendToMagic(
                "/shader/load",
                values: [shader.name, Float32(shader.energyScore), Float32(shader.moodValence)]
            )
        }

        // Send images
        if let images = images {
            try? hub.sendToMagic("/image/fit", values: ["cover"])
            try? hub.sendToMagic("/image/folder", values: [images.folder.path])
        }
    }
}
