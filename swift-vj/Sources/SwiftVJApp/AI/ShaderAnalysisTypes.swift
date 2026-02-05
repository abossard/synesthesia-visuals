// ShaderAnalysisTypes.swift - Shared types for shader AI analysis

import Foundation
import SwiftVJCore

/// Result of shader analysis from an AI provider
struct ShaderAnalysisResult: Codable, Equatable, Sendable {
    let title: String
    let description: String
    let mood: String
    let energy: Double
    let colors: [String]
    let effects: [String]
    let geometry: [String]
    let objects: [String]
    let complexity: String
    let visualMetadata: [String: String]
    let djPhases: [String]?  // DJ set phases this shader fits

    enum CodingKeys: String, CodingKey {
        case title, description, mood, energy, colors, effects, geometry, objects, complexity
        case visualMetadata = "visual_metadata"
        case djPhases = "dj_phases"
    }

    /// Convert dj_phases strings to Phase enum set
    var phases: Set<Phase> {
        Phase.fromStrings(djPhases ?? [])
    }
}
