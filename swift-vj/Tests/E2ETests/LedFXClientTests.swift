// LedFXClientTests.swift - Integration tests for LedFX client
// Following TDD: Test behaviors, skip if LedFX unavailable

import XCTest
@testable import SwiftVJCore

final class LedFXClientTests: XCTestCase {
    
    var client: LedFXClient!
    var isLedFXAvailable = false
    
    override func setUp() async throws {
        client = LedFXClient(baseURL: "http://127.0.0.1:8888")
        
        // Test if LedFX is available
        do {
            _ = try await client.getInfo()
            isLedFXAvailable = true
        } catch {
            isLedFXAvailable = false
        }
    }
    
    // MARK: - Connection Tests
    
    func testGetInfo_returnsServerInfo() async throws {
        guard isLedFXAvailable else {
            throw XCTSkip("LedFX server not available at http://127.0.0.1:8888")
        }
        
        let info = try await client.getInfo()
        
        XCTAssertEqual(info.name, "LedFx")
        XCTAssertFalse(info.version.isEmpty)
        XCTAssertFalse(info.url.isEmpty)
    }
    
    // MARK: - Scene Tests
    
    func testListScenes_returnsScenes() async throws {
        guard isLedFXAvailable else {
            throw XCTSkip("LedFX server not available")
        }
        
        let scenes = try await client.listScenes()
        
        // Should return at least an empty dictionary
        XCTAssertNotNil(scenes)
    }
    
    func testPutScene_createsScene() async throws {
        guard isLedFXAvailable else {
            throw XCTSkip("LedFX server not available")
        }
        
        let scene = LedFXScene(
            name: "Test Scene",
            virtuals: [
                "virtual-1": VirtualAction(action: .forceblack)
            ],
            active: false
        )
        
        // Create scene
        try await client.putScene(id: "test_scene", scene: scene)
        
        // Verify it was created
        let scenes = try await client.listScenes()
        XCTAssertNotNil(scenes["test_scene"])
        
        // Clean up
        try? await client.deleteScene(id: "test_scene")
    }
    
    func testActivateScene_activatesScene() async throws {
        guard isLedFXAvailable else {
            throw XCTSkip("LedFX server not available")
        }
        
        // Create a test scene
        let scene = LedFXScene(
            name: "Test Activation",
            virtuals: [
                "virtual-1": VirtualAction(action: .forceblack)
            ],
            active: false
        )
        
        try await client.putScene(id: "test_activate", scene: scene)
        
        // Activate it
        try await client.activateScene(id: "test_activate")
        
        // Note: Verification would require polling scene status
        // Clean up
        try? await client.deleteScene(id: "test_activate")
    }
    
    func testDeleteScene_removesScene() async throws {
        guard isLedFXAvailable else {
            throw XCTSkip("LedFX server not available")
        }
        
        // Create a scene
        let scene = LedFXScene(
            name: "Test Delete",
            virtuals: [:],
            active: false
        )
        
        try await client.putScene(id: "test_delete", scene: scene)
        
        // Delete it
        try await client.deleteScene(id: "test_delete")
        
        // Verify it's gone
        let scenes = try await client.listScenes()
        XCTAssertNil(scenes["test_delete"])
    }
    
    // MARK: - Virtual Device Tests
    
    func testListVirtuals_returnsVirtuals() async throws {
        guard isLedFXAvailable else {
            throw XCTSkip("LedFX server not available")
        }
        
        let virtuals = try await client.listVirtuals()
        
        XCTAssertNotNil(virtuals)
    }
    
    // MARK: - Error Handling
    
    func testGetInfo_withInvalidURL_throwsError() async throws {
        let invalidClient = LedFXClient(baseURL: "http://localhost:9999")
        
        do {
            _ = try await invalidClient.getInfo()
            XCTFail("Should have thrown an error")
        } catch {
            // Expected error
            XCTAssertTrue(error is LedFXError || error is URLError)
        }
    }
}
