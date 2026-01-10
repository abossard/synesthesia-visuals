// Phase.swift - DJ Set Flow Phases
// Domain layer: pure data types for phase management

import Foundation

// MARK: - Phase Enum

/// DJ set flow phases for categorizing songs and shaders.
/// Used as soft metadata for shader matching - not a hard filter.
public enum Phase: String, Sendable, Codable, CaseIterable, Hashable {
    case disco = "disco"
    case buildup = "buildup"
    case peak = "peak"
    case release = "release"
    case feature = "feature"

    /// Display name for UI
    public var displayName: String {
        switch self {
        case .disco: return "Disco/Jungle"
        case .buildup: return "Buildup"
        case .peak: return "Peak"
        case .release: return "Release"
        case .feature: return "Feature"
        }
    }

    /// Description for UI tooltips/help text
    public var description: String {
        switch self {
        case .disco:
            return "Slower songs, easy to get into, jungle style beats or generally nice songs to listen to"
        case .buildup:
            return "Stronger songs, harder, bridge from starters. May start slow and end with more energy"
        case .peak:
            return "Strong, fast, dark, loud, high energy, borderline hardstyle. Pair with strong buildup songs"
        case .release:
            return "After 2-3 peaks, let people breathe. Strong and atmospheric but above starters"
        case .feature:
            return "Fun, special, erratic songs. Cool remixes, songs that don't fit elsewhere"
        }
    }

    /// Suggested energy range (0.0-1.0)
    public var energyRange: ClosedRange<Double> {
        switch self {
        case .disco: return 0.2...0.5
        case .buildup: return 0.4...0.7
        case .peak: return 0.7...1.0
        case .release: return 0.4...0.6
        case .feature: return 0.3...0.9
        }
    }

    /// Suggested valence range (-1.0 to 1.0)
    public var valenceRange: ClosedRange<Double> {
        switch self {
        case .disco: return 0.0...0.7      // Neutral to positive
        case .buildup: return -0.3...0.5   // Slightly dark to positive
        case .peak: return -0.8...0.0      // Dark
        case .release: return -0.2...0.4   // Neutral-ish
        case .feature: return -1.0...1.0   // Anything goes
        }
    }

    /// Icon for UI (SF Symbol name)
    public var iconName: String {
        switch self {
        case .disco: return "music.note.house"
        case .buildup: return "arrow.up.right"
        case .peak: return "bolt.fill"
        case .release: return "wind"
        case .feature: return "star.fill"
        }
    }

    /// Color hex for UI
    public var colorHex: String {
        switch self {
        case .disco: return "#4CAF50"   // Green
        case .buildup: return "#FF9800" // Orange
        case .peak: return "#F44336"    // Red
        case .release: return "#2196F3" // Blue
        case .feature: return "#9C27B0" // Purple
        }
    }

    /// Short prompt description for LLM
    public var llmDescription: String {
        switch self {
        case .disco: return "Starter songs, jungle beats, 90-125 BPM, easy listening"
        case .buildup: return "Bridge songs, 115-140 BPM, building energy"
        case .peak: return "High energy, dark, loud, 135-160 BPM"
        case .release: return "Breathing room, atmospheric, after peaks"
        case .feature: return "Special/erratic, remixes, doesn't fit elsewhere"
        }
    }
}

// MARK: - Phase Helpers

extension Phase {
    /// Parse from string (case-insensitive)
    public static func from(_ string: String) -> Phase? {
        Phase(rawValue: string.lowercased())
    }

    /// Parse multiple phases from strings
    public static func fromStrings(_ strings: [String]) -> Set<Phase> {
        Set(strings.compactMap { Phase.from($0) })
    }

    /// Get all phases as LLM prompt text
    public static var llmPromptText: String {
        Phase.allCases.map { "    - \($0.rawValue): \($0.llmDescription)" }.joined(separator: "\n")
    }
}
