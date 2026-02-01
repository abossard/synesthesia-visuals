// ShaderRepositoryE2ETests.swift - End-to-end tests for ObservableShaderRepository
// Tests: single source of truth pattern, reload, mutations, selection integration
// Uses real shaders directory - no mocks

import XCTest
@testable import SwiftVJCore
@testable import ShaderRepository

@MainActor
final class ShaderRepositoryE2ETests: XCTestCase {
    
    // MARK: - Test Paths
    
    static let projectRoot = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()  // E2ETests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // swift-vj
    
    static let shadersDir = projectRoot.appendingPathComponent("Shaders")
    static let glslDir = shadersDir.appendingPathComponent("glsl")
    static let masksDir = shadersDir.appendingPathComponent("masks")
    
    // Temp directory for test isolation
    var tempDir: URL!
    var tempGlslDir: URL!
    var tempMasksDir: URL!
    
    // System under test
    var repository: ObservableShaderRepository!
    
    // MARK: - Setup / Teardown
    
    override func setUp() async throws {
        // Create temp directory for test isolation
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShaderRepoTests-\(UUID().uuidString)")
        tempGlslDir = tempDir.appendingPathComponent("glsl")
        tempMasksDir = tempDir.appendingPathComponent("masks")
        
        try FileManager.default.createDirectory(at: tempGlslDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempMasksDir, withIntermediateDirectories: true)
        
        // Create repository pointing to temp directory
        repository = ObservableShaderRepository()
        repository.configure(metallibURL: nil, shadersDirectory: tempDir)
    }
    
    override func tearDown() async throws {
        repository = nil
        // Clean up temp directory
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }
    
    // MARK: - Helper: Copy shader files
    
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
    
    private func findTestShader() throws -> String {
        guard FileManager.default.fileExists(atPath: Self.glslDir.path) else {
            throw XCTSkip("Shaders glsl folder not found at \(Self.glslDir.path)")
        }
        let contents = try FileManager.default.contentsOfDirectory(atPath: Self.glslDir.path)
        let txtFiles = contents.filter { $0.hasSuffix(".txt") }
        guard let first = txtFiles.first else {
            throw XCTSkip("No shaders found in glsl folder")
        }
        return String(first.dropLast(4))  // Remove .txt
    }
    
    // MARK: - Test: Reload Populates allShaders
    
    func testReloadPopulatesAllShadersFromDirectory() async throws {
        // Arrange: Copy some shaders to temp
        let shaderName = try findTestShader()
        try copyShader(named: shaderName, from: Self.glslDir, to: tempGlslDir)
        
        XCTAssertTrue(repository.allShaders.isEmpty, "Precondition: allShaders should be empty")
        
        // Act: Reload
        await repository.reload()
        
        // Assert: allShaders populated
        XCTAssertFalse(repository.allShaders.isEmpty, "allShaders should have shaders after reload")
        XCTAssertTrue(repository.allShaders.contains { $0.name == shaderName }, 
                      "Should contain the copied shader")
    }
    
    func testReloadDetectsFolderCorrectly() async throws {
        // Arrange: Copy shader to both glsl and masks with different names
        let shaderName = try findTestShader()
        try copyShader(named: shaderName, from: Self.glslDir, to: tempGlslDir)
        
        // Create a "copy" in masks with different name
        let maskShaderName = "\(shaderName)_mask"
        let sourceFile = tempGlslDir.appendingPathComponent("\(shaderName).txt")
        let destFile = tempMasksDir.appendingPathComponent("\(maskShaderName).txt")
        try FileManager.default.copyItem(at: sourceFile, to: destFile)
        
        // Act: Reload
        await repository.reload()
        
        // Assert: Both shaders found with correct folders
        let glslShader = repository.allShaders.first { $0.name == shaderName }
        let maskShader = repository.allShaders.first { $0.name == maskShaderName }
        
        XCTAssertNotNil(glslShader, "Should find shader in glsl")
        XCTAssertNotNil(maskShader, "Should find shader in masks")
        XCTAssertEqual(glslShader?.folder, "glsl", "GLSL shader should have folder=glsl")
        XCTAssertEqual(maskShader?.folder, "masks", "Mask shader should have folder=masks")
    }
    
    // MARK: - Test: Computed Filters
    
    func testMasksFilterReturnsOnlyMasksFolder() async throws {
        // Arrange: Copy shaders to both folders
        let shaderName = try findTestShader()
        try copyShader(named: shaderName, from: Self.glslDir, to: tempGlslDir)
        
        let maskShaderName = "\(shaderName)_mask"
        let sourceFile = tempGlslDir.appendingPathComponent("\(shaderName).txt")
        let destFile = tempMasksDir.appendingPathComponent("\(maskShaderName).txt")
        try FileManager.default.copyItem(at: sourceFile, to: destFile)
        
        await repository.reload()
        
        // Act
        let masks = repository.masks
        
        // Assert
        XCTAssertFalse(masks.isEmpty, "Should have masks")
        XCTAssertTrue(masks.allSatisfy { $0.folder == "masks" }, "All should be from masks folder")
    }
    
    func testRegularShadersExcludesMasks() async throws {
        // Arrange
        let shaderName = try findTestShader()
        try copyShader(named: shaderName, from: Self.glslDir, to: tempGlslDir)
        
        let maskShaderName = "\(shaderName)_mask"
        let sourceFile = tempGlslDir.appendingPathComponent("\(shaderName).txt")
        let destFile = tempMasksDir.appendingPathComponent("\(maskShaderName).txt")
        try FileManager.default.copyItem(at: sourceFile, to: destFile)
        
        await repository.reload()
        
        // Act
        let regular = repository.regularShaders
        
        // Assert
        XCTAssertFalse(regular.isEmpty, "Should have regular shaders")
        XCTAssertTrue(regular.allSatisfy { $0.folder != "masks" }, "Should exclude masks")
    }
    
    // MARK: - Test: MoveToFolder Mutation
    
    func testMoveToFolderUpdatesShaderFolder() async throws {
        // Arrange: Copy shader to glsl
        let shaderName = try findTestShader()
        try copyShader(named: shaderName, from: Self.glslDir, to: tempGlslDir)
        await repository.reload()
        
        guard let shader = repository.allShaders.first(where: { $0.name == shaderName }) else {
            XCTFail("Shader not found after reload")
            return
        }
        XCTAssertEqual(shader.folder, "glsl", "Precondition: shader in glsl")
        
        // Act: Move to masks
        try repository.moveToFolder(shaderName: shader.name, folder: "masks")
        
        // Assert: Shader now in masks (in-memory)
        let updated = repository.allShaders.first { $0.name == shaderName }
        XCTAssertEqual(updated?.folder, "masks", "Shader should be in masks after move")
        
        // Assert: File actually moved on disk
        let movedFile = tempMasksDir.appendingPathComponent("\(shaderName).txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedFile.path), 
                      "File should exist in masks folder")
        
        let originalFile = tempGlslDir.appendingPathComponent("\(shaderName).txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalFile.path), 
                       "File should be removed from glsl folder")
    }
    
    func testMoveToFolderMovesAllRelatedFiles() async throws {
        // Arrange: Copy shader with analysis.json
        let shaderName = try findTestShader()
        try copyShader(named: shaderName, from: Self.glslDir, to: tempGlslDir)
        
        // Create dummy analysis.json
        let analysisFile = tempGlslDir.appendingPathComponent("\(shaderName).analysis.json")
        try """
        {"name": "\(shaderName)", "status": "ok"}
        """.write(to: analysisFile, atomically: true, encoding: .utf8)
        
        await repository.reload()
        
        guard let shader = repository.allShaders.first(where: { $0.name == shaderName }) else {
            XCTFail("Shader not found")
            return
        }
        
        // Act: Move to masks
        try repository.moveToFolder(shaderName: shader.name, folder: "masks")
        
        // Assert: Both .txt and .analysis.json moved
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: tempMasksDir.appendingPathComponent("\(shaderName).txt").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: tempMasksDir.appendingPathComponent("\(shaderName).analysis.json").path))
    }
    
    // MARK: - Test: Delete Mutation
    
    func testDeleteRemovesShaderFromList() async throws {
        // Arrange
        let shaderName = try findTestShader()
        try copyShader(named: shaderName, from: Self.glslDir, to: tempGlslDir)
        await repository.reload()
        
        XCTAssertTrue(repository.allShaders.contains { $0.name == shaderName }, 
                      "Precondition: shader in list")
        
        guard repository.allShaders.first(where: { $0.name == shaderName }) != nil else {
            XCTFail("Shader not found")
            return
        }
        
        // Act
        try repository.delete(shaderName: shaderName)
        
        // Assert
        XCTAssertFalse(repository.allShaders.contains { $0.name == shaderName }, 
                       "Shader should be removed from list")
    }
    
    func testDeleteRemovesFilesFromDisk() async throws {
        // Arrange
        let shaderName = try findTestShader()
        try copyShader(named: shaderName, from: Self.glslDir, to: tempGlslDir)
        await repository.reload()
        
        guard repository.allShaders.first(where: { $0.name == shaderName }) != nil else {
            XCTFail("Shader not found")
            return
        }
        
        let txtFile = tempGlslDir.appendingPathComponent("\(shaderName).txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: txtFile.path), "Precondition: file exists")
        
        // Act
        try repository.delete(shaderName: shaderName)
        
        // Assert: File removed
        XCTAssertFalse(FileManager.default.fileExists(atPath: txtFile.path), "File should be deleted")
    }
    
    // MARK: - Test: IsRenderable Check
    
    func testIsRenderableReturnsTrueForValidShader() async throws {
        // This test requires a real metallib with compiled shaders
        // Skip if no metallib available
        let metallibURL = Self.projectRoot
            .appendingPathComponent("Shaders")
            .appendingPathComponent("Shaders.metallib")
        
        guard FileManager.default.fileExists(atPath: metallibURL.path) else {
            throw XCTSkip("Shaders.metallib not found")
        }
        
        // Configure with real metallib
        let realRepo = ObservableShaderRepository()
        realRepo.configure(metallibURL: metallibURL, shadersDirectory: Self.shadersDir)
        await realRepo.reload()
        
        guard let shader = realRepo.renderableShaders.first else {
            throw XCTSkip("No renderable shaders found")
        }
        
        // Act & Assert
        XCTAssertTrue(realRepo.isRenderable(shader.name), "\(shader.name) should be renderable")
    }
    
    func testIsRenderableReturnsFalseForUnknownShader() {
        XCTAssertFalse(repository.isRenderable("fake_shader_xyz"), 
                       "Unknown shader should not be renderable")
    }
    
    // MARK: - Test: Available Folders
    
    func testAvailableFoldersReturnsDiscoveredFolders() async throws {
        // Arrange: Create shaders in both folders
        let shaderName = try findTestShader()
        try copyShader(named: shaderName, from: Self.glslDir, to: tempGlslDir)
        
        let maskFile = tempMasksDir.appendingPathComponent("test_mask.txt")
        try "// test mask".write(to: maskFile, atomically: true, encoding: .utf8)
        
        await repository.reload()
        
        // Act
        let folders = repository.folders
        
        // Assert
        XCTAssertTrue(folders.contains("glsl"), "Should include glsl")
        XCTAssertTrue(folders.contains("masks"), "Should include masks")
    }
    
    // MARK: - Test: Published Property Updates SwiftUI
    
    func testAllShadersPublishedTriggersOnReload() async throws {
        // Arrange
        let shaderName = try findTestShader()
        try copyShader(named: shaderName, from: Self.glslDir, to: tempGlslDir)
        
        let initialCount = repository.allShaders.count
        
        // Act
        await repository.reload()
        
        // Assert: Count changed (proves @Published triggered)
        XCTAssertNotEqual(repository.allShaders.count, initialCount, 
                          "allShaders should update after reload")
    }
}
