// Infrastructure Tests - Test Config, Backoff, and ServiceHealth
// Following TDD: test observable behaviors

import XCTest
@testable import SwiftVJCore

final class InfrastructureTests: XCTestCase {

    // MARK: - Config Tests

    func test_config_oscPortsAreDefined() {
        // OSC port constants should have sensible values
        XCTAssertEqual(Config.oscReceivePort, 9999)
        XCTAssertEqual(Config.oscVJUniversePort, 10000)
        XCTAssertEqual(Config.oscMagicPort, 11111)
        XCTAssertEqual(Config.oscVDJPort, 9009)
        XCTAssertEqual(Config.oscSynesthesiaPort, 7777)
    }

    func test_config_timingStepIsDefined() {
        XCTAssertEqual(Config.timingStepMs, 200)
    }

    func test_config_lyricsCacheTTL() {
        // 7 days in seconds
        let sevenDays: TimeInterval = 86400 * 7
        XCTAssertEqual(Config.lyricsCacheTTLSeconds, sevenDays)
    }

    func test_config_dataDirectoryIsValid() {
        let dataDir = Config.dataDirectory
        XCTAssertTrue(dataDir.path.contains("SwiftVJ"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dataDir.path))
    }

    func test_config_cacheDirectoryPath() {
        let cacheDir = Config.cacheDirectory
        XCTAssertTrue(cacheDir.path.contains("cache"))
    }

    func test_config_settingsFilePath() {
        let settingsFile = Config.settingsFile
        XCTAssertTrue(settingsFile.lastPathComponent == "settings.json")
    }

    // MARK: - BackoffPolicy Tests

    func test_backoffPolicy_defaultValues() {
        let policy = BackoffPolicy()

        XCTAssertEqual(policy.baseDelay, 0.5)
        XCTAssertEqual(policy.maxDelay, 30.0)
        XCTAssertEqual(policy.factor, 2.0)
    }

    func test_backoffPolicy_delayIncreasesExponentially() {
        let policy = BackoffPolicy(baseDelay: 1.0, maxDelay: 100.0, factor: 2.0)

        XCTAssertEqual(policy.delay(for: 0), 1.0)   // 1 * 2^0 = 1
        XCTAssertEqual(policy.delay(for: 1), 2.0)   // 1 * 2^1 = 2
        XCTAssertEqual(policy.delay(for: 2), 4.0)   // 1 * 2^2 = 4
        XCTAssertEqual(policy.delay(for: 3), 8.0)   // 1 * 2^3 = 8
    }

    func test_backoffPolicy_respectsMaxDelay() {
        let policy = BackoffPolicy(baseDelay: 1.0, maxDelay: 5.0, factor: 2.0)

        // Should cap at max
        XCTAssertEqual(policy.delay(for: 10), 5.0)
        XCTAssertEqual(policy.delay(for: 100), 5.0)
    }

    func test_backoffPolicy_handlesNegativeAttempts() {
        let policy = BackoffPolicy(baseDelay: 1.0)

        // Negative attempts should return base delay
        let delay = policy.delay(for: -5)
        XCTAssertEqual(delay, 1.0)
    }

    // MARK: - BackoffState Tests

    func test_backoffState_initialStateIsReady() {
        let state = BackoffState()

        XCTAssertTrue(state.ready())
        XCTAssertEqual(state.attempts, 0)
        XCTAssertEqual(state.lastError, "")
    }

    func test_backoffState_recordFailureIncreasesAttempts() {
        let state = BackoffState()
        let failed = state.recordFailure(error: "Connection refused")

        XCTAssertEqual(failed.attempts, 1)
        XCTAssertEqual(failed.lastError, "Connection refused")
    }

    func test_backoffState_recordFailureDelaysRetry() {
        let now = Date()
        let state = BackoffState()
        let failed = state.recordFailure(error: "Error", at: now)

        // Should not be ready immediately
        XCTAssertFalse(failed.ready(at: now))

        // Should have time remaining
        XCTAssertGreaterThan(failed.timeRemaining(at: now), 0)
    }

    func test_backoffState_readyAfterDelay() {
        let now = Date()
        let policy = BackoffPolicy(baseDelay: 1.0)
        let state = BackoffState(policy: policy)

        let failed = state.recordFailure(error: "Error", at: now)

        // Not ready at now
        XCTAssertFalse(failed.ready(at: now))

        // Ready after delay
        let later = now.addingTimeInterval(2.0)
        XCTAssertTrue(failed.ready(at: later))
    }

    func test_backoffState_recordSuccessResets() {
        let state = BackoffState(attempts: 5, lastError: "Previous error")
        let success = state.recordSuccess()

        XCTAssertEqual(success.attempts, 0)
        XCTAssertEqual(success.lastError, "")
        XCTAssertTrue(success.ready())
    }

    func test_backoffState_cumulativeFailures() {
        var state = BackoffState()

        // Multiple failures should increase attempts
        state = state.recordFailure(error: "Error 1")
        XCTAssertEqual(state.attempts, 1)

        state = state.recordFailure(error: "Error 2")
        XCTAssertEqual(state.attempts, 2)

        state = state.recordFailure(error: "Error 3")
        XCTAssertEqual(state.attempts, 3)
    }

    // MARK: - ServiceHealth Tests

    func test_serviceHealth_initiallyUnavailable() async {
        let health = ServiceHealth(name: "TestService")

        let available = await health.available
        XCTAssertFalse(available)
    }

    func test_serviceHealth_markAvailableChangesState() async {
        let health = ServiceHealth(name: "TestService")

        await health.markAvailable(message: "Connected")

        let available = await health.available
        XCTAssertTrue(available)
    }

    func test_serviceHealth_markUnavailableChangesState() async {
        let health = ServiceHealth(name: "TestService")
        await health.markAvailable()
        await health.markUnavailable(error: "Connection lost")

        let available = await health.available
        XCTAssertFalse(available)
    }

    func test_serviceHealth_statusContainsInfo() async {
        let health = ServiceHealth(name: "MyService")
        await health.markUnavailable(error: "Test error")

        let status = await health.status()

        XCTAssertEqual(status["name"] as? String, "MyService")
        XCTAssertEqual(status["available"] as? Bool, false)
        XCTAssertEqual(status["error"] as? String, "Test error")
        XCTAssertEqual(status["errorCount"] as? Int, 1)
    }

    func test_serviceHealth_shouldRetryAfterInterval() async {
        let health = ServiceHealth(name: "TestService")
        await health.markUnavailable(error: "Error")

        // Immediately after failure, should not retry
        // (unless 30 seconds passed - in test this is instant)
        let shouldRetry = await health.shouldRetry
        // Note: shouldRetry checks if reconnectInterval has passed since lastCheck
        // Since we just checked, it should be false
        XCTAssertFalse(shouldRetry)
    }

    func test_serviceHealth_errorCountIncrements() async {
        let health = ServiceHealth(name: "TestService")

        await health.markUnavailable(error: "Error 1")
        await health.markUnavailable(error: "Error 2")
        await health.markUnavailable(error: "Error 3")

        let status = await health.status()
        XCTAssertEqual(status["errorCount"] as? Int, 3)
    }
}
