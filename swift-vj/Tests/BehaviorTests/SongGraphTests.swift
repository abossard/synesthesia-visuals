import Testing
@testable import SwiftVJCore
import SongRepository

// MARK: - Test Helpers

private func makeSong(
    artist: String,
    title: String,
    mood: String = "",
    keywords: [String] = [],
    themes: [String] = [],
    categories: [String: Double] = [:],
    djPhase: Phase? = nil
) -> Song {
    let analysis = StoredSongAnalysis(
        keywords: keywords,
        themes: themes,
        visualAdjectives: [],
        mood: mood,
        energy: 0.5,
        valence: 0.0,
        categories: categories,
        djPhase: djPhase
    )
    return Song(
        id: SongID(artist: artist, title: title),
        artist: artist,
        title: title,
        analysis: analysis
    )
}

private func makeSongNoAnalysis(artist: String, title: String) -> Song {
    Song(
        id: SongID(artist: artist, title: title),
        artist: artist,
        title: title
    )
}

// MARK: - Build Tests

@Suite("SongGraph.build")
struct SongGraphBuildTests {

    @Test("Empty songs produce empty graph")
    func buildEmpty() {
        let graph = SongGraph.build(songs: [])
        #expect(graph.nodes.isEmpty)
        #expect(graph.edges.isEmpty)
        #expect(graph.adjacency.isEmpty)
    }

    @Test("Single song produces one node and no edges")
    func buildSingleSong() {
        let song = makeSong(artist: "A", title: "T1", mood: "happy")
        let graph = SongGraph.build(songs: [song])
        #expect(graph.nodes.count == 1)
        #expect(graph.edges.isEmpty)
        #expect(graph.nodes[song.id] != nil)
    }

    @Test("Song without analysis produces node with empty tags")
    func buildSongNoAnalysis() {
        let song = makeSongNoAnalysis(artist: "A", title: "T1")
        let graph = SongGraph.build(songs: [song])
        let node = graph.nodes[song.id]
        #expect(node != nil)
        #expect(node?.tags.isEmpty == true)
    }

    @Test("Songs sharing tags get similarity edges")
    func buildSimilarityEdges() {
        let s1 = makeSong(artist: "A", title: "T1", mood: "happy", keywords: ["dance", "energy"])
        let s2 = makeSong(artist: "B", title: "T2", mood: "happy", keywords: ["dance"])
        let graph = SongGraph.build(songs: [s1, s2], similarityThreshold: 0.1)

        #expect(!graph.edges.isEmpty)
        let edge = graph.edges.first
        #expect(edge?.edgeType == .similarity)
        #expect(edge != nil && edge!.weight > 0)
    }

    @Test("Songs with no shared tags produce no edges")
    func buildNoSharedTags() {
        let s1 = makeSong(artist: "A", title: "T1", mood: "happy", keywords: ["dance"])
        let s2 = makeSong(artist: "B", title: "T2", mood: "sad", keywords: ["ballad"])
        let graph = SongGraph.build(songs: [s1, s2], similarityThreshold: 0.5)

        #expect(graph.edges.isEmpty)
    }

    @Test("Explicit connections appear as edges")
    func buildExplicitConnections() {
        let s1 = makeSong(artist: "A", title: "T1", mood: "chill")
        let s2 = makeSong(artist: "B", title: "T2", mood: "dark")
        let conn = SongConnection(
            sourceSongId: s1.id,
            targetSongId: s2.id,
            connectionType: .transition,
            weight: 0.9
        )
        let graph = SongGraph.build(songs: [s1, s2], connections: [conn], similarityThreshold: 1.0)

        let transitionEdges = graph.edges.filter { $0.edgeType == .transition }
        #expect(transitionEdges.count == 1)
        #expect(transitionEdges.first?.weight == 0.9)
    }

    @Test("Tags extracted include mood, phase, keywords, themes, and high-score categories")
    func buildTagExtraction() {
        let song = makeSong(
            artist: "X", title: "Y",
            mood: "euphoric",
            keywords: ["synth"],
            themes: ["nightlife"],
            categories: ["electronic": 0.9, "ambient": 0.1],
            djPhase: .peak
        )
        let graph = SongGraph.build(songs: [song])
        let tags = graph.nodes[song.id]!.tags

        #expect(tags.contains("mood:euphoric"))
        #expect(tags.contains("phase:peak"))
        #expect(tags.contains("keyword:synth"))
        #expect(tags.contains("theme:nightlife"))
        #expect(tags.contains("category:electronic"))
        #expect(!tags.contains("category:ambient")) // score 0.1 ≤ 0.3 threshold
    }
}

// MARK: - Connected Components

@Suite("SongGraph.connectedComponents")
struct SongGraphConnectedComponentsTests {

    @Test("Empty graph has no components")
    func emptyGraph() {
        let graph = SongGraph.build(songs: [])
        let components = SongGraph.connectedComponents(graph)
        #expect(components.isEmpty)
    }

    @Test("Isolated nodes are individual components")
    func isolatedNodes() {
        let s1 = makeSong(artist: "A", title: "T1", mood: "happy")
        let s2 = makeSong(artist: "B", title: "T2", mood: "sad")
        let graph = SongGraph.build(songs: [s1, s2], similarityThreshold: 1.0)

        let components = SongGraph.connectedComponents(graph)
        #expect(components.count == 2)
        for comp in components {
            #expect(comp.count == 1)
        }
    }

    @Test("Connected songs form one cluster")
    func oneCluster() {
        let s1 = makeSong(artist: "A", title: "T1", mood: "happy", keywords: ["dance"])
        let s2 = makeSong(artist: "B", title: "T2", mood: "happy", keywords: ["dance"])
        let s3 = makeSong(artist: "C", title: "T3", mood: "happy", keywords: ["dance"])
        let graph = SongGraph.build(songs: [s1, s2, s3], similarityThreshold: 0.1)

        let components = SongGraph.connectedComponents(graph)
        #expect(components.count == 1)
        #expect(components.first?.count == 3)
    }

    @Test("Multiple disjoint clusters")
    func multipleClusters() {
        // Cluster 1: share "dance"
        let s1 = makeSong(artist: "A", title: "T1", keywords: ["dance"])
        let s2 = makeSong(artist: "B", title: "T2", keywords: ["dance"])
        // Cluster 2: share "ambient"
        let s3 = makeSong(artist: "C", title: "T3", keywords: ["ambient"])
        let s4 = makeSong(artist: "D", title: "T4", keywords: ["ambient"])
        let graph = SongGraph.build(songs: [s1, s2, s3, s4], similarityThreshold: 0.1)

        let components = SongGraph.connectedComponents(graph)
        #expect(components.count == 2)
        #expect(components[0].count == 2)
        #expect(components[1].count == 2)
    }

    @Test("Components sorted by size descending")
    func componentsSortedBySize() {
        // Big cluster: 3 songs sharing "electronic"
        let s1 = makeSong(artist: "A", title: "T1", keywords: ["electronic"])
        let s2 = makeSong(artist: "B", title: "T2", keywords: ["electronic"])
        let s3 = makeSong(artist: "C", title: "T3", keywords: ["electronic"])
        // Small cluster: 1 isolated song
        let s4 = makeSong(artist: "D", title: "T4", keywords: ["classical"])
        let graph = SongGraph.build(songs: [s1, s2, s3, s4], similarityThreshold: 0.1)

        let components = SongGraph.connectedComponents(graph)
        #expect(components.first!.count >= components.last!.count)
    }
}

// MARK: - findSimilar

@Suite("SongGraph.findSimilar")
struct SongGraphFindSimilarTests {

    @Test("Returns empty for unknown song ID")
    func unknownSong() {
        let graph = SongGraph.build(songs: [])
        let result = SongGraph.findSimilar(to: SongID(artist: "X", title: "Y"), in: graph)
        #expect(result.isEmpty)
    }

    @Test("Returns similar songs ordered by score descending")
    func orderedByScore() {
        let target = makeSong(artist: "T", title: "Target", mood: "happy", keywords: ["dance", "energy"])
        let close  = makeSong(artist: "A", title: "Close", mood: "happy", keywords: ["dance", "energy"])
        let mid    = makeSong(artist: "B", title: "Mid", mood: "happy", keywords: ["chill"])
        let far    = makeSong(artist: "C", title: "Far", mood: "sad", keywords: ["ballad"])
        let graph = SongGraph.build(songs: [target, close, mid, far])

        let results = SongGraph.findSimilar(to: target.id, in: graph)
        #expect(!results.isEmpty)
        // Verify descending order
        for i in 0..<(results.count - 1) {
            #expect(results[i].1 >= results[i + 1].1)
        }
        // close should score higher than mid
        if let closeScore = results.first(where: { $0.0 == close.id })?.1,
           let midScore = results.first(where: { $0.0 == mid.id })?.1 {
            #expect(closeScore > midScore)
        }
    }

    @Test("Respects limit parameter")
    func respectsLimit() {
        let target = makeSong(artist: "T", title: "Target", mood: "happy", keywords: ["dance"])
        let s1 = makeSong(artist: "A", title: "T1", mood: "happy")
        let s2 = makeSong(artist: "B", title: "T2", mood: "happy")
        let s3 = makeSong(artist: "C", title: "T3", mood: "happy")
        let graph = SongGraph.build(songs: [target, s1, s2, s3])

        let results = SongGraph.findSimilar(to: target.id, in: graph, limit: 1)
        #expect(results.count <= 1)
    }

    @Test("Does not include the target song itself")
    func excludesSelf() {
        let target = makeSong(artist: "T", title: "Target", mood: "happy")
        let other = makeSong(artist: "A", title: "Other", mood: "happy")
        let graph = SongGraph.build(songs: [target, other])

        let results = SongGraph.findSimilar(to: target.id, in: graph)
        #expect(!results.contains(where: { $0.0 == target.id }))
    }

    @Test("Only returns songs with positive similarity")
    func positiveSimilarityOnly() {
        let target = makeSong(artist: "T", title: "Target", mood: "happy")
        let unrelated = makeSong(artist: "A", title: "Unrelated", mood: "sad", keywords: ["noise"])
        let graph = SongGraph.build(songs: [target, unrelated])

        let results = SongGraph.findSimilar(to: target.id, in: graph)
        for (_, score) in results {
            #expect(score > 0)
        }
    }
}

// MARK: - discoverHiddenConnections

@Suite("SongGraph.discoverHiddenConnections")
struct SongGraphDiscoverHiddenConnectionsTests {

    @Test("No hidden connections in empty graph")
    func emptyGraph() {
        let graph = SongGraph.build(songs: [])
        let hidden = SongGraph.discoverHiddenConnections(in: graph)
        #expect(hidden.isEmpty)
    }

    @Test("Discovers unconnected songs sharing tags")
    func discoversSharedTags() {
        // Two songs share mood but have no edge at high threshold
        let s1 = makeSong(artist: "A", title: "T1", mood: "happy", keywords: ["x", "y", "z"])
        let s2 = makeSong(artist: "B", title: "T2", mood: "happy", keywords: ["x", "y", "w"])
        // Build with very high threshold so no similarity edges are created
        let graph = SongGraph.build(songs: [s1, s2], similarityThreshold: 1.0)

        let hidden = SongGraph.discoverHiddenConnections(in: graph, threshold: 0.1)
        #expect(!hidden.isEmpty)
        #expect(hidden.first?.connectionType == .similarity)
    }

    @Test("Already-connected songs are excluded")
    func excludesConnected() {
        let s1 = makeSong(artist: "A", title: "T1", mood: "happy", keywords: ["dance"])
        let s2 = makeSong(artist: "B", title: "T2", mood: "happy", keywords: ["dance"])
        // Low threshold ensures they get a similarity edge
        let graph = SongGraph.build(songs: [s1, s2], similarityThreshold: 0.01)

        let hidden = SongGraph.discoverHiddenConnections(in: graph, threshold: 0.01)
        #expect(hidden.isEmpty)
    }

    @Test("Results sorted by weight descending")
    func sortedByWeight() {
        let s1 = makeSong(artist: "A", title: "T1", mood: "happy", keywords: ["a", "b", "c"])
        let s2 = makeSong(artist: "B", title: "T2", mood: "happy", keywords: ["a", "b"])
        let s3 = makeSong(artist: "C", title: "T3", mood: "happy", keywords: ["a"])
        let graph = SongGraph.build(songs: [s1, s2, s3], similarityThreshold: 1.0)

        let hidden = SongGraph.discoverHiddenConnections(in: graph, threshold: 0.1)
        for i in 0..<(hidden.count - 1) {
            #expect(hidden[i].weight >= hidden[i + 1].weight)
        }
    }
}

// MARK: - shortestPath

@Suite("SongGraph.shortestPath")
struct SongGraphShortestPathTests {

    @Test("Path to self is single-element array")
    func pathToSelf() {
        let song = makeSong(artist: "A", title: "T1", mood: "happy")
        let graph = SongGraph.build(songs: [song])
        let path = SongGraph.shortestPath(graph, from: song.id, to: song.id)
        #expect(path == [song.id])
    }

    @Test("Direct neighbors have path of length 2")
    func directPath() {
        let s1 = makeSong(artist: "A", title: "T1", mood: "happy", keywords: ["dance"])
        let s2 = makeSong(artist: "B", title: "T2", mood: "happy", keywords: ["dance"])
        let graph = SongGraph.build(songs: [s1, s2], similarityThreshold: 0.01)

        let path = SongGraph.shortestPath(graph, from: s1.id, to: s2.id)
        #expect(path != nil)
        #expect(path?.count == 2)
        #expect(path?.first == s1.id)
        #expect(path?.last == s2.id)
    }

    @Test("Indirect path through intermediate node")
    func indirectPath() {
        // A connects to B (share "dance"), B connects to C (share "chill"), A not to C
        let a = makeSong(artist: "A", title: "A", keywords: ["dance"])
        let b = makeSong(artist: "B", title: "B", keywords: ["dance", "chill"])
        let c = makeSong(artist: "C", title: "C", keywords: ["chill"])
        let graph = SongGraph.build(songs: [a, b, c], similarityThreshold: 0.1)

        let path = SongGraph.shortestPath(graph, from: a.id, to: c.id)
        #expect(path != nil)
        #expect(path!.first == a.id)
        #expect(path!.last == c.id)
        #expect(path!.contains(b.id))
    }

    @Test("Returns nil for unreachable pair")
    func unreachablePair() {
        let s1 = makeSong(artist: "A", title: "T1", mood: "happy")
        let s2 = makeSong(artist: "B", title: "T2", mood: "sad", keywords: ["noise"])
        let graph = SongGraph.build(songs: [s1, s2], similarityThreshold: 1.0)

        let path = SongGraph.shortestPath(graph, from: s1.id, to: s2.id)
        #expect(path == nil)
    }

    @Test("Returns nil for unknown source or target")
    func unknownNodes() {
        let song = makeSong(artist: "A", title: "T1", mood: "happy")
        let graph = SongGraph.build(songs: [song])
        let unknown = SongID(artist: "X", title: "Y")

        #expect(SongGraph.shortestPath(graph, from: unknown, to: song.id) == nil)
        #expect(SongGraph.shortestPath(graph, from: song.id, to: unknown) == nil)
    }
}
