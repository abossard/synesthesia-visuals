import XCTest
@testable import SwiftVJApp
import SongRepository

@MainActor
final class SwiftVJMCPDataServiceTests: XCTestCase {
    private func makeService() -> (appState: AppState, service: SwiftVJMCPDataService) {
        let appState = AppState(testMode: true)
        return (appState, SwiftVJMCPDataService(appState: appState))
    }

    private func requestData(id: Int, method: String, params: [String: Any] = [:]) throws -> Data {
        var object: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method
        ]
        if !params.isEmpty {
            object["params"] = params
        }
        return try JSONSerialization.data(withJSONObject: object, options: [])
    }

    private func responseObject(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Expected JSON object response")
            return [:]
        }
        return object
    }

    func testToolsListContainsDataManagementTools() async throws {
        let (_, service) = makeService()
        let request = try requestData(id: 1, method: "tools/list")
        guard let responseData = await service.handle(messageData: request) else {
            return XCTFail("Expected response data")
        }
        let response = try responseObject(from: responseData)
        let result = response["result"] as? [String: Any]
        let rawTools: [Any] = (result?["tools"] as? [Any]) ?? []
        let names = Set(rawTools.compactMap { ($0 as? [String: Any])?["name"] as? String })

        XCTAssertTrue(names.contains("data.batch_apply"))
        XCTAssertTrue(names.contains("shaders.list"))
        XCTAssertTrue(names.contains("masks.list"))
        XCTAssertTrue(names.contains("songs.list"))
        XCTAssertTrue(names.contains("automation.get_timeline"))
        XCTAssertFalse(names.contains("render.set_enabled"))
        XCTAssertFalse(names.contains("playback.start"))
        XCTAssertFalse(names.contains("pipeline.process"))
    }

    func testBatchApplySetsTimelineAndPlaylists() async throws {
        let (appState, service) = makeService()
        let songID = SongID(artist: "MCP Artist", title: "MCP Title")
        let timelineJSON: [String: Any] = [
            "cues": [[
                "id": UUID().uuidString,
                "timeSec": 12.0,
                "actionType": "osc",
                "value": "/ledfx/test",
                "oscTarget": NSNull(),
                "args": [],
                "source": NSNull()
            ]],
            "valueLanes": [],
            "updatedAt": ISO8601DateFormatter().string(from: Date())
        ]

        let operations: [[String: Any]] = [
            [
                "tool": "automation.set_timeline",
                "arguments": [
                    "songId": songID.rawValue,
                    "timeline": timelineJSON
                ]
            ],
            [
                "tool": "playlists.set",
                "arguments": [
                    "phase": "peak",
                    "shaderPlaylist": ["shader_alpha", "shader_beta"],
                    "maskPlaylist": ["mask_alpha"],
                    "shaderIndex": 1
                ]
            ]
        ]

        let callParams: [String: Any] = [
            "name": "data.batch_apply",
            "arguments": [
                "mode": "bestEffort",
                "operations": operations
            ] as [String: Any]
        ]
        let request = try requestData(id: 2, method: "tools/call", params: callParams)
        guard let responseData = await service.handle(messageData: request) else {
            return XCTFail("Expected response data")
        }
        let response = try responseObject(from: responseData)
        let result = response["result"] as? [String: Any]
        let isError: Bool = (result?["isError"] as? Bool) ?? true
        XCTAssertFalse(isError)

        try? await Task.sleep(for: .milliseconds(25))
        XCTAssertEqual(appState.automationTimeline(for: songID)?.cues.count, 1)
        XCTAssertEqual(appState.shaderPlaylist(for: SongRepository.Phase.peak), ["shader_alpha", "shader_beta"])
        XCTAssertEqual(appState.shaderPlaylistCurrentIndex(for: SongRepository.Phase.peak), 1)
        XCTAssertEqual(appState.maskPlaylist(for: SongRepository.Phase.peak), ["mask_alpha"])
    }

    func testUnknownToolReturnsToolError() async throws {
        let (_, service) = makeService()
        let callParams: [String: Any] = [
            "name": "render.start_engine",
            "arguments": [String: Any]()
        ]
        let request = try requestData(id: 3, method: "tools/call", params: callParams)
        guard let responseData = await service.handle(messageData: request) else {
            return XCTFail("Expected response data")
        }
        let response = try responseObject(from: responseData)
        let result = response["result"] as? [String: Any]
        let isError: Bool = (result?["isError"] as? Bool) ?? false
        XCTAssertTrue(isError)
    }
}
