import Foundation

// MARK: - PhaseGraph — Pure DAG operations on phase flow edges

/// Stateless calculations for phase flow DAGs.
/// Port of Musicky's phase-graph.ts adapted for SwiftVJ's Phase enum.
public enum PhaseGraph {

    // MARK: - Public API

    /// Topological sort via Kahn's algorithm.
    /// Falls back to edge-appearance order when the graph contains cycles.
    public static func order(edges: [PhaseFlowEdge]) -> [String] {
        let phases = collectPhases(edges: edges)
        if phases.isEmpty { return [] }

        var adj = buildAdjacency(edges: edges)
        var inDegree: [String: Int] = [:]
        for phase in phases { inDegree[phase] = 0 }
        for (_, neighbors) in adj {
            for (target, _) in neighbors {
                inDegree[target, default: 0] += 1
            }
        }

        // Max incoming weight per phase (for tie-breaking)
        var maxInWeight: [String: Double] = [:]
        for edge in edges {
            let current = maxInWeight[edge.toPhase] ?? 0.0
            if edge.weight > current { maxInWeight[edge.toPhase] = edge.weight }
        }

        // Seeds: in-degree 0, sorted by max incoming weight descending
        var queue = phases
            .filter { (inDegree[$0] ?? 0) == 0 }
            .sorted { (maxInWeight[$0] ?? 0) > (maxInWeight[$1] ?? 0) }

        var result: [String] = []

        while !queue.isEmpty {
            let node = queue.removeFirst()
            result.append(node)

            let neighbors = adj[node] ?? []
            for (target, _) in neighbors {
                inDegree[target, default: 0] -= 1
                if inDegree[target] == 0 {
                    queue.append(target)
                    // Re-sort after insertion for stable tie-breaking
                    queue.sort { (maxInWeight[$0] ?? 0) > (maxInWeight[$1] ?? 0) }
                }
            }
        }

        // Cycle detected — fall back to edge-appearance order
        if result.count != phases.count {
            return collectPhasesOrdered(edges: edges)
        }
        return result
    }

    /// Validate that edges form a DAG.
    /// Returns `(true, nil)` when valid, `(false, cyclePath)` when a cycle exists.
    public static func validate(edges: [PhaseFlowEdge]) -> (valid: Bool, cycle: [String]?) {
        let phases = collectPhases(edges: edges)
        let adj = buildAdjacency(edges: edges)

        var state: [String: NodeState] = [:]
        for phase in phases { state[phase] = .unvisited }
        var stack: [String] = []

        for phase in phases {
            if state[phase] == .unvisited {
                if let cycle = dfs(node: phase, adj: adj, state: &state, stack: &stack) {
                    return (false, cycle)
                }
            }
        }
        return (true, nil)
    }

    /// Check whether adding `from → to` would introduce a cycle.
    public static func wouldCreateCycle(edges: [PhaseFlowEdge], from: String, to: String) -> Bool {
        var extended = edges
        extended.append(PhaseFlowEdge(fromPhase: from, toPhase: to))
        let (valid, _) = validate(edges: extended)
        return !valid
    }

    /// Suggest a default linear DAG from a list of phase names.
    /// Recognises common DJ phase names (case-insensitive) and orders them
    /// into a natural progression.
    public static func suggestDefaultFlow(phases: [String]) -> [PhaseFlowEdge] {
        if phases.isEmpty { return [] }

        let sorted = phases.sorted { orderHint(for: $0) < orderHint(for: $1) }

        var edges: [PhaseFlowEdge] = []
        for i in 0 ..< sorted.count - 1 {
            edges.append(PhaseFlowEdge(fromPhase: sorted[i], toPhase: sorted[i + 1], weight: 1.0))
        }
        return edges
    }

    /// Longest path through the DAG (most comprehensive set flow).
    /// Returns an empty array when edges are empty or the graph has a cycle.
    public static func longestPath(edges: [PhaseFlowEdge]) -> [String] {
        let sorted = order(edges: edges)
        if sorted.isEmpty { return [] }

        let (valid, _) = validate(edges: edges)
        if !valid { return [] }

        let adj = buildAdjacency(edges: edges)

        var dist: [String: Double] = [:]
        var pred: [String: String] = [:]
        for phase in sorted { dist[phase] = -.infinity }

        // Sources start at 0
        let sourceSet = Set(sorted).subtracting(Set(edges.map(\.toPhase)))
        for source in sourceSet { dist[source] = 0 }

        for node in sorted {
            guard let d = dist[node], d > -.infinity else { continue }
            for (target, weight) in adj[node] ?? [] {
                let candidate = d + weight
                if candidate > (dist[target] ?? -.infinity) {
                    dist[target] = candidate
                    pred[target] = node
                }
            }
        }

        // Find endpoint with maximum distance
        guard let end = sorted.max(by: { (dist[$0] ?? -.infinity) < (dist[$1] ?? -.infinity) }),
              let endDist = dist[end], endDist > -.infinity else {
            return []
        }

        // Reconstruct path
        var path: [String] = [end]
        var current = end
        while let prev = pred[current] {
            path.append(prev)
            current = prev
        }
        return path.reversed()
    }

    // MARK: - Internal helpers

    private enum NodeState { case unvisited, visiting, visited }

    private static func buildAdjacency(edges: [PhaseFlowEdge]) -> [String: [(target: String, weight: Double)]] {
        var adj: [String: [(target: String, weight: Double)]] = [:]
        for edge in edges {
            adj[edge.fromPhase, default: []].append((edge.toPhase, edge.weight))
        }
        return adj
    }

    /// Collect all unique phases preserving first-seen order.
    private static func collectPhasesOrdered(edges: [PhaseFlowEdge]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for edge in edges {
            for phase in [edge.fromPhase, edge.toPhase] {
                if seen.insert(phase).inserted {
                    result.append(phase)
                }
            }
        }
        return result
    }

    /// Collect all unique phases (unordered set).
    private static func collectPhases(edges: [PhaseFlowEdge]) -> [String] {
        collectPhasesOrdered(edges: edges)
    }

    /// DFS cycle detection. Returns the cycle path if one is found.
    private static func dfs(
        node: String,
        adj: [String: [(target: String, weight: Double)]],
        state: inout [String: NodeState],
        stack: inout [String]
    ) -> [String]? {
        state[node] = .visiting
        stack.append(node)

        for (neighbor, _) in adj[node] ?? [] {
            switch state[neighbor] {
            case .visiting:
                // Cycle found — extract it from the stack
                if let idx = stack.firstIndex(of: neighbor) {
                    return Array(stack[idx...]) + [neighbor]
                }
                return [neighbor, node, neighbor]
            case .unvisited:
                if let cycle = dfs(node: neighbor, adj: adj, state: &state, stack: &stack) {
                    return cycle
                }
            case .visited, .none:
                break
            }
        }

        stack.removeLast()
        state[node] = .visited
        return nil
    }

    /// Map a phase name to a numeric sort hint for `suggestDefaultFlow`.
    private static func orderHint(for phase: String) -> Int {
        switch phase.lowercased() {
        case "opener", "intro", "disco":       return 0
        case "warmup", "warm-up":              return 1
        case "buildup", "build-up", "build":   return 2
        case "peak", "drop", "main":           return 3
        case "cooldown", "cool-down",
             "release", "breakdown":           return 4
        case "closer", "outro", "feature":     return 5
        default:                               return 6
        }
    }
}
