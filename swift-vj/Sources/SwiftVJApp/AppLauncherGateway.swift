import Foundation
import AppKit
import SwiftVJCore

actor AppLauncherGateway: LauncherEffectHandling {
    private let fileManager: FileManager
    private let launcherLogDirectory: URL
    private var runningCommandProcesses: [String: Process] = [:]

    init(fileManager: FileManager = .default, launcherLogDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.launcherLogDirectory = launcherLogDirectory ?? Self.defaultLauncherLogDirectory(fileManager: fileManager)
    }

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
                try launchCommandInBackground(
                    target: target,
                    commandLine: commandLine,
                    workingDirectory: target.workingDirectory
                )
                return (true, nil)
            } catch {
                return (false, "Failed to launch command \(target.displayName): \(error.localizedDescription)")
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
        switch target.kind {
        case .app:
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

        case .command:
            guard let process = runningCommandProcesses[target.id] else {
                return (false, nil)
            }

            if process.isRunning {
                process.terminate()
                return (true, nil)
            }

            runningCommandProcesses[target.id] = nil
            return (false, nil)
        }
    }

    func terminateAll(_ targets: [LaunchTarget]) async -> LauncherTerminateReport {
        var terminatedIDs: [String] = []
        var notRunning: [String] = []
        var failed: [String: String] = [:]

        for target in targets {
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
            if let process = runningCommandProcesses[target.id] {
                if process.isRunning {
                    return true
                }
                runningCommandProcesses[target.id] = nil
            }
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

    private func launchCommandInBackground(
        target: LaunchTarget,
        commandLine: String,
        workingDirectory: String?
    ) throws {
        let resolvedWorkingDirectory = try resolvedWorkingDirectoryURL(workingDirectory)
        let logFileURL = try makeLogFileURL(for: target)
        try createLogDirectoryIfNeeded()
        let logHandle = try createLogFileHandle(at: logFileURL)
        defer { try? logHandle.close() }
        try writeLogHeader(
            to: logHandle,
            target: target,
            commandLine: commandLine,
            workingDirectory: resolvedWorkingDirectory?.path
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", commandLine]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = logHandle
        process.standardError = logHandle
        if let workingDirectoryURL = resolvedWorkingDirectory {
            process.currentDirectoryURL = workingDirectoryURL
        }

        process.terminationHandler = { [weak self] _ in
            Task { await self?.commandProcessDidTerminate(targetID: target.id) }
        }

        runningCommandProcesses[target.id] = process
        do {
            try process.run()
        } catch {
            runningCommandProcesses[target.id] = nil
            throw error
        }
    }

    private func commandProcessDidTerminate(targetID: String) {
        runningCommandProcesses[targetID] = nil
    }

    private func createLogDirectoryIfNeeded() throws {
        try fileManager.createDirectory(
            at: launcherLogDirectory,
            withIntermediateDirectories: true
        )
    }

    private func createLogFileHandle(at url: URL) throws -> FileHandle {
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        return try FileHandle(forWritingTo: url)
    }

    private func writeLogHeader(
        to handle: FileHandle,
        target: LaunchTarget,
        commandLine: String,
        workingDirectory: String?
    ) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let workingDirectoryValue = (workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? workingDirectory!.trimmingCharacters(in: .whitespacesAndNewlines)
            : "-"
        let lines = [
            "=== SwiftVJ launcher log ===",
            "Target: \(target.displayName) (\(target.id))",
            "Kind: \(target.kind.rawValue)",
            "Started: \(formatter.string(from: Date()))",
            "Working directory: \(workingDirectoryValue)",
            "Command: \(commandLine)",
            "---"
        ]
        let payload = lines.joined(separator: "\n") + "\n"
        if let data = payload.data(using: .utf8) {
            try handle.write(contentsOf: data)
        }
    }

    private func makeLogFileURL(for target: LaunchTarget) throws -> URL {
        let timestamp = Self.launchLogTimestampString(from: Date())
        let name = sanitizeLogComponent(target.displayName.isEmpty ? target.id : target.displayName)
        let id = sanitizeLogComponent(target.id)
        return launcherLogDirectory.appendingPathComponent("\(name)-\(id)-\(timestamp).log")
    }

    private func resolvedWorkingDirectoryURL(_ workingDirectory: String?) throws -> URL? {
        guard let workingDirectory else { return nil }
        let trimmed = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let expanded = (trimmed as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw NSError(
                domain: "AppLauncherGateway",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Working directory does not exist: \(trimmed)"]
            )
        }
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    private func sanitizeLogComponent(_ value: String) -> String {
        let sanitized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[^A-Za-z0-9._-]+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
        return sanitized.isEmpty ? "target" : sanitized
    }

    private static func launchLogTimestampString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: date)
    }

    private static func defaultLauncherLogDirectory(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport.appendingPathComponent("SwiftVJ/launcher-logs", isDirectory: true)
    }
}
