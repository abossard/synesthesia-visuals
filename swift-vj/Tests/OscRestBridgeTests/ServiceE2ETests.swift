// ServiceE2ETests.swift - End-to-end service tests
// Tests complete flows with real behavior

import XCTest
@testable import OscRestBridge

final class ServiceE2ETests: XCTestCase {
    
    var httpClient: TestHTTPClient!
    var clock: TestClock!
    var service: OscRestBridgeService!
    
    override func setUp() async throws {
        httpClient = TestHTTPClient()
        clock = TestClock()
        service = OscRestBridgeService(
            httpClient: httpClient,
            clock: clock
        )
    }
    
    // MARK: - Scene Activation Tests
    
    func test_sceneActivate_sendsCorrectRequest() async throws {
        // Given: Service with config
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
            id: "strobe_scene"
            on_activate:
              request:
                method: "PUT"
                path: "/api/scenes"
                body:
                  id: "${scene.id}"
                  action: "activate"
        oneshots: {}
        params: {}
        """
        
        try await service.loadConfig(from: yaml.data(using: .utf8)!)
        try await service.start()
        
        // When: OSC scene activate message (simulated via direct call)
        await service.handleOSCMessage(path: "/ledfx/scene/strobe/0", values: [1.0])
        
        // Give async handlers time to run
        try await Task.sleep(for: .milliseconds(100))
        
        // Then: HTTP request sent
        let requests = await httpClient.requests
        XCTAssertEqual(requests.count, 1)
        
        let request = requests[0]
        XCTAssertEqual(request.method, "PUT")
        XCTAssertEqual(request.url, "http://127.0.0.1:8888/api/scenes")
        
        let body = try XCTUnwrap(request.body)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["id"] as? String, "strobe_scene")
        XCTAssertEqual(json?["action"] as? String, "activate")
    }
    
    func test_sceneDeactivate_whenEnabled_sendsRequest() async throws {
        // Given: Scene with deactivate enabled
        let yaml = """
        version: 1
        server:
          osc_listen:
            host: "0.0.0.0"
            port: 9000
          http:
            base_url: "http://localhost:8888"
            timeout_ms: 1500
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
                  action: "activate"
            on_deactivate:
              enabled: true
              request:
                method: "PUT"
                path: "/api/scenes"
                body:
                  action: "deactivate"
        oneshots: {}
        params: {}
        """
        
        try await service.loadConfig(from: yaml.data(using: .utf8)!)
        try await service.start()
        
        // When: OSC scene deactivate (value = 0)
        await service.handleOSCMessage(path: "/ledfx/scene/strobe/0", values: [0.0])
        try await Task.sleep(for: .milliseconds(100))
        
        // Then: Deactivate request sent
        let requests = await httpClient.requests
        XCTAssertEqual(requests.count, 1)
        
        let body = try XCTUnwrap(requests[0].body)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["action"] as? String, "deactivate")
    }
    
    func test_sceneDeactivate_whenDisabled_sendsNothing() async throws {
        // Given: Scene with deactivate disabled
        let yaml = """
        version: 1
        server:
          osc_listen:
            host: "0.0.0.0"
            port: 9000
          http:
            base_url: "http://localhost:8888"
            timeout_ms: 1500
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
                  action: "activate"
            on_deactivate:
              enabled: false
              request:
                method: "PUT"
                path: "/api/scenes"
                body:
                  action: "deactivate"
        oneshots: {}
        params: {}
        """
        
        try await service.loadConfig(from: yaml.data(using: .utf8)!)
        try await service.start()
        
        // When: OSC scene deactivate (value = 0)
        await service.handleOSCMessage(path: "/ledfx/scene/strobe/0", values: [0.0])
        try await Task.sleep(for: .milliseconds(100))
        
        // Then: No request sent
        let requests = await httpClient.requests
        XCTAssertEqual(requests.count, 0)
    }
    
    // MARK: - Oneshot Tests
    
    func test_oneshot_onlyTriggersOnPositive() async throws {
        let yaml = """
        version: 1
        server:
          osc_listen:
            host: "0.0.0.0"
            port: 9000
          http:
            base_url: "http://localhost:8888"
            timeout_ms: 1500
        slots:
          "0":
            name: "main"
            targets:
              virtual_ids: ["virtual-1"]
        scenes: {}
        oneshots:
          flash:
            request:
              method: "PUT"
              path: "/api/oneshot"
              body:
                trigger: true
        params: {}
        """
        
        try await service.loadConfig(from: yaml.data(using: .utf8)!)
        try await service.start()
        
        // When: Value = 0
        await service.handleOSCMessage(path: "/ledfx/oneshot/flash/0", values: [0.0])
        try await Task.sleep(for: .milliseconds(50))
        
        var requests = await httpClient.requests
        XCTAssertEqual(requests.count, 0)
        
        // When: Value > 0
        await service.handleOSCMessage(path: "/ledfx/oneshot/flash/0", values: [1.0])
        try await Task.sleep(for: .milliseconds(50))
        
        requests = await httpClient.requests
        XCTAssertEqual(requests.count, 1)
    }
    
    // MARK: - Blackout Tests
    
    func test_blackout_activatesBlackoutScene() async throws {
        let yaml = """
        version: 1
        server:
          osc_listen:
            host: "0.0.0.0"
            port: 9000
          http:
            base_url: "http://localhost:8888"
            timeout_ms: 1500
        slots:
          "0":
            name: "main"
            targets:
              virtual_ids: ["virtual-1"]
            blackout:
              scene: "blackout"
              restore_previous_scene: true
        scenes:
          blackout:
            id: "blackout"
            on_activate:
              request:
                method: "PUT"
                path: "/api/scenes"
                body:
                  id: "blackout"
                  action: "activate"
            on_deactivate:
              enabled: true
              request:
                method: "PUT"
                path: "/api/scenes"
                body:
                  id: "blackout"
                  action: "deactivate"
        oneshots: {}
        params: {}
        """
        
        try await service.loadConfig(from: yaml.data(using: .utf8)!)
        try await service.start()
        
        // When: Blackout activate
        await service.handleOSCMessage(path: "/ledfx/blackout/0", values: [1.0])
        try await Task.sleep(for: .milliseconds(100))
        
        // Then: Blackout scene activated
        let requests = await httpClient.requests
        XCTAssertEqual(requests.count, 1)
        
        let body = try XCTUnwrap(requests[0].body)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["action"] as? String, "activate")
        XCTAssertEqual(json?["id"] as? String, "blackout")
        
        // Check state
        let state = await service.getState()
        XCTAssertEqual(state.slotState["0"]?.blackoutActive, true)
    }
    
    // MARK: - Parameter Tests
    
    func test_param_scalingAndPatching() async throws {
        let yaml = """
        version: 1
        server:
          osc_listen:
            host: "0.0.0.0"
            port: 9000
          http:
            base_url: "http://localhost:8888"
            timeout_ms: 1500
        slots:
          "0":
            name: "main"
            targets:
              virtual_ids: ["virtual-1"]
        scenes: {}
        oneshots: {}
        params:
          speed:
            input:
              accepted: ["midi_0_127"]
              default_mode: "midi_0_127"
            scale:
              type: "linear"
              in_min: 0
              in_max: 127
              out_min: 1.0
              out_max: 10.0
            request:
              method: "PUT"
              path: "/api/effects/${slot.targets.virtual_ids[0]}"
              body_template:
                config:
                  speed: 5.0
              patch_ops:
                - op: "set"
                  pointer: "/config/speed"
                  value: "${param.scaled}"
        """
        
        try await service.loadConfig(from: yaml.data(using: .utf8)!)
        try await service.start()
        
        // When: MIDI value 63.5 (half of 127) → should map to 5.5 (middle of 1..10)
        await service.handleOSCMessage(path: "/ledfx/param/speed/0", values: [63.5])
        try await Task.sleep(for: .milliseconds(100))
        
        // Then: Request with scaled value
        let requests = await httpClient.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].url, "http://localhost:8888/api/effects/virtual-1")
        
        let body = try XCTUnwrap(requests[0].body)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let config = json?["config"] as? [String: Any]
        let speed = try XCTUnwrap(config?["speed"] as? Double)
        XCTAssertEqual(speed, 5.5, accuracy: 0.1)
    }
    
    // MARK: - Unknown Route Tests
    
    func test_unknownRoute_recordsEvent() async throws {
        let yaml = """
        version: 1
        server:
          osc_listen:
            host: "0.0.0.0"
            port: 9000
          http:
            base_url: "http://localhost:8888"
            timeout_ms: 1500
        slots:
          "0":
            name: "main"
            targets:
              virtual_ids: ["virtual-1"]
        scenes: {}
        oneshots: {}
        params: {}
        """
        
        try await service.loadConfig(from: yaml.data(using: .utf8)!)
        try await service.start()
        
        // When: Unknown scene
        await service.handleOSCMessage(path: "/ledfx/scene/unknown/0", values: [1.0])
        try await Task.sleep(for: .milliseconds(100))
        
        // Then: No HTTP request, but event recorded
        let requests = await httpClient.requests
        XCTAssertEqual(requests.count, 0)
        
        let state = await service.getState()
        XCTAssertEqual(state.stats.totalOscUnknown, 1)
        XCTAssertTrue(state.recentOsc.contains { $0.unknownReason != nil })
    }
    
    // MARK: - Dry Run Tests
    
    func test_dryRun_doesNotExecuteRequests() async throws {
        let yaml = """
        version: 1
        server:
          osc_listen:
            host: "0.0.0.0"
            port: 9000
          http:
            base_url: "http://localhost:8888"
            timeout_ms: 1500
        slots:
          "0":
            name: "main"
            targets:
              virtual_ids: ["virtual-1"]
        scenes:
          test:
            id: "test"
            on_activate:
              request:
                method: "PUT"
                path: "/api/test"
                body: {}
        oneshots: {}
        params: {}
        """
        
        try await service.loadConfig(from: yaml.data(using: .utf8)!)
        await service.setDryRun(true)
        try await service.start()
        
        // When: Scene activate in dry run mode
        await service.handleOSCMessage(path: "/ledfx/scene/test/0", values: [1.0])
        try await Task.sleep(for: .milliseconds(100))
        
        // Then: Request planned but not executed
        let requests = await httpClient.requests
        XCTAssertEqual(requests.count, 0)
        
        let state = await service.getState()
        XCTAssertEqual(state.stats.totalRestPlanned, 1)
        XCTAssertEqual(state.stats.totalRestSent, 0)
    }
    
    // MARK: - HTTP Failure Tests
    
    func test_httpFailure_recordsError() async throws {
        let yaml = """
        version: 1
        server:
          osc_listen:
            host: "0.0.0.0"
            port: 9000
          http:
            base_url: "http://localhost:8888"
            timeout_ms: 1500
        slots:
          "0":
            name: "main"
            targets:
              virtual_ids: ["virtual-1"]
        scenes:
          test:
            id: "test"
            on_activate:
              request:
                method: "PUT"
                path: "/api/test"
                body: {}
        oneshots: {}
        params: {}
        """
        
        try await service.loadConfig(from: yaml.data(using: .utf8)!)
        try await service.start()
        
        // Given: HTTP client will fail
        await httpClient.setShouldFail(true)
        
        // When: Scene activate
        await service.handleOSCMessage(path: "/ledfx/scene/test/0", values: [1.0])
        try await Task.sleep(for: .milliseconds(100))
        
        // Then: Failure recorded
        let state = await service.getState()
        XCTAssertEqual(state.stats.totalRestFailures, 1)
        XCTAssertTrue(state.recentHttp.contains { $0.error != nil })
    }
}

// MARK: - Test HTTP Client Extension

extension TestHTTPClient {
    func setShouldFail(_ shouldFail: Bool) {
        Task {
            await self.updateShouldFail(shouldFail)
        }
    }
    
    private func updateShouldFail(_ value: Bool) {
        self.shouldFail = value
    }
}
