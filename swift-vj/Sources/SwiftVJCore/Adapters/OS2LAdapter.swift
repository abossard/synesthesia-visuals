// OS2LAdapter - TCP bridge: receive OS2L from VirtualDJ, forward to QLC+
// Following Grokking Simplicity: this is an action (side effects / IO)

import Foundation
import Network

/// Actor-based OS2L TCP adapter.
///
/// Listens for incoming OS2L JSON messages from VirtualDJ on `listenPort`,
/// parses them into `OS2LEvent` values, fires the `onEvent` callback,
/// and forwards the raw JSON line to QLC+ on `forwardPort`.
public actor OS2LAdapter {

    // MARK: - Configuration

    private let listenPort: UInt16
    private let forwardHost: String
    private let forwardPort: UInt16

    // MARK: - Network State

    private var listener: NWListener?
    private var incomingConnection: NWConnection?
    private var forwardConnection: NWConnection?
    private var receiveBuffer: String = ""
    private var isRunning: Bool = false

    // MARK: - Stats

    private var messagesReceived: Int = 0
    private var messagesForwarded: Int = 0
    private var lastEventTime: Date?
    private var forwardConnected: Bool = false

    // MARK: - Callback

    /// Called on every parsed event. Set before calling `start()`.
    public var onEvent: (@Sendable (OS2LEvent) -> Void)?

    // MARK: - Init

    public init(
        listenPort: UInt16 = 9997,
        forwardHost: String = "127.0.0.1",
        forwardPort: UInt16 = 9996
    ) {
        self.listenPort = listenPort
        self.forwardHost = forwardHost
        self.forwardPort = forwardPort
    }

    // MARK: - Public API

    /// Start the TCP listener and connect to QLC+.
    public func start() async throws {
        guard !isRunning else { return }
        isRunning = true

        try startListener()
        connectToForwardTarget()
        print("[OS2L] Started — listening on port \(listenPort), forwarding to \(forwardHost):\(forwardPort)")
    }

    /// Gracefully shut down all connections and the listener.
    public func stop() async {
        guard isRunning else { return }
        isRunning = false

        listener?.cancel()
        listener = nil
        incomingConnection?.cancel()
        incomingConnection = nil
        forwardConnection?.cancel()
        forwardConnection = nil
        receiveBuffer = ""
        forwardConnected = false
        print("[OS2L] Stopped")
    }

    /// Snapshot of current adapter state for diagnostics.
    public func getStatus() -> [String: Any] {
        [
            "isRunning": isRunning,
            "listenPort": listenPort,
            "forwardHost": forwardHost,
            "forwardPort": forwardPort,
            "messagesReceived": messagesReceived,
            "messagesForwarded": messagesForwarded,
            "forwardConnected": forwardConnected,
            "hasIncomingConnection": incomingConnection != nil,
            "lastEventTime": lastEventTime?.description ?? "never",
        ]
    }

    // MARK: - Listener

    private func startListener() throws {
        let params = NWParameters.tcp
        let port = NWEndpoint.Port(rawValue: listenPort)!
        let nwListener = try NWListener(using: params, on: port)

        nwListener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task { await self.handleNewIncomingConnection(connection) }
        }

        nwListener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[OS2L] Listener ready on port \(self.listenPort)")
            case .failed(let error):
                print("[OS2L] Listener failed: \(error)")
            default:
                break
            }
        }

        nwListener.start(queue: .global(qos: .userInitiated))
        self.listener = nwListener
    }

    // MARK: - Incoming Connections (VDJ)

    private func handleNewIncomingConnection(_ connection: NWConnection) {
        // Accept new, close old (single-client model)
        if let old = incomingConnection {
            old.cancel()
            print("[OS2L] Replaced previous incoming connection")
        }

        incomingConnection = connection
        receiveBuffer = ""

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                print("[OS2L] Incoming connection ready")
                Task { await self.receiveLoop(on: connection) }
            case .failed(let error):
                print("[OS2L] Incoming connection failed: \(error)")
                Task { await self.clearIncoming(connection) }
            case .cancelled:
                Task { await self.clearIncoming(connection) }
            default:
                break
            }
        }

        connection.start(queue: .global(qos: .userInitiated))
    }

    private func clearIncoming(_ connection: NWConnection) {
        if incomingConnection === connection {
            incomingConnection = nil
            receiveBuffer = ""
        }
    }

    // MARK: - Receive Loop

    private func receiveLoop(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            [weak self] content, _, isComplete, error in
            guard let self else { return }

            Task {
                if let data = content, let chunk = String(data: data, encoding: .utf8) {
                    await self.processChunk(chunk, from: connection)
                }

                if isComplete || error != nil {
                    await self.clearIncoming(connection)
                    return
                }

                // Continue reading
                await self.receiveLoop(on: connection)
            }
        }
    }

    private func processChunk(_ chunk: String, from connection: NWConnection) {
        guard incomingConnection === connection else { return }

        receiveBuffer.append(chunk)

        let (lines, remainder) = extractOS2LLines(from: receiveBuffer)
        receiveBuffer = remainder

        for line in lines {
            messagesReceived += 1
            lastEventTime = Date()

            let event = parseOS2LEvent(from: line)
            onEvent?(event)

            forwardRawLine(line)
        }
    }

    // MARK: - Forward Connection (QLC+)

    private func connectToForwardTarget() {
        let host = NWEndpoint.Host(forwardHost)
        let port = NWEndpoint.Port(rawValue: forwardPort)!
        let connection = NWConnection(host: host, port: port, using: .tcp)

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                print("[OS2L] Forward connection ready → \(self.forwardHost):\(self.forwardPort)")
                Task { await self.setForwardConnected(true) }
            case .waiting(let error):
                print("[OS2L] Forward connection waiting: \(error)")
                Task { await self.setForwardConnected(false) }
            case .failed(let error):
                print("[OS2L] Forward connection failed: \(error)")
                Task { await self.setForwardConnected(false) }
                Task { await self.scheduleReconnect() }
            case .cancelled:
                Task { await self.setForwardConnected(false) }
            default:
                break
            }
        }

        connection.start(queue: .global(qos: .userInitiated))
        self.forwardConnection = connection
    }

    private func setForwardConnected(_ value: Bool) {
        forwardConnected = value
    }

    /// Send a raw JSON string to the forward target (QLC+).
    public func sendRaw(json: String) {
        forwardRawLine(json)
    }

    private func forwardRawLine(_ line: String) {
        guard forwardConnected, let connection = forwardConnection else { return }

        let payload = line + "\n"
        guard let data = payload.data(using: .utf8) else { return }

        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if let error {
                print("[OS2L] Forward send error: \(error)")
                Task { await self.setForwardConnected(false) }
                Task { await self.scheduleReconnect() }
            } else {
                Task { await self.incrementForwarded() }
            }
        })
    }

    private func incrementForwarded() {
        messagesForwarded += 1
    }

    // MARK: - Reconnection

    private func scheduleReconnect() {
        guard isRunning else { return }

        forwardConnection?.cancel()
        forwardConnection = nil

        print("[OS2L] Reconnecting to QLC+ in 2s…")
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard await self.isRunning else { return }
            await self.connectToForwardTarget()
        }
    }
}
