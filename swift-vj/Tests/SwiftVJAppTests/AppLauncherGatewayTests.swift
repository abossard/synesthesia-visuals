import XCTest
@testable import SwiftVJApp
@testable import SwiftVJCore

@MainActor
final class AppLauncherGatewayTests: XCTestCase {
    func testCommandLaunchWritesLogWithoutOpeningTerminal() async throws {
        let logDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: logDirectory) }
        let gateway = AppLauncherGateway(launcherLogDirectory: logDirectory)
        let target = LaunchTarget.commandTarget(
            id: "cmd:echo",
            displayName: "Echo",
            commandLine: "printf 'hello from launcher\\n'",
            workingDirectory: nil
        )

        let result = await gateway.launchTarget(target)
        XCTAssertTrue(result.launched)
        XCTAssertNil(result.error)

        let logContents = try await waitForLogContents(in: logDirectory)
        XCTAssertTrue(logContents.contains("hello from launcher"))
        XCTAssertTrue(logContents.contains("Command: printf 'hello from launcher"))
        XCTAssertTrue(logContents.contains("Kind: command"))
    }

    func testTerminateCommandTargetStopsBackgroundProcess() async throws {
        let logDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: logDirectory) }
        let gateway = AppLauncherGateway(launcherLogDirectory: logDirectory)
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

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftVJAppLauncher-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func waitForLogContents(in directory: URL) async throws -> String {
        let deadline = Date().addingTimeInterval(5)
        repeat {
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            if let logURL = files.first(where: { $0.pathExtension == "log" }) {
                let data = try Data(contentsOf: logURL)
                let text = String(data: data, encoding: .utf8) ?? ""
                if text.contains("hello from launcher") {
                    return text
                }
            }
            try await Task.sleep(for: .milliseconds(100))
        } while Date() < deadline

        throw NSError(
            domain: "AppLauncherGatewayTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for launcher log output"]
        )
    }
}
