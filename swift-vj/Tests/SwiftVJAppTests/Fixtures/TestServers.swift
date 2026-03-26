import Network
import Foundation

// MARK: - Shared actor for collecting received lines

actor ReceivedLines {
    var text = ""
    func append(_ chunk: String) { text += chunk }
    func lines() -> [String] { text.split(separator: "\n").map(String.init) }
    func allText() -> String { text }
}

// MARK: - Shared actor for recording HTTP requests

struct RecordedRequest: Sendable {
    let method: String
    let path: String
    let body: String
}

actor RequestRecorder {
    var requests: [RecordedRequest] = []
    func record(_ req: RecordedRequest) { requests.append(req) }
    func all() -> [RecordedRequest] { requests }
}

// MARK: - TCPTestServer

/// A reusable TCP test server that records all received data.
/// Deep module: wraps NWListener with a clean async API.
final class TCPTestServer: @unchecked Sendable {
    let port: UInt16
    private var listener: NWListener?
    private let receivedData = ReceivedLines()

    init(port: UInt16 = UInt16.random(in: 20000...30000)) {
        self.port = port
    }

    func start() async throws {
        listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)

        return try await withCheckedThrowingContinuation { cont in
            listener!.stateUpdateHandler = { state in
                if case .ready = state { cont.resume() }
                if case .failed(let err) = state { cont.resume(throwing: err) }
            }
            let accumulator = self.receivedData
            listener!.newConnectionHandler = { conn in
                conn.start(queue: .global())
                Self.receiveLoop(conn, into: accumulator)
            }
            listener!.start(queue: .global())
        }
    }

    private static func receiveLoop(_ conn: NWConnection, into accumulator: ReceivedLines) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, _ in
            if let data, let str = String(data: data, encoding: .utf8) {
                Task { await accumulator.append(str) }
            }
            if !isComplete { receiveLoop(conn, into: accumulator) }
        }
    }

    func receivedText() async -> String { await receivedData.allText() }
    func receivedLines() async -> [String] { await receivedData.lines() }

    func stop() { listener?.cancel() }
    deinit { stop() }
}

// MARK: - HTTPTestServer

/// A reusable HTTP test server that records requests and responds 200 OK.
/// Deep module: wraps NWListener to act as a fake REST backend.
final class HTTPTestServer: @unchecked Sendable {
    let port: UInt16
    private var listener: NWListener?
    private let recorder = RequestRecorder()

    init(port: UInt16 = UInt16.random(in: 20000...30000)) {
        self.port = port
    }

    func start() async throws {
        listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)

        return try await withCheckedThrowingContinuation { cont in
            listener!.stateUpdateHandler = { state in
                if case .ready = state { cont.resume() }
                if case .failed(let err) = state { cont.resume(throwing: err) }
            }
            let rec = self.recorder
            listener!.newConnectionHandler = { conn in
                conn.start(queue: .global())
                Self.handleHTTP(conn, recorder: rec)
            }
            listener!.start(queue: .global())
        }
    }

    private static func handleHTTP(_ conn: NWConnection, recorder: RequestRecorder) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
            guard let data, let raw = String(data: data, encoding: .utf8) else { return }
            let lines = raw.split(separator: "\r\n", omittingEmptySubsequences: false)
            let parts = (lines.first ?? "").split(separator: " ")
            let method = parts.count > 0 ? String(parts[0]) : "?"
            let path = parts.count > 1 ? String(parts[1]) : "?"

            var contentLength = 0
            for line in lines {
                let lower = line.lowercased()
                if lower.hasPrefix("content-length:") {
                    let val = lower.replacingOccurrences(of: "content-length:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    contentLength = Int(val) ?? 0
                }
            }

            let body: String
            if let emptyIdx = lines.firstIndex(where: { $0.isEmpty }) {
                body = lines.dropFirst(emptyIdx + 1).joined(separator: "\n")
            } else {
                body = ""
            }

            let respond: @Sendable (String) -> Void = { finalBody in
                Task { await recorder.record(RecordedRequest(method: method, path: path, body: finalBody)) }
                let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 16\r\n\r\n{\"status\":\"ok\"}"
                conn.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
            }

            if body.count >= contentLength || contentLength == 0 {
                respond(body)
            } else {
                conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data2, _, _, _ in
                    var fullBody = body
                    if let data2, let extra = String(data: data2, encoding: .utf8) {
                        fullBody += extra
                    }
                    respond(fullBody)
                }
            }
        }
    }

    func requests() async -> [RecordedRequest] { await recorder.all() }
    func stop() { listener?.cancel() }
    deinit { stop() }
}

// MARK: - TCPTestClient

/// Send data over TCP and wait for connection.
final class TCPTestClient: @unchecked Sendable {
    private let connection: NWConnection

    init(host: String = "127.0.0.1", port: UInt16) {
        connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
    }

    func connect() async throws {
        return try await withCheckedThrowingContinuation { cont in
            connection.stateUpdateHandler = { state in
                if case .ready = state { cont.resume() }
                if case .failed(let err) = state { cont.resume(throwing: err) }
            }
            connection.start(queue: .global())
        }
    }

    func send(_ text: String) {
        connection.send(content: text.data(using: .utf8), completion: .contentProcessed { _ in })
    }

    func close() { connection.cancel() }
    deinit { close() }
}
