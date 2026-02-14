import XCTest
import Foundation
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

    func testReloadConfigurationAppliesUserSelectedConfigFromDefaults() async throws {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: LLMClient.configPathDefaultsKey)
        defer {
            if let previous {
                defaults.set(previous, forKey: LLMClient.configPathDefaultsKey)
            } else {
                defaults.removeObject(forKey: LLMClient.configPathDefaultsKey)
            }
        }

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let openAIConfigURL = tempDirectory.appendingPathComponent("openai.json")
        let openAIConfig = TachikomaLLMRuntimeConfig(
            songAnalysis: TachikomaProviderConfig(
                provider: .openai,
                model: "gpt-4o-mini",
                apiKey: "test-openai-key"
            ),
            shaderAnalysis: TachikomaProviderConfig(
                provider: .openai,
                model: "gpt-4o-mini",
                apiKey: "test-openai-key"
            )
        )
        try JSONEncoder().encode(openAIConfig).write(to: openAIConfigURL)

        let anthropicConfigURL = tempDirectory.appendingPathComponent("anthropic.json")
        let anthropicConfig = TachikomaLLMRuntimeConfig(
            songAnalysis: TachikomaProviderConfig(
                provider: .anthropic,
                model: "claude-3-5-sonnet-latest",
                apiKey: "test-anthropic-key"
            ),
            shaderAnalysis: TachikomaProviderConfig(
                provider: .anthropic,
                model: "claude-3-5-sonnet-latest",
                apiKey: "test-anthropic-key"
            )
        )
        try JSONEncoder().encode(anthropicConfig).write(to: anthropicConfigURL)

        let client = LLMClient()

        defaults.set(openAIConfigURL.path, forKey: LLMClient.configPathDefaultsKey)
        await client.reloadConfiguration()
        await client.start()
        let openAIAvailable = await client.isAvailable
        let openAIBackend = await client.backendInfo
        XCTAssertTrue(openAIAvailable)
        XCTAssertTrue(openAIBackend.contains("OpenAI"))

        defaults.set(anthropicConfigURL.path, forKey: LLMClient.configPathDefaultsKey)
        await client.reloadConfiguration()
        await client.start()
        let anthropicAvailable = await client.isAvailable
        let anthropicBackend = await client.backendInfo
        XCTAssertTrue(anthropicAvailable)
        XCTAssertTrue(anthropicBackend.contains("Anthropic"))

        defaults.set(tempDirectory.appendingPathComponent("missing.json").path, forKey: LLMClient.configPathDefaultsKey)
        await client.reloadConfiguration()
        await client.start()
        let missingConfigAvailable = await client.isAvailable
        XCTAssertFalse(missingConfigAvailable)
        let status = await client.status()
        XCTAssertTrue(status.error.contains("config not selected or invalid"))
    }

    func testConfigurationDoesNotAutoReloadUntilExplicitReload() async throws {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: LLMClient.configPathDefaultsKey)
        defer {
            if let previous {
                defaults.set(previous, forKey: LLMClient.configPathDefaultsKey)
            } else {
                defaults.removeObject(forKey: LLMClient.configPathDefaultsKey)
            }
        }

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let openAIConfigURL = tempDirectory.appendingPathComponent("openai.json")
        let openAIConfig = TachikomaLLMRuntimeConfig(
            songAnalysis: TachikomaProviderConfig(
                provider: .openai,
                model: "gpt-4o-mini",
                apiKey: "test-openai-key"
            ),
            shaderAnalysis: TachikomaProviderConfig(
                provider: .openai,
                model: "gpt-4o-mini",
                apiKey: "test-openai-key"
            )
        )
        try JSONEncoder().encode(openAIConfig).write(to: openAIConfigURL)

        let anthropicConfigURL = tempDirectory.appendingPathComponent("anthropic.json")
        let anthropicConfig = TachikomaLLMRuntimeConfig(
            songAnalysis: TachikomaProviderConfig(
                provider: .anthropic,
                model: "claude-3-5-sonnet-latest",
                apiKey: "test-anthropic-key"
            ),
            shaderAnalysis: TachikomaProviderConfig(
                provider: .anthropic,
                model: "claude-3-5-sonnet-latest",
                apiKey: "test-anthropic-key"
            )
        )
        try JSONEncoder().encode(anthropicConfig).write(to: anthropicConfigURL)

        defaults.set(openAIConfigURL.path, forKey: LLMClient.configPathDefaultsKey)
        let client = LLMClient()

        await client.start()
        let initialBackend = await client.backendInfo
        XCTAssertTrue(initialBackend.contains("OpenAI"))

        defaults.set(anthropicConfigURL.path, forKey: LLMClient.configPathDefaultsKey)
        await client.start()
        let stillOpenAIBackend = await client.backendInfo
        XCTAssertTrue(stillOpenAIBackend.contains("OpenAI"))

        await client.reloadConfiguration()
        await client.start()
        let reloadedBackend = await client.backendInfo
        XCTAssertTrue(reloadedBackend.contains("Anthropic"))
    }
}
