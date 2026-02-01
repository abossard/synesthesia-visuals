// OscRestBridgeTests.swift - End-to-end behavioral tests
// Tests observable behavior, not implementation details

import XCTest
@testable import OscRestBridge

final class OscRestBridgeTests: XCTestCase {
    
    // MARK: - Config Loading Tests
    
    func test_loadValidConfig_succeeds() async throws {
        // Given: A valid YAML config
        let yaml = """
        version: 1
        server:
          osc_listen:
            host: "0.0.0.0"
            port: 9000
          http:
            base_url: "http://127.0.0.1:8888"
            timeout_ms: 1500
            default_headers:
              Content-Type: "application/json"
        slots:
          "0":
            name: "main"
            targets:
              virtual_ids: ["virtual-1"]
        scenes:
          strobe:
            id: "strobe"
            on_activate:
              request:
                method: "PUT"
                path: "/api/scenes"
                body:
                  id: "strobe"
        oneshots: {}
        params: {}
        """
        
        // When: Load the config
        let config = try ConfigLoader.load(from: yaml)
        
        // Then: Config is valid
        XCTAssertEqual(config.version, 1)
        XCTAssertEqual(config.server.http.base_url, "http://127.0.0.1:8888")
        XCTAssertEqual(config.slots.count, 1)
        XCTAssertEqual(config.scenes.count, 1)
    }
    
    func test_loadInvalidConfig_fails() throws {
        // Given: Invalid YAML (missing required field)
        let yaml = """
        version: 1
        server:
          osc_listen:
            host: "0.0.0.0"
            port: 9000
        """
        
        // When/Then: Loading fails
        XCTAssertThrowsError(try ConfigLoader.load(from: yaml))
    }
    
    func test_validation_missingSlot() throws {
        // Given: Config with no slots
        let yaml = """
        version: 1
        server:
          osc_listen:
            host: "0.0.0.0"
            port: 9000
          http:
            base_url: "http://127.0.0.1:8888"
            timeout_ms: 1500
        slots: {}
        scenes: {}
        oneshots: {}
        params: {}
        """
        
        // When/Then: Validation fails
        do {
            _ = try ConfigLoader.load(from: yaml)
            XCTFail("Should have thrown")
        } catch ConfigLoader.LoadError.validationFailed(let errors) {
            XCTAssertTrue(errors.contains { $0.path == "slots" })
        }
    }
    
    // MARK: - OSC Route Parsing Tests
    
    func test_parseSceneRoute() {
        // Given: Scene OSC path
        let path = "/ledfx/scene/strobe/0"
        
        // When: Parse
        let parsed = OSCRouteParser.parse(path)
        
        // Then: Correctly parsed
        XCTAssertEqual(parsed, .scene(slot: "0", sceneName: "strobe"))
    }
    
    func test_parseOneshotRoute() {
        let parsed = OSCRouteParser.parse("/ledfx/oneshot/whiteflash/1")
        XCTAssertEqual(parsed, .oneshot(slot: "1", oneshotName: "whiteflash"))
    }
    
    func test_parseBlackoutRoute() {
        let parsed = OSCRouteParser.parse("/ledfx/blackout/0")
        XCTAssertEqual(parsed, .blackout(slot: "0"))
    }
    
    func test_parseParamRoute() {
        let parsed = OSCRouteParser.parse("/ledfx/param/strobe_speed/0")
        XCTAssertEqual(parsed, .param(slot: "0", paramName: "strobe_speed"))
    }
    
    func test_parseMalformedRoute_returnsNil() {
        XCTAssertNil(OSCRouteParser.parse("/wrong/path"))
        XCTAssertNil(OSCRouteParser.parse("/ledfx/unknown/name/0"))
        XCTAssertNil(OSCRouteParser.parse("/ledfx/scene/name"))  // Missing slot
    }
    
    // MARK: - Parameter Scaling Tests
    
    func test_scaleParameter_midiToRange() {
        // Given: MIDI config
        let scale = ParamScale(type: "linear", in_min: 0, in_max: 127, out_min: 0, out_max: 100)
        let input = ParamInput(accepted: ["midi_0_127"], default_mode: "midi_0_127")
        
        // When: Scale MIDI 63.5 (half of 127)
        let (scaled, mode) = ParameterScaling.scale(63.5, config: scale, inputConfig: input)
        
        // Then: Outputs approximately 50
        XCTAssertEqual(mode, "midi_0_127")
        XCTAssertEqual(scaled, 50.0, accuracy: 0.1)
    }
    
    func test_scaleParameter_squareCurve() {
        // Given: Square curve
        let scale = ParamScale(type: "curve", curve: "square", in_min: 0, in_max: 127, out_min: 0, out_max: 100)
        let input = ParamInput(accepted: ["midi_0_127"], default_mode: "midi_0_127")
        
        // When: Scale 63.5 (normalized 0.5)
        let (scaled, _) = ParameterScaling.scale(63.5, config: scale, inputConfig: input)
        
        // Then: 0.5^2 = 0.25 → 25
        XCTAssertEqual(scaled, 25.0, accuracy: 1.0)
    }
    
    func test_scaleParameter_expCurve() {
        // Given: Exponential curve
        let scale = ParamScale(type: "curve", curve: "exp", in_min: 0, in_max: 1, out_min: 0, out_max: 100)
        let input = ParamInput(accepted: ["normalized_0_1"], default_mode: "normalized_0_1")
        
        // When: Scale 0.5
        let (scaled, _) = ParameterScaling.scale(0.5, config: scale, inputConfig: input)
        
        // Then: Result is exponential (formula: (exp(4*0.5) - 1) / (exp(4) - 1))
        let expected = (exp(4 * 0.5) - 1) / (exp(4) - 1) * 100
        XCTAssertEqual(scaled, expected, accuracy: 0.1)
    }
    
    // MARK: - Template Engine Tests
    
    func test_templateInterpolation_sceneId() {
        let context = TemplateEngine.TemplateContext(sceneId: "strobe")
        let result = TemplateEngine.interpolate("Scene: ${scene.id}", context: context)
        XCTAssertEqual(result, "Scene: strobe")
    }
    
    func test_templateInterpolation_virtualId() {
        let context = TemplateEngine.TemplateContext(slotVirtualIds: ["virtual-1", "virtual-2"])
        let result = TemplateEngine.interpolate("/api/virtuals/${slot.targets.virtual_ids[0]}", context: context)
        XCTAssertEqual(result, "/api/virtuals/virtual-1")
    }
    
    func test_templateSubstitution_numericValue() {
        let context = TemplateEngine.TemplateContext(paramScaled: 42.5)
        let substituted = TemplateEngine.substituteJSON("${param.scaled}", context: context)
        
        // Should return numeric, not string
        XCTAssertEqual(substituted as? Double, 42.5)
    }
    
    // MARK: - JSON Patcher Tests
    
    func test_jsonPatcher_set() throws {
        let json: [String: Any] = ["config": ["speed": 1.0]]
        let context = TemplateEngine.TemplateContext(paramScaled: 5.5)
        let op = PatchOp(op: "set", pointer: "/config/speed", value: AnyCodable("${param.scaled}"))
        
        let result = try JSONPatcher.applyPatches([op], to: json, context: context)
        
        let config = result["config"] as? [String: Any]
        XCTAssertEqual(config?["speed"] as? Double, 5.5)
    }
    
    func test_jsonPatcher_merge() throws {
        let json: [String: Any] = ["config": ["speed": 1.0]]
        let context = TemplateEngine.TemplateContext()
        let op = PatchOp(op: "merge", pointer: "/config", value: AnyCodable(["brightness": 0.8]))
        
        let result = try JSONPatcher.applyPatches([op], to: json, context: context)
        
        let config = result["config"] as? [String: Any]
        XCTAssertEqual(config?["speed"] as? Double, 1.0)
        XCTAssertEqual(config?["brightness"] as? Double, 0.8)
    }
    
    func test_jsonPatcher_delete() throws {
        let json: [String: Any] = ["config": ["speed": 1.0, "extra": "value"]]
        let context = TemplateEngine.TemplateContext()
        let op = PatchOp(op: "delete", pointer: "/config/extra")
        
        let result = try JSONPatcher.applyPatches([op], to: json, context: context)
        
        let config = result["config"] as? [String: Any]
        XCTAssertNotNil(config?["speed"])
        XCTAssertNil(config?["extra"])
    }
}
