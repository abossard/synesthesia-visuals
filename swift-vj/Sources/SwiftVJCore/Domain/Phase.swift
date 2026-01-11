// Phase.swift - DJ Set Flow Phases
// Re-exports ShaderRepository.Phase as the canonical type

import ShaderRepository

// Re-export for backwards compatibility
public typealias Phase = ShaderRepository.Phase

// MARK: - Phase Extensions (SwiftVJCore specific)

extension ShaderRepository.Phase {
    /// Suggested valence range (-1.0 to 1.0)
    public var valenceRange: ClosedRange<Double> {
        switch self {
        case .disco: return 0.0...0.7
        case .buildup: return -0.3...0.5
        case .peak: return -0.8...0.0
        case .release: return -0.2...0.4
        case .feature: return -1.0...1.0
        }
    }

    /// Color hex for UI
    public var colorHex: String {
        switch self {
        case .disco: return "#4CAF50"
        case .buildup: return "#FF9800"
        case .peak: return "#F44336"
        case .release: return "#2196F3"
        case .feature: return "#9C27B0"
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

    /// Get all phases as LLM prompt text
    public static var llmPromptText: String {
        ShaderRepository.Phase.allCases.map { "    - \($0.rawValue): \($0.llmDescription)" }.joined(separator: "\n")
    }
}
