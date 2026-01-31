// LedFXTypesTests.swift - Tests for LedFX domain types
// Following TDD: Test data type behaviors

import XCTest
@testable import SwiftVJCore

final class LedFXTypesTests: XCTestCase {
    
    // MARK: - Scene Tests
    
    func testScene_codable_encodesAndDecodes() throws {
        let original = LedFXScene(
            name: "Test Scene",
            sceneImage: "image.png",
            sceneTags: "tag1,tag2",
            virtuals: [
                "virtual-1": VirtualAction(
                    action: .activate,
                    type: "scroll",
                    config: EffectConfig(["speed": .double(1.5)])
                )
            ],
            active: true
        )
        
        // Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        // Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(LedFXScene.self, from: data)
        
        // Verify
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.sceneImage, original.sceneImage)
        XCTAssertEqual(decoded.sceneTags, original.sceneTags)
        XCTAssertEqual(decoded.active, original.active)
        XCTAssertEqual(decoded.virtuals.count, 1)
    }
    
    func testScene_withActive_createsNewInstance() {
        let original = LedFXScene(
            name: "Test",
            virtuals: [:],
            active: false
        )
        
        let modified = original.withActive(true)
        
        XCTAssertFalse(original.active)
        XCTAssertTrue(modified.active)
        XCTAssertEqual(modified.name, original.name)
    }
    
    // MARK: - VirtualAction Tests
    
    func testVirtualAction_activate_hasTypeAndConfig() {
        let action = VirtualAction(
            action: .activate,
            type: "strobe",
            config: EffectConfig(["speed": .double(2.0)])
        )
        
        XCTAssertEqual(action.action, .activate)
        XCTAssertEqual(action.type, "strobe")
        XCTAssertNotNil(action.config)
    }
    
    func testVirtualAction_forceblack_hasNoTypeOrConfig() {
        let action = VirtualAction(action: .forceblack)
        
        XCTAssertEqual(action.action, .forceblack)
        XCTAssertNil(action.type)
        XCTAssertNil(action.config)
    }
    
    // MARK: - EffectConfig Tests
    
    func testEffectConfig_subscript_getsValue() {
        let config = EffectConfig([
            "brightness": .double(0.8),
            "color": .string("#FF0000")
        ])
        
        XCTAssertNotNil(config["brightness"])
        XCTAssertNotNil(config["color"])
        XCTAssertNil(config["nonexistent"])
    }
    
    func testEffectConfig_with_createsNewConfig() {
        let original = EffectConfig(["speed": .double(1.0)])
        
        let modified = original.with("speed", .double(2.0))
        
        // Original unchanged
        if case .double(let originalSpeed) = original["speed"] {
            XCTAssertEqual(originalSpeed, 1.0)
        }
        
        // Modified has new value
        if case .double(let modifiedSpeed) = modified["speed"] {
            XCTAssertEqual(modifiedSpeed, 2.0)
        }
    }
    
    func testEffectConfig_with_addsNewKey() {
        let original = EffectConfig(["speed": .double(1.0)])
        
        let modified = original.with("color", .string("#FF0000"))
        
        XCTAssertNil(original["color"])
        XCTAssertNotNil(modified["color"])
        XCTAssertNotNil(modified["speed"])
    }
    
    // MARK: - EffectValue Tests
    
    func testEffectValue_string_encodesAndDecodes() throws {
        let value = EffectValue.string("#FF0000")
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(EffectValue.self, from: data)
        
        if case .string(let str) = decoded {
            XCTAssertEqual(str, "#FF0000")
        } else {
            XCTFail("Should decode as string")
        }
    }
    
    func testEffectValue_double_encodesAndDecodes() throws {
        let value = EffectValue.double(1.5)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(EffectValue.self, from: data)
        
        if case .double(let num) = decoded {
            XCTAssertEqual(num, 1.5, accuracy: 0.01)
        } else {
            XCTFail("Should decode as double")
        }
    }
    
    func testEffectValue_int_encodesAndDecodes() throws {
        let value = EffectValue.int(42)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(EffectValue.self, from: data)
        
        if case .int(let num) = decoded {
            XCTAssertEqual(num, 42)
        } else {
            XCTFail("Should decode as int")
        }
    }
    
    func testEffectValue_bool_encodesAndDecodes() throws {
        let value = EffectValue.bool(true)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(EffectValue.self, from: data)
        
        if case .bool(let flag) = decoded {
            XCTAssertTrue(flag)
        } else {
            XCTFail("Should decode as bool")
        }
    }
    
    // MARK: - SceneActionRequest Tests
    
    func testSceneActionRequest_activate_encodesCorrectly() throws {
        let request = SceneActionRequest(id: "test", action: .activate)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        XCTAssertEqual(json?["id"] as? String, "test")
        XCTAssertEqual(json?["action"] as? String, "activate")
        XCTAssertNil(json?["activate_in"])
    }
    
    func testSceneActionRequest_activateWithDelay_encodesCorrectly() throws {
        let request = SceneActionRequest(id: "test", action: .activate, activateIn: 5)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        XCTAssertEqual(json?["id"] as? String, "test")
        XCTAssertEqual(json?["action"] as? String, "activate")
        XCTAssertEqual(json?["activate_in"] as? Int, 5)
    }
    
    // MARK: - OneshotRequest Tests
    
    func testOneshotRequest_hasDefaultValues() {
        let request = OneshotRequest(color: "#FF0000")
        
        XCTAssertEqual(request.tool, "oneshot")
        XCTAssertEqual(request.color, "#FF0000")
        XCTAssertEqual(request.ramp, 0)
        XCTAssertEqual(request.hold, 100)
        XCTAssertEqual(request.fade, 200)
        XCTAssertEqual(request.brightness, 1.0, accuracy: 0.01)
    }
    
    func testOneshotRequest_customValues() {
        let request = OneshotRequest(
            color: "#0000FF",
            ramp: 50,
            hold: 200,
            fade: 500,
            brightness: 0.5
        )
        
        XCTAssertEqual(request.color, "#0000FF")
        XCTAssertEqual(request.ramp, 50)
        XCTAssertEqual(request.hold, 200)
        XCTAssertEqual(request.fade, 500)
        XCTAssertEqual(request.brightness, 0.5, accuracy: 0.01)
    }
    
    // MARK: - LedFXInfo Tests
    
    func testLedFXInfo_equality() {
        let info1 = LedFXInfo(url: "http://localhost:8888", name: "LedFx", version: "1.0.0")
        let info2 = LedFXInfo(url: "http://localhost:8888", name: "LedFx", version: "1.0.0")
        let info3 = LedFXInfo(url: "http://localhost:8888", name: "LedFx", version: "2.0.0")
        
        XCTAssertEqual(info1, info2)
        XCTAssertNotEqual(info1, info3)
    }
}
