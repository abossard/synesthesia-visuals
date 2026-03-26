// HubIntegrationTests.swift — E2E tests with real TCP and HTTP.
// Data-driven via fixtures. Reusable test infrastructure.

import XCTest
import Network
@testable import SwiftVJCore

final class HubIntegrationTests: XCTestCase {

    // MARK: - Test 1: All fixture events flow through OS2L adapter → hub log

    func test_os2l_all_fixture_events_logged() async throws {
        let log = HubMessageLog()
        let adapterPort = UInt16.random(in: 20000...30000)

        let adapter = OS2LAdapter(
            listenPort: adapterPort,
            forwardHost: "127.0.0.1",
            forwardPort: 1,
            hubLog: log
        )
        try await adapter.start()
        try await Task.sleep(for: .milliseconds(200))

        let client = TCPTestClient(port: adapterPort)
        try await client.connect()
        client.send(OS2LFixtures.multiLinePayload)
        try await Task.sleep(for: .milliseconds(800))

        let messages = await log.getMessages()
        XCTAssertEqual(messages.count, OS2LFixtures.allEvents.count,
            "Expected \(OS2LFixtures.allEvents.count) hub messages, got \(messages.count)")

        // Each fixture event should produce a log entry containing its key identifier
        for fixture in OS2LFixtures.allEvents {
            let title = fixture.expected.displayTitle
            let found = messages.contains { $0.title == title }
            XCTAssertTrue(found, "[\(fixture.label)] Missing hub log for displayTitle '\(title)'. Got: \(messages.map(\.title))")
        }

        // All should be source .os2l
        let os2lOnly = await log.getMessages(source: .os2l)
        XCTAssertEqual(os2lOnly.count, OS2LFixtures.allEvents.count)
        let oscOnly = await log.getMessages(source: .osc)
        XCTAssertEqual(oscOnly.count, 0)

        client.close()
        await adapter.stop()
    }

    // MARK: - Test 2: All fixture events forwarded to QLC+ TCP target

    func test_os2l_all_fixture_events_forwarded_to_qlc() async throws {
        let qlcServer = TCPTestServer()
        try await qlcServer.start()

        let adapterPort = UInt16.random(in: 20000...30000)
        let adapter = OS2LAdapter(
            listenPort: adapterPort,
            forwardHost: "127.0.0.1",
            forwardPort: qlcServer.port
        )
        try await adapter.start()
        try await Task.sleep(for: .milliseconds(300))

        let client = TCPTestClient(port: adapterPort)
        try await client.connect()
        client.send(OS2LFixtures.multiLinePayload)
        try await Task.sleep(for: .milliseconds(800))

        let forwarded = await qlcServer.receivedLines()
        XCTAssertEqual(forwarded.count, OS2LFixtures.allEvents.count,
            "Expected \(OS2LFixtures.allEvents.count) forwarded lines, got \(forwarded.count)")

        // Verify each fixture's JSON appears in forwarded data
        for fixture in OS2LFixtures.allEvents {
            let found = forwarded.contains { $0.contains(fixture.json) }
            XCTAssertTrue(found, "[\(fixture.label)] Not forwarded. Got: \(forwarded)")
        }

        client.close()
        await adapter.stop()
        qlcServer.stop()
    }

    // MARK: - Test 3: OS2L buttons trigger correct LedFX REST calls (parametrized)

    func test_os2l_buttons_trigger_ledfx_calls() async throws {
        for scenario in LedFXFixtures.scenarios {
            let httpServer = HTTPTestServer()
            try await httpServer.start()

            let ledFXClient = LedFXClient(baseURL: "http://127.0.0.1:\(httpServer.port)")
            let bridge = OS2LToLedFXBridge(client: ledFXClient)
            await bridge.setMappings(scenario.mappings)

            await bridge.handleOS2LEvent(.button(name: scenario.buttonName, state: .on))
            try await Task.sleep(for: .milliseconds(500))

            let requests = await httpServer.requests()

            if let expectedTarget = scenario.expectedTarget {
                XCTAssertFalse(requests.isEmpty,
                    "[\(scenario.label)] Expected HTTP request for '\(expectedTarget)' but got none")

                let endpoint = scenario.expectedIsScene ? "scenes" : "playlists"
                let match = requests.first { $0.path.contains(endpoint) }
                XCTAssertNotNil(match,
                    "[\(scenario.label)] Expected request to /api/\(endpoint), got: \(requests.map(\.path))")
            } else {
                XCTAssertTrue(requests.isEmpty,
                    "[\(scenario.label)] Expected no HTTP requests but got \(requests.count)")
            }

            httpServer.stop()
        }
    }

    // MARK: - Test 4: TCP reassembly — split payload across multiple writes

    func test_os2l_handles_split_tcp_messages() async throws {
        let log = HubMessageLog()
        let adapterPort = UInt16.random(in: 20000...30000)

        let adapter = OS2LAdapter(
            listenPort: adapterPort,
            forwardHost: "127.0.0.1",
            forwardPort: 1,
            hubLog: log
        )
        try await adapter.start()
        try await Task.sleep(for: .milliseconds(200))

        let client = TCPTestClient(port: adapterPort)
        try await client.connect()

        let chunks = OS2LFixtures.splitPayloads
        for chunk in chunks {
            client.send(chunk)
            try await Task.sleep(for: .milliseconds(100))
        }
        try await Task.sleep(for: .milliseconds(800))

        let messages = await log.getMessages()
        XCTAssertEqual(messages.count, OS2LFixtures.allEvents.count,
            "Split TCP should reassemble to \(OS2LFixtures.allEvents.count) events, got \(messages.count)")

        client.close()
        await adapter.stop()
    }

    // MARK: - Test 5: Button OFF state does NOT trigger LedFX

    func test_os2l_button_off_does_not_trigger_ledfx() async throws {
        let httpServer = HTTPTestServer()
        try await httpServer.start()

        let ledFXClient = LedFXClient(baseURL: "http://127.0.0.1:\(httpServer.port)")
        let bridge = OS2LToLedFXBridge(client: ledFXClient)

        // Send all button fixtures but with state .off
        for fixture in OS2LFixtures.buttonEvents {
            if case let .button(name, _) = fixture.expected {
                await bridge.handleOS2LEvent(.button(name: name, state: .off))
            }
        }
        try await Task.sleep(for: .milliseconds(500))

        let requests = await httpServer.requests()
        XCTAssertTrue(requests.isEmpty,
            "Button OFF should not trigger HTTP calls, got \(requests.count) requests")

        httpServer.stop()
    }
}
