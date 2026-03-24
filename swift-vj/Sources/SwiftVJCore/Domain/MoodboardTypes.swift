// MoodboardTypes.swift - Immutable domain types for the Moodboard feature
// Following Grokking Simplicity: pure data with no behavior

import Foundation
import CoreGraphics
import SongRepository

// MARK: - Grid Constants

/// Canvas grid size for snap-to-grid positioning
public let moodboardGridSize: CGFloat = 20

/// Snap a point to the nearest grid intersection
public func snapToGrid(_ point: CGPoint, gridSize: CGFloat = moodboardGridSize) -> CGPoint {
    CGPoint(
        x: (point.x / gridSize).rounded() * gridSize,
        y: (point.y / gridSize).rounded() * gridSize
    )
}

// MARK: - Layout Mode

/// Available auto-layout algorithms for the moodboard canvas
public enum LayoutMode: String, Codable, Sendable, CaseIterable {
    /// Force-directed spring-electric layout (organic clustering)
    case auto
    /// Hierarchical left-to-right (for directed song succession)
    case flow
    /// Tags in columns on left, songs on right grouped by connection
    case grouped
}

// MARK: - Edge Directionality

/// Determine whether an edge between two node kinds should be directed.
/// - song → song: directed (succession)
/// - tag → tag: directed (relationship)
/// - song ↔ tag: undirected (membership)
public func edgeIsDirected(sourceKind: MoodboardNodeKind, targetKind: MoodboardNodeKind) -> Bool {
    switch (sourceKind, targetKind) {
    case (.song, .song): return true
    case (.tag, .tag): return true
    case (.song, .tag), (.tag, .song): return false
    default: return false
    }
}

// MARK: - Node Types

/// The kind of node on the moodboard canvas
public enum MoodboardNodeKind: String, Codable, Sendable, CaseIterable {
    case song
    case tag
    case container
}

/// Tag categories for organizing songs
public enum TagCategory: String, Codable, Sendable, CaseIterable {
    case genre
    case phase
    case mood
    case topic
    case custom
}

/// Types of edges between nodes
public enum EdgeType: String, Codable, Sendable, CaseIterable {
    case similarity
    case transition
    case remix
    case custom
    case tagMembership
}

// MARK: - Moodboard Node

/// A node on the moodboard canvas. Immutable value type.
public struct MoodboardNode: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let kind: MoodboardNodeKind
    public var position: CGPoint

    // Song-specific (nil for tag/container nodes)
    public let songId: SongID?

    // Audio file path (stored on the node, persisted with the board)
    public let audioFilePath: String?

    // Tag-specific (nil for song/container nodes)
    public let tagLabel: String?
    public let tagCategory: TagCategory?

    public init(
        id: String,
        kind: MoodboardNodeKind,
        position: CGPoint = .zero,
        songId: SongID? = nil,
        audioFilePath: String? = nil,
        tagLabel: String? = nil,
        tagCategory: TagCategory? = nil
    ) {
        self.id = id
        self.kind = kind
        self.position = position
        self.songId = songId
        self.audioFilePath = audioFilePath
        self.tagLabel = tagLabel
        self.tagCategory = tagCategory
    }

    /// Create a song node from a SongID
    public static func songNode(for songId: SongID, at position: CGPoint = .zero, audioFilePath: String? = nil) -> MoodboardNode {
        MoodboardNode(
            id: "song:\(songId.rawValue)",
            kind: .song,
            position: position,
            songId: songId,
            audioFilePath: audioFilePath
        )
    }

    /// Create a tag node
    public static func tagNode(label: String, category: TagCategory, at position: CGPoint = .zero) -> MoodboardNode {
        MoodboardNode(
            id: "tag:\(category.rawValue):\(label)",
            kind: .tag,
            position: position,
            tagLabel: label,
            tagCategory: category
        )
    }

    /// Copy with updated position
    public func withPosition(_ pos: CGPoint) -> MoodboardNode {
        MoodboardNode(
            id: id, kind: kind, position: pos,
            songId: songId, audioFilePath: audioFilePath,
            tagLabel: tagLabel, tagCategory: tagCategory
        )
    }

    /// Copy with updated audio file path
    public func withAudioFilePath(_ path: String?) -> MoodboardNode {
        MoodboardNode(
            id: id, kind: kind, position: position,
            songId: songId, audioFilePath: path,
            tagLabel: tagLabel, tagCategory: tagCategory
        )
    }
}

// MARK: - Moodboard Edge

/// A weighted, typed edge between two nodes. Immutable value type.
public struct MoodboardEdge: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let sourceId: String
    public let targetId: String
    public let edgeType: EdgeType
    public var weight: Double
    public let isDirected: Bool

    public init(
        id: String,
        sourceId: String,
        targetId: String,
        edgeType: EdgeType,
        weight: Double = 1.0,
        isDirected: Bool = false
    ) {
        self.id = id
        self.sourceId = sourceId
        self.targetId = targetId
        self.edgeType = edgeType
        self.weight = weight
        self.isDirected = isDirected
    }

    /// Copy with updated weight
    public func withWeight(_ w: Double) -> MoodboardEdge {
        MoodboardEdge(
            id: id, sourceId: sourceId, targetId: targetId,
            edgeType: edgeType, weight: w, isDirected: isDirected
        )
    }
}

// MARK: - Song Connection (Persisted)

/// An explicit, user-created connection between two songs.
/// Persisted in SongStore alongside song data.
public struct SongConnection: Equatable, Sendable, Codable, Identifiable {
    public var id: String { "\(sourceSongId.rawValue)::\(targetSongId.rawValue)::\(connectionType.rawValue)" }
    public let sourceSongId: SongID
    public let targetSongId: SongID
    public let connectionType: EdgeType
    public var weight: Double

    public init(
        sourceSongId: SongID,
        targetSongId: SongID,
        connectionType: EdgeType = .custom,
        weight: Double = 1.0
    ) {
        self.sourceSongId = sourceSongId
        self.targetSongId = targetSongId
        self.connectionType = connectionType
        self.weight = weight
    }

    /// Copy with updated weight
    public func withWeight(_ w: Double) -> SongConnection {
        SongConnection(
            sourceSongId: sourceSongId, targetSongId: targetSongId,
            connectionType: connectionType, weight: w
        )
    }
}

// MARK: - Phase Flow

/// A weighted edge in the phase flow DAG.
public struct PhaseFlowEdge: Equatable, Sendable, Codable, Identifiable {
    public var id: String { "\(fromPhase)::\(toPhase)" }
    public let fromPhase: String
    public let toPhase: String
    public var weight: Double

    public init(fromPhase: String, toPhase: String, weight: Double = 1.0) {
        self.fromPhase = fromPhase
        self.toPhase = toPhase
        self.weight = weight
    }

    /// Copy with updated weight
    public func withWeight(_ w: Double) -> PhaseFlowEdge {
        PhaseFlowEdge(fromPhase: fromPhase, toPhase: toPhase, weight: w)
    }
}

// MARK: - Canvas / Viewport State

/// Viewport state for the moodboard canvas.
public struct ViewportState: Equatable, Sendable, Codable {
    public var offset: CGPoint
    public var zoom: Double

    public init(offset: CGPoint = .zero, zoom: Double = 1.0) {
        self.offset = offset
        self.zoom = zoom
    }

    public static let `default` = ViewportState()
}

/// A persisted canvas position entry for a node.
public struct CanvasPositionEntry: Equatable, Sendable, Codable, Identifiable {
    public var id: String { nodeId }
    public let nodeId: String
    public let x: Double
    public let y: Double

    public init(nodeId: String, x: Double, y: Double) {
        self.nodeId = nodeId
        self.x = x
        self.y = y
    }
}

// MARK: - Named Board (Save/Load)

/// A named moodboard snapshot that can be saved and loaded.
public struct MoodboardBoard: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public var name: String
    public let createdAt: Date
    public var updatedAt: Date
    public var nodes: [MoodboardNode]
    public var edges: [MoodboardEdge]
    public var connections: [SongConnection]
    public var phaseFlowEdges: [PhaseFlowEdge]
    public var viewport: ViewportState

    public init(
        id: String = UUID().uuidString,
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        nodes: [MoodboardNode] = [],
        edges: [MoodboardEdge] = [],
        connections: [SongConnection] = [],
        phaseFlowEdges: [PhaseFlowEdge] = [],
        viewport: ViewportState = .default
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.nodes = nodes
        self.edges = edges
        self.connections = connections
        self.phaseFlowEdges = phaseFlowEdges
        self.viewport = viewport
    }
}

/// Lightweight reference to a saved board (for listing).
public struct MoodboardBoardSummary: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let name: String
    public let updatedAt: Date
    public let nodeCount: Int

    public init(id: String, name: String, updatedAt: Date, nodeCount: Int) {
        self.id = id
        self.name = name
        self.updatedAt = updatedAt
        self.nodeCount = nodeCount
    }
}

// MARK: - Song Graph Data

/// Internal graph representation built from songs.
/// Produced by `SongGraph.build()`, consumed by all graph query functions.
public struct SongGraphData: Sendable {
    /// All song nodes indexed by SongID
    public let nodes: [SongID: SongGraphNode]
    /// All edges (implicit from tags + explicit connections)
    public let edges: [SongGraphEdge]
    /// Adjacency list for fast neighbor lookup
    public let adjacency: [SongID: [SongGraphEdge]]

    public init(
        nodes: [SongID: SongGraphNode],
        edges: [SongGraphEdge],
        adjacency: [SongID: [SongGraphEdge]]
    ) {
        self.nodes = nodes
        self.edges = edges
        self.adjacency = adjacency
    }
}

/// A node in the song graph carrying tag information extracted from Song.
public struct SongGraphNode: Sendable, Equatable {
    public let id: SongID
    public let tags: Set<String>

    public init(id: SongID, tags: Set<String>) {
        self.id = id
        self.tags = tags
    }
}

/// An edge in the song graph.
public struct SongGraphEdge: Sendable, Equatable, Identifiable {
    public var id: String { "\(sourceId.rawValue)::\(targetId.rawValue)" }
    public let sourceId: SongID
    public let targetId: SongID
    public let edgeType: EdgeType
    public let weight: Double

    public init(sourceId: SongID, targetId: SongID, edgeType: EdgeType, weight: Double) {
        self.sourceId = sourceId
        self.targetId = targetId
        self.edgeType = edgeType
        self.weight = weight
    }
}
