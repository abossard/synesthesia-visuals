// ShaderSelectionE2ETests.swift - End-to-end tests for ShaderSelectionManager
// Tests: selection state, navigation, repository integration
// Uses real shaders directory

import XCTest
@testable import SwiftVJCore
@testable import ShaderRepository

@MainActor
final class ShaderSelectionE2ETests: XCTestCase {
    
    // MARK: - Test Paths
    
    static let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // E2ETests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // swift-vj
    
    static let shadersDir = projectRoot.appendingPathComponent("Shaders")
    
    // Temp directory for test isolation
    var tempDir: URL!
    var tempGlslDir: URL!
    var tempMasksDir: URL!
    
    // System under test
    var repository: ObservableShaderRepository!
    var selection: ShaderSelectionManager!
    
    // MARK: - Setup / Teardown
    
    override func setUp() async throws {
        // Create temp directory for test isolation
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShaderSelectionTests-\(UUID().uuidString)")
        tempGlslDir = tempDir.appendingPathComponent("glsl")
        tempMasksDir = tempDir.appendingPathComponent("masks")
        
        try FileManager.default.createDirectory(at: tempGlslDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempMasksDir, withIntermediateDirectories: true)
        
        // Create repository and selection manager
        repository = ObservableShaderRepository()
        repository.configure(metallibURL: nil, shadersDirectory: tempDir)

        selection = ShaderSelectionManager()
        selection.repository = repository
    }
    
    override func tearDown() async throws {
        selection = nil
        repository = nil
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }
    
    // MARK: - Helper
    
    private func copyShader(named shaderName: String, from sourceDir: URL, to destDir: URL) throws {
        let extensions = ["txt", "png", "analysis.json"]
        for ext in extensions {
            let sourceFile = sourceDir.appendingPathComponent("\(shaderName).\(ext)")
            let destFile = destDir.appendingPathComponent("\(shaderName).\(ext)")
            
            if FileManager.default.fileExists(atPath: sourceFile.path) {
                try FileManager.default.copyItem(at: sourceFile, to: destFile)
            }
        }
    }
    
    private func createDummyShader(named name: String, in dir: URL) throws {
        let file = dir.appendingPathComponent("\(name).txt")
        try """
        // Dummy shader \(name)
        vec4 fragment_\(name.replacingOccurrences(of: "-", with: "_"))(vec2 uv) {
            return vec4(uv, 0.0, 1.0);
        }
        """.write(to: file, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Test: Initial State
    
    func testInitialMainStateIsNone() {
        XCTAssertNil(selection.mainShaderName, "mainState should be nil initially")
    }
    
    func testInitialMaskStateIsNone() {
        XCTAssertNil(selection.maskShaderName, "maskState should be nil initially")
    }
    
    // MARK: - Test: Select Main
    
    func testSelectMainUpdatesMainState() async throws {
        // Arrange: Create shader and reload
        try createDummyShader(named: "test_shader", in: tempGlslDir)
        await repository.reload()
        
        // Act
        selection.selectMain(name: "test_shader")
        
        // Assert
        XCTAssertEqual(selection.mainShaderName, "test_shader", "mainState should be updated")
    }
    
    func testSelectMainDoesNotAffectMaskState() async throws {
        // Arrange
        try createDummyShader(named: "shader_a", in: tempGlslDir)
        try createDummyShader(named: "mask_b", in: tempMasksDir)
        await repository.reload()
        
        selection.selectMask(name: "mask_b")
        
        // Act
        selection.selectMain(name: "shader_a")
        
        // Assert
        XCTAssertEqual(selection.mainShaderName, "shader_a")
        XCTAssertEqual(selection.maskShaderName, "mask_b", "Mask should be unchanged")
    }
    
    // MARK: - Test: Select Mask
    
    func testSelectMaskUpdatesMaskState() async throws {
        // Arrange
        try createDummyShader(named: "test_mask", in: tempMasksDir)
        await repository.reload()
        
        // Act
        selection.selectMask(name: "test_mask")
        
        // Assert
        XCTAssertEqual(selection.maskShaderName, "test_mask")
    }
    
    func testSelectMaskDoesNotAffectMainState() async throws {
        // Arrange
        try createDummyShader(named: "shader_a", in: tempGlslDir)
        try createDummyShader(named: "mask_b", in: tempMasksDir)
        await repository.reload()
        
        selection.selectMain(name: "shader_a")
        
        // Act
        selection.selectMask(name: "mask_b")
        
        // Assert
        XCTAssertEqual(selection.mainShaderName, "shader_a", "Main should be unchanged")
        XCTAssertEqual(selection.maskShaderName, "mask_b")
    }
    
    // MARK: - Test: Navigation
    
    func testNextMainCyclesForward() async throws {
        // Arrange: Create 3 shaders
        try createDummyShader(named: "shader_1", in: tempGlslDir)
        try createDummyShader(named: "shader_2", in: tempGlslDir)
        try createDummyShader(named: "shader_3", in: tempGlslDir)
        await repository.reload()
        
        selection.selectMain(name: "shader_1")
        
        // Act: Navigate forward
        selection.nextMain()
        
        // Assert: Moved to next shader
        XCTAssertNotEqual(selection.mainShaderName, "shader_1", "Should have moved to next shader")
    }
    
    func testPrevMainCyclesBackward() async throws {
        // Arrange
        try createDummyShader(named: "shader_1", in: tempGlslDir)
        try createDummyShader(named: "shader_2", in: tempGlslDir)
        await repository.reload()
        
        selection.selectMain(name: "shader_2")
        
        // Act
        selection.prevMain()
        
        // Assert
        XCTAssertNotEqual(selection.mainShaderName, "shader_2", "Should have moved to prev shader")
    }
    
    func testNextMainWrapsAround() async throws {
        // Arrange: Create 2 shaders
        try createDummyShader(named: "aaa_shader", in: tempGlslDir)
        try createDummyShader(named: "zzz_shader", in: tempGlslDir)
        await repository.reload()
        
        // Select last (alphabetically)
        selection.selectMain(name: "zzz_shader")
        
        // Act: Next should wrap to first
        selection.nextMain()
        
        // Assert: Should wrap to first shader
        XCTAssertEqual(selection.mainShaderName, "aaa_shader", "Should wrap to first shader")
    }
    
    // MARK: - Test: Random Selection
    
    func testRandomMainSelectsAShader() async throws {
        // Arrange
        try createDummyShader(named: "shader_1", in: tempGlslDir)
        try createDummyShader(named: "shader_2", in: tempGlslDir)
        try createDummyShader(named: "shader_3", in: tempGlslDir)
        await repository.reload()
        
        // Act
        selection.randomMain()
        
        // Assert: Some shader is selected
        XCTAssertNotNil(selection.mainShaderName, "Should have selected a shader")
    }
    
    func testRandomMaskSelectsFromMasksFolder() async throws {
        // Arrange
        try createDummyShader(named: "regular_shader", in: tempGlslDir)
        try createDummyShader(named: "mask_1", in: tempMasksDir)
        try createDummyShader(named: "mask_2", in: tempMasksDir)
        await repository.reload()
        
        // Act
        selection.randomMask()
        
        // Assert: Selected from masks
        let selectedName = selection.maskShaderName
        XCTAssertNotNil(selectedName)
        
        let selectedShader = repository.allShaders.first { $0.name == selectedName }
        XCTAssertEqual(selectedShader?.folder, "masks", "Random mask should be from masks folder")
    }
    
    // MARK: - Test: Weak Repository Reference
    
    func testNavigationWithNilRepositoryDoesNotCrash() {
        // Arrange: Set repository to nil
        selection.repository = nil
        
        // Act & Assert: Should not crash
        selection.nextMain()
        selection.prevMain()
        selection.randomMain()
        selection.nextMask()
        selection.prevMask()
        selection.randomMask()
        
        // If we get here, no crash occurred
        XCTAssertNil(selection.mainShaderName, "State should remain nil")
    }
    
    // MARK: - Test: Selection Finds Shader Info
    
    func testSelectMainPopulatesShaderInfo() async throws {
        // Arrange: Create shader with analysis
        try createDummyShader(named: "detailed_shader", in: tempGlslDir)
        
        // Create analysis file
        let analysisPath = tempGlslDir.appendingPathComponent("detailed_shader.analysis.json")
        try """
        {
            "name": "detailed_shader",
            "mood": "energetic",
            "energy": 0.8,
            "valence": 0.6
        }
        """.write(to: analysisPath, atomically: true, encoding: .utf8)
        
        await repository.reload()
        
        // Act
        selection.selectMain(name: "detailed_shader")
        
        // Assert: State has shader details
        XCTAssertEqual(selection.mainShaderName, "detailed_shader")
        XCTAssertNotNil(selection.mainState.current, "Should have shader info populated")
    }
    
    // MARK: - Test: Clear Selection
    
    func testClearMainRemovesSelection() async throws {
        // Arrange
        try createDummyShader(named: "test_shader", in: tempGlslDir)
        await repository.reload()
        selection.selectMain(name: "test_shader")
        
        XCTAssertNotNil(selection.mainShaderName, "Precondition: should have selection")
        
        // Act
        selection.clearMain()
        
        // Assert
        XCTAssertNil(selection.mainShaderName, "Main selection should be cleared")
    }
    
    func testClearMaskRemovesSelection() async throws {
        // Arrange
        try createDummyShader(named: "test_mask", in: tempMasksDir)
        await repository.reload()
        selection.selectMask(name: "test_mask")
        
        // Act
        selection.clearMask()
        
        // Assert
        XCTAssertNil(selection.maskShaderName, "Mask selection should be cleared")
    }
}
