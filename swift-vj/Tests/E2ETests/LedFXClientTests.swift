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
        
        XCTAssertTrue(info.name.localizedCaseInsensitiveContains("ledfx"))
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

        let virtualId = try await requireVirtualId()
        
        let scene = LedFXScene(
            name: "Test Scene",
            virtuals: [
                virtualId: VirtualAction(action: .forceblack)
            ],
            active: false
        )
        
        // Create scene
        try await client.putScene(id: "test_scene", scene: scene)
        
        // Verify it was created
        let scenes = try await client.listScenes()
        let expectedId = "test_scene".replacingOccurrences(of: "_", with: "-")
        XCTAssertTrue(scenes["test_scene"] != nil || scenes[expectedId] != nil)
        
        // Clean up
        try? await client.deleteScene(id: "test_scene")
    }
    
    func testActivateScene_activatesScene() async throws {
        guard isLedFXAvailable else {
            throw XCTSkip("LedFX server not available")
        }

        let virtualId = try await requireVirtualId()
        
        // Create a test scene
        let scene = LedFXScene(
            name: "Test Activation",
            virtuals: [
                virtualId: VirtualAction(action: .forceblack)
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

        let virtualId = try await requireVirtualId()
        
        // Create a scene
        let scene = LedFXScene(
            name: "Test Delete",
            virtuals: [virtualId: VirtualAction(action: .forceblack)],
            active: false
        )
        
        try await client.putScene(id: "test_delete", scene: scene)
        
        // Delete it (some LedFX builds do not support delete)
        do {
            try await client.deleteScene(id: "test_delete")
        } catch {
            throw XCTSkip("LedFX delete API not supported")
        }
        
        // Verify it's gone if delete is supported
        let scenes = try await client.listScenes()
        let expectedId = "test_delete".replacingOccurrences(of: "_", with: "-")
        XCTAssertTrue(scenes["test_delete"] == nil && scenes[expectedId] == nil)
    }
    
    // MARK: - Virtual Device Tests
    
    func testListVirtuals_returnsVirtuals() async throws {
        guard isLedFXAvailable else {
            throw XCTSkip("LedFX server not available")
        }
        
        let virtuals = try await client.listVirtuals()
        
        XCTAssertNotNil(virtuals)
    }

    // MARK: - Helpers

    private func requireVirtualId() async throws -> String {
        let virtuals = try await client.listVirtuals()
        if let first = virtuals.keys.sorted().first {
            return first
        }
        throw XCTSkip("No LedFX virtuals available")
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
