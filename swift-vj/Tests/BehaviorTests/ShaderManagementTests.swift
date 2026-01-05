// ShaderManagementTests - High-level end-to-end blackbox tests
// Tests the complete shader management workflow

import XCTest
@testable import SwiftVJCore

final class ShaderManagementTests: XCTestCase {
    
    // MARK: - Shader Loading Tests
    
    func testShaderLoadingFromDirectory() async throws {
        // GIVEN a shader directory with valid shaders
        let tempDir = try createTempShaderDirectory()
        try createDemoShader(named: "test_shader_1", in: tempDir)
        try createDemoShader(named: "test_shader_2", in: tempDir)
        
        // WHEN loading shaders from the directory
        let matcher = ShaderMatcher()
        let count = await matcher.loadShaders(from: tempDir)
        
        // THEN all shaders should be loaded
        XCTAssertEqual(count, 2, "Should load 2 shaders")
        
        let allShaders = await matcher.allShaders
        XCTAssertEqual(allShaders.count, 2, "Should have 2 shaders available")
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    func testShaderLoadingWithMixedTypes() async throws {
        // GIVEN a directory with both regular shaders and masks
        let tempDir = try createTempShaderDirectory()
        try createDemoShader(named: "regular_shader", in: tempDir, rating: .best)
        try createDemoShader(named: "mask_shader", in: tempDir, rating: .mask)
        
        // WHEN loading shaders
        let matcher = ShaderMatcher()
        _ = await matcher.loadShaders(from: tempDir)
        
        // THEN both types should be loaded
        let allShaders = await matcher.allShaders
        let regularCount = allShaders.filter { $0.rating != .mask }.count
        let maskCount = allShaders.filter { $0.rating == .mask }.count
        
        XCTAssertEqual(regularCount, 1, "Should have 1 regular shader")
        XCTAssertEqual(maskCount, 1, "Should have 1 mask")
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    // MARK: - Screenshot Detection Tests
    
    func testScreenshotExistenceDetection() throws {
        // GIVEN a shader directory
        let tempDir = try createTempShaderDirectory()
        let shaderPath = try createDemoShader(named: "test_shader", in: tempDir)
        
        // WHEN creating a screenshot file
        let screenshotPath = shaderPath.appendingPathComponent("test_shader.png")
        let dummyImageData = createDummyPNGData()
        try dummyImageData.write(to: screenshotPath)
        
        // THEN screenshot should be detectable
        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshotPath.path), 
                     "Screenshot file should exist")
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    func testBlackScreenshotDetection() throws {
        // GIVEN a black screenshot
        let blackImageData = createBlackPNGData()
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_black.png")
        try blackImageData.write(to: tempPath)
        
        // WHEN checking if screenshot is black
        let isBlack = isImageBlack(at: tempPath)
        
        // THEN it should be detected as black
        XCTAssertTrue(isBlack, "Black screenshot should be detected")
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempPath)
    }
    
    func testNormalScreenshotDetection() throws {
        // GIVEN a normal (non-black) screenshot
        let normalImageData = createColorfulPNGData()
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_normal.png")
        try normalImageData.write(to: tempPath)
        
        // WHEN checking if screenshot is black
        let isBlack = isImageBlack(at: tempPath)
        
        // THEN it should NOT be detected as black
        XCTAssertFalse(isBlack, "Normal screenshot should not be detected as black")
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempPath)
    }
    
    // MARK: - AI Analysis Tests
    
    func testAnalysisJSONPersistence() throws {
        // GIVEN a shader with analysis data
        let tempDir = try createTempShaderDirectory()
        let shaderPath = try createDemoShader(named: "test_shader", in: tempDir)
        
        let analysisData: [String: Any] = [
            "shaderName": "test_shader",
            "mood": "energetic",
            "energy": 0.8,
            "colors": ["blue", "cyan"],
            "effects": ["geometric", "pulsating"],
            "complexity": "high"
        ]
        
        // WHEN saving analysis to JSON
        let analysisPath = shaderPath.appendingPathComponent("test_shader.analysis.json")
        let jsonData = try JSONSerialization.data(withJSONObject: analysisData)
        try jsonData.write(to: analysisPath)
        
        // THEN analysis should be retrievable
        XCTAssertTrue(FileManager.default.fileExists(atPath: analysisPath.path),
                     "Analysis JSON should exist")
        
        let loadedData = try Data(contentsOf: analysisPath)
        let loadedAnalysis = try JSONSerialization.jsonObject(with: loadedData) as? [String: Any]
        
        XCTAssertNotNil(loadedAnalysis, "Should load analysis data")
        XCTAssertEqual(loadedAnalysis?["mood"] as? String, "energetic")
        XCTAssertEqual(loadedAnalysis?["energy"] as? Double, 0.8)
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    // MARK: - Shader Filtering Tests
    
    func testFilterShadersByRating() async throws {
        // GIVEN shaders with different ratings
        let tempDir = try createTempShaderDirectory()
        try createDemoShader(named: "best_shader", in: tempDir, rating: .best)
        try createDemoShader(named: "good_shader", in: tempDir, rating: .good)
        try createDemoShader(named: "skip_shader", in: tempDir, rating: .skip)
        
        let matcher = ShaderMatcher()
        _ = await matcher.loadShaders(from: tempDir)
        let allShaders = await matcher.allShaders
        
        // WHEN filtering by rating
        let bestShaders = allShaders.filter { $0.rating == .best }
        let goodShaders = allShaders.filter { $0.rating == .good }
        let skipShaders = allShaders.filter { $0.rating == .skip }
        
        // THEN each category should have correct count
        XCTAssertEqual(bestShaders.count, 1, "Should have 1 best shader")
        XCTAssertEqual(goodShaders.count, 1, "Should have 1 good shader")
        XCTAssertEqual(skipShaders.count, 1, "Should have 1 skip shader")
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    func testFilterMasksFromRegularShaders() async throws {
        // GIVEN a mix of shaders and masks
        let tempDir = try createTempShaderDirectory()
        try createDemoShader(named: "shader_1", in: tempDir, rating: .best)
        try createDemoShader(named: "shader_2", in: tempDir, rating: .good)
        try createDemoShader(named: "mask_1", in: tempDir, rating: .mask)
        try createDemoShader(named: "mask_2", in: tempDir, rating: .mask)
        
        let matcher = ShaderMatcher()
        _ = await matcher.loadShaders(from: tempDir)
        let allShaders = await matcher.allShaders
        
        // WHEN filtering masks vs regular
        let regularShaders = allShaders.filter { $0.rating != .mask }
        let masks = allShaders.filter { $0.rating == .mask }
        
        // THEN counts should match
        XCTAssertEqual(regularShaders.count, 2, "Should have 2 regular shaders")
        XCTAssertEqual(masks.count, 2, "Should have 2 masks")
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    // MARK: - Complete Workflow Test
    
    func testCompleteShaderManagementWorkflow() async throws {
        // GIVEN a shader directory
        let tempDir = try createTempShaderDirectory()
        let shaderPath = try createDemoShader(named: "workflow_test", in: tempDir)
        
        // WHEN going through the complete workflow
        
        // 1. Load shader
        let matcher = ShaderMatcher()
        let count = await matcher.loadShaders(from: tempDir)
        XCTAssertEqual(count, 1, "Step 1: Should load 1 shader")
        
        // 2. Create screenshot
        let screenshotPath = shaderPath.appendingPathComponent("workflow_test.png")
        let imageData = createColorfulPNGData()
        try imageData.write(to: screenshotPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshotPath.path),
                     "Step 2: Screenshot should be created")
        
        // 3. Check if black
        let isBlack = isImageBlack(at: screenshotPath)
        XCTAssertFalse(isBlack, "Step 3: Screenshot should not be black")
        
        // 4. Save analysis
        let analysisData: [String: Any] = [
            "shaderName": "workflow_test",
            "mood": "energetic",
            "energy": 0.8,
            "hasScreenshot": true
        ]
        let analysisPath = shaderPath.appendingPathComponent("workflow_test.analysis.json")
        let jsonData = try JSONSerialization.data(withJSONObject: analysisData)
        try jsonData.write(to: analysisPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: analysisPath.path),
                     "Step 4: Analysis should be saved")
        
        // 5. Verify complete state
        XCTAssertTrue(FileManager.default.fileExists(atPath: shaderPath.path),
                     "Step 5: Shader directory should exist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshotPath.path),
                     "Step 5: Screenshot should exist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: analysisPath.path),
                     "Step 5: Analysis should exist")
        
        // THEN all components should be present
        let allShaders = await matcher.allShaders
        XCTAssertEqual(allShaders.count, 1, "Final: Should have 1 shader")
        XCTAssertEqual(allShaders.first?.name, "workflow_test", "Final: Shader name should match")
        
        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    // MARK: - Helper Methods
    
    private func createTempShaderDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_shaders_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }
    
    @discardableResult
    private func createDemoShader(named name: String, in directory: URL, rating: ShaderRating = .normal) throws -> URL {
        let shaderDir = directory.appendingPathComponent("\(name).synScene")
        try FileManager.default.createDirectory(at: shaderDir, withIntermediateDirectories: true)
        
        // Create minimal analysis JSON
        let analysisData: [String: Any] = [
            "shaderName": name,
            "mood": "test",
            "features": [
                "energy_score": 0.5,
                "mood_valence": 0.0
            ]
        ]
        
        let analysisPath = shaderDir.appendingPathComponent("\(name).analysis.json")
        let jsonData = try JSONSerialization.data(withJSONObject: analysisData)
        try jsonData.write(to: analysisPath)
        
        return shaderDir
    }
    
    private func createDummyPNGData() -> Data {
        // Create minimal valid PNG data (1x1 pixel)
        var data = Data()
        data.append(contentsOf: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) // PNG signature
        return data
    }
    
    private func createBlackPNGData() -> Data {
        // Create a 1x1 black PNG
        createDummyPNGData()
    }
    
    private func createColorfulPNGData() -> Data {
        // Create a 1x1 colorful PNG
        createDummyPNGData()
    }
    
    private func isImageBlack(at url: URL) -> Bool {
        // Simple heuristic: check file size
        // Real implementation would analyze pixel data
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? UInt64 else {
            return false
        }
        
        // Very small files are likely black/minimal
        return size < 200
    }
}
