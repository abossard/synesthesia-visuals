// ShaderMatcherTests - Behavior tests for shader matching
// Tests pure matching logic without external dependencies

import XCTest
@testable import SwiftVJCore

final class ShaderMatcherTests: XCTestCase {
    
    // MARK: - Empty Matcher Tests
    
    func testMatchReturnsEmptyWhenNoShaders() async throws {
        let matcher = ShaderMatcher()
        let results = await matcher.match(energy: 0.8, valence: 0.5)
        XCTAssertTrue(results.isEmpty)
    }
    
    func testMatchByMoodReturnsEmptyWhenNoShaders() async throws {
        let matcher = ShaderMatcher()
        let results = await matcher.matchByMood("energetic", energy: 0.9)
        XCTAssertTrue(results.isEmpty)
    }
    
    func testSearchReturnsEmptyWhenNoShaders() async throws {
        let matcher = ShaderMatcher()
        let results = await matcher.search(query: "tunnel")
        XCTAssertTrue(results.isEmpty)
    }
    
    func testCountIsZeroWhenNoShaders() async throws {
        let matcher = ShaderMatcher()
        let count = await matcher.count
        XCTAssertEqual(count, 0)
    }
    
    func testRandomShaderReturnsNilWhenNoShaders() async throws {
        let matcher = ShaderMatcher()
        let shader = await matcher.randomShader()
        XCTAssertNil(shader)
    }
    
    func testGetShaderReturnsNilForUnknownName() async throws {
        let matcher = ShaderMatcher()
        let shader = await matcher.getShader(name: "nonexistent")
        XCTAssertNil(shader)
    }
    
    // MARK: - Feature Vector Tests (Pure Functions)
    
    func testBuildShaderTargetVectorReturnsCorrectDimensions() {
        let vector = buildShaderTargetVector(energy: 0.8, valence: 0.5)
        XCTAssertEqual(vector.count, 6)
    }
    
    func testBuildShaderTargetVectorEnergyMapped() {
        let vector = buildShaderTargetVector(energy: 0.9, valence: 0.0)
        XCTAssertEqual(vector[0], 0.9, accuracy: 0.001)
    }
    
    func testBuildShaderTargetVectorValenceMapped() {
        let vector = buildShaderTargetVector(energy: 0.5, valence: -0.8)
        XCTAssertEqual(vector[1], -0.8, accuracy: 0.001)
    }
    
    func testFeatureDistanceZeroForIdentical() {
        let v = [0.5, 0.5, 0.5, 0.5, 0.5, 0.5]
        let distance = featureDistance(v, v)
        XCTAssertEqual(distance, 0.0, accuracy: 0.0001)
    }
    
    func testFeatureDistancePositiveForDifferent() {
        let v1 = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
        let v2 = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
        let distance = featureDistance(v1, v2)
        XCTAssertGreaterThan(distance, 0.0)
    }
    
    func testFeatureDistanceSymmetric() {
        let v1 = [0.2, 0.4, 0.6, 0.8, 0.3, 0.7]
        let v2 = [0.8, 0.3, 0.5, 0.2, 0.9, 0.1]
        XCTAssertEqual(featureDistance(v1, v2), featureDistance(v2, v1), accuracy: 0.0001)
    }
}
