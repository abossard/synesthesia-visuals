// TerminalInput.swift
// Raw terminal input handler for single-key presses (no Enter required)
// Uses POSIX termios to disable canonical mode

import Foundation
import Darwin

/// Handles raw terminal input without line buffering
/// Reads single keypresses and dispatches to callback
@MainActor
class TerminalInput {
    private var originalTermios: termios?
    private var inputTask: Task<Void, Never>?
    private let onKeyPress: (Character) -> Void
    private var isRunning = false

    init(onKeyPress: @escaping (Character) -> Void) {
        self.onKeyPress = onKeyPress
    }

    /// Enable raw mode (disable canonical input and echo)
    func start() {
        guard !isRunning else { return }
        isRunning = true

        // Save original terminal settings
        var term = termios()
        tcgetattr(STDIN_FILENO, &term)
        originalTermios = term

        // Disable canonical mode (line buffering) and echo
        term.c_lflag &= ~tcflag_t(ICANON | ECHO)
        term.c_cc.16 = 1  // VMIN = 1 (read at least 1 char)
        term.c_cc.17 = 0  // VTIME = 0 (no timeout)

        tcsetattr(STDIN_FILENO, TCSANOW, &term)

        // Start reading loop in background
        inputTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                var char: UInt8 = 0
                let result = read(STDIN_FILENO, &char, 1)

                if result > 0, let scalar = UnicodeScalar(char) {
                    let character = Character(scalar)

                    // Dispatch to main actor
                    await MainActor.run {
                        self?.onKeyPress(character)
                    }
                }

                // Small sleep to prevent CPU spinning
                try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
            }
        }
    }

    /// Restore original terminal settings
    func stop() {
        guard isRunning else { return }
        isRunning = false

        inputTask?.cancel()
        inputTask = nil

        if var term = originalTermios {
            tcsetattr(STDIN_FILENO, TCSANOW, &term)
        }
    }

    deinit {
        stop()
    }
}
