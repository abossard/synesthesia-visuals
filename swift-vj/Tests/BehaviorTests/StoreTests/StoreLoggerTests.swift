import XCTest
@testable import SwiftVJCore

@MainActor
final class StoreLoggerTests: XCTestCase {

    func testFilterHighFrequencyFiltersOscMessageReceived() {
        let logger = StoreLogger<SwiftVJCore.AppState, AppAction>()
        logger.filterHighFrequency()

        let action: AppAction = .ui(.oscMessageReceived(address: "/deck/1/play", args: ["1"]))
        let shouldKeep = logger.customFilter?(action) ?? true

        XCTAssertFalse(shouldKeep)
    }

    func testFilterHighFrequencyFiltersOscEventReceived() {
        let logger = StoreLogger<SwiftVJCore.AppState, AppAction>()
        logger.filterHighFrequency()

        let event = OscEvent(address: "/deck/1/get_bpm", args: [.float(128.0)])
        let action: AppAction = .launchpad(.oscEventReceived(event))
        let shouldKeep = logger.customFilter?(action) ?? true

        XCTAssertFalse(shouldKeep)
    }

    func testFilterHighFrequencyKeepsNonOscActions() {
        let logger = StoreLogger<SwiftVJCore.AppState, AppAction>()
        logger.filterHighFrequency()

        let action: AppAction = .startup
        let shouldKeep = logger.customFilter?(action) ?? false

        XCTAssertTrue(shouldKeep)
    }
}
