// OscRestBridgeService.swift - Main service actor
// Following A Philosophy of Software Design: deep module with simple interface

import Foundation
import OSCKit

/// Main OSC → REST bridge service
public actor OscRestBridgeService {
    private struct QueuedRequest: Sendable {
        let id: UUID
        let plan: HTTPRequestPlan
        let config: BridgeConfig
        let timestamp: Date
    }
    
    // MARK: - Dependencies (protocols for testing)
    
    private let httpClient: HTTPClient
    private let clock: Clock
    
    // MARK: - State
    
    private var config: BridgeConfig?
    private var isRunning: Bool = false
    private var slotStates: [String: SlotState] = [:]
    
    // Ring buffers
    private var oscBuffer: CircularBuffer<OSCMessageRecord>
    private var httpBuffer: CircularBuffer<HTTPRequestRecord>
    
    // Statistics
    private var stats: BridgeStats = BridgeStats()
    private var statsStartTime: Date?
    
    // Event stream
    private let eventContinuation: AsyncStream<BridgeEvent>.Continuation
    public let events: AsyncStream<BridgeEvent>
    
    // Dry run mode
    private var dryRun: Bool = false

    // Request execution control
    private let maxConcurrentRequests: Int = 8
    private var inFlightRequests: [UUID: Task<Void, Never>] = [:]
    private var pendingRequests: [QueuedRequest] = []
    private var pendingRequestHead: Int = 0
    
    // MARK: - Initialization
    
    public init(
        httpClient: HTTPClient,
        clock: Clock = SystemClock()
    ) {
        self.httpClient = httpClient
        self.clock = clock
        
        self.oscBuffer = CircularBuffer(capacity: 100)
        self.httpBuffer = CircularBuffer(capacity: 100)
        
        var continuation: AsyncStream<BridgeEvent>.Continuation!
        self.events = AsyncStream { cont in
            continuation = cont
        }
        self.eventContinuation = continuation
    }
    
    // MARK: - Lifecycle
    
    public func start() async throws {
        guard !isRunning else { return }
        
        guard config != nil else {
            throw BridgeError.configNotLoaded
        }
        
        // No OSC transport to start - we subscribe to the existing OSCHub
        // The subscription is handled externally in AppState
        
        isRunning = true
        statsStartTime = clock.now()
        
        eventContinuation.yield(.started(timestamp: clock.now()))
    }
    
    public func stop() async {
        guard isRunning else { return }
        
        // No OSC transport to stop - unsubscription handled externally
        
        isRunning = false

        // Cancel running requests and clear queued work.
        for task in inFlightRequests.values {
            task.cancel()
        }
        inFlightRequests.removeAll(keepingCapacity: true)
        pendingRequests.removeAll(keepingCapacity: false)
        pendingRequestHead = 0
        
        eventContinuation.yield(.stopped(timestamp: clock.now()))
    }
    
    // MARK: - OSC Message Handler (called from OSCHub subscription)
    
    // MARK: - Configuration
    
    public func loadConfig(from url: URL) async throws {
        let loaded = try ConfigLoader.load(from: url)
        config = loaded
        
        // Reset slot states
        slotStates = loaded.slots.mapValues { _ in SlotState() }
        
        let summary = ConfigLoader.summary(from: loaded)
        eventContinuation.yield(.configLoaded(timestamp: clock.now(), summary: summary))
    }
    
    public func loadConfig(from data: Data) async throws {
        let loaded = try ConfigLoader.load(from: data)
        config = loaded
        
        // Reset slot states
        slotStates = loaded.slots.mapValues { _ in SlotState() }
        
        let summary = ConfigLoader.summary(from: loaded)
        eventContinuation.yield(.configLoaded(timestamp: clock.now(), summary: summary))
    }
    
    public func reloadConfig(from url: URL) async throws {
        let oldSummary = config.map { ConfigLoader.summary(from: $0) }
        
        try await loadConfig(from: url)
        
        if let old = oldSummary, let new = config.map({ ConfigLoader.summary(from: $0) }) {
            let changes = computeChanges(from: old, to: new)
            eventContinuation.yield(.configReloaded(timestamp: clock.now(), summary: new, changesSummary: changes))
        }
    }
    
    private func computeChanges(from old: ConfigSummary, to new: ConfigSummary) -> String {
        var changes: [String] = []
        
        if old.sceneCount != new.sceneCount {
            changes.append("scenes: \(old.sceneCount) → \(new.sceneCount)")
        }
        if old.oneshotCount != new.oneshotCount {
            changes.append("oneshots: \(old.oneshotCount) → \(new.oneshotCount)")
        }
        if old.paramCount != new.paramCount {
            changes.append("params: \(old.paramCount) → \(new.paramCount)")
        }
        if old.slotCount != new.slotCount {
            changes.append("slots: \(old.slotCount) → \(new.slotCount)")
        }
        
        return changes.isEmpty ? "No structural changes" : changes.joined(separator: ", ")
    }
    
    // MARK: - State Access
    
    public func getState() -> BridgeStateSnapshot {
        let configStatus: ConfigStatus = config.map { cfg in
            .valid(summary: ConfigLoader.summary(from: cfg))
        } ?? .notLoaded
        
        return BridgeStateSnapshot(
            isRunning: isRunning,
            configStatus: configStatus,
            stats: computeCurrentStats(),
            slotState: slotStates,
            recentOsc: Array(oscBuffer.items),
            recentHttp: Array(httpBuffer.items),
            dryRun: dryRun
        )
    }
    
    public func setDryRun(_ enabled: Bool) {
        dryRun = enabled
    }
    
    public func clearStats() {
        stats = BridgeStats()
        statsStartTime = clock.now()
    }
    
    public func clearBuffers() {
        oscBuffer = CircularBuffer(capacity: 100)
        httpBuffer = CircularBuffer(capacity: 100)
    }
    
    public func clearSlotStates() {
        slotStates = config?.slots.mapValues { _ in SlotState() } ?? [:]
    }
    
    // MARK: - OSC Message Handling
    
    public func handleOSCMessage(path: String, values: [Any]) async {
        let numericValue = OSCRouteParser.extractNumeric(values)
        await handleOSCMessage(path: path, numericValue: numericValue)
    }

    public func handleOSCMessage(path: String, numericValue: Double?) async {
        let timestamp = clock.now()
        guard isRunning else { return }

        // Extract numeric value
        guard let numericValue else {
            recordUnknownOSC(path: path, value: 0, reason: "No numeric argument", timestamp: timestamp)
            return
        }
        
        // Parse route
        guard let parsed = OSCRouteParser.parse(path) else {
            recordUnknownOSC(path: path, value: numericValue, reason: "Malformed path", timestamp: timestamp)
            return
        }
        
        // Update stats (fast, no allocation)
        stats.totalOscReceived += 1
        
        // Update slot message count
        let slot: String
        switch parsed {
        case .scene(let s, _),
             .playlist(let s, _),
             .playlistControl(let s, _),
             .oneshot(let s, _),
             .blackout(let s),
             .param(let s, _):
            slot = s
        }
        stats.slotMessages[slot, default: 0] += 1
        
        // Record OSC (only if buffer has capacity - prevents memory growth)
        if oscBuffer.items.count < 100 {
            let record = OSCMessageRecord(
                timestamp: timestamp,
                path: path,
                value: numericValue,
                parsed: parsed,
                unknownReason: nil
            )
            oscBuffer.append(record)
        }
        
        // Build HTTP requests
        guard let config = config else { return }
        
        do {
            let plans = try RequestBuilder.build(route: parsed, value: numericValue, config: config)
            
            for plan in plans {
                stats.totalRestPlanned += 1
                
                if dryRun {
                    // Dry run: don't execute, just record
                    if httpBuffer.items.count < 100 {
                        let record = HTTPRequestRecord(
                            timestamp: clock.now(),
                            method: plan.method,
                            url: plan.url,
                            bodyPreview: plan.bodyPreview,
                            statusCode: nil,
                            responsePreview: nil,
                            error: nil,
                            planned: true
                        )
                        httpBuffer.append(record)
                    }
                } else {
                    enqueueRequest(
                        QueuedRequest(
                            id: UUID(),
                            plan: plan,
                            config: config,
                            timestamp: timestamp
                        )
                    )
                }
            }
            
            // Update slot state based on route type
            updateSlotState(parsed: parsed, value: numericValue)
            
        } catch RequestBuilder.BuildError.unknownScene(let name) {
            recordUnknownOSC(path: path, value: numericValue, reason: "Unknown scene: \(name)", timestamp: timestamp)
        } catch RequestBuilder.BuildError.unknownPlaylist(let name) {
            recordUnknownOSC(path: path, value: numericValue, reason: "Unknown playlist: \(name)", timestamp: timestamp)
        } catch RequestBuilder.BuildError.unknownPlaylistControl(let name) {
            recordUnknownOSC(path: path, value: numericValue, reason: "Unknown playlist control: \(name)", timestamp: timestamp)
        } catch RequestBuilder.BuildError.unknownOneshot(let name) {
            recordUnknownOSC(path: path, value: numericValue, reason: "Unknown oneshot: \(name)", timestamp: timestamp)
        } catch RequestBuilder.BuildError.unknownParam(let name) {
            recordUnknownOSC(path: path, value: numericValue, reason: "Unknown param: \(name)", timestamp: timestamp)
        } catch RequestBuilder.BuildError.unknownSlot(let slot) {
            recordUnknownOSC(path: path, value: numericValue, reason: "Unknown slot: \(slot)", timestamp: timestamp)
        } catch {
            recordUnknownOSC(path: path, value: numericValue, reason: "Build error: \(error.localizedDescription)", timestamp: timestamp)
        }
    }

    private func enqueueRequest(_ request: QueuedRequest) {
        pendingRequests.append(request)
        startQueuedRequestsIfPossible()
    }

    private func dequeueRequest() -> QueuedRequest? {
        guard pendingRequestHead < pendingRequests.count else {
            if pendingRequestHead > 0 {
                pendingRequests.removeAll(keepingCapacity: true)
                pendingRequestHead = 0
            }
            return nil
        }

        let request = pendingRequests[pendingRequestHead]
        pendingRequestHead += 1

        if pendingRequestHead > 64 && pendingRequestHead * 2 >= pendingRequests.count {
            pendingRequests.removeFirst(pendingRequestHead)
            pendingRequestHead = 0
        }

        return request
    }

    private func startQueuedRequestsIfPossible() {
        guard isRunning else { return }

        while inFlightRequests.count < maxConcurrentRequests, let request = dequeueRequest() {
            let requestId = request.id
            inFlightRequests[requestId] = Task { [weak self] in
                guard let self else { return }
                await self.executeRequest(request.plan, config: request.config, timestamp: request.timestamp)
                await self.markRequestFinished(requestId)
            }
        }
    }

    private func markRequestFinished(_ requestId: UUID) {
        inFlightRequests[requestId] = nil
        startQueuedRequestsIfPossible()
    }
    
    private func recordUnknownOSC(path: String, value: Double, reason: String, timestamp: Date) {
        stats.totalOscUnknown += 1
        
        // Only record in buffer if space available
        if oscBuffer.items.count < 100 {
            let record = OSCMessageRecord(
                timestamp: timestamp,
                path: path,
                value: value,
                parsed: nil,
                unknownReason: reason
            )
            oscBuffer.append(record)
        }
    }
    
    // MARK: - HTTP Execution
    
    private func executeRequest(_ plan: HTTPRequestPlan, config: BridgeConfig, timestamp: Date) async {
        stats.totalRestSent += 1
        
        do {
            let (statusCode, responseBody) = try await httpClient.execute(
                method: plan.method,
                url: plan.url,
                headers: plan.headers,
                body: plan.body,
                timeoutMs: config.server.http.timeout_ms
            )
            
            // Only record if buffer has space
            if httpBuffer.items.count < 100 {
                let record = HTTPRequestRecord(
                    timestamp: clock.now(),
                    method: plan.method,
                    url: plan.url,
                    bodyPreview: plan.bodyPreview,
                    statusCode: statusCode,
                    responsePreview: responsePreview(from: responseBody),
                    error: nil,
                    planned: false
                )
                httpBuffer.append(record)
            }
            
        } catch is CancellationError {
            // Cancellation is expected during shutdown.
        } catch {
            stats.totalRestFailures += 1
            
            // Always record failures (important for debugging)
            if httpBuffer.items.count < 100 {
                let record = HTTPRequestRecord(
                    timestamp: clock.now(),
                    method: plan.method,
                    url: plan.url,
                    bodyPreview: plan.bodyPreview,
                    statusCode: nil,
                    responsePreview: nil,
                    error: error.localizedDescription,
                    planned: false
                )
                httpBuffer.append(record)
            }
        }
    }
    
    // MARK: - Slot State Management
    
    private func updateSlotState(parsed: ParsedOSCRoute, value: Double) {
        switch parsed {
        case .scene(let slot, let sceneName):
            if value > 0 {
                // Activating a scene
                slotStates[slot, default: SlotState()].lastActiveSceneName = sceneName
                slotStates[slot, default: SlotState()].lastSceneChangeTime = clock.now()
                slotStates[slot, default: SlotState()].blackoutActive = false
                
                stats.sceneActivations[sceneName, default: 0] += 1
            }
            
        case .playlist(_, let playlistId):
            if value > 0 {
                stats.playlistStarts[playlistId, default: 0] += 1
            }

        case .playlistControl(_, let action):
            if value > 0 {
                stats.playlistActions[action, default: 0] += 1
            }

        case .oneshot(_, let oneshotName):
            if value > 0 {
                stats.oneshotTriggers[oneshotName, default: 0] += 1
            }
            
        case .blackout(let slot):
            if value > 0 {
                // Activate blackout
                slotStates[slot, default: SlotState()].blackoutActive = true
                slotStates[slot, default: SlotState()].lastSceneChangeTime = clock.now()
            } else {
                // Deactivate blackout
                slotStates[slot, default: SlotState()].blackoutActive = false
                slotStates[slot, default: SlotState()].lastSceneChangeTime = clock.now()
                
                // Restore previous scene if configured
                if let slotConfig = config?.slots[slot],
                   let blackoutConfig = slotConfig.blackout,
                         blackoutConfig.restore_previous_scene,
                         slotStates[slot]?.lastActiveSceneName != nil {
                    // Note: Restoration is handled by sending another OSC message externally
                    // or by building a request plan here. For now, just track state.
                }
            }
            
        case .param(_, let paramName):
            stats.paramUpdates[paramName, default: 0] += 1
        }
    }
    
    // MARK: - Statistics
    
    private func computeCurrentStats() -> BridgeStats {
        var current = stats
        
        // Compute rates
        if let startTime = statsStartTime {
            let elapsed = clock.now().timeIntervalSince(startTime)
            if elapsed > 0 {
                current.oscRate = Double(stats.totalOscReceived) / elapsed
                current.httpRate = Double(stats.totalRestSent) / elapsed
            }
        }
        
        return current
    }

    private func responsePreview(from data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return String(text.prefix(200))
    }
}

// MARK: - Supporting Types

public struct BridgeStateSnapshot: Sendable {
    public let isRunning: Bool
    public let configStatus: ConfigStatus
    public let stats: BridgeStats
    public let slotState: [String: SlotState]
    public let recentOsc: [OSCMessageRecord]
    public let recentHttp: [HTTPRequestRecord]
    public let dryRun: Bool
}

public enum BridgeError: Error, LocalizedError {
    case configNotLoaded
    case alreadyRunning
    
    public var errorDescription: String? {
        switch self {
        case .configNotLoaded: return "Config not loaded"
        case .alreadyRunning: return "Already running"
        }
    }
}

// MARK: - Circular Buffer

private struct CircularBuffer<T> {
    private var buffer: [T]
    private let capacity: Int
    private var head: Int = 0
    
    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = []
        self.buffer.reserveCapacity(capacity)
    }
    
    mutating func append(_ item: T) {
        if buffer.count < capacity {
            buffer.append(item)
        } else {
            buffer[head] = item
            head = (head + 1) % capacity
        }
    }
    
    var items: [T] {
        if buffer.count < capacity {
            return buffer
        } else {
            // Reorder to get chronological order
            return Array(buffer[head..<buffer.count] + buffer[0..<head])
        }
    }
}
