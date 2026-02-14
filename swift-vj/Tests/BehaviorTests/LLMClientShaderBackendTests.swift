import XCTest
@testable import SwiftVJCore

final class LLMClientShaderBackendTests: XCTestCase {
    func testStartShaderAnalysisUsesShaderConfig() async throws {
        let runtimeConfig = TachikomaLLMRuntimeConfig(
            songAnalysis: TachikomaProviderConfig(
                provider: .lmstudio,
                model: "current",
                baseURL: "not a url"
            ),
            shaderAnalysis: TachikomaProviderConfig(
                provider: .ollama,
                model: "llama3.2"
            )
        )
        let client = LLMClient(runtimeConfig: runtimeConfig)

        await client.start()
        let songAvailable = await client.isAvailable
        XCTAssertFalse(songAvailable, "Song LM Studio provider should be unavailable")

        await client.startShaderAnalysis()
        let shaderAvailable = await client.isAvailable
        XCTAssertTrue(shaderAvailable, "Shader provider should be considered available")

        let backend = await client.backendInfo
        XCTAssertTrue(backend.contains("Ollama"), "Expected Ollama backend, got \(backend)")
    }
}
