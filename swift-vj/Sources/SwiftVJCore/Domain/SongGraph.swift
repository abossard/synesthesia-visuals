import Foundation
import SongRepository

// MARK: - SongGraph (Pure Calculation Module)

/// Graph operations over songs: build similarity graphs, find clusters, discover connections.
///
/// Port of Musicky's graph-engine.ts adapted for SwiftVJ's Song model.
/// All functions are pure calculations — no side effects, no I/O, no Store access.
public enum SongGraph {

    // MARK: - Build

    /// Build a graph from songs and explicit connections.
    ///
    /// Extracts tags from each song's analysis (mood, phase, keywords, themes, categories)
    /// and creates implicit similarity edges between songs sharing tags (Jaccard ≥ threshold).
    /// Explicit `SongConnection` entries are added as additional edges.
    public static func build(
        songs: [Song],
        connections: [SongConnection] = [],
        similarityThreshold: Double = 0.1
    ) -> SongGraphData {
        let nodes = buildNodes(from: songs)
        let similarityEdges = buildSimilarityEdges(nodes: nodes, threshold: similarityThreshold)
        let explicitEdges = connections.map { connection in
            SongGraphEdge(
                sourceId: connection.sourceSongId,
                targetId: connection.targetSongId,
                edgeType: connection.connectionType,
                weight: connection.weight
            )
        }
        let allEdges = similarityEdges + explicitEdges
        let adjacency = buildAdjacency(edges: allEdges)
        return SongGraphData(nodes: nodes, edges: allEdges, adjacency: adjacency)
    }

    // MARK: - Query

    /// Find songs most similar to the target based on Jaccard tag similarity.
    public static func findSimilar(
        to songId: SongID,
        in graph: SongGraphData,
        limit: Int = 10
    ) -> [(SongID, Double)] {
        guard let targetNode = graph.nodes[songId] else { return [] }

        return graph.nodes.values
            .filter { $0.id != songId }
            .map { node in (node.id, jaccardSimilarity(targetNode.tags, node.tags)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { ($0.0, $0.1) }
    }

    /// Find connected components (clusters of related songs) using BFS.
    public static func connectedComponents(_ graph: SongGraphData) -> [[SongID]] {
        var visited = Set<SongID>()
        var components: [[SongID]] = []

        for nodeId in graph.nodes.keys {
            guard !visited.contains(nodeId) else { continue }
            let component = bfsComponent(from: nodeId, adjacency: graph.adjacency, visited: &visited)
            components.append(component)
        }

        return components.sorted { $0.count > $1.count }
    }

    /// Discover pairs of songs sharing tags but not explicitly connected.
    public static func discoverHiddenConnections(
        in graph: SongGraphData,
        threshold: Double = 0.2
    ) -> [SongConnection] {
        let connectedPairs = buildConnectedPairSet(from: graph.edges)
        let nodeList = Array(graph.nodes.values)
        var results: [SongConnection] = []

        for i in 0..<nodeList.count {
            for j in (i + 1)..<nodeList.count {
                let a = nodeList[i]
                let b = nodeList[j]
                let pair = normalizedPair(a.id, b.id)
                guard !connectedPairs.contains(pair) else { continue }

                let similarity = jaccardSimilarity(a.tags, b.tags)
                guard similarity >= threshold else { continue }

                results.append(SongConnection(
                    sourceSongId: a.id,
                    targetSongId: b.id,
                    connectionType: .similarity,
                    weight: similarity
                ))
            }
        }

        return results.sorted { $0.weight > $1.weight }
    }

    /// Find shortest path between two songs via edges (BFS).
    public static func shortestPath(
        _ graph: SongGraphData,
        from source: SongID,
        to target: SongID
    ) -> [SongID]? {
        guard graph.nodes[source] != nil, graph.nodes[target] != nil else { return nil }
        guard source != target else { return [source] }

        var visited = Set<SongID>([source])
        var queue: [SongID] = [source]
        var parent: [SongID: SongID] = [:]
        var head = 0

        while head < queue.count {
            let current = queue[head]
            head += 1

            guard let neighbors = graph.adjacency[current] else { continue }
            for edge in neighbors {
                let neighbor = edge.sourceId == current ? edge.targetId : edge.sourceId
                guard !visited.contains(neighbor) else { continue }

                visited.insert(neighbor)
                parent[neighbor] = current
                if neighbor == target {
                    return reconstructPath(parent: parent, from: source, to: target)
                }
                queue.append(neighbor)
            }
        }

        return nil
    }
}

// MARK: - Internal Calculations

private extension SongGraph {

    /// Extract tags from a song's analysis into a `SongGraphNode`.
    static func extractTags(from song: Song) -> Set<String> {
        guard let analysis = song.analysis else { return [] }
        var tags = Set<String>()

        if !analysis.mood.isEmpty {
            tags.insert("mood:\(analysis.mood)")
        }
        if let phase = analysis.djPhase {
            tags.insert("phase:\(phase.rawValue)")
        }
        for keyword in analysis.keywords {
            tags.insert("keyword:\(keyword)")
        }
        for theme in analysis.themes {
            tags.insert("theme:\(theme)")
        }
        for (key, score) in analysis.categories where score > 0.3 {
            tags.insert("category:\(key)")
        }

        return tags
    }

    static func buildNodes(from songs: [Song]) -> [SongID: SongGraphNode] {
        var nodes: [SongID: SongGraphNode] = [:]
        nodes.reserveCapacity(songs.count)
        for song in songs {
            nodes[song.id] = SongGraphNode(id: song.id, tags: extractTags(from: song))
        }
        return nodes
    }

    static func buildSimilarityEdges(
        nodes: [SongID: SongGraphNode],
        threshold: Double
    ) -> [SongGraphEdge] {
        let nodeList = Array(nodes.values)
        var edges: [SongGraphEdge] = []

        for i in 0..<nodeList.count {
            for j in (i + 1)..<nodeList.count {
                let a = nodeList[i]
                let b = nodeList[j]
                let similarity = jaccardSimilarity(a.tags, b.tags)
                guard similarity >= threshold else { continue }
                edges.append(SongGraphEdge(
                    sourceId: a.id,
                    targetId: b.id,
                    edgeType: .similarity,
                    weight: similarity
                ))
            }
        }

        return edges
    }

    static func buildAdjacency(edges: [SongGraphEdge]) -> [SongID: [SongGraphEdge]] {
        var adjacency: [SongID: [SongGraphEdge]] = [:]
        for edge in edges {
            adjacency[edge.sourceId, default: []].append(edge)
            adjacency[edge.targetId, default: []].append(edge)
        }
        return adjacency
    }

    /// Jaccard similarity: |A ∩ B| / |A ∪ B|
    static func jaccardSimilarity(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 0 }
        let intersection = a.intersection(b).count
        let union = a.union(b).count
        return Double(intersection) / Double(union)
    }

    /// BFS to collect all nodes reachable from `start`.
    static func bfsComponent(
        from start: SongID,
        adjacency: [SongID: [SongGraphEdge]],
        visited: inout Set<SongID>
    ) -> [SongID] {
        var component: [SongID] = []
        var queue: [SongID] = [start]
        var head = 0
        visited.insert(start)

        while head < queue.count {
            let current = queue[head]
            head += 1
            component.append(current)

            guard let neighbors = adjacency[current] else { continue }
            for edge in neighbors {
                let neighbor = edge.sourceId == current ? edge.targetId : edge.sourceId
                guard !visited.contains(neighbor) else { continue }
                visited.insert(neighbor)
                queue.append(neighbor)
            }
        }

        return component
    }

    /// Build a set of normalized (alphabetically ordered) pairs for fast lookup.
    static func buildConnectedPairSet(from edges: [SongGraphEdge]) -> Set<String> {
        var pairs = Set<String>()
        for edge in edges {
            pairs.insert(normalizedPair(edge.sourceId, edge.targetId))
        }
        return pairs
    }

    static func normalizedPair(_ a: SongID, _ b: SongID) -> String {
        a.rawValue < b.rawValue
            ? "\(a.rawValue)::\(b.rawValue)"
            : "\(b.rawValue)::\(a.rawValue)"
    }

    /// Reconstruct path from BFS parent map.
    static func reconstructPath(
        parent: [SongID: SongID],
        from source: SongID,
        to target: SongID
    ) -> [SongID] {
        var path: [SongID] = [target]
        var current = target
        while current != source {
            guard let prev = parent[current] else { return [] }
            path.append(prev)
            current = prev
        }
        return path.reversed()
    }
}
