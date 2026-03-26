// HubIntegrationTests.swift - E2E tests exercising real TCP, OSC, and HTTP networking
// No mocking — these tests start real listeners and make real connections.

import XCTest
import Network
@testable import SwiftVJCore

// MARK: - Test Helpers (top-level for Sendable safety)

/// Actor that accumulates received TCP data as text.
private actor ReceivedDataAccumulator {
    var text: String = ""

    func append(_ chunk: String) {
        text += chunk
    }
}

/// Recorded HTTP request for verification.
private struct RecordedHTTPRequest: Sendable {
    let method: String
    let path: String
    let body: String
}

/// Actor that records HTTP requests received by the fake server.
private actor HTTPRequestRecorder {
    var requests: [RecordedHTTPRequest] = []

    func record(_ request: RecordedHTTPRequest) {
        requests.append(request)
    }
}

/// Recursively receive all data from a connection into an accumulator.
private func receiveAll(on connection: NWConnection, into accumulator: ReceivedDataAccumulator) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, _ in
        if let data = data, let str = String(data: data, encoding: .utf8) {
            Task { await accumulator.append(str) }
        }
        if !isComplete {
            receiveAll(on: connection, into: accumulator)
        }
    }
}

/// Handle an incoming HTTP connection: read full request, respond 200, record it.
private func handleHTTPConnection(_ connection: NWConnection, recorder: HTTPRequestRecorder) {
    // Read a generous chunk — HTTP PUT from URLSession will typically arrive in one read
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
        guard let data = data, let raw = String(data: data, encoding: .utf8) else { return }

        let lines = raw.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else { return }

        let parts = requestLine.split(separator: " ")
        let method = parts.count > 0 ? String(parts[0]) : "?"
        let path = parts.count > 1 ? String(parts[1]) : "?"

        // Check Content-Length to see if we need more data
        var contentLength = 0
        for line in lines {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let val = lower.replacingOccurrences(of: "content-length:", with: "").trimmingCharacters(in: .whitespaces)
                contentLength = Int(val) ?? 0
            }
        }

        // Extract body (after empty line)
        let body: String
        if let emptyIdx = lines.firstIndex(where: { $0.isEmpty }) {
            body = lines.dropFirst(emptyIdx + 1).joined(separator: "\n")
        } else {
            body = ""
        }

        // If we have the body or there's no content-length, record immediately
        if body.count >= contentLength || contentLength == 0 {
            Task { await recorder.record(RecordedHTTPRequest(method: method, path: path, body: body)) }
            let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 16\r\n\r\n{\"status\":\"ok\"}"
            connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        } else {
            // Need to read more — the body arrived in a separate TCP segment
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data2, _, _, _ in
                var fullBody = body
                if let data2 = data2, let extra = String(data: data2, encoding: .utf8) {
                    fullBody += extra
                }
                Task { await recorder.record(RecordedHTTPRequest(method: method, path: path, body: fullBody)) }
                let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 16\r\n\r\n{\"status\":\"ok\"}"
                connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }
}

// MARK: - Tests

final class HubIntegrationTests: XCTestCase {

    private func randomPort() -> UInt16 {
        UInt16.random(in: 20000...30000)
    }

    // MARK: - Test 1: OS2L TCP → Event Parsing → Hub Log

    func test_os2l_adapter_receives_and_logs_tcp_messages() async throws {
        let log = HubMessageLog()
        let port = randomPort()

        let adapter = OS2LAdapter(
            listenPort: port,
            forwardHost: "127.0.0.1",
            forwardPort: 1,
            hubLog: log
        )

        try await adapter.start()
        try await Task.sleep(for: .milliseconds(200))

        // Connect a TCP client
        let connection = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )

        let connected = expectation(description: "TCP connected")
        connection.stateUpdateHandler = { state in
            if case .ready = state { connected.fulfill() }
        }
        connection.start(queue: .global())
        await fulfillment(of: [connected], timeout: 3)

        // Send three OS2L JSON lines
        let lines = [
            #"{"evt":"btn","name":"strobe","state":"on"}"#,
            #"{"evt":"beat"}"#,
            #"{"evt":"cmd","id":1,"param":75}"#,
        ]
        let payload = lines.joined(separator: "\n") + "\n"
        connection.send(content: payload.data(using: .utf8), completion: .contentProcessed { _ in })

        // Wait for processing
        try await Task.sleep(for: .milliseconds(800))

        // The adapter logs via hubLog directly using displayTitle format
        let messages = await log.getMessages()
        XCTAssertEqual(messages.count, 3, "Expected 3 hub log messages, got \(messages.count)")

        let allTitles = messages.map(\.title)
        XCTAssertTrue(allTitles.contains(where: { $0.contains("strobe") }), "Should contain strobe, got: \(allTitles)")
        XCTAssertTrue(allTitles.contains(where: { $0.contains("beat") }), "Should contain beat, got: \(allTitles)")
        XCTAssertTrue(allTitles.contains(where: { $0.contains("cmd") }), "Should contain cmd, got: \(allTitles)")

        // Verify source filtering
        let os2lOnly = await log.getMessages(source: .os2l)
        XCTAssertEqual(os2lOnly.count, 3)

        let oscOnly = await log.getMessages(source: .osc)
        XCTAssertEqual(oscOnly.count, 0)

        // Cleanup
        connection.cancel()
        await adapter.stop()
    }

    // MARK: - Test 2: OS2L Forward Passthrough

    func test_os2l_adapter_forwards_to_qlc_target() async throws {
        let fakeQLCPort = randomPort()
        let adapterPort = randomPort()

        let receivedData = ReceivedDataAccumulator()
        let fakeQLC = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: fakeQLCPort)!)

        let qlcReady = expectation(description: "QLC listener ready")
        fakeQLC.stateUpdateHandler = { state in
            if case .ready = state { qlcReady.fulfill() }
        }
        fakeQLC.newConnectionHandler = { conn in
            conn.start(queue: .global())
            receiveAll(on: conn, into: receivedData)
        }
        fakeQLC.start(queue: .global())
        await fulfillment(of: [qlcReady], timeout: 3)

        let adapter = OS2LAdapter(
            listenPort: adapterPort,
            forwardHost: "127.0.0.1",
            forwardPort: fakeQLCPort
        )
        try await adapter.start()
        try await Task.sleep(for: .milliseconds(300))

        // Connect a TCP client (simulating VirtualDJ)
        let clientConn = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: adapterPort)!,
            using: .tcp
        )
        let clientReady = expectation(description: "Client connected")
        clientConn.stateUpdateHandler = { state in
            if case .ready = state { clientReady.fulfill() }
        }
        clientConn.start(queue: .global())
        await fulfillment(of: [clientReady], timeout: 3)

        let json = #"{"evt":"btn","name":"drop","state":"on"}"#
        let payload = json + "\n"
        clientConn.send(content: payload.data(using: .utf8), completion: .contentProcessed { _ in })

        try await Task.sleep(for: .milliseconds(800))

        let received = await receivedData.text
        XCTAssertTrue(
            received.contains("drop"),
            "QLC+ target should have received the forwarded JSON containing 'drop', got: \(received)"
        )

        // Cleanup
        clientConn.cancel()
        await adapter.stop()
        fakeQLC.cancel()
    }

    // MARK: - Test 3: OS2L Button → LedFX REST Call

    func test_os2l_button_triggers_ledfx_playlist() async throws {
        let httpPort = randomPort()
        let recorder = HTTPRequestRecorder()

        let httpListener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: httpPort)!)
        let httpReady = expectation(description: "HTTP listener ready")
        httpListener.stateUpdateHandler = { state in
            if case .ready = state { httpReady.fulfill() }
        }
        httpListener.newConnectionHandler = { conn in
            conn.start(queue: .global())
            handleHTTPConnection(conn, recorder: recorder)
        }
        httpListener.start(queue: .global())
        await fulfillment(of: [httpReady], timeout: 3)

        let client = LedFXClient(baseURL: "http://127.0.0.1:\(httpPort)")
        let bridge = OS2LToLedFXBridge(client: client)

        // Default mappings include "*" → "$1" wildcard passthrough
        await bridge.handleOS2LEvent(.button(name: "drop", state: .on))

        try await Task.sleep(for: .milliseconds(500))

        let requests = await recorder.requests
        XCTAssertGreaterThanOrEqual(
            requests.count, 1,
            "Expected at least 1 HTTP request from bridge, got \(requests.count)"
        )

        let matchingReq = requests.first { $0.path.contains("playlists") }
        XCTAssertNotNil(matchingReq, "Expected a request to /api/playlists, got: \(requests.map(\.path))")
        XCTAssertEqual(matchingReq?.method, "PUT")

        if let body = matchingReq?.body {
            XCTAssertTrue(body.contains("drop"), "Request body should contain playlist name 'drop', got: \(body)")
        }

        // Cleanup
        httpListener.cancel()
    }

    // MARK: - Test 4: HubMessageLog Basics

    func test_hub_message_log_records_and_filters() async {
        let log = HubMessageLog()
        await log.record(HubMessage(source: .osc, title: "/test", detail: "args"))
        await log.record(HubMessage(source: .os2l, title: "beat", detail: ""))
        await log.record(HubMessage(source: .rest, title: "PUT /api", detail: "200"))

        let all = await log.getMessages()
        XCTAssertEqual(all.count, 3)

        let oscOnly = await log.getMessages(source: .osc)
        XCTAssertEqual(oscOnly.count, 1)
        XCTAssertEqual(oscOnly[0].title, "/test")

        let os2lOnly = await log.getMessages(source: .os2l)
        XCTAssertEqual(os2lOnly.count, 1)
        XCTAssertEqual(os2lOnly[0].title, "beat")

        let restOnly = await log.getMessages(source: .rest)
        XCTAssertEqual(restOnly.count, 1)
        XCTAssertEqual(restOnly[0].title, "PUT /api")
    }

    // MARK: - Test 5: HubMessageLog Circular Buffer

    func test_hub_message_log_evicts_oldest() async {
        let log = HubMessageLog(maxMessages: 3)
        for i in 0..<5 {
            await log.record(HubMessage(source: .osc, title: "/msg/\(i)"))
        }
        let msgs = await log.getMessages()
        XCTAssertEqual(msgs.count, 3)
        XCTAssertEqual(msgs[0].title, "/msg/2")  // oldest surviving
        XCTAssertEqual(msgs[1].title, "/msg/3")
        XCTAssertEqual(msgs[2].title, "/msg/4")  // newest
    }
}
