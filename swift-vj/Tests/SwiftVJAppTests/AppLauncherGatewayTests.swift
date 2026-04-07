import XCTest
@testable import SwiftVJApp
@testable import SwiftVJCore

@MainActor
final class AppLauncherGatewayTests: XCTestCase {
    func testCommandLaunchCreatesTerminalSession() async throws {
        let gateway = AppLauncherGateway(terminalManager: TerminalWindowManager.shared)
        let target = LaunchTarget.commandTarget(
            id: "cmd:echo",
            displayName: "Echo",
            commandLine: "printf 'hello from launcher\\n'",
            workingDirectory: nil
        )

        let result = await gateway.launchTarget(target)
        XCTAssertTrue(result.launched)
        XCTAssertNil(result.error)

        // Wait briefly for process
        try await Task.sleep(for: .milliseconds(500))

        // Clean up
        _ = await gateway.terminateTarget(target)
    }

    func testTerminateCommandTargetStopsTerminalProcess() async throws {
        let gateway = AppLauncherGateway(terminalManager: TerminalWindowManager.shared)
        let target = LaunchTarget.commandTarget(
            id: "cmd:sleep",
            displayName: "Sleep",
            commandLine: "sleep 30",
            workingDirectory: nil
        )

        let result = await gateway.launchTarget(target)
        XCTAssertTrue(result.launched)
        XCTAssertNil(result.error)

        let terminateResult = await gateway.terminateTarget(target)
        XCTAssertTrue(terminateResult.terminated)
        XCTAssertNil(terminateResult.error)

        try await Task.sleep(for: .seconds(1))
        let secondTerminate = await gateway.terminateTarget(target)
        XCTAssertFalse(secondTerminate.terminated)
        XCTAssertNil(secondTerminate.error)
    }
}
