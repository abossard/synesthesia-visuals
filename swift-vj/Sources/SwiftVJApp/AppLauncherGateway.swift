import Foundation
import AppKit
import SwiftVJCore

actor AppLauncherGateway: LauncherEffectHandling {
    func analyzeDroppedItems(_ urls: [URL]) async -> [LaunchTarget] {
        var results: [LaunchTarget] = []
        var seen = Set<String>()

        for url in urls {
            guard let target = await analyzeAppURL(url) else { continue }
            let identity = target.normalizedIdentity
            if seen.contains(identity) { continue }
            seen.insert(identity)
            results.append(target)
        }

        return results
    }

    func launchTarget(_ target: LaunchTarget) async -> (launched: Bool, error: String?) {
        if await isTargetRunning(target) {
            return (false, nil)
        }

        switch target.kind {
        case .app:
            guard let appPath = target.appPath, !appPath.isEmpty else {
                return (false, "Missing app path for \(target.displayName).")
            }
            let appURL = URL(fileURLWithPath: appPath)
            do {
                try await openApplication(appURL)
                return (true, nil)
            } catch {
                return (false, "Failed to launch \(target.displayName): \(error.localizedDescription)")
            }

        case .command:
            let commandLine = target.commandLine?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !commandLine.isEmpty else {
                return (false, "Missing command line for \(target.displayName).")
            }

            do {
                try await launchCommandInTerminal(
                    commandLine: commandLine,
                    workingDirectory: target.workingDirectory
                )
                return (true, nil)
            } catch {
                return (false, "Failed to launch terminal command \(target.displayName): \(error.localizedDescription)")
            }
        }
    }

    func launchTargetsIfNeeded(_ targets: [LaunchTarget]) async -> LauncherLaunchReport {
        var launched: [String] = []
        var alreadyRunning: [String] = []
        var failed: [String: String] = [:]

        for target in targets {
            if await isTargetRunning(target) {
                alreadyRunning.append(target.id)
                continue
            }

            let result = await launchTarget(target)
            if let error = result.error {
                failed[target.id] = error
            } else if result.launched {
                launched.append(target.id)
            }
        }

        let running = await collectRunningTargetIDs(for: targets)
        return LauncherLaunchReport(
            launchedTargetIDs: launched,
            alreadyRunningTargetIDs: alreadyRunning,
            failedTargetErrors: failed,
            runningTargetIDs: running
        )
    }

    func terminateTarget(_ target: LaunchTarget) async -> (terminated: Bool, error: String?) {
        guard target.kind == .app else {
            return (false, "Cannot terminate command targets — close their terminal window manually.")
        }

        guard await isTargetRunning(target) else {
            return (false, nil)
        }

        let apps = await MainActor.run {
            runningApplications(bundleIdentifier: target.appBundleIdentifier, appPath: target.appPath)
        }

        guard !apps.isEmpty else {
            return (false, nil)
        }

        var terminated = false
        for app in apps {
            if app.terminate() {
                terminated = true
            }
        }

        return (terminated, terminated ? nil : "Failed to terminate \(target.displayName).")
    }

    func terminateAll(_ targets: [LaunchTarget]) async -> LauncherTerminateReport {
        var terminatedIDs: [String] = []
        var notRunning: [String] = []
        var failed: [String: String] = [:]

        for target in targets where target.kind == .app {
            if !(await isTargetRunning(target)) {
                notRunning.append(target.id)
                continue
            }

            let result = await terminateTarget(target)
            if let error = result.error {
                failed[target.id] = error
            } else if result.terminated {
                terminatedIDs.append(target.id)
            } else {
                notRunning.append(target.id)
            }
        }

        try? await Task.sleep(for: .milliseconds(500))
        let running = await collectRunningTargetIDs(for: targets)
        return LauncherTerminateReport(
            terminatedTargetIDs: terminatedIDs,
            notRunningTargetIDs: notRunning,
            failedTargetErrors: failed,
            runningTargetIDs: running
        )
    }

    private func collectRunningTargetIDs(for targets: [LaunchTarget]) async -> Set<String> {
        var running = Set<String>()
        for target in targets {
            if await isTargetRunning(target) {
                running.insert(target.id)
            }
        }
        return running
    }

    // MARK: - Private

    private func analyzeAppURL(_ droppedURL: URL) async -> LaunchTarget? {
        let standardized = droppedURL.standardizedFileURL
        guard standardized.pathExtension.lowercased() == "app" else { return nil }

        let appURL = standardized.resolvingSymlinksInPath()
        let bundle = Bundle(url: appURL)
        let bundleIdentifier = bundle?.bundleIdentifier
        let displayName = appDisplayName(bundle: bundle, url: appURL)
        let id = makeAppTargetID(bundleIdentifier: bundleIdentifier, appURL: appURL)

        return LaunchTarget.appTarget(
            id: id,
            displayName: displayName,
            bundleIdentifier: bundleIdentifier,
            appPath: appURL.path
        )
    }

    private func appDisplayName(bundle: Bundle?, url: URL) -> String {
        if let display = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !display.isEmpty {
            return display
        }
        if let name = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !name.isEmpty {
            return name
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private func makeAppTargetID(bundleIdentifier: String?, appURL: URL) -> String {
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return "app.bundle.\(bundleIdentifier.lowercased())"
        }
        return "app.path.\(appURL.path.lowercased())"
    }

    private func isTargetRunning(_ target: LaunchTarget) async -> Bool {
        switch target.kind {
        case .app:
            return await isAppRunning(bundleIdentifier: target.appBundleIdentifier, appPath: target.appPath)
        case .command:
            // Command targets run in external terminal; no in-app runtime tracking.
            return false
        }
    }

    private func isAppRunning(bundleIdentifier: String?, appPath: String?) async -> Bool {
        await MainActor.run {
            !runningApplications(bundleIdentifier: bundleIdentifier, appPath: appPath).isEmpty
        }
    }

    @MainActor
    private func runningApplications(bundleIdentifier: String?, appPath: String?) -> [NSRunningApplication] {
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        }

        guard let appPath, !appPath.isEmpty else { return [] }
        let normalized = URL(fileURLWithPath: appPath).standardizedFileURL.path
        return NSWorkspace.shared.runningApplications.filter {
            $0.bundleURL?.standardizedFileURL.path == normalized
        }
    }

    private func openApplication(_ appURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.main.async {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                NSWorkspace.shared.openApplication(
                    at: appURL,
                    configuration: configuration
                ) { _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
        }
    }

    private func launchCommandInTerminal(commandLine: String, workingDirectory: String?) async throws {
        let shellCommand = buildShellCommand(commandLine: commandLine, workingDirectory: workingDirectory)
        let terminalScript = """
        tell application "Terminal"
            activate
            if (count of windows) is 0 then
                do script ""
            end if
            do script "\(appleScriptEscaped(shellCommand))" in front window
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", terminalScript]
        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let description = (message?.isEmpty == false) ? (message ?? "osascript failed") : "osascript failed"
            throw NSError(
                domain: "AppLauncherGateway",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: description]
            )
        }
    }

    private func buildShellCommand(commandLine: String, workingDirectory: String?) -> String {
        guard let workingDirectory else { return commandLine }
        let trimmed = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return commandLine }
        let expanded = (trimmed as NSString).expandingTildeInPath
        return "cd \(shellSingleQuote(expanded)) && \(commandLine)"
    }

    private func shellSingleQuote(_ text: String) -> String {
        "'\(text.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func appleScriptEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
