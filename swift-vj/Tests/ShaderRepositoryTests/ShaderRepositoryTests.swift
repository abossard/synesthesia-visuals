// ShaderRepositoryTests.swift - End-to-end tests using real shader files
// No mocks - uses actual shader directory and metallib

import XCTest
@testable import ShaderRepository

final class ShaderRepositoryTests: XCTestCase {
    
    // MARK: - Test Paths
    
    // Real paths to shader resources
    static let projectRoot = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()  // ShaderRepositoryTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // swift-vj
    
    static let shadersDir = projectRoot.appendingPathComponent("Shaders")
    static let metallibPath = projectRoot
        .appendingPathComponent("Sources/SwiftVJApp/Resources/Shaders.metallib")

    private func requireShadersDir() throws -> URL {
        guard FileManager.default.fileExists(atPath: Self.shadersDir.path) else {
            throw XCTSkip("Shaders directory not found at \(Self.shadersDir.path)")
        }
        return Self.shadersDir
    }
    
    // MARK: - Setup Verification
    
    func testShadersDirectoryExists() throws {
        _ = try requireShadersDir()
    }
    
    func testGlslFolderExists() throws {
        let glslDir = try requireShadersDir().appendingPathComponent("glsl")
        guard FileManager.default.fileExists(atPath: glslDir.path) else {
            throw XCTSkip("glsl folder not found at \(glslDir.path)")
        }
    }
    
    // MARK: - MetallibParser Tests
    
    func testMetallibParserFindsShaders() throws {
        // Skip if metallib doesn't exist (not compiled yet)
        guard FileManager.default.fileExists(atPath: Self.metallibPath.path) else {
            throw XCTSkip("Metallib not found at \(Self.metallibPath.path) - run shader compilation first")
        }
        
        let names = try MetallibParser.parseMetallib(at: Self.metallibPath)
        
        XCTAssertGreaterThan(names.count, 0, "Should find at least one shader in metallib")
        
        // Check that names don't have "fragment_" prefix
        for name in names {
            XCTAssertFalse(name.hasPrefix("fragment_"), "Shader names should not have fragment_ prefix")
        }
    }
    
    func testMetallibParserThrowsForMissingFile() {
        let badURL = URL(fileURLWithPath: "/nonexistent/path.metallib")
        
        XCTAssertThrowsError(try MetallibParser.parseMetallib(at: badURL)) { error in
            XCTAssertTrue(error is MetallibError)
        }
    }
    
    // MARK: - ShaderRepository Loading Tests
    
    func testLoadAllFindsShaders() throws {
        let shaders = try Shaders.loadAll(shadersDir: requireShadersDir())
        
        XCTAssertGreaterThan(shaders.count, 0, "Should find shaders in directory")
    }
    
    func testLoadAllWithMetallib() throws {
        guard FileManager.default.fileExists(atPath: Self.metallibPath.path) else {
            throw XCTSkip("Metallib not found")
        }
        
        let shaders = try Shaders.loadAll(
            shadersDir: requireShadersDir(),
            metallibURL: Self.metallibPath
        )
        
        // At least some shaders should have Metal function names
        let renderableCount = shaders.filter { $0.isRenderable }.count
        XCTAssertGreaterThan(renderableCount, 0, "Some shaders should have Metal function names")
    }
    
    func testLoadedShadersHaveValidProperties() throws {
        let shaders = try Shaders.loadAll(shadersDir: requireShadersDir())
        
        for shader in shaders.prefix(10) {
            // Basic properties
            XCTAssertFalse(shader.name.isEmpty, "Shader name should not be empty")
            XCTAssertTrue(FileManager.default.fileExists(atPath: shader.sourceURL.path), "Source file should exist")
            XCTAssertFalse(shader.folder.isEmpty, "Folder should not be empty")
            
            // ID should match name
            XCTAssertEqual(shader.id.rawValue, shader.name)
        }
    }
    
    func testLoadedShadersWithAnalysis() throws {
        let shaders = try Shaders.loadAll(shadersDir: requireShadersDir())
        
        // Find shaders with analysis
        let withAnalysis = shaders.filter { $0.analysis != nil }
        
        // There should be at least some shaders with analysis
        XCTAssertGreaterThan(withAnalysis.count, 0, "Some shaders should have analysis")
        
        // Verify analysis properties
        for shader in withAnalysis.prefix(5) {
            let analysis = shader.analysis!
            XCTAssertFalse(analysis.title.isEmpty, "Analysis title should not be empty")
        }
    }
    
    // MARK: - Search Tests
    
    func testSearchByName() throws {
        let shaders = try Shaders.loadAll(shadersDir: requireShadersDir())
        
        // Search for a known shader pattern
        let results = Shaders.search(query: "rainbow", in: shaders)
        
        // Should find some rainbow-related shaders
        XCTAssertGreaterThan(results.count, 0, "Should find shaders matching 'rainbow'")
        
        // First result should have rainbow in name
        XCTAssertTrue(
            results.first?.name.lowercased().contains("rainbow") ?? false,
            "First result should contain 'rainbow' in name"
        )
    }
    
    func testSearchEmptyQuery() throws {
        let shaders = try Shaders.loadAll(shadersDir: requireShadersDir())
        
        let results = Shaders.search(query: "", in: shaders)
        
        // Empty query returns all shaders
        XCTAssertEqual(results.count, shaders.count)
    }
    
    func testSearchNoResults() throws {
        let shaders = try Shaders.loadAll(shadersDir: requireShadersDir())
        
        let results = Shaders.search(query: "xyznonexistent123", in: shaders)
        
        XCTAssertEqual(results.count, 0, "Should find no shaders for nonsense query")
    }
    
    // MARK: - Matching Tests
    
    func testMatchByEnergy() throws {
        let shaders = try Shaders.loadAll(shadersDir: requireShadersDir())
        let withAnalysis = shaders.filter { $0.analysis != nil }
        
        guard withAnalysis.count >= 5 else {
            throw XCTSkip("Not enough shaders with analysis for matching test")
        }
        
        // Match high energy
        let highEnergy = Shaders.match(energy: 0.9, valence: 0.5, in: withAnalysis, topK: 5)
        
        XCTAssertEqual(highEnergy.count, 5, "Should return requested number of results")
        
        // Scores should be sorted ascending (lower is better)
        for i in 0..<(highEnergy.count - 1) {
            XCTAssertLessThanOrEqual(highEnergy[i].score, highEnergy[i + 1].score)
        }
    }
    
    func testMatchByMood() throws {
        let shaders = try Shaders.loadAll(shadersDir: requireShadersDir())
        let withAnalysis = shaders.filter { $0.analysis != nil }
        
        guard withAnalysis.count >= 3 else {
            throw XCTSkip("Not enough shaders with analysis")
        }
        
        let results = Shaders.matchByMood("energetic", in: withAnalysis, topK: 3)
        
        XCTAssertGreaterThan(results.count, 0, "Should return some results")
    }
    
    // MARK: - Filtering Tests
    
    func testFilterByFolder() throws {
        let shaders = try Shaders.loadAll(shadersDir: requireShadersDir())
        
        let glslShaders = Shaders.filter(byFolder: "glsl", in: shaders)
        
        XCTAssertGreaterThan(glslShaders.count, 0, "Should find glsl shaders")
        XCTAssertTrue(glslShaders.allSatisfy { $0.folder == "glsl" })
    }
    
    func testFilterOutBlack() throws {
        let shaders = try Shaders.loadAll(shadersDir: requireShadersDir())
        
        let blackCount = shaders.filter { $0.isBlack }.count
        let filtered = Shaders.filterOutBlack(in: shaders)
        
        XCTAssertEqual(filtered.count, shaders.count - blackCount)
        XCTAssertTrue(filtered.allSatisfy { !$0.isBlack })
    }
    
    func testFilterRenderable() throws {
        _ = try requireShadersDir()
        guard FileManager.default.fileExists(atPath: Self.metallibPath.path) else {
            throw XCTSkip("Metallib not found")
        }
        
        let shaders = try Shaders.loadAll(
            shadersDir: requireShadersDir(),
            metallibURL: Self.metallibPath
        )
        
        let renderable = Shaders.filterRenderable(in: shaders)
        
        XCTAssertGreaterThan(renderable.count, 0, "Should find renderable shaders")
        XCTAssertTrue(renderable.allSatisfy { $0.isRenderable })
    }
    
    // MARK: - Statistics Tests
    
    func testFoldersList() throws {
        let shaders = try Shaders.loadAll(shadersDir: requireShadersDir())
        
        let folders = Shaders.folders(in: shaders)
        
        XCTAssertTrue(folders.contains("glsl"), "Should include glsl folder")
    }
    
    func testCountByFolder() throws {
        let shaders = try Shaders.loadAll(shadersDir: requireShadersDir())
        
        let counts = Shaders.countByFolder(in: shaders)
        
        XCTAssertGreaterThan(counts["glsl"] ?? 0, 0, "glsl folder should have shaders")
    }
    
    // MARK: - Read/Write Tests
    
    func testReadSource() throws {
        let shaders = try Shaders.loadAll(shadersDir: requireShadersDir())
        
        guard let shader = shaders.first else {
            throw XCTSkip("No shaders found")
        }
        
        let source = try Shaders.readSource(for: shader)
        
        XCTAssertFalse(source.isEmpty, "Source should not be empty")
    }
    
    // MARK: - Type Tests
    
    func testShaderIDEquality() {
        let id1 = ShaderID("test")
        let id2 = ShaderID("test")
        let id3 = ShaderID("other")
        
        XCTAssertEqual(id1, id2)
        XCTAssertNotEqual(id1, id3)
    }
    
    func testShaderRatingComparison() {
        XCTAssertLessThan(ShaderRating.best, ShaderRating.good)
        XCTAssertLessThan(ShaderRating.good, ShaderRating.normal)
        XCTAssertLessThan(ShaderRating.normal, ShaderRating.mask)
        XCTAssertLessThan(ShaderRating.mask, ShaderRating.skip)
    }
    
    func testPhaseFromStrings() {
        let phases = Phase.fromStrings(["disco", "peak", "invalid"])
        
        XCTAssertEqual(phases.count, 2)
        XCTAssertTrue(phases.contains(.disco))
        XCTAssertTrue(phases.contains(.peak))
    }
    
    // MARK: - ShaderAnalysis Tests
    
    func testShaderAnalysisDecoding() throws {
        let json = """
        {
            "title": "Test Shader",
            "description": "A test description",
            "mood": "energetic",
            "energy": 0.8,
            "colors": ["red", "blue"],
            "effects": ["particles"],
            "geometry": ["circles"],
            "objects": ["stars"],
            "complexity": "high",
            "visual_metadata": {
                "contrast": "high",
                "motion": "fast"
            },
            "dj_phases": ["peak", "buildup"]
        }
        """
        
        let analysis = try JSONDecoder().decode(ShaderAnalysis.self, from: json.data(using: .utf8)!)
        
        XCTAssertEqual(analysis.title, "Test Shader")
        XCTAssertEqual(analysis.energy, 0.8)
        XCTAssertEqual(analysis.colors, ["red", "blue"])
        XCTAssertEqual(analysis.phases, [.peak, .buildup])
        XCTAssertEqual(analysis.visualMetadata?.contrast, "high")
    }
    
    func testFeatureVector() throws {
        let json = """
        {
            "title": "Energetic",
            "description": "",
            "mood": "energetic",
            "energy": 0.9,
            "colors": ["red", "orange"],
            "effects": [],
            "geometry": [],
            "objects": [],
            "complexity": "high"
        }
        """
        
        let analysis = try JSONDecoder().decode(ShaderAnalysis.self, from: json.data(using: .utf8)!)
        let vector = analysis.featureVector
        
        XCTAssertEqual(vector[0], 0.9, "Energy should be 0.9")
        XCTAssertEqual(vector.count, 4, "Feature vector should have 4 elements")
    }
}

// MARK: - ShaderAnalyzer Tests

final class ShaderAnalyzerTests: XCTestCase {
    
    func testLMStudioAvailability() async throws {
        let available = await ShaderAnalyzer.isAvailable()
        
        if !available {
            throw XCTSkip("LM Studio is not running - skipping analyzer tests")
        }
        
        XCTAssertTrue(available)
    }
    
    func testAnalyzeShader() async throws {
        // Check if LM Studio is available
        guard await ShaderAnalyzer.isAvailable() else {
            throw XCTSkip("LM Studio is not running")
        }
        guard FileManager.default.fileExists(atPath: ShaderRepositoryTests.shadersDir.path) else {
            throw XCTSkip("Shaders directory not found at \(ShaderRepositoryTests.shadersDir.path)")
        }
        
        // Load a real shader
        let shaders = try Shaders.loadAll(shadersDir: ShaderRepositoryTests.shadersDir)
        
        guard let shader = shaders.first(where: { !$0.isBlack }) else {
            throw XCTSkip("No non-black shaders found")
        }
        
        // Try to analyze - skip if model not loaded
        do {
            let analysis = try await ShaderAnalyzer.analyze(shader: shader)
            
            XCTAssertFalse(analysis.title.isEmpty, "Analysis should have title")
            XCTAssertGreaterThanOrEqual(analysis.energy, 0.0)
            XCTAssertLessThanOrEqual(analysis.energy, 1.0)
        } catch let error as AnalyzerError {
            if case .serverError(let code, let body) = error, code == 400, body.contains("No models loaded") {
                throw XCTSkip("LM Studio has no model loaded")
            }
            throw error
        }
    }
}
