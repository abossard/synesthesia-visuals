// FeatureFlagsTests - Test feature flag defaults, persistence, and round-trip
// Following TDD: test observable behaviors, not implementation details

import XCTest
@testable import SwiftVJCore

final class FeatureFlagsTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "FeatureFlagsTests.\(UUID().uuidString)"

    override func setUp() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Defaults

    func test_featureFlags_allEnabledByDefault() {
        let flags = FeatureFlags()
        XCTAssertTrue(flags.renderingEnabled)
        XCTAssertTrue(flags.performanceEnabled)
        XCTAssertTrue(flags.shadersEnabled)
        XCTAssertTrue(flags.launchpadEnabled)
        XCTAssertTrue(flags.songsEnabled)
    }

    func test_featureFlags_loadReturnsAllEnabledWhenNoKeys() {
        let flags = FeatureFlags.load(from: defaults)
        XCTAssertTrue(flags.renderingEnabled)
        XCTAssertTrue(flags.performanceEnabled)
        XCTAssertTrue(flags.shadersEnabled)
        XCTAssertTrue(flags.launchpadEnabled)
        XCTAssertTrue(flags.songsEnabled)
    }

    // MARK: - Persistence Round-Trip

    func test_featureFlags_saveAndLoadRoundTrips() {
        let original = FeatureFlags(
            renderingEnabled: false,
            performanceEnabled: true,
            shadersEnabled: false,
            launchpadEnabled: true,
            songsEnabled: false
        )
        original.save(to: defaults)

        let loaded = FeatureFlags.load(from: defaults)
        XCTAssertEqual(loaded, original)
    }

    func test_featureFlags_individualFlagPersists() {
        var flags = FeatureFlags()
        flags.launchpadEnabled = false
        flags.save(to: defaults)

        let loaded = FeatureFlags.load(from: defaults)
        XCTAssertTrue(loaded.renderingEnabled)
        XCTAssertTrue(loaded.performanceEnabled)
        XCTAssertTrue(loaded.shadersEnabled)
        XCTAssertFalse(loaded.launchpadEnabled)
        XCTAssertTrue(loaded.songsEnabled)
    }

    // MARK: - Equatable

    func test_featureFlags_equalityWorks() {
        let a = FeatureFlags(renderingEnabled: false, songsEnabled: false)
        let b = FeatureFlags(renderingEnabled: false, songsEnabled: false)
        let c = FeatureFlags(renderingEnabled: true, songsEnabled: false)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - UserDefaults Keys

    func test_featureFlags_usesExpectedKeys() {
        let flags = FeatureFlags(
            renderingEnabled: false,
            performanceEnabled: false,
            shadersEnabled: false,
            launchpadEnabled: false,
            songsEnabled: false
        )
        flags.save(to: defaults)

        XCTAssertEqual(defaults.bool(forKey: FeatureFlags.Keys.rendering), false)
        XCTAssertEqual(defaults.bool(forKey: FeatureFlags.Keys.performance), false)
        XCTAssertEqual(defaults.bool(forKey: FeatureFlags.Keys.shaders), false)
        XCTAssertEqual(defaults.bool(forKey: FeatureFlags.Keys.launchpad), false)
        XCTAssertEqual(defaults.bool(forKey: FeatureFlags.Keys.songs), false)
    }
}
