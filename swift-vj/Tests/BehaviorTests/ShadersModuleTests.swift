// ShadersModuleTests - Tests for shader selection with usage tracking

import Foundation
import XCTest
@testable import SwiftVJCore

final class ShadersModuleTests: XCTestCase {
    private var tempDirectory: URL?
    
    // MARK: - Lifecycle Tests
    
    func testModuleStartsNotRunning() async throws {
        let module = ShadersModule()
        let started = await module.isStarted
        XCTAssertFalse(started)
    }
    
    func testModuleCanStart() async throws {
        let module = ShadersModule()
        try await module.start()
        let started = await module.isStarted
        XCTAssertTrue(started)
    }
    
    func testModuleCanStop() async throws {
        let module = ShadersModule()
        try await module.start()
        await module.stop()
        let started = await module.isStarted
        XCTAssertFalse(started)
    }
    
    func testDoubleStartThrows() async throws {
        let module = ShadersModule()
        try await module.start()
        
        do {
            try await module.start()
            XCTFail("Should throw on double start")
        } catch ModuleError.alreadyStarted {
            // Expected
        }
    }
    
    // MARK: - Selection Tests
    
    func testSelectWithNoShadersReturnsNil() async throws {
        let module = ShadersModule()
        try await module.start()
        
        let result = await module.selectForSong(
            categories: nil,
            energy: 0.5,
            valence: 0.2
        )
        
        XCTAssertNil(result)
    }
    
    func testMatchWithNoShadersReturnsEmpty() async throws {
        let module = ShadersModule()
        try await module.start()
        
        let results = await module.match(energy: 0.7, valence: 0.3)
        
        XCTAssertTrue(results.isEmpty)
    }
    
    // MARK: - Usage Tracking
    
    func testResetUsageDoesNotCrash() async throws {
        let module = ShadersModule()
        await module.resetUsage()
        // Just verify no crash
    }
    
    func testGetStatusReturnsDict() async throws {
        let module = ShadersModule()
        let status = await module.getStatus()
        
        XCTAssertNotNil(status["started"])
    }

    // MARK: - Stress / Regression

    func testSelectForSong_rapidSelectionsStayInsideQualityShortlist() async throws {
        let module = ShadersModule()
        let shadersDir = try createShaderFixtureDirectory()
        _ = await module.loadAllShaderFiles(from: shadersDir)

        let expectedShortlist: Set<String> = ["alpha", "beta", "gamma"]
        var selectedNames: Set<String> = []

        for _ in 0..<120 {
            guard let selected = await module.selectForSong(
                categories: nil,
                energy: 0.8,
                valence: 0.2,
                phase: nil,
                excludeLast: false
            ) else {
                XCTFail("Expected shader selection")
                return
            }
            selectedNames.insert(selected.name)
        }

        XCTAssertFalse(selectedNames.isEmpty)
        XCTAssertTrue(
            selectedNames.isSubset(of: expectedShortlist),
            "Selection escaped shortlist: \(selectedNames.sorted())"
        )
    }

    func testSelectDecisionForSong_returnsShortlistAndSelectedShader() async throws {
        let module = ShadersModule()
        let shadersDir = try createShaderFixtureDirectory()
        _ = await module.loadAllShaderFiles(from: shadersDir)

        let decision = await module.selectDecisionForSong(
            categories: nil,
            energy: 0.8,
            valence: 0.2,
            phase: nil,
            excludeLast: false
        )

        XCTAssertNotNil(decision)
        guard let decision else { return }
        XCTAssertFalse(decision.shortlist.isEmpty)
        XCTAssertLessThanOrEqual(decision.shortlist.count, 3)
        XCTAssertTrue(decision.shortlist.contains(where: { $0.name == decision.selected.name }))
    }

    func testSearch_largeLibraryRemainsResponsive() async throws {
        let module = ShadersModule()
        let shadersDir = try createShaderFixtureDirectory(shaderCount: 400)
        let loaded = await module.loadAllShaderFiles(from: shadersDir)
        XCTAssertEqual(loaded, 400)

        let start = DispatchTime.now()
        let results = await module.search(query: "shader_039", topK: 30)
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000

        XCTAssertFalse(results.isEmpty)
        XCTAssertLessThan(elapsedMs, 4_000, "Large-library search took \(elapsedMs)ms")
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    private func createShaderFixtureDirectory(shaderCount: Int = 5) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShadersModuleTests-\(UUID().uuidString)", isDirectory: true)
        let glslDir = root.appendingPathComponent("glsl", isDirectory: true)
        try FileManager.default.createDirectory(at: glslDir, withIntermediateDirectories: true)
        tempDirectory = root

        if shaderCount <= 5 {
            try writeShader(named: "alpha", energy: 0.80, valence: 0.20, in: glslDir)
            try writeShader(named: "beta", energy: 0.78, valence: 0.22, in: glslDir)
            try writeShader(named: "gamma", energy: 0.75, valence: 0.18, in: glslDir)
            try writeShader(named: "delta", energy: 0.45, valence: -0.20, in: glslDir)
            try writeShader(named: "epsilon", energy: 0.10, valence: -0.80, in: glslDir)
        } else {
            for index in 0..<shaderCount {
                let energy = min(1.0, max(0.0, 0.2 + Double(index % 100) / 120.0))
                let valence = -0.8 + (Double(index % 80) / 80.0) * 1.6
                try writeShader(
                    named: String(format: "shader_%03d", index),
                    energy: energy,
                    valence: valence,
                    in: glslDir
                )
            }
        }

        return root
    }

    private func writeShader(named name: String, energy: Double, valence: Double, in directory: URL) throws {
        let shaderURL = directory.appendingPathComponent("\(name).txt")
        try "void main() {}".write(to: shaderURL, atomically: true, encoding: .utf8)

        let analysisURL = directory.appendingPathComponent("\(name).analysis.json")
        let payload: [String: Any] = [
            "shaderName": name,
            "shaderType": "glsl",
            "features": [
                "energy_score": energy,
                "mood_valence": valence,
                "color_warmth": 0.5,
                "motion_speed": 0.5,
                "geometric_score": 0.5,
                "visual_density": 0.5
            ],
            "mood": "test",
            "colors": ["blue"],
            "effects": ["flow"],
            "description": "fixture"
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        try data.write(to: analysisURL)
    }
}
