import XCTest
@testable import SwiftVJCore

final class LLMClientShaderBackendTests: XCTestCase {
    func testStartShaderAnalysisUsesShaderConfig() async throws {
        let runtimeConfig = TachikomaLLMRuntimeConfig(
            songAnalysis: TachikomaProviderConfig(
                provider: .openai,
                model: "gpt-4o-mini",
                apiKey: "test-key"
            ),
            shaderAnalysis: TachikomaProviderConfig(
                provider: .ollama,
                model: "llama3.2"
            )
        )
        let client = LLMClient(runtimeConfig: runtimeConfig)

        await client.start()
        let songAvailable = await client.isAvailable
        XCTAssertTrue(songAvailable, "Song provider should be available")
        let songBackend = await client.backendInfo
        XCTAssertTrue(songBackend.contains("OpenAI"), "Expected OpenAI backend after start()")

        await client.startShaderAnalysis()
        let shaderAvailable = await client.isAvailable
        XCTAssertTrue(shaderAvailable, "Shader provider should be considered available")

        let backend = await client.backendInfo
        XCTAssertTrue(backend.contains("Ollama"), "Expected Ollama backend, got \(backend)")
    }
}
