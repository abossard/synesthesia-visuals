// OS2LTypes.swift - Domain types for OS2L protocol
// Following Grokking Simplicity: immutable data types (calculations, not actions)

import Foundation

// MARK: - OS2L Events

public enum OS2LButtonState: String, Codable, Sendable {
    case on
    case off
}

public enum OS2LEvent: Equatable, Sendable {
    case button(name: String, state: OS2LButtonState)
    case command(id: Int, param: Int)
    case beat
    case unknown(raw: String)
}

// MARK: - JSON Parsing (Pure Functions)

/// Internal Codable envelope for decoding OS2L JSON messages.
private struct OS2LButtonMessage: Decodable {
    let evt: String
    let name: String
    let state: String
}

private struct OS2LCommandMessage: Decodable {
    let evt: String
    let id: Int
    let param: Int
}

private struct OS2LBaseMessage: Decodable {
    let evt: String
}

/// Parse a single JSON line into an OS2LEvent.
/// Pure function — no side effects.
public func parseOS2LEvent(from jsonString: String) -> OS2LEvent {
    guard let data = jsonString.data(using: .utf8) else {
        return .unknown(raw: jsonString)
    }

    let decoder = JSONDecoder()

    guard let base = try? decoder.decode(OS2LBaseMessage.self, from: data) else {
        return .unknown(raw: jsonString)
    }

    switch base.evt {
    case "btn":
        guard let msg = try? decoder.decode(OS2LButtonMessage.self, from: data),
              let state = OS2LButtonState(rawValue: msg.state) else {
            return .unknown(raw: jsonString)
        }
        return .button(name: msg.name, state: state)

    case "cmd":
        guard let msg = try? decoder.decode(OS2LCommandMessage.self, from: data) else {
            return .unknown(raw: jsonString)
        }
        return .command(id: msg.id, param: msg.param)

    case "beat":
        return .beat

    default:
        return .unknown(raw: jsonString)
    }
}

// MARK: - Display Title (for Hub Dashboard)

extension OS2LEvent {
    public var displayTitle: String {
        switch self {
        case .button(let name, let state): return "btn \"\(name)\" \(state.rawValue)"
        case .command(let id, let param): return "cmd id:\(id) param:\(param)"
        case .beat: return "beat"
        case .unknown(let raw): return "unknown: \(String(raw.prefix(30)))"
        }
    }
}

/// Extract complete newline-delimited JSON lines from a buffer.
/// Returns (parsed lines, remaining partial data).
/// Pure function — no side effects.
public func extractOS2LLines(from buffer: String) -> (lines: [String], remainder: String) {
    let parts = buffer.split(separator: "\n", omittingEmptySubsequences: false)
    guard parts.count > 1 else {
        return (lines: [], remainder: buffer)
    }

    let completeLines = parts.dropLast().map(String.init).filter { !$0.isEmpty }
    let remainder = String(parts.last ?? "")
    return (lines: completeLines, remainder: remainder)
}
