// ImagesModuleTests - Tests for image module behavior

import XCTest
@testable import SwiftVJCore

final class ImagesModuleTests: XCTestCase {
    
    // MARK: - Lifecycle Tests
    
    func testModuleStartsNotRunning() async throws {
        let module = ImagesModule()
        let started = await module.isStarted
        XCTAssertFalse(started)
    }
    
    func testModuleCanStart() async throws {
        let module = ImagesModule()
        try await module.start()
        let started = await module.isStarted
        XCTAssertTrue(started)
    }
    
    func testModuleCanStop() async throws {
        let module = ImagesModule()
        try await module.start()
        await module.stop()
        let started = await module.isStarted
        XCTAssertFalse(started)
    }
    
    func testDoubleStartThrows() async throws {
        let module = ImagesModule()
        try await module.start()
        
        do {
            try await module.start()
            XCTFail("Should throw on double start")
        } catch ModuleError.alreadyStarted {
            // Expected
        }
    }
    
    // MARK: - Status Tests
    
    func testGetStatusReturnsDict() async throws {
        let module = ImagesModule()
        let status = await module.getStatus()
        
        XCTAssertNotNil(status["started"])
        XCTAssertEqual(status["started"] as? Bool, false)
    }
    
    func testStatusReflectsStarted() async throws {
        let module = ImagesModule()
        try await module.start()
        
        let status = await module.getStatus()
        XCTAssertEqual(status["started"] as? Bool, true)
    }
    
    // MARK: - Fetch Tests
    
    func testCurrentResultStartsNil() async throws {
        let module = ImagesModule()
        let result = await module.currentResult
        XCTAssertNil(result)
    }
    
    func testGetFolderForTrack() async throws {
        let module = ImagesModule()
        let track = Track(artist: "Radiohead", title: "Paranoid Android")
        
        let dir = await module.getFolder(for: track)
        
        XCTAssertTrue(dir.path.contains("radiohead") || dir.path.contains("Radiohead"))
    }
}
