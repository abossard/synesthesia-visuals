import XCTest
@testable import SwiftVJCore
import Tachikoma

final class TachikomaLMStudioE2ETests: XCTestCase {
    func test_llmClient_usesUserSelectedRepoConfigWithLMStudio() async throws {
        try require(.lmStudioAvailable)
        let configURL = try repoTachikomaConfigURL()

        let defaults = UserDefaults.standard
        let oldValue = defaults.string(forKey: LLMClient.configPathDefaultsKey)
        defaults.set(configURL.path, forKey: LLMClient.configPathDefaultsKey)
        defer {
            if let oldValue {
                defaults.set(oldValue, forKey: LLMClient.configPathDefaultsKey)
            } else {
                defaults.removeObject(forKey: LLMClient.configPathDefaultsKey)
            }
        }

        let client = LLMClient()
        await client.startShaderAnalysis()

        let available = await client.isAvailable
        XCTAssertTrue(available, "LLM client should be available with selected Tachikoma config")
        let backend = await client.backendInfo
        XCTAssertTrue(backend.contains("LMStudio"), "Expected LMStudio backend, got \(backend)")
    }

    private func repoTachikomaConfigURL(file: StaticString = #filePath) throws -> URL {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let root = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let configURL = root.appendingPathComponent("tachikoma.json")
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw XCTSkip("Repo tachikoma.json not found at \(configURL.path)")
        }
        return configURL
    }

    func test_tachikoma_roundTrip_generate_hitsLMStudio() async throws {
        try require(.lmStudioAvailable)
        let configURL = try repoTachikomaConfigURL()
        guard let runtimeConfig = TachikomaLLMRuntimeConfig.load(from: configURL) else {
            XCTFail("Failed to load Tachikoma config from \(configURL.path)")
            return
        }

        let prompt = "Reply with exactly: SWIFTVJ_BACKEND_OK"
        let output = try await generate(
            prompt,
            using: runtimeConfig.songAnalysis.languageModel,
            maxTokens: 48,
            temperature: 0.0,
            timeout: 20,
            configuration: runtimeConfig.makeTachikomaConfiguration()
        )

        let normalized = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        XCTAssertFalse(normalized.isEmpty, "Expected non-empty LM Studio response")
    }
}
