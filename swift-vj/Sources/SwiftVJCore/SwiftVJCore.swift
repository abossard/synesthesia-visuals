// SwiftVJCore - Main library export
// Re-exports all public types and functions

@_exported import Foundation
@_exported import ShaderRepository

// Domain types
public typealias LyricLineType = LyricLine
public typealias TrackType = Track

// Legacy alias for migration - prefer ShaderStore
@available(*, deprecated, renamed: "ShaderStore")
public typealias ShaderRepoActor = ShaderStore

// Version info
public let swiftVJVersion = "0.1.0"
