// ShadersModuleTests - Tests for shader selection with usage tracking

import XCTest
@testable import SwiftVJCore

final class ShadersModuleTests: XCTestCase {
    
    // MARK: - Lifecycle Tests
    
    func testModuleStartsNotRunning() async throws {
        let module = ShadersModule()
        let started = await module.isStarted
        XCTAssertFalse(started)
    }
    
    func testModuleCanStart() async throws {
        let module = ShadersModule()
        try await module.start()
        let started = await module.isStarted
        XCTAssertTrue(started)
    }
    
    func testModuleCanStop() async throws {
        let module = ShadersModule()
        try await module.start()
        await module.stop()
        let started = await module.isStarted
        XCTAssertFalse(started)
    }
    
    func testDoubleStartThrows() async throws {
        let module = ShadersModule()
        try await module.start()
        
        do {
            try await module.start()
            XCTFail("Should throw on double start")
        } catch ModuleError.alreadyStarted {
            // Expected
        }
    }
    
    // MARK: - Selection Tests
    
    func testSelectWithNoShadersReturnsNil() async throws {
        let module = ShadersModule()
        try await module.start()
        
        let result = await module.selectForSong(
            categories: nil,
            energy: 0.5,
            valence: 0.2
        )
        
        XCTAssertNil(result)
    }
    
    func testMatchWithNoShadersReturnsEmpty() async throws {
        let module = ShadersModule()
        try await module.start()
        
        let results = await module.match(energy: 0.7, valence: 0.3)
        
        XCTAssertTrue(results.isEmpty)
    }
    
    // MARK: - Usage Tracking
    
    func testResetUsageDoesNotCrash() async throws {
        let module = ShadersModule()
        await module.resetUsage()
        // Just verify no crash
    }
    
    func testGetStatusReturnsDict() async throws {
        let module = ShadersModule()
        let status = await module.getStatus()
        
        XCTAssertNotNil(status["started"])
    }
}
