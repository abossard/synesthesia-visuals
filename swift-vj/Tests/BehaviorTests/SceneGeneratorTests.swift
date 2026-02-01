// SceneGeneratorTests.swift - Tests for scene generation logic
// Following TDD: Test behaviors, not implementation

import XCTest
@testable import SwiftVJCore

final class SceneGeneratorTests: XCTestCase {
    
    let virtualIds = ["virtual-1", "virtual-2"]
    
    // MARK: - Basic Scene Generation
    
    func testGenerateScene_createsSceneWithCorrectName() {
        let scene = SceneGenerator.generateScene(
            name: "Test Scene",
            virtualIds: virtualIds,
            energy: 0.5,
            valence: 0.5
        )
        
        XCTAssertEqual(scene.name, "Test Scene")
    }
    
    func testGenerateScene_includesAllVirtuals() {
        let scene = SceneGenerator.generateScene(
            name: "Test",
            virtualIds: virtualIds,
            energy: 0.5,
            valence: 0.5
        )
        
        XCTAssertEqual(scene.virtuals.count, 2)
        XCTAssertNotNil(scene.virtuals["virtual-1"])
        XCTAssertNotNil(scene.virtuals["virtual-2"])
    }
    
    func testGenerateScene_setsInactive() {
        let scene = SceneGenerator.generateScene(
            name: "Test",
            virtualIds: virtualIds,
            energy: 0.5,
            valence: 0.5
        )
        
        XCTAssertFalse(scene.active)
    }
    
    func testGenerateScene_includesTags() {
        let scene = SceneGenerator.generateScene(
            name: "Test",
            virtualIds: virtualIds,
            energy: 0.5,
            valence: 0.5,
            tags: ["tag1", "tag2"]
        )
        
        XCTAssertEqual(scene.sceneTags, "tag1,tag2")
    }
    
    // MARK: - Energy/Valence Mapping
    
    func testHighEnergyPositiveMood_selectsStrobeEffect() {
        let scene = SceneGenerator.generateScene(
            name: "High Energy Positive",
            virtualIds: virtualIds,
            energy: 0.9,  // High energy
            valence: 0.8  // Positive mood
        )
        
        // Should select strobe for high energy + positive
        let firstVirtual = scene.virtuals["virtual-1"]
        XCTAssertEqual(firstVirtual?.type, "strobe")
        XCTAssertEqual(firstVirtual?.action, .activate)
    }
    
    func testHighEnergyNegativeMood_selectsEnergyEffect() {
        let scene = SceneGenerator.generateScene(
            name: "High Energy Negative",
            virtualIds: virtualIds,
            energy: 0.9,  // High energy
            valence: 0.3  // Negative mood
        )
        
        // Should select energy for high energy + negative
        let firstVirtual = scene.virtuals["virtual-1"]
        XCTAssertEqual(firstVirtual?.type, "energy")
    }
    
    func testMediumEnergyPositive_selectsScrollEffect() {
        let scene = SceneGenerator.generateScene(
            name: "Medium Energy Positive",
            virtualIds: virtualIds,
            energy: 0.6,
            valence: 0.7
        )
        
        let firstVirtual = scene.virtuals["virtual-1"]
        XCTAssertEqual(firstVirtual?.type, "scroll")
    }
    
    func testLowEnergyPositive_selectsWavelengthEffect() {
        let scene = SceneGenerator.generateScene(
            name: "Low Energy Positive",
            virtualIds: virtualIds,
            energy: 0.2,
            valence: 0.7
        )
        
        let firstVirtual = scene.virtuals["virtual-1"]
        XCTAssertEqual(firstVirtual?.type, "wavelength")
    }
    
    func testLowEnergyNegative_selectsFadeEffect() {
        let scene = SceneGenerator.generateScene(
            name: "Low Energy Negative",
            virtualIds: virtualIds,
            energy: 0.2,
            valence: 0.3
        )
        
        let firstVirtual = scene.virtuals["virtual-1"]
        XCTAssertEqual(firstVirtual?.type, "fade")
    }
    
    // MARK: - Effect Configuration
    
    func testGenerateScene_includesBrightnessConfig() {
        let scene = SceneGenerator.generateScene(
            name: "Test",
            virtualIds: virtualIds,
            energy: 0.5,
            valence: 0.5
        )
        
        let config = scene.virtuals["virtual-1"]?.config
        XCTAssertNotNil(config?["brightness"])
        
        if case .double(let brightness) = config?["brightness"] {
            XCTAssert(brightness >= 0.7 && brightness <= 1.0)
        } else {
            XCTFail("Brightness should be a double")
        }
    }
    
    func testStrobeEffect_includesSpeedConfig() {
        let scene = SceneGenerator.generateScene(
            name: "Strobe",
            virtualIds: virtualIds,
            energy: 0.9,
            valence: 0.8,
            bpm: 120.0
        )
        
        let config = scene.virtuals["virtual-1"]?.config
        XCTAssertNotNil(config?["speed"])
        
        // With 120 BPM, speed should be 2 Hz (120/60)
        if case .double(let speed) = config?["speed"] {
            XCTAssertEqual(speed, 2.0, accuracy: 0.01)
        }
    }
    
    // MARK: - Blackout Scene
    
    func testGenerateBlackoutScene_setsForceblackAction() {
        let scene = SceneGenerator.generateBlackoutScene(virtualIds: virtualIds)
        
        XCTAssertEqual(scene.name, "blackout")
        
        for virtualId in virtualIds {
            let action = scene.virtuals[virtualId]
            XCTAssertEqual(action?.action, .forceblack)
        }
    }
    
    func testGenerateBlackoutScene_includesUtilityTag() {
        let scene = SceneGenerator.generateBlackoutScene(virtualIds: virtualIds)
        
        XCTAssertTrue(scene.sceneTags?.contains("blackout") ?? false)
    }
    
    // MARK: - Color Scene
    
    func testGenerateColorScene_setsColorAndBrightness() {
        let scene = SceneGenerator.generateColorScene(
            name: "Red",
            virtualIds: virtualIds,
            color: "#FF0000",
            brightness: 0.8
        )
        
        let config = scene.virtuals["virtual-1"]?.config
        
        if case .string(let color) = config?["color"] {
            XCTAssertEqual(color, "#FF0000")
        } else {
            XCTFail("Color should be a string")
        }
        
        if case .double(let brightness) = config?["brightness"] {
            XCTAssertEqual(brightness, 0.8, accuracy: 0.01)
        } else {
            XCTFail("Brightness should be a double")
        }
    }
    
    func testGenerateColorScene_usesSolidEffect() {
        let scene = SceneGenerator.generateColorScene(
            name: "Blue",
            virtualIds: virtualIds,
            color: "#0000FF"
        )
        
        let firstVirtual = scene.virtuals["virtual-1"]
        XCTAssertEqual(firstVirtual?.type, "solid")
        XCTAssertEqual(firstVirtual?.action, .activate)
    }
    
    // MARK: - DJ Set Scenes
    
    func testGenerateDJSetScenes_includesBlackout() {
        let tracks = [
            (name: "Track 1", energy: 0.5, valence: 0.5, bpm: Optional(120.0))
        ]
        
        let scenes = SceneGenerator.generateDJSetScenes(
            virtualIds: virtualIds,
            tracks: tracks
        )
        
        XCTAssertNotNil(scenes["blackout"])
        XCTAssertEqual(scenes["blackout"]?.virtuals["virtual-1"]?.action, .forceblack)
    }
    
    func testGenerateDJSetScenes_createsScenePerTrack() {
        let tracks = [
            (name: "Track 1", energy: 0.5, valence: 0.5, bpm: Optional(120.0)),
            (name: "Track 2", energy: 0.8, valence: 0.7, bpm: Optional(140.0)),
            (name: "Track 3", energy: 0.3, valence: 0.6, bpm: nil)
        ]
        
        let scenes = SceneGenerator.generateDJSetScenes(
            virtualIds: virtualIds,
            tracks: tracks
        )
        
        XCTAssertNotNil(scenes["track_1"])
        XCTAssertNotNil(scenes["track_2"])
        XCTAssertNotNil(scenes["track_3"])
        
        XCTAssertEqual(scenes["track_1"]?.name, "Track 1")
        XCTAssertEqual(scenes["track_2"]?.name, "Track 2")
        XCTAssertEqual(scenes["track_3"]?.name, "Track 3")
    }
    
    func testGenerateDJSetScenes_includesUtilityScenes() {
        let scenes = SceneGenerator.generateDJSetScenes(
            virtualIds: virtualIds,
            tracks: []
        )
        
        XCTAssertNotNil(scenes["warm_white"])
        XCTAssertNotNil(scenes["cool_white"])
    }
    
    // MARK: - Preset Scenes
    
    func testGeneratePresetScenes_includesEnergyLevels() {
        let scenes = SceneGenerator.generatePresetScenes(virtualIds: virtualIds)
        
        XCTAssertNotNil(scenes["high_energy"])
        XCTAssertNotNil(scenes["medium_energy"])
        XCTAssertNotNil(scenes["low_energy"])
    }
    
    func testGeneratePresetScenes_includesMoodScenes() {
        let scenes = SceneGenerator.generatePresetScenes(virtualIds: virtualIds)
        
        XCTAssertNotNil(scenes["uplifting"])
        XCTAssertNotNil(scenes["dark"])
    }
    
    func testGeneratePresetScenes_includesBlackout() {
        let scenes = SceneGenerator.generatePresetScenes(virtualIds: virtualIds)
        
        XCTAssertNotNil(scenes["blackout"])
    }
    
    // MARK: - Scene Immutability
    
    func testScene_withActive_createsNewScene() {
        let original = SceneGenerator.generateScene(
            name: "Test",
            virtualIds: virtualIds,
            energy: 0.5,
            valence: 0.5
        )
        
        let modified = original.withActive(true)
        
        // Original unchanged
        XCTAssertFalse(original.active)
        
        // Modified has new value
        XCTAssertTrue(modified.active)
        
        // Other fields preserved
        XCTAssertEqual(modified.name, original.name)
        XCTAssertEqual(modified.virtuals.count, original.virtuals.count)
    }
}
