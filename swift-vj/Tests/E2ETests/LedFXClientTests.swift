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
    
    func testCreateScene_createsScene() async throws {
        guard isLedFXAvailable else {
            throw XCTSkip("LedFX server not available")
        }

        let virtualId = try await requireVirtualId()
        
        let scene = LedFXScene(
            name: "Test Scene \(UUID().uuidString)",
            virtuals: [
                virtualId: VirtualAction(action: .forceblack)
            ],
            active: false
        )
        
        // Create scene
        let sceneId = try await client.createScene(scene: scene)
        
        // Verify it was created
        let scenes = try await client.listScenes()
        XCTAssertNotNil(scenes[sceneId])
        
        // Clean up
        try? await client.deleteScene(id: sceneId)
    }
    
    func testActivateScene_activatesScene() async throws {
        guard isLedFXAvailable else {
            throw XCTSkip("LedFX server not available")
        }

        let virtualId = try await requireVirtualId()
        
        // Create a test scene
        let scene = LedFXScene(
            name: "Test Activation \(UUID().uuidString)",
            virtuals: [
                virtualId: VirtualAction(action: .forceblack)
            ],
            active: false
        )
        
        let sceneId = try await client.createScene(scene: scene)
        
        // Activate it
        try await client.activateScene(id: sceneId)
        
        // Note: Verification would require polling scene status
        // Clean up
        try? await client.deleteScene(id: sceneId)
    }
    
    func testDeleteScene_removesScene() async throws {
        guard isLedFXAvailable else {
            throw XCTSkip("LedFX server not available")
        }

        let virtualId = try await requireVirtualId()
        
        // Create a scene
        let scene = LedFXScene(
            name: "Test Delete \(UUID().uuidString)",
            virtuals: [virtualId: VirtualAction(action: .forceblack)],
            active: false
        )
        
        let sceneId = try await client.createScene(scene: scene)
        
        // Delete it (some LedFX builds do not support delete)
        do {
            try await client.deleteScene(id: sceneId)
        } catch {
            throw XCTSkip("LedFX delete API not supported")
        }
        
        // Verify it's gone if delete is supported
        let scenes = try await client.listScenes()
        XCTAssertNil(scenes[sceneId])
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
