// Phase 3 Module Tests - TDD for module behaviors
// Tests verify module contracts and interactions

import XCTest
@testable import SwiftVJCore

final class PlaybackModuleTests: XCTestCase {
    
    func testStartSetsIsStarted() async throws {
        let module = PlaybackModule()
        
        let beforeStatus = await module.getStatus()
        XCTAssertEqual(beforeStatus["started"] as? Bool, false)
        
        try await module.start()
        
        let afterStatus = await module.getStatus()
        XCTAssertEqual(afterStatus["started"] as? Bool, true)
        
        await module.stop()
        
        let stoppedStatus = await module.getStatus()
        XCTAssertEqual(stoppedStatus["started"] as? Bool, false)
    }
    
    func testDoubleStartThrows() async throws {
        let module = PlaybackModule()
        try await module.start()
        
        do {
            try await module.start()
            XCTFail("Should throw")
        } catch ModuleError.alreadyStarted {
            // Expected
        }
        
        await module.stop()
    }
    
    func testGetStatusReturnsModuleState() async throws {
        let module = PlaybackModule()
        try await module.start()
        
        let status = await module.getStatus()
        XCTAssertNotNil(status["started"])
        XCTAssertEqual(status["started"] as? Bool, true)
        XCTAssertNotNil(status["source"])
        
        await module.stop()
    }
}

final class LyricsModuleTests: XCTestCase {
    
    func testStartAndStop() async throws {
        let fetcher = LyricsFetcher()
        let module = LyricsModule(fetcher: fetcher)
        
        try await module.start()
        let startStatus = await module.getStatus()
        XCTAssertEqual(startStatus["started"] as? Bool, true)
        
        await module.stop()
        let stopStatus = await module.getStatus()
        XCTAssertEqual(stopStatus["started"] as? Bool, false)
    }
    
    func testLoadLyricsReturnsEmptyForUnknownTrack() async throws {
        let fetcher = LyricsFetcher()
        let module = LyricsModule(fetcher: fetcher)
        try await module.start()
        
        let track = Track(artist: "Unknown Artist XYZ", title: "Unknown Song 123")
        let lines = await module.loadLyrics(for: track)
        
        XCTAssertTrue(lines.isEmpty)
        
        await module.stop()
    }
}

final class AIModuleTests: XCTestCase {
    
    func testStartAndStop() async throws {
        let module = AIModule()
        
        try await module.start()
        let startStatus = await module.getStatus()
        XCTAssertEqual(startStatus["started"] as? Bool, true)
        
        await module.stop()
        let stopStatus = await module.getStatus()
        XCTAssertEqual(stopStatus["started"] as? Bool, false)
    }
    
    func testAnalyzeReturnsResult() async throws {
        let module = AIModule()
        try await module.start()
        
        let track = Track(artist: "Test", title: "Song")
        let lyrics = "Hello world, this is a test song"
        
        let result = await module.analyze(track: track, lyrics: lyrics)
        
        XCTAssertFalse(result.mood.isEmpty)
        
        await module.stop()
    }
    
    func testStatusIncludesBackendInfo() async throws {
        let module = AIModule()
        
        let status = await module.getStatus()
        XCTAssertNotNil(status["backend"])
        XCTAssertNotNil(status["started"])
    }
}

final class PipelineModuleTests: XCTestCase {
    
    private func createPipeline() -> PipelineModule {
        let fetcher = LyricsFetcher()
        let lyrics = LyricsModule(fetcher: fetcher)
        let ai = AIModule()
        return PipelineModule(lyricsModule: lyrics, aiModule: ai)
    }
    
    func testStartStartsDependencies() async throws {
        let pipeline = createPipeline()
        
        try await pipeline.start()
        let startStatus = await pipeline.getStatus()
        XCTAssertEqual(startStatus["started"] as? Bool, true)
        
        await pipeline.stop()
        let stopStatus = await pipeline.getStatus()
        XCTAssertEqual(stopStatus["started"] as? Bool, false)
    }
    
    func testProcessReturnsResult() async throws {
        let pipeline = createPipeline()
        try await pipeline.start()
        
        let track = Track(artist: "Test", title: "Song", duration: 180)
        let result = await pipeline.process(track: track)
        
        XCTAssertEqual(result.artist, "Test")
        XCTAssertEqual(result.title, "Song")
        XCTAssertGreaterThan(result.totalTimeMs, 0)
        
        await pipeline.stop()
    }
    
    func testProcessCachesResult() async throws {
        let pipeline = createPipeline()
        try await pipeline.start()
        
        let track = Track(artist: "CacheTest", title: "Song")
        
        let first = await pipeline.process(track: track)
        XCTAssertEqual(first.artist, "CacheTest")
        
        let start = Date()
        let second = await pipeline.process(track: track)
        let elapsed = Date().timeIntervalSince(start)
        
        XCTAssertEqual(second.artist, "CacheTest")
        XCTAssertLessThan(elapsed, 0.1)
        
        await pipeline.stop()
    }
    
    func testStatusShowsProcessingState() async throws {
        let pipeline = createPipeline()
        try await pipeline.start()
        
        let status = await pipeline.getStatus()
        XCTAssertEqual(status["started"] as? Bool, true)
        XCTAssertEqual(status["processing"] as? Bool, false)
        XCTAssertEqual(status["cache_size"] as? Int, 0)
        
        await pipeline.stop()
    }
}

final class ModuleRegistryTests: XCTestCase {
    
    func testRegisterAndRetrieve() async throws {
        let registry = ModuleRegistry()
        let module = PlaybackModule()
        
        await registry.register(name: "playback", module: module)
        
        let hasPlayback = await registry.has("playback")
        let hasUnknown = await registry.has("unknown")
        
        XCTAssertTrue(hasPlayback)
        XCTAssertFalse(hasUnknown)
        
        let retrieved = await registry.get("playback", as: PlaybackModule.self)
        XCTAssertNotNil(retrieved)
    }
    
    func testStartAllStartsModules() async throws {
        let registry = ModuleRegistry()
        let playback = PlaybackModule()
        let ai = AIModule()
        
        await registry.register(name: "playback", module: playback)
        await registry.register(name: "ai", module: ai)
        
        try await registry.startAll()
        
        let playbackStatus = await playback.getStatus()
        let aiStatus = await ai.getStatus()
        XCTAssertEqual(playbackStatus["started"] as? Bool, true)
        XCTAssertEqual(aiStatus["started"] as? Bool, true)
        
        await registry.stopAll()
        
        let playbackStopped = await playback.getStatus()
        let aiStopped = await ai.getStatus()
        XCTAssertEqual(playbackStopped["started"] as? Bool, false)
        XCTAssertEqual(aiStopped["started"] as? Bool, false)
    }
    
    func testDependenciesStartInOrder() async throws {
        let registry = ModuleRegistry()
        let playback = PlaybackModule()
        let ai = AIModule()
        
        await registry.register(name: "playback", module: playback)
        await registry.register(name: "ai", module: ai, dependencies: ["playback"])
        
        try await registry.startAll()
        
        let playbackStatus = await playback.getStatus()
        let aiStatus = await ai.getStatus()
        XCTAssertEqual(playbackStatus["started"] as? Bool, true)
        XCTAssertEqual(aiStatus["started"] as? Bool, true)
        
        await registry.stopAll()
    }
    
    func testMissingDependencyThrows() async throws {
        let registry = ModuleRegistry()
        let ai = AIModule()
        
        await registry.register(name: "ai", module: ai, dependencies: ["missing"])
        
        do {
            try await registry.startAll()
            XCTFail("Should throw for missing dependency")
        } catch {
            // Expected
        }
    }
    
    func testGetStatusReturnsAllModules() async throws {
        let registry = ModuleRegistry()
        await registry.register(name: "playback", module: PlaybackModule())
        await registry.register(name: "ai", module: AIModule())
        
        try await registry.startAll()
        
        let status = await registry.getStatus()
        XCTAssertEqual(status.count, 2)
        XCTAssertNotNil(status["playback"])
        XCTAssertNotNil(status["ai"])
        XCTAssertEqual(status["playback"]?["started"] as? Bool, true)
        
        await registry.stopAll()
    }
}
