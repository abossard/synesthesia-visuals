// ShaderFileOperationsE2ETests.swift - End-to-end tests for shader file operations
// Tests: marking as mask/not mask, mask folder filtering, shader deletion
// Uses temporary copies of real shaders - no mocks

import XCTest
@testable import ShaderRepository

final class ShaderFileOperationsE2ETests: XCTestCase {
    
    // MARK: - Test Paths
    
    static let projectRoot = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()  // E2ETests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // swift-vj
    
    static let shadersDir = projectRoot.appendingPathComponent("Shaders")
    static let glslDir = shadersDir.appendingPathComponent("glsl")
    static let masksDir = shadersDir.appendingPathComponent("masks")

    private func requireShadersDir() throws {
        guard FileManager.default.fileExists(atPath: Self.glslDir.path) else {
            throw XCTSkip("Shaders glsl folder not found at \(Self.glslDir.path)")
        }
    }
    
    // Temp directory for test isolation
    var tempDir: URL!
    var tempGlslDir: URL!
    var tempMasksDir: URL!
    
    // Related file extensions (matches ShaderConstants.relatedExtensions)
    let relatedExtensions = ["txt", "png", "analysis.json"]
    
    // MARK: - Setup / Teardown
    
    override func setUpWithError() throws {
        // Create temp directory for test isolation
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShaderFileOpTests-\(UUID().uuidString)")
        tempGlslDir = tempDir.appendingPathComponent("glsl")
        tempMasksDir = tempDir.appendingPathComponent("masks")
        
        try FileManager.default.createDirectory(at: tempGlslDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempMasksDir, withIntermediateDirectories: true)
    }
    
    override func tearDownWithError() throws {
        // Clean up temp directory
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }
    
    // MARK: - Helper: Copy a shader with all related files
    
    /// Copy a shader and its related files from source to destination directory
    private func copyShader(named shaderName: String, from sourceDir: URL, to destDir: URL) throws {
        for ext in relatedExtensions {
            let sourceFile = sourceDir.appendingPathComponent("\(shaderName).\(ext)")
            let destFile = destDir.appendingPathComponent("\(shaderName).\(ext)")
            
            if FileManager.default.fileExists(atPath: sourceFile.path) {
                try FileManager.default.copyItem(at: sourceFile, to: destFile)
            }
        }
    }
    
    /// Move a shader and its related files from source to destination directory
    private func moveShader(named shaderName: String, from sourceDir: URL, to destDir: URL) throws {
        for ext in relatedExtensions {
            let sourceFile = sourceDir.appendingPathComponent("\(shaderName).\(ext)")
            let destFile = destDir.appendingPathComponent("\(shaderName).\(ext)")
            
            if FileManager.default.fileExists(atPath: sourceFile.path) {
                try FileManager.default.moveItem(at: sourceFile, to: destFile)
            }
        }
    }
    
    /// Delete a shader and its related files
    private func deleteShader(named shaderName: String, from dir: URL) throws {
        for ext in relatedExtensions {
            let file = dir.appendingPathComponent("\(shaderName).\(ext)")
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
        }
    }
    
    /// Check if shader exists in directory (at least the .txt file)
    private func shaderExists(named shaderName: String, in dir: URL) -> Bool {
        let txtFile = dir.appendingPathComponent("\(shaderName).txt")
        return FileManager.default.fileExists(atPath: txtFile.path)
    }
    
    /// List all .txt files in a directory (shader source files)
    private func listShaders(in dir: URL) -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            return []
        }
        return contents
            .filter { $0.hasSuffix(".txt") }
            .map { String($0.dropLast(4)) }  // Remove .txt extension
    }
    
    /// Find a test shader from real shaders directory
    private func findTestShader() throws -> String {
        let glslShaders = listShaders(in: Self.glslDir)
        guard let shaderName = glslShaders.first else {
            throw XCTSkip("No shaders found in glsl folder to use as test data")
        }
        return shaderName
    }
    
    // MARK: - Test: Mark Shader as Mask (Move to Masks Folder)
    
    func testMoveShaderToMasksFolderCreatesInMasks() throws {
        // Arrange: Copy a shader to temp glsl dir
        let shaderName = try findTestShader()
        try copyShader(named: shaderName, from: Self.glslDir, to: tempGlslDir)
        
        XCTAssertTrue(shaderExists(named: shaderName, in: tempGlslDir), "Precondition: shader should exist in glsl")
        XCTAssertFalse(shaderExists(named: shaderName, in: tempMasksDir), "Precondition: shader should NOT exist in masks")
        
        // Act: Move to masks (marking as mask)
        try moveShader(named: shaderName, from: tempGlslDir, to: tempMasksDir)
        
        // Assert: Shader is now in masks, not in glsl
        XCTAssertFalse(shaderExists(named: shaderName, in: tempGlslDir), "Shader should be removed from glsl")
        XCTAssertTrue(shaderExists(named: shaderName, in: tempMasksDir), "Shader should exist in masks")
    }
    
    func testMoveShaderToMasksMovesAllRelatedFiles() throws {
        // Arrange: Copy a shader that has analysis.json and potentially .png
        let shaderName = try findTestShader()
        try copyShader(named: shaderName, from: Self.glslDir, to: tempGlslDir)
        
        // Count files before move
        var filesBefore: [String] = []
        for ext in relatedExtensions {
            let file = tempGlslDir.appendingPathComponent("\(shaderName).\(ext)")
            if FileManager.default.fileExists(atPath: file.path) {
                filesBefore.append(ext)
            }
        }
        
        // Act: Move to masks
        try moveShader(named: shaderName, from: tempGlslDir, to: tempMasksDir)
        
        // Assert: All related files moved
        for ext in filesBefore {
            let sourceFile = tempGlslDir.appendingPathComponent("\(shaderName).\(ext)")
            let destFile = tempMasksDir.appendingPathComponent("\(shaderName).\(ext)")
            
            XCTAssertFalse(FileManager.default.fileExists(atPath: sourceFile.path), 
                           "\(ext) file should be removed from source")
            XCTAssertTrue(FileManager.default.fileExists(atPath: destFile.path), 
                          "\(ext) file should exist in destination")
        }
    }
    
    // MARK: - Test: Unmark Shader as Mask (Move from Masks Folder)
    
    func testMoveShaderFromMasksToGlsl() throws {
        // Arrange: Copy a shader to temp masks dir
        let shaderName = try findTestShader()
        try copyShader(named: shaderName, from: Self.glslDir, to: tempMasksDir)
        
        XCTAssertTrue(shaderExists(named: shaderName, in: tempMasksDir), "Precondition: shader should exist in masks")
        XCTAssertFalse(shaderExists(named: shaderName, in: tempGlslDir), "Precondition: shader should NOT exist in glsl")
        
        // Act: Move back to glsl (unmarking as mask)
        try moveShader(named: shaderName, from: tempMasksDir, to: tempGlslDir)
        
        // Assert: Shader is now in glsl, not in masks
        XCTAssertTrue(shaderExists(named: shaderName, in: tempGlslDir), "Shader should exist in glsl")
        XCTAssertFalse(shaderExists(named: shaderName, in: tempMasksDir), "Shader should be removed from masks")
    }
    
    // MARK: - Test: Shader Repository Respects Folder Structure
    
    func testShaderRepositoryDetectsFolderCorrectly() throws {
        try requireShadersDir()
        // Load shaders from real directory
        let shaders = try Shaders.loadAll(shadersDir: Self.shadersDir)
        
        // Verify shaders are tagged with correct folder
        let glslShaders = shaders.filter { $0.folder == "glsl" }
        let maskShaders = shaders.filter { $0.folder == "masks" }
        
        XCTAssertGreaterThan(glslShaders.count, 0, "Should find glsl shaders")
        
        // Verify source paths match folder
        for shader in glslShaders.prefix(5) {
            XCTAssertTrue(shader.sourceURL.path.contains("/glsl/"), 
                          "GLSL shader path should contain /glsl/")
        }
        
        for shader in maskShaders.prefix(5) {
            XCTAssertTrue(shader.sourceURL.path.contains("/masks/"), 
                          "Mask shader path should contain /masks/")
        }
    }
    
    func testFilterByFolderReturnsOnlyMasks() throws {
        try requireShadersDir()
        let shaders = try Shaders.loadAll(shadersDir: Self.shadersDir)
        
        let masks = Shaders.filter(byFolder: "masks", in: shaders)
        
        // All returned shaders should be from masks folder
        XCTAssertTrue(masks.allSatisfy { $0.folder == "masks" }, 
                      "filter(byFolder: masks) should return only masks")
    }
    
    func testFilterByFolderExcludesMasks() throws {
        try requireShadersDir()
        let shaders = try Shaders.loadAll(shadersDir: Self.shadersDir)
        
        let glsl = Shaders.filter(byFolder: "glsl", in: shaders)
        
        // No mask shaders should be in result
        XCTAssertTrue(glsl.allSatisfy { $0.folder != "masks" }, 
                      "filter(byFolder: glsl) should not include masks")
    }
    
    func testMaskShadersHaveMaskRating() throws {
        try requireShadersDir()
        let shaders = try Shaders.loadAll(shadersDir: Self.shadersDir)
        let masks = Shaders.filter(byFolder: "masks", in: shaders)
        
        guard !masks.isEmpty else {
            throw XCTSkip("No mask shaders found - cannot test rating")
        }
        
        // Mask shaders should have .mask rating (from ShaderRepository loading logic)
        for shader in masks {
            XCTAssertEqual(shader.rating, .mask, 
                           "Shader '\(shader.name)' in masks folder should have .mask rating")
        }
    }
    
    // MARK: - Test: Shader Deletion
    
    func testDeleteShaderRemovesTxtFile() throws {
        // Arrange: Copy shader to temp
        let shaderName = try findTestShader()
        try copyShader(named: shaderName, from: Self.glslDir, to: tempGlslDir)
        
        XCTAssertTrue(shaderExists(named: shaderName, in: tempGlslDir), "Precondition: shader should exist")
        
        // Act: Delete shader
        try deleteShader(named: shaderName, from: tempGlslDir)
        
        // Assert: Shader no longer exists
        XCTAssertFalse(shaderExists(named: shaderName, in: tempGlslDir), "Shader should be deleted")
    }
    
    func testDeleteShaderRemovesAllRelatedFiles() throws {
        // Arrange: Copy shader with related files
        let shaderName = try findTestShader()
        try copyShader(named: shaderName, from: Self.glslDir, to: tempGlslDir)
        
        // Create dummy .png and .analysis.json if they don't exist
        let pngFile = tempGlslDir.appendingPathComponent("\(shaderName).png")
        let analysisFile = tempGlslDir.appendingPathComponent("\(shaderName).analysis.json")
        
        if !FileManager.default.fileExists(atPath: pngFile.path) {
            FileManager.default.createFile(atPath: pngFile.path, contents: Data())
        }
        if !FileManager.default.fileExists(atPath: analysisFile.path) {
            try "{}".write(to: analysisFile, atomically: true, encoding: .utf8)
        }
        
        // Act: Delete shader
        try deleteShader(named: shaderName, from: tempGlslDir)
        
        // Assert: All related files removed
        for ext in relatedExtensions {
            let file = tempGlslDir.appendingPathComponent("\(shaderName).\(ext)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), 
                           ".\(ext) file should be deleted")
        }
    }
    
    func testDeleteShaderDoesNotAffectOtherShaders() throws {
        // Arrange: Copy two shaders
        let glslShaders = listShaders(in: Self.glslDir)
        guard glslShaders.count >= 2 else {
            throw XCTSkip("Need at least 2 shaders for this test")
        }
        
        let shader1 = glslShaders[0]
        let shader2 = glslShaders[1]
        
        try copyShader(named: shader1, from: Self.glslDir, to: tempGlslDir)
        try copyShader(named: shader2, from: Self.glslDir, to: tempGlslDir)
        
        // Act: Delete only shader1
        try deleteShader(named: shader1, from: tempGlslDir)
        
        // Assert: shader2 still exists
        XCTAssertFalse(shaderExists(named: shader1, in: tempGlslDir), "shader1 should be deleted")
        XCTAssertTrue(shaderExists(named: shader2, in: tempGlslDir), "shader2 should NOT be affected")
    }
    
    // MARK: - Test: Edge Cases
    
    func testMoveNonExistentShaderDoesNotCrash() throws {
        let fakeShaderName = "nonexistent_shader_xyz123"
        
        // This should not throw or crash - just no files to move
        XCTAssertNoThrow(try moveShader(named: fakeShaderName, from: tempGlslDir, to: tempMasksDir))
    }
    
    func testDeleteNonExistentShaderDoesNotCrash() throws {
        let fakeShaderName = "nonexistent_shader_xyz123"
        
        // This should not throw or crash - just no files to delete
        XCTAssertNoThrow(try deleteShader(named: fakeShaderName, from: tempGlslDir))
    }
    
    func testMoveShaderPreservesFileContents() throws {
        // Arrange: Copy shader and read its content
        let shaderName = try findTestShader()
        try copyShader(named: shaderName, from: Self.glslDir, to: tempGlslDir)
        
        let originalContent = try String(contentsOf: tempGlslDir.appendingPathComponent("\(shaderName).txt"))
        
        // Act: Move to masks
        try moveShader(named: shaderName, from: tempGlslDir, to: tempMasksDir)
        
        // Assert: Content is preserved
        let movedContent = try String(contentsOf: tempMasksDir.appendingPathComponent("\(shaderName).txt"))
        XCTAssertEqual(originalContent, movedContent, "File content should be preserved after move")
    }
    
    // MARK: - Test: Integration with ShaderRepository
    
    func testReloadAfterMoveToMasksShowsShaderInMasks() throws {
        // Skip if masks folder doesn't exist
        guard FileManager.default.fileExists(atPath: Self.masksDir.path) else {
            throw XCTSkip("Masks folder doesn't exist")
        }
        
        // Copy a shader to glsl
        let shaderName = try findTestShader()
        try copyShader(named: shaderName, from: Self.glslDir, to: tempGlslDir)
        
        // Reload - should see shader in glsl
        let shadersWithGlsl = try Shaders.loadAll(shadersDir: tempDir)
        let inGlsl = shadersWithGlsl.first { $0.name == shaderName && $0.folder == "glsl" }
        XCTAssertNotNil(inGlsl, "Shader should appear in glsl folder")
        
        // Move to masks
        try moveShader(named: shaderName, from: tempGlslDir, to: tempMasksDir)
        
        // Reload - should see shader in masks, not in glsl
        let shadersWithMask = try Shaders.loadAll(shadersDir: tempDir)
        let inMasks = shadersWithMask.first { $0.name == shaderName && $0.folder == "masks" }
        let stillInGlsl = shadersWithMask.first { $0.name == shaderName && $0.folder == "glsl" }
        
        XCTAssertNotNil(inMasks, "Shader should appear in masks folder after move")
        XCTAssertNil(stillInGlsl, "Shader should NOT appear in glsl folder after move")
    }
    
    func testReloadAfterDeleteRemovesShaderFromList() throws {
        // Copy a shader to temp
        let shaderName = try findTestShader()
        try copyShader(named: shaderName, from: Self.glslDir, to: tempGlslDir)
        
        // Load shaders - should include our shader
        let shadersBefore = try Shaders.loadAll(shadersDir: tempDir)
        XCTAssertTrue(shadersBefore.contains { $0.name == shaderName }, "Shader should be in list before delete")
        
        // Delete the shader
        try deleteShader(named: shaderName, from: tempGlslDir)
        
        // Reload - shader should be gone
        let shadersAfter = try Shaders.loadAll(shadersDir: tempDir)
        XCTAssertFalse(shadersAfter.contains { $0.name == shaderName }, "Shader should NOT be in list after delete")
    }
}
