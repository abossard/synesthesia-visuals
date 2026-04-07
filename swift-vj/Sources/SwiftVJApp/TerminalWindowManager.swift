import AppKit
import SwiftTerm
import SwiftVJCore

/// Manages per-target terminal windows backed by SwiftTerm's LocalProcessTerminalView.
/// Each command target gets its own PTY-backed terminal with full VT100/Xterm emulation.
@MainActor
final class TerminalWindowManager {
    static let shared = TerminalWindowManager()

    private var sessions: [String: TerminalWindowSession] = [:]

    struct TerminalWindowSession {
        let terminalView: LocalProcessTerminalView
        let window: NSWindow
        let windowDelegate: TerminalWindowDelegate
        var processExited: Bool = false
        var exitCode: Int32? = nil
    }

    private init() {}

    /// Creates a new terminal session for a command target.
    /// Returns true if the session was created and process started.
    func createSession(
        targetID: String,
        displayName: String,
        command: String,
        workingDirectory: String?
    ) -> Bool {
        if let existing = sessions[targetID], !existing.processExited {
            return false
        }
        // Clean up old exited session
        sessions[targetID] = nil

        let terminalView = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "⬤ \(displayName)"
        window.contentView = terminalView
        window.isReleasedWhenClosed = false
        window.center()

        let windowDelegate = TerminalWindowDelegate(targetID: targetID, manager: self)
        window.delegate = windowDelegate

        let processDelegate = TerminalProcessDelegate(targetID: targetID, manager: self)
        terminalView.processDelegate = processDelegate

        let session = TerminalWindowSession(
            terminalView: terminalView,
            window: window,
            windowDelegate: windowDelegate
        )
        sessions[targetID] = session

        let env = buildEnvironment(workingDirectory: workingDirectory)
        terminalView.startProcess(
            executable: "/bin/zsh",
            args: ["-lc", command],
            environment: env,
            execName: "zsh",
            currentDirectory: workingDirectory
        )

        return true
    }

    /// Shows or brings to front the terminal window for a target.
    func showTerminal(targetID: String) {
        guard let session = sessions[targetID] else { return }
        session.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Whether a terminal session exists and its process is still running.
    func isRunning(targetID: String) -> Bool {
        guard let session = sessions[targetID] else { return false }
        return !session.processExited
    }

    /// Whether a terminal session exists (running or exited).
    func hasSession(targetID: String) -> Bool {
        sessions[targetID] != nil
    }

    /// Terminates the process in a terminal session.
    func terminate(targetID: String) {
        guard let session = sessions[targetID] else { return }
        session.terminalView.terminate()
    }

    /// Cleans up a session completely (after user removes the target).
    func cleanup(targetID: String) {
        guard let session = sessions[targetID] else { return }
        if !session.processExited {
            session.terminalView.terminate()
        }
        session.window.close()
        sessions[targetID] = nil
    }

    /// Terminates all running sessions (app shutdown).
    func terminateAll() {
        for (id, session) in sessions {
            if !session.processExited {
                session.terminalView.terminate()
            }
            session.window.close()
            sessions[id] = nil
        }
    }

    // MARK: - Internal callbacks

    func processDidTerminate(targetID: String, exitCode: Int32?) {
        guard var session = sessions[targetID] else { return }
        session.processExited = true
        session.exitCode = exitCode
        sessions[targetID] = session

        let statusText = exitCode.map { " (exit \($0))" } ?? ""
        session.window.title = "⏹ \(session.window.title.dropFirst(2))\(statusText)"
    }

    func windowWillClose(targetID: String) {
        // Don't destroy session — just let the window hide.
        // The window can be re-shown with showTerminal().
    }

    // MARK: - Private

    private func buildEnvironment(workingDirectory: String?) -> [String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        if let cwd = workingDirectory {
            env["PWD"] = cwd
        }
        return env.map { "\($0.key)=\($0.value)" }
    }
}

// MARK: - Window Delegate

@MainActor
final class TerminalWindowDelegate: NSObject, NSWindowDelegate {
    nonisolated(unsafe) private let targetID: String
    nonisolated(unsafe) private weak var manager: TerminalWindowManager?

    init(targetID: String, manager: TerminalWindowManager) {
        self.targetID = targetID
        self.manager = manager
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        let tid = targetID
        let mgr = manager
        Task { @MainActor in
            mgr?.windowWillClose(targetID: tid)
        }
    }

    nonisolated func windowShouldClose(_ sender: NSWindow) -> Bool {
        Task { @MainActor in
            sender.orderOut(nil)
        }
        return false
    }
}

// MARK: - Process Delegate

@MainActor
final class TerminalProcessDelegate: NSObject, LocalProcessTerminalViewDelegate, @unchecked Sendable {
    nonisolated(unsafe) private let targetID: String
    nonisolated(unsafe) private weak var manager: TerminalWindowManager?

    init(targetID: String, manager: TerminalWindowManager) {
        self.targetID = targetID
        self.manager = manager
    }

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        Task { @MainActor in
            source.window?.title = title
        }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        let tid = targetID
        let mgr = manager
        Task { @MainActor in
            mgr?.processDidTerminate(targetID: tid, exitCode: exitCode)
        }
    }
}
