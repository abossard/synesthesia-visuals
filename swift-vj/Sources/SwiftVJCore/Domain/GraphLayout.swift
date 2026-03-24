// GraphLayout.swift - Pure layout algorithms for moodboard canvas
// All functions are pure: (nodes, edges) -> [nodeId: CGPoint]
// Following Grokking Simplicity: calculations with no side effects

import CoreGraphics

// MARK: - Force-Directed Layout

/// Organic spring-electric layout. Nodes repel, edges attract.
/// Good for general-purpose graphs with clusters.
public func forceDirectedLayout(
    nodes: [MoodboardNode],
    edges: [MoodboardEdge],
    iterations: Int = 200,
    repulsion: CGFloat = 5000,
    attraction: CGFloat = 0.01,
    idealLength: CGFloat = 160
) -> [String: CGPoint] {
    guard !nodes.isEmpty else { return [:] }

    // Initialize positions (use existing or spread in a circle)
    var positions = [String: CGPoint]()
    let center = CGPoint(x: 400, y: 300)
    let radius: CGFloat = CGFloat(nodes.count) * 20
    for (i, node) in nodes.enumerated() {
        if node.position != .zero {
            positions[node.id] = node.position
        } else {
            let angle = CGFloat(i) / CGFloat(nodes.count) * 2 * .pi
            positions[node.id] = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
    }

    let nodeIds = nodes.map(\.id)
    var damping: CGFloat = 0.5

    // Build adjacency for fast edge lookup
    var adjacency = [String: [(String, MoodboardEdge)]]()
    for edge in edges {
        adjacency[edge.sourceId, default: []].append((edge.targetId, edge))
        adjacency[edge.targetId, default: []].append((edge.sourceId, edge))
    }

    for _ in 0..<iterations {
        var forces = [String: CGPoint]()
        for id in nodeIds { forces[id] = .zero }

        // Repulsion between all node pairs
        for i in 0..<nodeIds.count {
            for j in (i + 1)..<nodeIds.count {
                let idA = nodeIds[i], idB = nodeIds[j]
                guard let posA = positions[idA], let posB = positions[idB] else { continue }
                let dx = posA.x - posB.x
                let dy = posA.y - posB.y
                let distSq = max(1, dx * dx + dy * dy)
                let dist = sqrt(distSq)
                let force = repulsion / distSq
                let fx = (dx / dist) * force
                let fy = (dy / dist) * force
                forces[idA] = CGPoint(x: forces[idA]!.x + fx, y: forces[idA]!.y + fy)
                forces[idB] = CGPoint(x: forces[idB]!.x - fx, y: forces[idB]!.y - fy)
            }
        }

        // Attraction along edges
        for edge in edges {
            guard let posA = positions[edge.sourceId], let posB = positions[edge.targetId] else { continue }
            let dx = posB.x - posA.x
            let dy = posB.y - posA.y
            let dist = max(1, sqrt(dx * dx + dy * dy))
            let force = (dist - idealLength) * attraction
            let fx = (dx / dist) * force
            let fy = (dy / dist) * force
            forces[edge.sourceId] = CGPoint(
                x: forces[edge.sourceId]!.x + fx,
                y: forces[edge.sourceId]!.y + fy
            )
            forces[edge.targetId] = CGPoint(
                x: forces[edge.targetId]!.x - fx,
                y: forces[edge.targetId]!.y - fy
            )
        }

        // Apply forces
        for id in nodeIds {
            guard let pos = positions[id], let f = forces[id] else { continue }
            positions[id] = CGPoint(
                x: pos.x + f.x * damping,
                y: pos.y + f.y * damping
            )
        }

        damping *= 0.98
    }

    return positions.mapValues { snapToGrid($0) }
}

// MARK: - Hierarchical Layout (Sugiyama-style)

/// Layered left-to-right layout for directed graphs.
/// Roots (no incoming directed edges) go to layer 0.
/// Good for song succession chains and phase flows.
public func hierarchicalLayout(
    nodes: [MoodboardNode],
    edges: [MoodboardEdge],
    layerSpacing: CGFloat = 200,
    nodeSpacing: CGFloat = 140,
    direction: HierarchicalDirection = .leftToRight
) -> [String: CGPoint] {
    guard !nodes.isEmpty else { return [:] }

    let nodeIds = Set(nodes.map(\.id))

    // Build directed adjacency (only directed edges count for layering)
    var outgoing = [String: [String]]()
    var incoming = [String: [String]]()
    for id in nodeIds {
        outgoing[id] = []
        incoming[id] = []
    }
    for edge in edges {
        guard nodeIds.contains(edge.sourceId), nodeIds.contains(edge.targetId) else { continue }
        if edge.isDirected {
            outgoing[edge.sourceId, default: []].append(edge.targetId)
            incoming[edge.targetId, default: []].append(edge.sourceId)
        }
    }

    // Layer assignment via longest-path from roots
    let roots = nodeIds.filter { (incoming[$0] ?? []).isEmpty }
    var layers = [String: Int]()

    // BFS-based longest path
    var queue = Array(roots)
    for root in roots { layers[root] = 0 }

    // Assign unconnected nodes as roots too
    for id in nodeIds where layers[id] == nil {
        layers[id] = 0
        queue.append(id)
    }

    var head = 0
    while head < queue.count {
        let current = queue[head]; head += 1
        let currentLayer = layers[current]!
        for next in outgoing[current] ?? [] {
            let newLayer = currentLayer + 1
            if layers[next] == nil || layers[next]! < newLayer {
                layers[next] = newLayer
                queue.append(next)
            }
        }
    }

    // Group nodes by layer
    var layerGroups = [Int: [String]]()
    for (id, layer) in layers {
        layerGroups[layer, default: []].append(id)
    }

    // Sort within layers by incoming edge barycenter
    for (layer, ids) in layerGroups {
        if layer == 0 { continue }
        layerGroups[layer] = ids.sorted { a, b in
            let aParents = (incoming[a] ?? []).compactMap { layers[$0] != nil ? layers[$0]! : nil }
            let bParents = (incoming[b] ?? []).compactMap { layers[$0] != nil ? layers[$0]! : nil }
            let aCenter = aParents.isEmpty ? 0.0 : Double(aParents.reduce(0, +)) / Double(aParents.count)
            let bCenter = bParents.isEmpty ? 0.0 : Double(bParents.reduce(0, +)) / Double(bParents.count)
            return aCenter < bCenter
        }
    }

    // Position nodes
    var positions = [String: CGPoint]()
    let maxLayer = layerGroups.keys.max() ?? 0
    let startX: CGFloat = 100
    let startY: CGFloat = 100

    for layer in 0...maxLayer {
        let ids = layerGroups[layer] ?? []
        for (index, id) in ids.enumerated() {
            let x: CGFloat, y: CGFloat
            switch direction {
            case .leftToRight:
                x = startX + CGFloat(layer) * layerSpacing
                y = startY + CGFloat(index) * nodeSpacing
            case .topToBottom:
                x = startX + CGFloat(index) * nodeSpacing
                y = startY + CGFloat(layer) * layerSpacing
            }
            positions[id] = snapToGrid(CGPoint(x: x, y: y))
        }
    }

    return positions
}

public enum HierarchicalDirection: String, Codable, Sendable {
    case leftToRight
    case topToBottom
}

// MARK: - Grouped Layout (Bipartite)

/// Tags in columns on the left, songs on the right, grouped by tag connection.
/// Songs connected to the same tags cluster together.
public func groupedLayout(
    nodes: [MoodboardNode],
    edges: [MoodboardEdge],
    tagColumnX: CGFloat = 100,
    songColumnX: CGFloat = 400,
    nodeSpacing: CGFloat = 140,
    categorySpacing: CGFloat = 60
) -> [String: CGPoint] {
    guard !nodes.isEmpty else { return [:] }

    let tagNodes = nodes.filter { $0.kind == .tag }
    let songNodes = nodes.filter { $0.kind == .song }
    let otherNodes = nodes.filter { $0.kind != .tag && $0.kind != .song }

    var positions = [String: CGPoint]()

    // Group tags by category, then lay them out vertically
    let tagsByCategory = Dictionary(grouping: tagNodes, by: { $0.tagCategory ?? .custom })
    var tagY: CGFloat = 100
    let sortedCategories = tagsByCategory.keys.sorted { $0.rawValue < $1.rawValue }

    for category in sortedCategories {
        let tags = tagsByCategory[category] ?? []
        for tag in tags {
            positions[tag.id] = snapToGrid(CGPoint(x: tagColumnX, y: tagY))
            tagY += nodeSpacing
        }
        tagY += categorySpacing
    }

    // Build tag → connected song IDs
    var songToTags = [String: [String]]()
    for edge in edges {
        if edge.edgeType == .tagMembership {
            let tagId = tagNodes.contains(where: { $0.id == edge.sourceId }) ? edge.sourceId : edge.targetId
            let songId = tagNodes.contains(where: { $0.id == edge.sourceId }) ? edge.targetId : edge.sourceId
            if songNodes.contains(where: { $0.id == songId }) {
                songToTags[songId, default: []].append(tagId)
            }
        }
    }

    // Sort songs by their first tag's Y position (cluster near their tags)
    let sortedSongs = songNodes.sorted { a, b in
        let aTagY = (songToTags[a.id] ?? []).compactMap { positions[$0]?.y }.min() ?? CGFloat.infinity
        let bTagY = (songToTags[b.id] ?? []).compactMap { positions[$0]?.y }.min() ?? CGFloat.infinity
        return aTagY < bTagY
    }

    var songY: CGFloat = 100
    for song in sortedSongs {
        positions[song.id] = snapToGrid(CGPoint(x: songColumnX, y: songY))
        songY += nodeSpacing
    }

    // Place unconnected songs at the bottom
    for song in songNodes where positions[song.id] == nil {
        positions[song.id] = snapToGrid(CGPoint(x: songColumnX, y: songY))
        songY += nodeSpacing
    }

    // Place other nodes (containers) below everything
    var otherY = max(tagY, songY) + categorySpacing
    for node in otherNodes {
        positions[node.id] = snapToGrid(CGPoint(x: (tagColumnX + songColumnX) / 2, y: otherY))
        otherY += nodeSpacing
    }

    return positions
}
