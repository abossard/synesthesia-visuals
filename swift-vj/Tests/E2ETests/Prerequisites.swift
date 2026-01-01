// Test Prerequisites - Check external service availability
// Adapted from python-vj/tests/conftest.py
// Tests skip gracefully when prerequisites are not available

import XCTest
import Foundation

/// Available prerequisites for E2E tests
public enum Prerequisite: String, CaseIterable {
    case internetConnection = "Internet Connection"
    case vdjRunning = "VirtualDJ Running"
    case vdjPlaying = "VirtualDJ Playing Music"
    case spotifyRunning = "Spotify Running"
    case lmStudioAvailable = "LM Studio (port 1234)"
    case vjUniverseListening = "VJUniverse (port 10000)"
    case synesthesiaRunning = "Synesthesia Running"
}

/// Checks and caches test prerequisites
public final class PrerequisiteChecker {
    /// Singleton instance
    public static let shared = PrerequisiteChecker()

    /// Cache of confirmed prerequisites (session-scoped)
    private var confirmed: Set<Prerequisite> = []

    /// Cache of failed prerequisites
    private var failed: Set<Prerequisite> = []

    private init() {}

    /// Reset cache (for testing)
    public func reset() {
        confirmed.removeAll()
        failed.removeAll()
    }

    /// Require a prerequisite, throwing XCTSkip if not available
    public func require(_ prerequisite: Prerequisite, file: StaticString = #file, line: UInt = #line) throws {
        // Check cache first
        if confirmed.contains(prerequisite) {
            return  // Already confirmed
        }

        if failed.contains(prerequisite) {
            throw XCTSkip("Prerequisite not available: \(prerequisite.rawValue)", file: file, line: line)
        }

        // Check the prerequisite
        if check(prerequisite) {
            confirmed.insert(prerequisite)
        } else {
            failed.insert(prerequisite)
            throw XCTSkip("Prerequisite not available: \(prerequisite.rawValue)", file: file, line: line)
        }
    }

    /// Check if a prerequisite is available (doesn't throw)
    public func check(_ prerequisite: Prerequisite) -> Bool {
        switch prerequisite {
        case .internetConnection:
            return canConnect(host: "lrclib.net", port: 443)

        case .lmStudioAvailable:
            return isPortOpen(1234)

        case .vjUniverseListening:
            // UDP port - harder to check, try TCP
            return isPortOpen(10000)

        case .vdjRunning:
            return isProcessRunning("VirtualDJ")

        case .spotifyRunning:
            return isProcessRunning("Spotify")

        case .synesthesiaRunning:
            return isProcessRunning("Synesthesia")

        case .vdjPlaying:
            // Would need to actually query VDJ via OSC
            // For now, just check if VDJ is running
            return isProcessRunning("VirtualDJ")
        }
    }

    // MARK: - Private Helpers

    private func canConnect(host: String, port: Int) -> Bool {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM

        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, String(port), &hints, &result)

        guard status == 0, let info = result else {
            return false
        }

        defer { freeaddrinfo(result) }

        let sock = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        // Set timeout
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        return connect(sock, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0
    }

    private func isPortOpen(_ port: UInt16) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        // Set timeout
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    private func isProcessRunning(_ name: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", name]

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
}

// MARK: - XCTestCase Extension

extension XCTestCase {
    /// Require a prerequisite for the current test
    public func require(_ prerequisite: Prerequisite, file: StaticString = #file, line: UInt = #line) throws {
        try PrerequisiteChecker.shared.require(prerequisite, file: file, line: line)
    }
}
