// CLILogger.swift
// Simple logging utility for CLI tool
// Outputs to stdout (info) and stderr (errors, debug)

import Foundation

struct CLILogger {
    let verbose: Bool

    func log(_ message: String) {
        print(message)
        fflush(stdout)
    }

    func info(_ message: String) {
        print(message)
        fflush(stdout)
    }

    func error(_ message: String) {
        fputs("ERROR: \(message)\n", stderr)
        fflush(stderr)
    }

    func debug(_ message: String) {
        if verbose {
            fputs("DEBUG: \(message)\n", stderr)
            fflush(stderr)
        }
    }

    func warning(_ message: String) {
        fputs("WARNING: \(message)\n", stderr)
        fflush(stderr)
    }
}
