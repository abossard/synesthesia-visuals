import Foundation
import SwiftVJCore
import SongRepository

final class SwiftVJMCPServer: @unchecked Sendable {
    private let input: FileHandle
    private let output: FileHandle
    private let queue = DispatchQueue(label: "swiftvj.mcp.server.queue")
    private let separator = Data("\r\n\r\n".utf8)
    private let messageHandler: (Data) async -> Data?

    private var buffer = Data()
    private var isRunning = false

    init(
        input: FileHandle = .standardInput,
        output: FileHandle = .standardOutput,
        messageHandler: @escaping (Data) async -> Data?
    ) {
        self.input = input
        self.output = output
        self.messageHandler = messageHandler
    }

    func start() {
        queue.async { [weak self] in
            guard let self, !self.isRunning else { return }
            self.isRunning = true
            self.input.readabilityHandler = { [weak self] handle in
                guard let self else { return }
                self.queue.async {
                    self.consume(handle.availableData)
                }
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isRunning = false
            self.input.readabilityHandler = nil
            self.buffer.removeAll(keepingCapacity: false)
        }
    }

    private func consume(_ chunk: Data) {
        guard isRunning else { return }
        guard !chunk.isEmpty else {
            stop()
            return
        }

        buffer.append(chunk)
        while let message = nextMessageBody() {
            Task { [weak self] in
                guard let self else { return }
                if let response = await self.messageHandler(message) {
                    self.send(response)
                }
            }
        }
    }

    private func nextMessageBody() -> Data? {
        guard let headerRange = buffer.range(of: separator) else {
            return nil
        }
        let headerData = buffer[..<headerRange.lowerBound]
        guard let headerString = String(data: headerData, encoding: .utf8),
              let contentLength = parseContentLength(headerString) else {
            buffer.removeSubrange(buffer.startIndex..<headerRange.upperBound)
            return nil
        }

        let bodyStart = headerRange.upperBound
        let availableBytes = buffer.distance(from: bodyStart, to: buffer.endIndex)
        guard availableBytes >= contentLength else { return nil }

        let bodyEnd = buffer.index(bodyStart, offsetBy: contentLength)
        let body = Data(buffer[bodyStart..<bodyEnd])
        buffer.removeSubrange(buffer.startIndex..<bodyEnd)
        return body
    }

    private func parseContentLength(_ header: String) -> Int? {
        for line in header.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard key == "content-length" else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(value)
        }
        return nil
    }

    private func send(_ payload: Data) {
        queue.async { [weak self] in
            guard let self, self.isRunning else { return }
            var framed = Data("Content-Length: \(payload.count)\r\n\r\n".utf8)
            framed.append(payload)
            self.output.write(framed)
        }
    }
}

@MainActor
final class SwiftVJMCPDataService {
    private weak var appState: AppState?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(appState: AppState) {
        self.appState = appState
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func handle(messageData: Data) async -> Data? {
        guard let request = (try? JSONSerialization.jsonObject(with: messageData)) as? [String: Any] else {
            return makeErrorResponse(id: NSNull(), code: -32700, message: "Parse error")
        }

        let id = request["id"]
        guard let method = request["method"] as? String else {
            return makeErrorResponse(id: id ?? NSNull(), code: -32600, message: "Invalid request")
        }

        let params = request["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            let result: [String: Any] = [
                "protocolVersion": "2024-11-05",
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "swift-vj-data", "version": swiftVJVersion]
            ]
            return makeResultResponse(id: id, result: result)

        case "notifications/initialized":
            return nil

        case "ping":
            return makeResultResponse(id: id, result: [:])

        case "tools/list":
            return makeResultResponse(id: id, result: ["tools": toolDefinitions()])

        case "tools/call":
            guard let name = stringValue(params["name"]) else {
                return makeErrorResponse(id: id ?? NSNull(), code: -32602, message: "Missing tool name")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let outcome = await executeTool(name: name, arguments: arguments, allowBatch: true)
            let text = prettyJSONString(outcome.payload)
            let result: [String: Any] = [
                "content": [["type": "text", "text": text]],
                "isError": outcome.isError,
                "structuredContent": outcome.payload
            ]
            return makeResultResponse(id: id, result: result)

        default:
            if id == nil {
                return nil
            }
            return makeErrorResponse(id: id ?? NSNull(), code: -32601, message: "Method not found: \(method)")
        }
    }

    private struct ToolOutcome {
        var payload: [String: Any]
        var isError: Bool
    }

    private func executeTool(name: String, arguments: [String: Any], allowBatch: Bool) async -> ToolOutcome {
        switch name {
        case "data.batch_apply":
            guard allowBatch else {
                return failure("Nested batch calls are not allowed")
            }
            return await handleBatchApply(arguments)

        case "shaders.list":
            return await listShaders(maskOnly: false, arguments: arguments)

        case "masks.list":
            return await listShaders(maskOnly: true, arguments: arguments)

        case "shaders.set_phases":
            return await setShaderPhases(maskOnly: false, arguments: arguments)

        case "masks.set_phases":
            return await setShaderPhases(maskOnly: true, arguments: arguments)

        case "shaders.move":
            return await moveShaders(maskOnly: false, arguments: arguments)

        case "masks.move":
            return await moveShaders(maskOnly: true, arguments: arguments)

        case "shaders.rename":
            return await renameShaders(maskOnly: false, arguments: arguments)

        case "masks.rename":
            return await renameShaders(maskOnly: true, arguments: arguments)

        case "songs.refresh":
            return await refreshSongs()

        case "songs.list":
            return listSongs(arguments)

        case "songs.set_shader":
            return await setSongShaders(arguments)

        case "songs.delete":
            return await deleteSongs(arguments)

        case "automation.get_timeline":
            return getAutomationTimeline(arguments)

        case "automation.set_timeline":
            return setAutomationTimeline(arguments)

        case "automation.set_settings":
            return setAutomationSettings(arguments)

        case "playlists.get":
            return getPlaylists(arguments)

        case "playlists.set":
            return setPlaylists(arguments)

        default:
            return failure("Unknown data-management tool: \(name)")
        }
    }

    private func toolDefinitions() -> [[String: Any]] {
        [
            tool(
                name: "data.batch_apply",
                description: "Apply multiple data-management operations in one call.",
                required: ["operations"]
            ),
            tool(name: "shaders.list", description: "List non-mask shaders."),
            tool(name: "masks.list", description: "List mask shaders."),
            tool(name: "shaders.set_phases", description: "Set shader phases (supports batch)."),
            tool(name: "masks.set_phases", description: "Set mask phases (supports batch)."),
            tool(name: "shaders.move", description: "Move shaders to folders (supports batch)."),
            tool(name: "masks.move", description: "Move masks to folders (supports batch)."),
            tool(name: "shaders.rename", description: "Rename shader files (supports batch)."),
            tool(name: "masks.rename", description: "Rename mask files (supports batch)."),
            tool(name: "songs.refresh", description: "Reload and refresh song state."),
            tool(name: "songs.list", description: "List songs from Store-backed state."),
            tool(name: "songs.set_shader", description: "Assign shaders to songs (supports batch)."),
            tool(name: "songs.delete", description: "Delete songs (supports batch)."),
            tool(name: "automation.get_timeline", description: "Read automation timeline for a song."),
            tool(name: "automation.set_timeline", description: "Replace automation timelines (supports batch)."),
            tool(name: "automation.set_settings", description: "Set automation master and auto-record settings."),
            tool(name: "playlists.get", description: "Read per-phase shader/mask playlists."),
            tool(name: "playlists.set", description: "Replace per-phase shader/mask playlists (supports batch).")
        ]
    }

    private func tool(name: String, description: String, required: [String] = []) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": [
                "type": "object",
                "required": required,
                "additionalProperties": true
            ]
        ]
    }

    private func handleBatchApply(_ arguments: [String: Any]) async -> ToolOutcome {
        let modeRaw = stringValue(arguments["mode"])?.lowercased() ?? "besteffort"
        let mode = modeRaw == "atomic" ? "atomic" : "bestEffort"
        let dryRun = boolValue(arguments["dryRun"], default: false)
        let operations = dictionaryArray(arguments["operations"])
        guard !operations.isEmpty else {
            return failure("operations must be a non-empty array")
        }

        var results: [[String: Any]] = []
        var errorCount = 0
        var executed = 0

        for (index, operation) in operations.enumerated() {
            guard let toolName = stringValue(operation["tool"]) else {
                let entry: [String: Any] = [
                    "index": index,
                    "tool": NSNull(),
                    "ok": false,
                    "result": ["error": "Missing operation.tool"]
                ]
                results.append(entry)
                errorCount += 1
                if mode == "atomic" { break }
                continue
            }

            var opArguments = operation["arguments"] as? [String: Any] ?? [:]
            if dryRun, opArguments["dryRun"] == nil {
                opArguments["dryRun"] = true
            }

            let outcome = await executeTool(name: toolName, arguments: opArguments, allowBatch: false)
            let entry: [String: Any] = [
                "index": index,
                "tool": toolName,
                "ok": !outcome.isError,
                "result": outcome.payload
            ]
            results.append(entry)
            executed += 1
            if outcome.isError {
                errorCount += 1
                if mode == "atomic" { break }
            }
        }

        return ToolOutcome(
            payload: [
                "mode": mode,
                "dryRun": dryRun,
                "requestedCount": operations.count,
                "executedCount": executed,
                "errorCount": errorCount,
                "results": results
            ],
            isError: errorCount > 0
        )
    }

    private func listShaders(maskOnly: Bool, arguments: [String: Any]) async -> ToolOutcome {
        guard let appState, let repository = appState.renderEngine?.shaderRepository else {
            return failure("Shader repository unavailable")
        }
        _ = await repository.reload()

        var shaders = maskOnly ? repository.masks : repository.regularShaders
        if let folder = stringValue(arguments["folder"]), !folder.isEmpty {
            shaders = shaders.filter { $0.folder.caseInsensitiveCompare(folder) == .orderedSame }
        }
        if let query = stringValue(arguments["query"])?.lowercased(), !query.isEmpty {
            shaders = shaders.filter { shader in
                shader.name.lowercased().contains(query) || shader.folder.lowercased().contains(query)
            }
        }
        if let limit = intValue(arguments["limit"]), limit > 0 {
            shaders = Array(shaders.prefix(limit))
        }

        let items = shaders.map(shaderPayload)
        return success([
            "domain": maskOnly ? "masks" : "shaders",
            "count": items.count,
            "items": items
        ])
    }

    private func setShaderPhases(maskOnly: Bool, arguments: [String: Any]) async -> ToolOutcome {
        guard let appState, let repository = appState.renderEngine?.shaderRepository else {
            return failure("Shader repository unavailable")
        }

        let dryRun = boolValue(arguments["dryRun"], default: false)
        let updates = phaseUpdates(arguments)
        guard !updates.isEmpty else {
            return failure("Provide updates or name+phases")
        }

        var updated: [String] = []
        var failed: [[String: Any]] = []

        for update in updates {
            guard let name = stringValue(update["name"]) else {
                failed.append(["name": NSNull(), "error": "Missing name"])
                continue
            }
            guard let shader = repository.shader(named: name) else {
                failed.append(["name": name, "error": "Shader not found"])
                continue
            }
            if maskOnly && !shader.isMask {
                failed.append(["name": name, "error": "Not a mask shader"])
                continue
            }
            if !maskOnly && shader.isMask {
                failed.append(["name": name, "error": "Use masks.set_phases for mask shader"])
                continue
            }
            guard update["phases"] != nil else {
                failed.append(["name": name, "error": "Missing phases"])
                continue
            }

            let phaseNames = stringArray(update["phases"])
            let invalid = phaseNames.filter { phase(from: $0) == nil }
            if !invalid.isEmpty {
                failed.append(["name": name, "error": "Invalid phases: \(invalid.joined(separator: ", "))"])
                continue
            }
            let phases = Set(phaseNames.compactMap { phase(from: $0) })
            guard !dryRun else {
                updated.append(name)
                continue
            }
            do {
                try persistShaderPhases(shader: shader, phases: phases)
                updated.append(name)
            } catch {
                failed.append(["name": name, "error": error.localizedDescription])
            }
        }

        if !dryRun, !updated.isEmpty {
            _ = await repository.reload()
        }

        return ToolOutcome(
            payload: [
                "dryRun": dryRun,
                "updatedCount": updated.count,
                "updated": updated,
                "failedCount": failed.count,
                "failed": failed
            ],
            isError: !failed.isEmpty
        )
    }

    private func moveShaders(maskOnly: Bool, arguments: [String: Any]) async -> ToolOutcome {
        guard let appState, let repository = appState.renderEngine?.shaderRepository else {
            return failure("Shader repository unavailable")
        }

        let dryRun = boolValue(arguments["dryRun"], default: false)
        let updates = moveUpdates(arguments)
        guard !updates.isEmpty else {
            return failure("Provide updates or name(s)+folder")
        }

        var moved: [String] = []
        var failed: [[String: Any]] = []

        for update in updates {
            guard let name = stringValue(update["name"]),
                  let folder = stringValue(update["folder"]),
                  !folder.isEmpty else {
                failed.append(["name": (stringValue(update["name"]) as Any?) ?? NSNull(), "error": "Missing name or folder"])
                continue
            }
            guard let shader = repository.shader(named: name) else {
                failed.append(["name": name, "error": "Shader not found"])
                continue
            }
            if maskOnly && !shader.isMask {
                failed.append(["name": name, "error": "Not a mask shader"])
                continue
            }
            if !maskOnly && shader.isMask {
                failed.append(["name": name, "error": "Use masks.move for mask shader"])
                continue
            }
            guard !dryRun else {
                moved.append(name)
                continue
            }
            do {
                try repository.moveToFolder(shaderName: name, folder: folder)
                moved.append(name)
            } catch {
                failed.append(["name": name, "error": error.localizedDescription])
            }
        }

        if !dryRun, !moved.isEmpty {
            _ = await repository.reload()
        }

        return ToolOutcome(
            payload: [
                "dryRun": dryRun,
                "movedCount": moved.count,
                "moved": moved,
                "failedCount": failed.count,
                "failed": failed
            ],
            isError: !failed.isEmpty
        )
    }

    private func renameShaders(maskOnly: Bool, arguments: [String: Any]) async -> ToolOutcome {
        guard let appState, let repository = appState.renderEngine?.shaderRepository else {
            return failure("Shader repository unavailable")
        }

        let dryRun = boolValue(arguments["dryRun"], default: false)
        let updates = renameUpdates(arguments)
        guard !updates.isEmpty else {
            return failure("Provide updates or oldName/newName")
        }

        var renamed: [[String: Any]] = []
        var failed: [[String: Any]] = []

        for update in updates {
            guard let oldName = stringValue(update["oldName"]),
                  let newName = stringValue(update["newName"]),
                  !newName.isEmpty else {
                failed.append([
                    "oldName": (stringValue(update["oldName"]) as Any?) ?? NSNull(),
                    "newName": (stringValue(update["newName"]) as Any?) ?? NSNull(),
                    "error": "Missing oldName or newName"
                ])
                continue
            }
            guard let shader = repository.shader(named: oldName) else {
                failed.append(["oldName": oldName, "newName": newName, "error": "Shader not found"])
                continue
            }
            if maskOnly && !shader.isMask {
                failed.append(["oldName": oldName, "newName": newName, "error": "Not a mask shader"])
                continue
            }
            if !maskOnly && shader.isMask {
                failed.append(["oldName": oldName, "newName": newName, "error": "Use masks.rename for mask shader"])
                continue
            }
            guard !dryRun else {
                renamed.append(["oldName": oldName, "newName": newName])
                continue
            }
            do {
                try renameShaderFiles(shader: shader, newName: newName)
                renamed.append(["oldName": oldName, "newName": newName])
            } catch {
                failed.append(["oldName": oldName, "newName": newName, "error": error.localizedDescription])
            }
        }

        if !dryRun, !renamed.isEmpty {
            _ = await repository.reload()
        }

        return ToolOutcome(
            payload: [
                "dryRun": dryRun,
                "renamedCount": renamed.count,
                "renamed": renamed,
                "failedCount": failed.count,
                "failed": failed
            ],
            isError: !failed.isEmpty
        )
    }

    private func refreshSongs() async -> ToolOutcome {
        guard let appState else { return failure("App state unavailable") }
        appState.send(.songs(.load))
        try? await Task.sleep(for: .milliseconds(120))
        appState.send(.songs(.refreshList))
        try? await Task.sleep(for: .milliseconds(120))
        return success([
            "totalCount": appState.songsState.totalCount,
            "displayedCount": appState.songsState.displayedSongs.count
        ])
    }

    private func listSongs(_ arguments: [String: Any]) -> ToolOutcome {
        guard let appState else { return failure("App state unavailable") }

        var songs = appState.songsState.displayedSongs
        if let query = stringValue(arguments["query"])?.lowercased(), !query.isEmpty {
            songs = songs.filter { song in
                song.artist.lowercased().contains(query)
                    || song.title.lowercased().contains(query)
                    || song.album.lowercased().contains(query)
                    || song.id.rawValue.lowercased().contains(query)
            }
        }
        if let statusRaw = stringValue(arguments["status"]),
           let status = SongStatus(rawValue: statusRaw) {
            songs = songs.filter { $0.status == status }
        }
        if let limit = intValue(arguments["limit"]), limit > 0 {
            songs = Array(songs.prefix(limit))
        }

        return success([
            "count": songs.count,
            "items": songs.map(songPayload)
        ])
    }

    private func setSongShaders(_ arguments: [String: Any]) async -> ToolOutcome {
        guard let appState else { return failure("App state unavailable") }
        let dryRun = boolValue(arguments["dryRun"], default: false)
        let assignments = songShaderAssignments(arguments)
        guard !assignments.isEmpty else {
            return failure("Provide assignments or songId+shaderName")
        }

        var updated: [[String: Any]] = []
        var failed: [[String: Any]] = []

        for assignment in assignments {
            guard let songIdRaw = stringValue(assignment["songId"]),
                  let shaderName = stringValue(assignment["shaderName"]),
                  !shaderName.isEmpty else {
                failed.append(["songId": (stringValue(assignment["songId"]) as Any?) ?? NSNull(), "error": "Missing songId or shaderName"])
                continue
            }
            guard !dryRun else {
                updated.append(["songId": songIdRaw, "shaderName": shaderName])
                continue
            }
            appState.send(.songs(.setShader(SongID(rawValue: songIdRaw), shaderName)))
            updated.append(["songId": songIdRaw, "shaderName": shaderName])
        }

        if !dryRun, !updated.isEmpty {
            try? await Task.sleep(for: .milliseconds(120))
            appState.send(.songs(.refreshList))
        }

        return ToolOutcome(
            payload: [
                "dryRun": dryRun,
                "updatedCount": updated.count,
                "updated": updated,
                "failedCount": failed.count,
                "failed": failed
            ],
            isError: !failed.isEmpty
        )
    }

    private func deleteSongs(_ arguments: [String: Any]) async -> ToolOutcome {
        guard let appState else { return failure("App state unavailable") }
        let dryRun = boolValue(arguments["dryRun"], default: false)
        let songIDs = songIDList(arguments)
        guard !songIDs.isEmpty else {
            return failure("Provide songIds or songId")
        }

        var deleted: [String] = []
        var failed: [[String: Any]] = []

        for songIdRaw in songIDs {
            guard !songIdRaw.isEmpty else {
                failed.append(["songId": NSNull(), "error": "Invalid songId"])
                continue
            }
            guard !dryRun else {
                deleted.append(songIdRaw)
                continue
            }
            appState.send(.songs(.deleteSong(SongID(rawValue: songIdRaw))))
            deleted.append(songIdRaw)
        }

        if !dryRun, !deleted.isEmpty {
            try? await Task.sleep(for: .milliseconds(120))
            appState.send(.songs(.refreshList))
        }

        return ToolOutcome(
            payload: [
                "dryRun": dryRun,
                "deletedCount": deleted.count,
                "deleted": deleted,
                "failedCount": failed.count,
                "failed": failed
            ],
            isError: !failed.isEmpty
        )
    }

    private func getAutomationTimeline(_ arguments: [String: Any]) -> ToolOutcome {
        guard let appState else { return failure("App state unavailable") }
        let songID: SongID?
        if let raw = stringValue(arguments["songId"]), !raw.isEmpty {
            songID = SongID(rawValue: raw)
        } else {
            songID = appState.automationState.selectedSongId
        }
        guard let songID else {
            return failure("Missing songId and no selected song")
        }

        let timeline = appState.automationTimeline(for: songID)
        return success([
            "songId": songID.rawValue,
            "exists": timeline != nil,
            "timeline": timeline.flatMap(toJSONObject) ?? NSNull(),
            "settings": [
                "isEnabled": appState.automationState.isEnabled,
                "autoRecordEnabled": appState.automationState.autoRecordEnabled,
                "autoRecordPrefixes": appState.automationState.autoRecordPrefixes
            ]
        ])
    }

    private func setAutomationTimeline(_ arguments: [String: Any]) -> ToolOutcome {
        guard let appState else { return failure("App state unavailable") }
        let dryRun = boolValue(arguments["dryRun"], default: false)
        let updates = timelineUpdates(arguments)
        guard !updates.isEmpty else {
            return failure("Provide updates or songId+timeline")
        }

        var updated: [String] = []
        var failed: [[String: Any]] = []

        for update in updates {
            guard let songIdRaw = stringValue(update["songId"]) else {
                failed.append(["songId": NSNull(), "error": "Missing songId"])
                continue
            }
            guard let timelineObject = update["timeline"] else {
                failed.append(["songId": songIdRaw, "error": "Missing timeline"])
                continue
            }
            do {
                _ = try decodeTimeline(from: timelineObject)
            } catch {
                failed.append(["songId": songIdRaw, "error": "Invalid timeline payload: \(error.localizedDescription)"])
                continue
            }
            guard !dryRun else {
                updated.append(songIdRaw)
                continue
            }
            do {
                let timeline = try decodeTimeline(from: timelineObject)
                appState.send(.automation(.setTimeline(songID: SongID(rawValue: songIdRaw), timeline: timeline)))
                updated.append(songIdRaw)
            } catch {
                failed.append(["songId": songIdRaw, "error": error.localizedDescription])
            }
        }

        return ToolOutcome(
            payload: [
                "dryRun": dryRun,
                "updatedCount": updated.count,
                "updatedSongIds": updated,
                "failedCount": failed.count,
                "failed": failed
            ],
            isError: !failed.isEmpty
        )
    }

    private func setAutomationSettings(_ arguments: [String: Any]) -> ToolOutcome {
        guard let appState else { return failure("App state unavailable") }
        if let enabled = boolValueOptional(arguments["isEnabled"]) {
            appState.setAutomationEnabled(enabled)
        }
        if let autoRecord = boolValueOptional(arguments["autoRecordEnabled"]) {
            appState.setAutomationAutoRecordEnabled(autoRecord)
        }
        if let prefixes = arguments["autoRecordPrefixes"] {
            appState.setAutomationAutoRecordPrefixes(stringArray(prefixes))
        }
        return success([
            "isEnabled": appState.automationState.isEnabled,
            "autoRecordEnabled": appState.automationState.autoRecordEnabled,
            "autoRecordPrefixes": appState.automationState.autoRecordPrefixes
        ])
    }

    private func getPlaylists(_ arguments: [String: Any]) -> ToolOutcome {
        guard let appState else { return failure("App state unavailable") }
        let phases: [Phase]
        if let raw = stringValue(arguments["phase"]) {
            guard let phase = phase(from: raw) else {
                return failure("Invalid phase: \(raw)")
            }
            phases = [phase]
        } else {
            phases = Phase.allCases
        }

        let phasePayloads = phases.map { phase in
            playlistPayload(appState: appState, phase: phase)
        }
        return success([
            "shaderAutoAdvanceOnSongChange": appState.shaderAutoAdvanceOnSongChange,
            "maskAutoAdvanceOnSongChange": appState.maskAutoAdvanceOnSongChange,
            "phases": phasePayloads
        ])
    }

    private func setPlaylists(_ arguments: [String: Any]) -> ToolOutcome {
        guard let appState else { return failure("App state unavailable") }
        let dryRun = boolValue(arguments["dryRun"], default: false)
        let updates = playlistUpdates(arguments)
        guard !updates.isEmpty else {
            return failure("Provide updates or phase payload")
        }

        var updated: [String] = []
        var failed: [[String: Any]] = []

        if let shaderAutoAdvance = boolValueOptional(arguments["shaderAutoAdvanceOnSongChange"]), !dryRun {
            appState.setShaderAutoAdvanceOnSongChange(shaderAutoAdvance)
        }
        if let maskAutoAdvance = boolValueOptional(arguments["maskAutoAdvanceOnSongChange"]), !dryRun {
            appState.setMaskAutoAdvanceOnSongChange(maskAutoAdvance)
        }

        for update in updates {
            guard let phaseRaw = stringValue(update["phase"]),
                  let phase = phase(from: phaseRaw) else {
                failed.append(["phase": (stringValue(update["phase"]) as Any?) ?? NSNull(), "error": "Invalid phase"])
                continue
            }

            guard !dryRun else {
                updated.append(phase.rawValue)
                continue
            }

            if let shaderPlaylistAny = update["shaderPlaylist"] {
                let desired = stringArray(shaderPlaylistAny)
                let existing = appState.shaderPlaylist(for: phase)
                if !existing.isEmpty {
                    for index in stride(from: existing.count - 1, through: 0, by: -1) {
                        appState.removeShaderFromPhasePlaylist(phase: phase, index: index)
                    }
                }
                for shader in desired.reversed() {
                    appState.addShaderToPhasePlaylist(phase: phase, shaderName: shader, activate: false)
                }
                if let shaderIndex = intValue(update["shaderIndex"]),
                   desired.indices.contains(shaderIndex) {
                    appState.activateShaderInPhasePlaylist(phase: phase, index: shaderIndex)
                }
            }

            if let maskPlaylistAny = update["maskPlaylist"] {
                let desired = stringArray(maskPlaylistAny)
                let existing = appState.maskPlaylist(for: phase)
                if !existing.isEmpty {
                    for index in stride(from: existing.count - 1, through: 0, by: -1) {
                        appState.removeMaskFromPhasePlaylist(phase: phase, index: index)
                    }
                }
                for mask in desired.reversed() {
                    appState.addMaskToPhasePlaylist(phase: phase, maskName: mask, activate: false)
                }
                if let maskIndex = intValue(update["maskIndex"]),
                   desired.indices.contains(maskIndex) {
                    appState.activateMaskInPhasePlaylist(phase: phase, index: maskIndex)
                }
            }

            updated.append(phase.rawValue)
        }

        return ToolOutcome(
            payload: [
                "dryRun": dryRun,
                "updatedCount": updated.count,
                "updatedPhases": updated,
                "failedCount": failed.count,
                "failed": failed
            ],
            isError: !failed.isEmpty
        )
    }

    private func playlistPayload(appState: AppState, phase: Phase) -> [String: Any] {
        [
            "phase": phase.rawValue,
            "shaderPlaylist": appState.shaderPlaylist(for: phase),
            "shaderIndex": (appState.shaderPlaylistCurrentIndex(for: phase) as Any?) ?? NSNull(),
            "maskPlaylist": appState.maskPlaylist(for: phase),
            "maskIndex": (appState.maskPlaylistCurrentIndex(for: phase) as Any?) ?? NSNull()
        ]
    }

    private func shaderPayload(_ shader: ShaderInfo) -> [String: Any] {
        [
            "name": shader.name,
            "path": shader.path,
            "folder": shader.folder,
            "isMask": shader.isMask,
            "rating": shader.rating.rawValue,
            "ratingName": shader.rating.displayName,
            "phases": shader.phases?.map(\.rawValue).sorted() ?? [],
            "mood": shader.mood,
            "energyScore": shader.energyScore,
            "colorWarmth": shader.colorWarmth,
            "motionSpeed": shader.motionSpeed
        ]
    }

    private func songPayload(_ song: Song) -> [String: Any] {
        [
            "id": song.id.rawValue,
            "artist": song.artist,
            "title": song.title,
            "album": song.album,
            "status": song.status.rawValue,
            "selectedShader": (song.selectedShader as Any?) ?? NSNull(),
            "phase": (song.phase?.rawValue as Any?) ?? NSNull(),
            "hasLyrics": song.hasLyrics,
            "imagesCount": song.imagesCount,
            "playCount": song.playCount,
            "lastPlayedAt": (song.lastPlayedAt.map(iso8601String) as Any?) ?? NSNull(),
            "lastAnalyzedAt": (song.lastAnalyzedAt.map(iso8601String) as Any?) ?? NSNull()
        ]
    }

    private func success(_ payload: [String: Any]) -> ToolOutcome {
        ToolOutcome(payload: payload, isError: false)
    }

    private func failure(_ message: String) -> ToolOutcome {
        appState?.log("[MCP] \(message)", level: .error)
        return ToolOutcome(payload: ["error": message], isError: true)
    }

    private func makeResultResponse(id: Any?, result: [String: Any]) -> Data? {
        guard let normalizedID = normalizeID(id) else { return nil }
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": normalizedID,
            "result": result
        ]
        return encodeJSON(payload)
    }

    private func makeErrorResponse(id: Any, code: Int, message: String) -> Data? {
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": normalizeID(id) ?? NSNull(),
            "error": [
                "code": code,
                "message": message
            ]
        ]
        return encodeJSON(payload)
    }

    private func encodeJSON(_ object: [String: Any]) -> Data? {
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        return try? JSONSerialization.data(withJSONObject: object, options: [])
    }

    private func normalizeID(_ id: Any?) -> Any? {
        guard let id else { return nil }
        if id is NSNull { return NSNull() }
        if let value = id as? String { return value }
        if let value = id as? Int { return value }
        if let value = id as? Double { return value }
        if let value = id as? NSNumber { return value }
        return NSNull()
    }

    private func prettyJSONString(_ payload: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "{\"error\":\"Failed to encode result\"}"
        }
        return text
    }

    private func toJSONObject<T: Encodable>(_ value: T) -> Any? {
        guard let data = try? encoder.encode(value) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private func decodeTimeline(from object: Any) throws -> SongAutomationTimeline {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else {
            throw NSError(domain: "SwiftVJMCPDataService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timeline is not valid JSON"])
        }

        if let decoded = try? decoder.decode(SongAutomationTimeline.self, from: data) {
            return decoded
        }

        let fallbackDecoder = JSONDecoder()
        if let decoded = try? fallbackDecoder.decode(SongAutomationTimeline.self, from: data) {
            return decoded
        }

        throw NSError(domain: "SwiftVJMCPDataService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timeline decoding failed"])
    }

    private func phaseUpdates(_ arguments: [String: Any]) -> [[String: Any]] {
        let explicit = dictionaryArray(arguments["updates"])
        if !explicit.isEmpty { return explicit }
        if let name = stringValue(arguments["name"]) {
            return [["name": name, "phases": arguments["phases"] ?? []]]
        }
        return []
    }

    private func moveUpdates(_ arguments: [String: Any]) -> [[String: Any]] {
        let explicit = dictionaryArray(arguments["updates"])
        if !explicit.isEmpty { return explicit }
        if let names = arguments["names"] as? [String],
           let folder = stringValue(arguments["folder"]) {
            return names.map { ["name": $0, "folder": folder] }
        }
        if let name = stringValue(arguments["name"]),
           let folder = stringValue(arguments["folder"]) {
            return [["name": name, "folder": folder]]
        }
        return []
    }

    private func renameUpdates(_ arguments: [String: Any]) -> [[String: Any]] {
        let explicit = dictionaryArray(arguments["updates"])
        if !explicit.isEmpty { return explicit }
        if let oldName = stringValue(arguments["oldName"]),
           let newName = stringValue(arguments["newName"]) {
            return [["oldName": oldName, "newName": newName]]
        }
        return []
    }

    private func songShaderAssignments(_ arguments: [String: Any]) -> [[String: Any]] {
        let explicit = dictionaryArray(arguments["assignments"])
        if !explicit.isEmpty { return explicit }
        if let songId = stringValue(arguments["songId"]),
           let shaderName = stringValue(arguments["shaderName"]) {
            return [["songId": songId, "shaderName": shaderName]]
        }
        return []
    }

    private func songIDList(_ arguments: [String: Any]) -> [String] {
        if let ids = arguments["songIds"] as? [String] {
            return ids
        }
        if let id = stringValue(arguments["songId"]) {
            return [id]
        }
        return []
    }

    private func timelineUpdates(_ arguments: [String: Any]) -> [[String: Any]] {
        let explicit = dictionaryArray(arguments["updates"])
        if !explicit.isEmpty { return explicit }
        if let songId = stringValue(arguments["songId"]), let timeline = arguments["timeline"] {
            return [["songId": songId, "timeline": timeline]]
        }
        return []
    }

    private func playlistUpdates(_ arguments: [String: Any]) -> [[String: Any]] {
        let explicit = dictionaryArray(arguments["updates"])
        if !explicit.isEmpty { return explicit }
        if let phase = stringValue(arguments["phase"]) {
            var update: [String: Any] = ["phase": phase]
            if let shaders = arguments["shaderPlaylist"] { update["shaderPlaylist"] = shaders }
            if let masks = arguments["maskPlaylist"] { update["maskPlaylist"] = masks }
            if let shaderIndex = arguments["shaderIndex"] { update["shaderIndex"] = shaderIndex }
            if let maskIndex = arguments["maskIndex"] { update["maskIndex"] = maskIndex }
            return [update]
        }
        return []
    }

    private func phase(from raw: String) -> Phase? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let direct = Phase(rawValue: normalized) {
            return direct
        }
        switch normalized {
        case "disco/jungle", "disco_jungle", "discojungle":
            return .disco
        default:
            return nil
        }
    }

    private func persistShaderPhases(shader: ShaderInfo, phases: Set<Phase>) throws {
        let analysisPath = Self.analysisPath(for: shader)

        var analysisDict: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: analysisPath.path),
           let data = try? Data(contentsOf: analysisPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            analysisDict = json
        } else {
            analysisDict = [
                "title": shader.name,
                "description": "",
                "mood": "",
                "energy": shader.energyScore,
                "colors": shader.colors,
                "effects": shader.effects,
                "geometry": [],
                "objects": [],
                "complexity": "unknown",
                "visual_metadata": [:]
            ]
        }

        analysisDict["dj_phases"] = phases.map(\.rawValue).sorted()
        let data = try JSONSerialization.data(withJSONObject: analysisDict, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: analysisPath)
    }

    private static func analysisPath(for shader: ShaderInfo) -> URL {
        let shaderPath = URL(fileURLWithPath: shader.path)
        let baseName = shaderPath.deletingPathExtension().lastPathComponent
        return shaderPath.deletingLastPathComponent().appendingPathComponent("\(baseName).analysis.json")
    }

    private func renameShaderFiles(shader: ShaderInfo, newName: String) throws {
        let sourceFile = URL(fileURLWithPath: shader.path)
        let sourceDir = sourceFile.deletingLastPathComponent()
        let oldBaseName = sourceFile.deletingPathExtension().lastPathComponent
        let sanitizedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sanitizedName.isEmpty else {
            throw NSError(domain: "SwiftVJMCPDataService", code: 10, userInfo: [NSLocalizedDescriptionKey: "newName must not be empty"])
        }
        guard sanitizedName != oldBaseName else { return }

        let suffixes = [".txt", ".png", ".analysis.json"]
        for suffix in suffixes {
            let destination = sourceDir.appendingPathComponent("\(sanitizedName)\(suffix)")
            if FileManager.default.fileExists(atPath: destination.path) {
                throw NSError(
                    domain: "SwiftVJMCPDataService",
                    code: 11,
                    userInfo: [NSLocalizedDescriptionKey: "Destination already exists: \(destination.lastPathComponent)"]
                )
            }
        }

        for suffix in suffixes {
            let source = sourceDir.appendingPathComponent("\(oldBaseName)\(suffix)")
            let destination = sourceDir.appendingPathComponent("\(sanitizedName)\(suffix)")
            if FileManager.default.fileExists(atPath: source.path) {
                try FileManager.default.moveItem(at: source, to: destination)
            }
        }
    }

    private func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private func stringArray(_ value: Any?) -> [String] {
        if let values = value as? [String] {
            return values
        }
        if let values = value as? [Any] {
            return values.compactMap(stringValue)
        }
        if let single = stringValue(value) {
            return [single]
        }
        return []
    }

    private func dictionaryArray(_ value: Any?) -> [[String: Any]] {
        guard let array = value as? [Any] else { return [] }
        return array.compactMap { $0 as? [String: Any] }
    }

    private func boolValue(_ value: Any?, default defaultValue: Bool) -> Bool {
        boolValueOptional(value) ?? defaultValue
    }

    private func boolValueOptional(_ value: Any?) -> Bool? {
        switch value {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes", "on":
                return true
            case "0", "false", "no", "off":
                return false
            default:
                return nil
            }
        default:
            return nil
        }
    }

    private func intValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }

    private func iso8601String(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
