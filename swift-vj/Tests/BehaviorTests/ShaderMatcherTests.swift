// ShaderMatcherTests - Behavior tests for shader matching
// Tests pure matching logic without external dependencies

import XCTest
@testable import SwiftVJCore

final class ShaderMatcherTests: XCTestCase {
    
    // MARK: - Test Fixtures
    
    override func setUp() async throws {
        try await super.setUp()
    }
    
    // MARK: - Matching Tests
    
    func testMatchReturnsEmptyWhenNoShaders() async throws {
        let matcher = ShaderMatcher()
        
        // No shaders loaded
        let results = await matcher.match(energy: 0.8, valence: 0.5)
        
        XCTAssertTrue(results.isEmpty, "Empty matcher should return empty results")
    }
    
    func testMatchByMoodReturnsEmptyWhenNoShaders() async throws {
        let matcher = ShaderMatcher()
        
        let results = await matcher.matchByMood("energetic", energy: 0.9)
        
        XCTAssertTrue(results.isEmpty, "Empty matcher should return empty results")
    }
    
    func testSearchReturnsEmptyWhenNoShaders() async throws {
        let matcher = ShaderMatcher()
        
        let results = await matcher.search(query: "tunnel")
        
        XCTAssertTrue(results.isEmpty, "Empty matcher should return empty results")
    }
    
    func testCountIsZeroWhenNoShaders() async throws {
        let matcher = ShaderMatcher()
        
        let count = await matcher.count
        
        XCTAssertEqual(count, 0, "Empty matcher should have 0 shaders")
    }
    
    func testRandomShaderReturnsNilWhenNoShaders() async throws {
        let matcher = ShaderMatcher()
        
        let shader = await matcher.randomShader()
        
        XCTAssertNil(shader, "Empty matcher should return nil for random")
    }
    
    func testGetShaderReturnsNilForUnknownName() async throws {
        let matcher = ShaderMatcher()
        
        let shader = await matcher.getShader(name: "nonexistent")
        
        XCTAssertNil(shader, "Should return nil for unknown shader")
    }
    
    // MARK: - Feature Vector Tests
    
    func testBuildShaderTargetVectorReturnsCorrectDimensions() {
        let vector = buildShaderTargetVector(energy: 0.8, valence: 0.5)
        
        XCTAssertEqual(vector.count, 6, "Target vector should have 6 dimensions")
    }
    
    func testBuildShaderTargetVectorEnergyMapped() {
        let vector = buildShaderTargetVector(energy: 0.9, valence: 0.0)
        
        XCTAssertEqual(vector[0], 0.9, accuracy: 0.001, "Energy should be first element")
    }
    
    func testBuildShaderTargetVectorValenceMapped() {
        let vector = buildShaderTargetVector(energy: 0.5, valence: -0.8)
        
        XCTAssertEqual(vector[1], -0.8, accuracy: 0.001, "Valence should be second element")
    }
    
    func testFeatureDistanceZeroForIdentical() {
        let v1 = [0.5, 0.5, 0.5, 0.5, 0.5, 0.5]
        let v2 = [0.5, 0.5, 0.5, 0.5, 0.5, 0.5]
        
        let distance = featureDistance(v1, v2)
        
        XCTAssertEqual(distance, 0.0, accuracy: 0.0001, "Identical vectors should have 0 distance")
    }
    
    func testFeatureDistancePositiveForDifferent() {
        let v1 = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
        let v2 = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
        
        let distance = featureDistance(v1, v2)
        
        XCTAssertGreaterThan(distance, 0.0, "Different vectors should have positive distance")
    }
    
    func testFeatureDistanceSymmetric() {
        let v1 = [0.2, 0.4, 0.6, 0.8, 0.3, 0.7]
        let v2 = [0.8, 0.3, 0.5, 0.2, 0.9, 0.1]
        
        let d1 = featureDistance(v1, v2)
        let d2 = featureDistance(v2, v1)
        
        XCTAssertEqual(d1, d2, accuracy: 0.0001, "Distance should be symmetric")
    }
}
