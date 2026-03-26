// LedFXFeature.swift - LedFX integration orchestrator for SwiftVJApp
// Keeps SwiftVJApp slim by encapsulating LedFX-specific handling.

import Foundation
import AppKit
import OSCKit
import OscRestBridge
import SwiftVJCore
import UniformTypeIdentifiers

@MainActor
final class LedFXFeature {
    private let store: Store<SwiftVJCore.AppState, AppAction>
    private let oscHub: OSCHub
    private let log: (String, LogLevel) -> Void
    private let isTestMode: Bool

    /// Port for the OscRestBridge's own OSC listener (separate from OSCHub)
    private static let oscRestBridgeListenPort: UInt16 = 9999

    private var oscRestBridge: OscRestBridgeService?
    private var ledfxModule: LedFXModule?
    private var bridgeEventsTask: Task<Void, Never>?

    private let ledfxBridgeConfigKey = "ledfx_bridge_yaml"
    private let ledfxBaseURLKey = "ledfx_baseURL"
    private let ledfxVirtualIdsKey = "ledfx_virtualIds"

    private struct LedFXBootstrapPayload: Sendable {
        let moduleError: String?
        let yaml: String
    }

    private struct LedFXRefreshPayload: Sendable {
        let serverInfo: LedFXInfo?
        let scenes: [String: LedFXScene]
        let virtuals: [String: LedFXVirtual]
        let playlists: [String: LedFXPlaylist]
        let isOnline: Bool
    }

    private struct LedFXGeneratedConfigPayload: Sendable {
        let config: BridgeConfig
        let yaml: String
        let playlistCount: Int
        let effectsCount: Int
    }

    init(
        store: Store<SwiftVJCore.AppState, AppAction>,
        oscHub: OSCHub,
        isTestMode: Bool,
        log: @escaping (String, LogLevel) -> Void
    ) {
        self.store = store
        self.oscHub = oscHub
        self.isTestMode = isTestMode
        self.log = log
    }

    deinit {
        bridgeEventsTask?.cancel()
    }

    // MARK: - Public API

    func seedDefaultsInStore() {
        guard !isTestMode else { return }
        let defaults = loadLedFXDefaults()
        store.send(.ledfx(.setBaseURL(defaults.baseURL)))
        store.send(.ledfx(.setVirtualIds(defaults.virtualIds.joined(separator: ", "))))
    }

    func startIntegrationFromDefaults() {
        guard !isTestMode else { return }
        let defaults = loadLedFXDefaults()
        store.send(.ledfx(.applySettings(baseURL: defaults.baseURL, virtualIds: defaults.virtualIds)))
    }

    func registerOscSubscriptions() {
        oscHub.subscribe(pattern: "/ledfx/*") { [weak self] address, values in
            Task { @MainActor in
                await self?.handleLedFXOSC(address: address, values: values)
            }
        }
    }

    var bridgeService: OscRestBridgeService? {
        oscRestBridge
    }

    func handle(_ action: LedFXAction) async {
        switch action {
        case .setBaseURL(let value):
            let normalized = normalizeLedFXBaseURL(value)
            UserDefaults.standard.set(normalized, forKey: ledfxBaseURLKey)

        case .setVirtualIds(let value):
            UserDefaults.standard.set(value, forKey: ledfxVirtualIdsKey)

        case .setSceneFilter, .setPlaylistFilter:
            break

        case .applySettings(let baseURL, let virtualIds):
            let normalizedBaseURL = normalizeLedFXBaseURL(baseURL)
            await configureLedFXIntegration(baseURL: normalizedBaseURL, virtualIds: virtualIds)
            store.send(.ledfx(.applyCompleted))
            store.send(.ledfx(.refresh))
            store.send(.ledfx(.loadCachedConfig))

        case .refresh:
            await refreshLedFXData()

        case .testConnection:
            await refreshLedFXData(errorPrefix: "Connection test failed")

        case .activateScene(let id):
            await stopLedFXPlaylist(force: true)
            await performLedFXModuleAction(
                errorPrefix: "Failed to activate scene",
                action: { module in try await module.activateScene(id: id) }
            )

        case .deactivateScene(let id):
            await performLedFXModuleAction(
                errorPrefix: "Failed to deactivate scene",
                action: { module in try await module.deactivateScene(id: id) }
            )

        case .deleteScene(let id):
            await performLedFXModuleAction(
                errorPrefix: "Failed to delete scene",
                action: { module in try await module.deleteScene(id: id) }
            )

        case .activatePlaylist(let id):
            await activateLedFXPlaylist(id: id)

        case .stopPlaylist:
            await stopLedFXPlaylist(force: true)

        case .setVirtualBrightness(let id, let brightness):
            await performLedFXModuleAction(
                errorPrefix: "Failed to set brightness",
                action: { module in try await module.setVirtualBrightness(id: id, brightness: brightness) }
            )

        case .generateScenes(let seeds):
            await performLedFXModuleAction(
                errorPrefix: "Failed to generate scenes",
                action: { module in
                    let tracks = seeds.map { (name: $0.name, energy: $0.energy, valence: $0.valence, bpm: $0.bpm) }
                    try await module.generateDJSetScenes(tracks: tracks)
                }
            )

        case .generateBridgeConfig:
            await generateLedFXBridgeConfig()

        case .saveGeneratedConfig:
            await saveLedFXGeneratedConfig()

        case .loadCachedConfig:
            await loadCachedLedFXConfig()

        case .loadGeneratedConfig(let yaml):
            await loadLedFXGeneratedConfig(yaml: yaml)

        case .sendTestScene:
            await sendLedFXTestScene()

        case .sendTestPlaylist:
            await sendLedFXTestPlaylist()

        case .sendTestOneshot:
            await sendLedFXTestOneshot()

        case .clearError,
             .refreshCompleted(_),
             .refreshFailed(_),
             .generateConfigCompleted(_, _, _),
             .generateConfigFailed(_),
             .cachedConfigLoaded(_, _),
             .cachedConfigFailed(_),
             .applyCompleted,
             .playlistActivated(_),
             .playlistStopped,
             .setError(_):
            break
        }
    }

    // MARK: - LedFX Integration

    private func configureLedFXIntegration(baseURL: String, virtualIds: [String]) async {
        let normalizedBaseURL = normalizeLedFXBaseURL(baseURL)
        UserDefaults.standard.set(normalizedBaseURL, forKey: ledfxBaseURLKey)
        UserDefaults.standard.set(virtualIds.joined(separator: ","), forKey: ledfxVirtualIdsKey)

        if let existing = ledfxModule {
            await existing.stop()
        }

        let module = LedFXModule(baseURL: normalizedBaseURL, virtualIds: virtualIds)
        ledfxModule = module

        let bridge = ensureOscRestBridge()
        let oscListenPort = Self.oscRestBridgeListenPort

        let result = await Task.detached(priority: .userInitiated) { () -> LedFXBootstrapPayload in
            do {
                try await module.start()
                let config = await Self.buildLedFXBridgeConfig(
                    baseURL: normalizedBaseURL,
                    virtualIds: virtualIds,
                    oscListenPort: oscListenPort
                )
                let yaml = try ConfigLoader.export(config)
                return LedFXBootstrapPayload(moduleError: nil, yaml: yaml)
            } catch {
                return LedFXBootstrapPayload(moduleError: error.localizedDescription, yaml: "")
            }
        }.value

        if let moduleError = result.moduleError {
            log("LedFX start failed: \(moduleError)", .error)
            store.send(.ledfx(.setError("LedFX start failed: \(moduleError)")))
        }

        if !result.yaml.isEmpty {
            await applyBridgeYaml(result.yaml, bridge: bridge)
        } else if let cached = UserDefaults.standard.string(forKey: ledfxBridgeConfigKey) {
            await applyBridgeYaml(cached, bridge: bridge)
        } else {
            let fallback = LedFXBridgeConfigGenerator.generateFallback(
                baseURL: normalizedBaseURL,
                virtualIds: virtualIds,
                oscListenPort: oscListenPort
            )
            do {
                try await applyBridgeConfig(fallback, bridge: bridge)
            } catch {
                log("Failed to apply fallback LedFX bridge config: \(error.localizedDescription)", .error)
                store.send(.ledfx(.setError("Failed to apply fallback LedFX bridge config: \(error.localizedDescription)")))
            }
        }
    }

    private func normalizeLedFXBaseURL(_ baseURL: String) -> String {
        baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func refreshLedFXData(errorPrefix: String = "Failed to refresh") async {
        guard let module = ensureLedFXModule() else {
            store.send(.ledfx(.refreshFailed("\(errorPrefix): Base URL is empty")))
            return
        }

        let baseURL = store.state.ledfx.baseURL
        let result = await Task.detached(priority: .userInitiated) { () -> Result<LedFXRefreshPayload, Error> in
            do {
                let client = LedFXClient(baseURL: baseURL)
                let info = try? await client.getInfo()

                let scenes: [String: LedFXScene]
                let virtuals: [String: LedFXVirtual]

                try await module.refreshScenes()
                try await module.refreshVirtuals()
                scenes = await module.getScenes()
                virtuals = await module.getVirtuals()

                let playlistsResponse = try? await client.listPlaylists()
                let playlists = playlistsResponse?.playlists ?? [:]

                return .success(LedFXRefreshPayload(
                    serverInfo: info,
                    scenes: scenes,
                    virtuals: virtuals,
                    playlists: playlists,
                    isOnline: true
                ))
            } catch {
                return .failure(error)
            }
        }.value

        let lastCheck = Date()
        switch result {
        case .success(let payload):
            let summary = payload.serverInfo.map { "v\($0.version)" } ?? "Online"
            store.send(.ledfx(.refreshCompleted(
                LedFXRefreshSnapshot(
                    serverInfo: payload.serverInfo,
                    scenes: payload.scenes,
                    virtuals: payload.virtuals,
                    playlists: payload.playlists,
                    isOnline: payload.isOnline,
                    healthSummary: summary,
                    lastHealthCheck: lastCheck
                )
            )))
        case .failure(let error):
            store.send(.ledfx(.refreshFailed("\(errorPrefix): \(error.localizedDescription)")))
        }
    }

    private func performLedFXModuleAction(
        errorPrefix: String,
        action: @escaping @Sendable (LedFXModule) async throws -> Void
    ) async {
        guard let module = ensureLedFXModule() else {
            store.send(.ledfx(.setError("\(errorPrefix): Base URL is empty")))
            return
        }

        let result = await Task.detached(priority: .userInitiated) { () -> Result<Void, Error> in
            do {
                try await action(module)
                return .success(())
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success:
            store.send(.ledfx(.refresh))
        case .failure(let error):
            store.send(.ledfx(.setError("\(errorPrefix): \(error.localizedDescription)")))
        }
    }

    private func activateLedFXPlaylist(id: String) async {
        let baseURL = store.state.ledfx.baseURL
        guard !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            store.send(.ledfx(.setError("Failed to activate playlist: Base URL is empty")))
            return
        }

        let result = await Task.detached(priority: .userInitiated) { () -> Result<Void, Error> in
            do {
                let client = LedFXClient(baseURL: baseURL)
                try await client.startPlaylist(id: id)
                return .success(())
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success:
            store.send(.ledfx(.playlistActivated(id)))
        case .failure(let error):
            store.send(.ledfx(.setError("Failed to activate playlist: \(error.localizedDescription)")))
        }
    }

    private func stopLedFXPlaylist(force: Bool) async {
        let baseURL = store.state.ledfx.baseURL
        guard !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            store.send(.ledfx(.setError("Failed to stop playlist: Base URL is empty")))
            return
        }

        if !force, store.state.ledfx.activePlaylistId == nil {
            return
        }

        let result = await Task.detached(priority: .userInitiated) { () -> Result<Void, Error> in
            do {
                let client = LedFXClient(baseURL: baseURL)
                try await client.stopPlaylist()
                return .success(())
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success:
            store.send(.ledfx(.playlistStopped))
        case .failure(let error):
            store.send(.ledfx(.setError("Failed to stop playlist: \(error.localizedDescription)")))
        }
    }

    private func generateLedFXBridgeConfig() async {
        let currentBaseURL = store.state.ledfx.baseURL
        let oscListenPort = Self.oscRestBridgeListenPort

        let result = await Task.detached(priority: .userInitiated) { () -> Result<LedFXGeneratedConfigPayload, Error> in
            do {
                let client = LedFXClient(baseURL: currentBaseURL)
                let playlistsResponse = try await client.listPlaylists()
                let scenesResponse = try await client.listScenes()
                let virtualsResponse = try await client.listVirtuals()
                let effectsResponse = try await client.listEffectsCatalog()

                let input = LedFXBridgeConfigGenerator.Input(
                    baseURL: currentBaseURL,
                    playlists: playlistsResponse.playlists,
                    scenes: scenesResponse,
                    virtuals: virtualsResponse,
                    effects: effectsResponse.effects
                )

                let config = try LedFXBridgeConfigGenerator.generate(
                    input: input,
                    oscListenPort: oscListenPort
                )
                let yaml = try ConfigLoader.export(config)

                return .success(LedFXGeneratedConfigPayload(
                    config: config,
                    yaml: yaml,
                    playlistCount: playlistsResponse.playlists.count,
                    effectsCount: effectsResponse.effects.count
                ))
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let payload):
            store.send(.ledfx(.generateConfigCompleted(
                yaml: payload.yaml,
                playlistCount: payload.playlistCount,
                effectsCount: payload.effectsCount
            )))
        case .failure(let error):
            store.send(.ledfx(.generateConfigFailed("Failed to generate config: \(error.localizedDescription)")))
        }
    }

    private func loadCachedLedFXConfig() async {
        guard let yaml = UserDefaults.standard.string(forKey: ledfxBridgeConfigKey) else { return }

        let result = await Task.detached(priority: .utility) { () -> Result<BridgeConfig, Error> in
            do {
                let config = try ConfigLoader.load(from: yaml)
                return .success(config)
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let config):
            store.send(.ledfx(.cachedConfigLoaded(
                yaml: yaml,
                playlistCount: config.playlists.count
            )))
        case .failure(let error):
            store.send(.ledfx(.cachedConfigFailed("Failed to load cached config: \(error.localizedDescription)")))
        }
    }

    private func loadLedFXGeneratedConfig(yaml: String) async {
        UserDefaults.standard.set(yaml, forKey: ledfxBridgeConfigKey)

        let bridge = ensureOscRestBridge()
        let result = await Task.detached(priority: .userInitiated) { () -> Result<Void, Error> in
            do {
                try await bridge.loadConfig(from: Data(yaml.utf8))
                try? await bridge.start()
                return .success(())
            } catch {
                return .failure(error)
            }
        }.value

        if case .failure(let error) = result {
            store.send(.ledfx(.setError("Failed to load config: \(error.localizedDescription)")))
        }
    }

    private func saveLedFXGeneratedConfig() async {
        guard let yaml = store.state.ledfx.generatedYaml else {
            store.send(.ledfx(.setError("Generate a config before saving")))
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "yaml") ?? .plainText]
        panel.nameFieldStringValue = "ledfx-bridge.yaml"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let result = await Task.detached(priority: .utility) { () -> Result<Void, Error> in
            do {
                try yaml.write(to: url, atomically: true, encoding: .utf8)
                return .success(())
            } catch {
                return .failure(error)
            }
        }.value

        if case .failure(let error) = result {
            store.send(.ledfx(.setError("Failed to save config: \(error.localizedDescription)")))
        }
    }

    private func sendLedFXTestScene() async {
        let scenes = store.state.ledfx.scenes
        guard let sceneId = scenes.keys.sorted().first else { return }
        let slot = slotIdsForPaths().first ?? "0"
        await sendLedFXOSC(path: "/ledfx/scene/\(sceneId)/\(slot)")
    }

    private func sendLedFXTestPlaylist() async {
        let playlists = store.state.ledfx.playlists
        guard let playlistId = playlists.keys.sorted().first else { return }
        let slot = slotIdsForPaths().first ?? "0"
        await sendLedFXOSC(path: "/ledfx/playlist/\(playlistId)/\(slot)")
    }

    private func sendLedFXTestOneshot() async {
        let oneshotName = defaultOneshotName()
        let slot = slotIdsForPaths().first ?? "0"
        await sendLedFXOSC(path: "/ledfx/oneshot/\(oneshotName)/\(slot)")
    }

    private func sendLedFXOSC(path: String) async {
        let hub = oscHub
        let targetPort = Self.oscRestBridgeListenPort
        let result = await Task.detached(priority: .userInitiated) { () -> Result<Void, Error> in
            do {
                let values: [any OSCValue] = [Float32(1.0)]
                try hub.send(path, values: values, host: "127.0.0.1", port: targetPort)
                return .success(())
            } catch {
                return .failure(error)
            }
        }.value

        if case .failure(let error) = result {
            store.send(.ledfx(.setError("Failed to send test OSC: \(error.localizedDescription)")))
        }
    }

    private func ensureLedFXModule() -> LedFXModule? {
        if let module = ledfxModule { return module }

        let trimmedBaseURL = store.state.ledfx.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBaseURL.isEmpty else { return nil }

        let module = LedFXModule(baseURL: trimmedBaseURL, virtualIds: virtualIdsFromState())
        ledfxModule = module
        return module
    }

    private func ensureOscRestBridge() -> OscRestBridgeService {
        if let bridge = oscRestBridge { return bridge }
        let bridge = createDefaultBridgeService()
        oscRestBridge = bridge
        startBridgeEventListener()
        return bridge
    }

    private func applyBridgeYaml(_ yaml: String, bridge: OscRestBridgeService) async {
        UserDefaults.standard.set(yaml, forKey: ledfxBridgeConfigKey)
        do {
            try await bridge.loadConfig(from: Data(yaml.utf8))
            try? await bridge.start()
        } catch {
            log("Failed to apply LedFX bridge config: \(error.localizedDescription)", .error)
            store.send(.ledfx(.setError("Failed to apply LedFX bridge config: \(error.localizedDescription)")))
        }
    }

    private func applyBridgeConfig(_ config: BridgeConfig, bridge: OscRestBridgeService) async throws {
        let yaml = try ConfigLoader.export(config)
        UserDefaults.standard.set(yaml, forKey: ledfxBridgeConfigKey)
        try await bridge.loadConfig(from: Data(yaml.utf8))
        try? await bridge.start()
    }

    private static func buildLedFXBridgeConfig(
        baseURL: String,
        virtualIds: [String],
        oscListenPort: UInt16
    ) async -> BridgeConfig {
        do {
            let client = LedFXClient(baseURL: baseURL)
            let virtuals = try await client.listVirtuals()

            if virtuals.isEmpty {
                return LedFXBridgeConfigGenerator.generateFallback(
                    baseURL: baseURL,
                    virtualIds: virtualIds,
                    oscListenPort: oscListenPort
                )
            }

            let scenes = (try? await client.listScenes()) ?? [:]
            let playlistsResponse = try? await client.listPlaylists()
            let playlists = playlistsResponse?.playlists ?? [:]
            let effectsResponse = try? await client.listEffectsCatalog()
            let effects = effectsResponse?.effects ?? [:]

            return try LedFXBridgeConfigGenerator.generate(
                input: LedFXBridgeConfigGenerator.Input(
                    baseURL: baseURL,
                    playlists: playlists,
                    scenes: scenes,
                    virtuals: virtuals,
                    effects: effects
                ),
                oscListenPort: oscListenPort
            )
        } catch {
            return LedFXBridgeConfigGenerator.generateFallback(
                baseURL: baseURL,
                virtualIds: virtualIds,
                oscListenPort: oscListenPort
            )
        }
    }

    private func loadLedFXDefaults() -> (baseURL: String, virtualIds: [String]) {
        let baseURL = UserDefaults.standard.string(forKey: ledfxBaseURLKey) ?? "http://127.0.0.1:8888"
        let virtualIdsString = UserDefaults.standard.string(forKey: ledfxVirtualIdsKey) ?? ""
        let virtualIds = virtualIdsString
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return (baseURL: baseURL, virtualIds: virtualIds)
    }

    private func virtualIdsFromState() -> [String] {
        store.state.ledfx.virtualIdsString
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func slotIdsForPaths() -> [String] {
        if let yaml = store.state.ledfx.generatedYaml,
           let config = try? ConfigLoader.load(from: yaml),
           !config.slots.isEmpty {
            return config.slots.keys.sorted()
        }
        let virtualIds = virtualIdsFromState()
        if !virtualIds.isEmpty {
            return virtualIds.indices.map { String($0) }
        }
        return ["0"]
    }

    private func defaultOneshotName() -> String {
        if let yaml = store.state.ledfx.generatedYaml,
           let config = try? ConfigLoader.load(from: yaml),
           let oneshot = config.oneshots.keys.sorted().first {
            return oneshot
        }
        return "whiteflash"
    }

    private func handleLedFXOSC(address: String, values: [Any]) async {
        guard let bridge = oscRestBridge else { return }
        let numericValue = OSCRouteParser.extractNumeric(values)
        await bridge.handleOSCMessage(path: address, numericValue: numericValue)
    }

    private func startBridgeEventListener() {
        bridgeEventsTask?.cancel()
        guard let bridge = oscRestBridge else { return }

        bridgeEventsTask = Task { [weak self] in
            let events = await bridge.events
            for await event in events {
                guard let self else { return }
                self.handleLedFXBridgeEvent(event)
            }
        }
    }

    private func handleLedFXBridgeEvent(_ event: BridgeEvent) {
        switch event {
        case .oscReceived(_, _, let value, let parsed):
            guard value > 0, let parsed else { return }
            switch parsed {
            case .playlist(_, let playlistId):
                store.send(.ledfx(.playlistActivated(playlistId)))
            case .playlistControl(_, let action):
                if action == "stop" {
                    store.send(.ledfx(.playlistStopped))
                }
            case .scene(_, _):
                store.send(.ledfx(.stopPlaylist))
            default:
                break
            }

        case .restResponse(_, let plan, let statusCode, let body):
            let summary = "LedFX REST \(statusCode) \(plan.method) \(plan.url)"
            log(summary, statusCode >= 400 ? .warning : .info)
            if statusCode >= 400 {
                store.send(.ledfx(.setError("LedFX REST \(statusCode): \(plan.url)")))
            }
            if let body, !body.isEmpty {
                log("LedFX REST body: \(body)", .debug)
            }

        case .restFailure(_, let plan, let error):
            log("LedFX REST failed \(plan.method) \(plan.url): \(error)", .error)
            store.send(.ledfx(.setError("LedFX REST error: \(error)")))

        case .configInvalid(_, let errors):
            let summary = errors.map { $0.message }.joined(separator: " • ")
            log("LedFX bridge config invalid: \(summary)", .error)
            store.send(.ledfx(.setError("LedFX config invalid: \(summary)")))

        default:
            break
        }
    }
}
