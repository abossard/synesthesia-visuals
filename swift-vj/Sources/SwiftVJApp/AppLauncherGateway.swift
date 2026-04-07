import Foundation
import AppKit
import SwiftVJCore

actor AppLauncherGateway: LauncherEffectHandling {
    private let fileManager: FileManager
    private let launcherLogDirectory: URL
    private let terminalManager: TerminalWindowManager

    init(
        fileManager: FileManager = .default,
        launcherLogDirectory: URL? = nil,
        terminalManager: TerminalWindowManager
    ) {
        self.fileManager = fileManager
        self.launcherLogDirectory = launcherLogDirectory ?? Self.defaultLauncherLogDirectory(fileManager: fileManager)
        self.terminalManager = terminalManager
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

            let launched = await MainActor.run {
                terminalManager.createSession(
                    targetID: target.id,
                    displayName: target.displayName,
                    command: commandLine,
                    workingDirectory: target.workingDirectory
                )
            }
            return (launched, launched ? nil : "Terminal session already exists for \(target.displayName).")
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
            let isRunning = await MainActor.run { terminalManager.isRunning(targetID: target.id) }
            guard isRunning else {
                return (false, nil)
            }

            await MainActor.run { terminalManager.terminate(targetID: target.id) }
            return (true, nil)
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

    // MARK: - Terminal

    func showTerminal(targetID: String) async {
        await MainActor.run { terminalManager.showTerminal(targetID: targetID) }
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
            return await MainActor.run { terminalManager.isRunning(targetID: target.id) }
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

    private static func defaultLauncherLogDirectory(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport.appendingPathComponent("SwiftVJ/launcher-logs", isDirectory: true)
    }
}
