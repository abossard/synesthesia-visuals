// MoodboardCanvasView - Interactive canvas for song node graph
// Performance: live pan/zoom via @State, edges follow dragged nodes,
// snap-to-grid, no implicit animations on positioned views, drawingGroup for edges.

import AppKit
import SwiftUI
import SwiftVJCore
import SongRepository
import UniformTypeIdentifiers

struct MoodboardCanvasView: View {
    @EnvironmentObject var appState: AppState

    // MARK: - Local gesture state (kept in @State for 60fps feedback)

    @State private var draggedNodeId: String?
    @State private var dragOffset: CGSize = .zero
    // Live pan: offset applied during gesture, committed to store on end
    @State private var livePanOffset: CGSize = .zero
    @State private var panAnchor: CGPoint = .zero
    // Live zoom: multiplier applied during gesture
    @State private var liveZoomScale: CGFloat = 1.0
    @State private var zoomAnchor: Double = 1.0
    // Edge drawing
    @State private var drawingEndScreen: CGPoint?
    @State private var edgeDropTargetId: String?
    @State private var canvasFrame: CGRect = .zero

    private var moodboard: MoodboardSubState { appState.moodboardState }
    private var storeViewport: ViewportState { moodboard.viewport }

    /// Effective viewport combining store state with live gesture deltas
    private var viewport: ViewportState {
        ViewportState(
            offset: CGPoint(
                x: storeViewport.offset.x + livePanOffset.width / effectiveZoom,
                y: storeViewport.offset.y + livePanOffset.height / effectiveZoom
            ),
            zoom: effectiveZoom
        )
    }

    private var effectiveZoom: Double {
        max(0.2, min(5.0, storeViewport.zoom * liveZoomScale))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Grid background + tap to deselect
                gridBackground(in: geometry)

                // Edges layer (rasterized for performance)
                edgesLayer(in: geometry)
                    .drawingGroup()

                // Drawing edge preview
                drawingEdgeLayer

                // Nodes layer
                nodesLayer(in: geometry)
            }
            .clipped()
            .gesture(panGesture)
            .gesture(zoomGesture)
            .onDrop(of: [UTType.plainText], delegate: CanvasDropDelegate(
                appState: appState,
                viewport: viewport,
                canvasToWorld: { screenToCanvas($0) }
            ))
            .background(
                GeometryReader { geo in
                    Color.clear.onAppear {
                        canvasFrame = geo.frame(in: .global)
                    }
                    .onChange(of: geo.size) {
                        canvasFrame = geo.frame(in: .global)
                    }
                }
            )
        }
        .accessibilityIdentifier(A11yID.moodboardCanvas)
    }

    // MARK: - Grid Background

    @ViewBuilder
    private func gridBackground(in geometry: GeometryProxy) -> some View {
        Canvas { context, size in
            // Dark background
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.85)))

            // Draw grid dots
            let gridSize = moodboardGridSize * viewport.zoom
            guard gridSize > 4 else { return } // Don't draw grid when too zoomed out

            let offsetX = viewport.offset.x * viewport.zoom
            let offsetY = viewport.offset.y * viewport.zoom
            let startX = offsetX.truncatingRemainder(dividingBy: gridSize)
            let startY = offsetY.truncatingRemainder(dividingBy: gridSize)
            let dotSize: CGFloat = max(1, viewport.zoom * 1.5)

            var x = startX
            while x < size.width {
                var y = startY
                while y < size.height {
                    let rect = CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.06)))
                    y += gridSize
                }
                x += gridSize
            }
        }
        .onTapGesture {
            if moodboard.isDrawingEdge {
                appState.send(.moodboard(.cancelDrawingEdge))
                drawingEndScreen = nil
                edgeDropTargetId = nil
            } else {
                appState.send(.moodboard(.selectNodes([])))
                appState.send(.moodboard(.selectEdges([])))
            }
        }
    }

    // MARK: - Edges

    @ViewBuilder
    private func edgesLayer(in geometry: GeometryProxy) -> some View {
        // Build position map including dragged-node offset
        let nodePositions = effectivePositionMap()
        let visRect = visibleRect(in: geometry.size)
        // Detect bidirectional pairs for offset
        let biPairs = bidirectionalPairs(edges: moodboard.edges)
        ForEach(moodboard.edges) { edge in
            if let from = nodePositions[edge.sourceId],
               let to = nodePositions[edge.targetId],
               visRect.contains(from) || visRect.contains(to) {
                let fromScreen = canvasToScreen(from)
                let toScreen = canvasToScreen(to)
                let isSelected = moodboard.selectedEdgeIds.contains(edge.id)
                // Offset if bidirectional pair exists
                let pairKey = "\(min(edge.sourceId, edge.targetId))::\(max(edge.sourceId, edge.targetId))"
                let isBiPair = biPairs.contains(pairKey)
                let offset: CGFloat = isBiPair ? (edge.sourceId < edge.targetId ? 6 : -6) : 0

                ZStack {
                    // Invisible wide stroke for hit-testing
                    EdgeShape(from: fromScreen, to: toScreen, offset: offset)
                        .stroke(Color.clear, lineWidth: 12)
                        .contentShape(
                            EdgeShape(from: fromScreen, to: toScreen, offset: offset)
                                .stroke(style: StrokeStyle(lineWidth: 12))
                        )

                    // Visible stroke
                    EdgeShape(from: fromScreen, to: toScreen, offset: offset)
                        .stroke(
                            edgeColor(for: edge),
                            style: StrokeStyle(lineWidth: isSelected ? 3 : max(1, edge.weight * 2), lineCap: .round)
                        )
                        .opacity(isSelected ? 1.0 : 0.4)

                    // Arrow head for directed edges
                    if edge.isDirected {
                        ArrowHead(from: fromScreen, to: toScreen, offset: offset)
                            .fill(edgeColor(for: edge))
                            .opacity(isSelected ? 1.0 : 0.5)
                    }

                    // Selection glow
                    if isSelected {
                        EdgeShape(from: fromScreen, to: toScreen, offset: offset)
                            .stroke(edgeColor(for: edge).opacity(0.3), lineWidth: 6)
                    }
                }
                .onTapGesture {
                    if NSEvent.modifierFlags.contains(.command) {
                        var ids = moodboard.selectedEdgeIds
                        if ids.contains(edge.id) { ids.remove(edge.id) } else { ids.insert(edge.id) }
                        appState.send(.moodboard(.selectEdges(ids)))
                    } else {
                        appState.send(.moodboard(.selectNodes([])))
                        appState.send(.moodboard(.selectEdges([edge.id])))
                    }
                }
            }
        }
    }

    /// Detect pairs of edges A→B and B→A (bidirectional) to offset them visually
    private func bidirectionalPairs(edges: [MoodboardEdge]) -> Set<String> {
        var directed = Set<String>() // "source::target"
        var biPairs = Set<String>()  // "min::max" canonical key
        for edge in edges where edge.isDirected {
            let fwd = "\(edge.sourceId)::\(edge.targetId)"
            let rev = "\(edge.targetId)::\(edge.sourceId)"
            if directed.contains(rev) {
                let key = "\(min(edge.sourceId, edge.targetId))::\(max(edge.sourceId, edge.targetId))"
                biPairs.insert(key)
            }
            directed.insert(fwd)
        }
        return biPairs
    }

    // MARK: - Nodes

    @ViewBuilder
    private func nodesLayer(in geometry: GeometryProxy) -> some View {
        let visibleRect = visibleRect(in: geometry.size)
        let previewingSongId = appState.previewState.currentSongId
        let previewPlaying = appState.previewState.isPlaying
        ForEach(filteredNodes) { node in
            let pos = effectivePosition(for: node)
            if visibleRect.contains(pos) {
                let screenPos = canvasToScreen(pos)
                let isSelected = moodboard.selectedNodeIds.contains(node.id)
                let isDropTarget = edgeDropTargetId == node.id

                nodeView(for: node, isSelected: isSelected, previewingSongId: previewingSongId, previewPlaying: previewPlaying)
                    .shadow(color: isDropTarget ? Color.accentColor : .clear, radius: isDropTarget ? 12 : 0)
                    .scaleEffect(isDropTarget ? 1.08 : 1.0)
                    .overlay(
                        NodeHandleView(
                            nodeId: node.id,
                            nodeSize: node.kind == .tag ? 100 : 120,
                            onStartDrag: { sourceId in
                                appState.send(.moodboard(.startDrawingEdge(sourceId: sourceId)))
                            },
                            onDragMoved: { globalPoint in
                                let localPoint = CGPoint(
                                    x: globalPoint.x - canvasFrame.minX,
                                    y: globalPoint.y - canvasFrame.minY
                                )
                                drawingEndScreen = localPoint
                                edgeDropTargetId = hitTestNode(at: localPoint, excluding: node.id)
                            },
                            onEndDrag: { globalPoint in
                                let localPoint = CGPoint(
                                    x: globalPoint.x - canvasFrame.minX,
                                    y: globalPoint.y - canvasFrame.minY
                                )
                                if let targetId = hitTestNode(at: localPoint, excluding: node.id) {
                                    appState.send(.moodboard(.finishDrawingEdge(targetId: targetId)))
                                } else {
                                    appState.send(.moodboard(.cancelDrawingEdge))
                                }
                                drawingEndScreen = nil
                                edgeDropTargetId = nil
                            }
                        )
                        .opacity(isSelected || moodboard.isDrawingEdge ? 1.0 : 0.0)
                    )
                    .position(screenPos)
                    .gesture(nodeDragGesture(for: node))
                    .onTapGesture {
                        if NSEvent.modifierFlags.contains(.command) {
                            var ids = moodboard.selectedNodeIds
                            if ids.contains(node.id) { ids.remove(node.id) } else { ids.insert(node.id) }
                            appState.send(.moodboard(.selectNodes(ids)))
                        } else {
                            appState.send(.moodboard(.selectEdges([])))
                            appState.send(.moodboard(.selectNodes([node.id])))
                        }
                    }
                    .onHover { hovering in
                        if node.kind == .song {
                            handleShiftHover(hovering: hovering, song: lookupSong(for: node))
                        }
                    }
            }
        }
    }

    private func hitTestNode(at localPoint: CGPoint, excluding excludeId: String) -> String? {
        let canvasPoint = screenToCanvas(localPoint)
        let hitRadius: CGFloat = 60 / viewport.zoom
        for node in moodboard.nodes where node.id != excludeId {
            let dx = canvasPoint.x - node.position.x
            let dy = canvasPoint.y - node.position.y
            if dx * dx + dy * dy <= hitRadius * hitRadius {
                return node.id
            }
        }
        return nil
    }

    @ViewBuilder
    private func nodeView(for node: MoodboardNode, isSelected: Bool, previewingSongId: SongID?, previewPlaying: Bool) -> some View {
        switch node.kind {
        case .song:
            let song = lookupSong(for: node)
            let isPreviewingThis = song.map { previewingSongId == $0.id } ?? false
            SongNodeView(
                node: node, song: song, isSelected: isSelected,
                isPreviewingThis: isPreviewingThis, isPreviewPlaying: previewPlaying,
                onPlay: { if let songId = song?.id { appState.send(.preview(.play(songId))) } },
                onPause: { appState.send(.preview(.pause)) }
            )
        case .tag, .container:
            let connectedCount = moodboard.edges.filter { $0.sourceId == node.id || $0.targetId == node.id }.count
            TagNodeView(node: node, isSelected: isSelected, connectedCount: connectedCount)
        }
    }

    // MARK: - Drawing Edge Preview

    @ViewBuilder
    private var drawingEdgeLayer: some View {
        if moodboard.isDrawingEdge,
           let sourceId = moodboard.drawingEdgeSourceId,
           let sourceNode = moodboard.nodes.first(where: { $0.id == sourceId }),
           let endPoint = drawingEndScreen {
            let fromScreen = canvasToScreen(sourceNode.position)
            EdgeShape(from: fromScreen, to: endPoint)
                .stroke(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        }
    }

    // MARK: - Gestures (live feedback via @State)

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                livePanOffset = value.translation
            }
            .onEnded { value in
                let newOffset = CGPoint(
                    x: storeViewport.offset.x + value.translation.width / effectiveZoom,
                    y: storeViewport.offset.y + value.translation.height / effectiveZoom
                )
                livePanOffset = .zero
                appState.send(.moodboard(.viewportChanged(
                    ViewportState(offset: newOffset, zoom: storeViewport.zoom)
                )))
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                liveZoomScale = value.magnification
            }
            .onEnded { value in
                let newZoom = max(0.2, min(5.0, storeViewport.zoom * value.magnification))
                liveZoomScale = 1.0
                appState.send(.moodboard(.viewportChanged(
                    ViewportState(offset: storeViewport.offset, zoom: newZoom)
                )))
            }
    }

    private func nodeDragGesture(for node: MoodboardNode) -> some Gesture {
        DragGesture()
            .onChanged { value in
                draggedNodeId = node.id
                dragOffset = value.translation
            }
            .onEnded { value in
                let newPosition = CGPoint(
                    x: node.position.x + value.translation.width / viewport.zoom,
                    y: node.position.y + value.translation.height / viewport.zoom
                )
                appState.send(.moodboard(.moveNode(node.id, to: newPosition)))
                draggedNodeId = nil
                dragOffset = .zero
            }
    }

    // MARK: - Coordinate Transforms

    private func canvasToScreen(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x + viewport.offset.x) * viewport.zoom,
            y: (point.y + viewport.offset.y) * viewport.zoom
        )
    }

    private func screenToCanvas(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x / viewport.zoom - viewport.offset.x,
            y: point.y / viewport.zoom - viewport.offset.y
        )
    }

    private func effectivePosition(for node: MoodboardNode) -> CGPoint {
        if draggedNodeId == node.id {
            return CGPoint(
                x: node.position.x + dragOffset.width / viewport.zoom,
                y: node.position.y + dragOffset.height / viewport.zoom
            )
        }
        return node.position
    }

    /// Build a position map that includes the dragged node's live offset.
    /// Used by edgesLayer so edges follow the node during drag.
    private func effectivePositionMap() -> [String: CGPoint] {
        var map = [String: CGPoint]()
        map.reserveCapacity(moodboard.nodes.count)
        for node in moodboard.nodes {
            map[node.id] = effectivePosition(for: node)
        }
        return map
    }

    private func visibleRect(in size: CGSize) -> CGRect {
        let margin: CGFloat = 120
        let origin = CGPoint(
            x: -viewport.offset.x - margin / viewport.zoom,
            y: -viewport.offset.y - margin / viewport.zoom
        )
        let visibleSize = CGSize(
            width: (size.width + margin * 2) / viewport.zoom,
            height: (size.height + margin * 2) / viewport.zoom
        )
        return CGRect(origin: origin, size: visibleSize)
    }

    // MARK: - Helpers

    private func handleShiftHover(hovering: Bool, song: Song?) {
        guard let song, song.audioFilePath != nil else { return }
        if hovering && NSEvent.modifierFlags.contains(.shift) {
            appState.send(.preview(.play(song.id)))
        } else if !hovering && appState.previewState.currentSongId == song.id {
            if NSEvent.modifierFlags.contains(.shift) {
                appState.send(.preview(.stop))
            }
        }
    }

    private var songLookup: [SongID: Song] {
        Dictionary(uniqueKeysWithValues: appState.songsState.displayedSongs.map { ($0.id, $0) })
    }

    private var filteredNodes: [MoodboardNode] {
        guard let filter = moodboard.activePhaseFilter else { return moodboard.nodes }
        let lookup = songLookup
        return moodboard.nodes.filter { node in
            guard let songId = node.songId else { return true }
            return lookup[songId]?.phase?.rawValue == filter
        }
    }

    private func lookupSong(for node: MoodboardNode) -> Song? {
        guard let songId = node.songId else { return nil }
        return songLookup[songId]
    }

    private func edgeColor(for edge: MoodboardEdge) -> Color {
        switch edge.edgeType {
        case .similarity: return .blue
        case .transition: return .green
        case .remix: return .orange
        case .custom: return .purple
        case .tagMembership: return .gray
        }
    }
}

// MARK: - Edge Shape

private struct EdgeShape: Shape {
    let from: CGPoint
    let to: CGPoint
    /// Perpendicular offset for bidirectional edge pairs
    let offset: CGFloat

    init(from: CGPoint, to: CGPoint, offset: CGFloat = 0) {
        self.from = from
        self.to = to
        self.offset = offset
    }

    func path(in rect: CGRect) -> Path {
        let (f, t) = offsetPoints()
        var path = Path()
        path.move(to: f)
        let controlOffset = abs(t.x - f.x) * 0.4
        path.addCurve(
            to: t,
            control1: CGPoint(x: f.x + controlOffset, y: f.y),
            control2: CGPoint(x: t.x - controlOffset, y: t.y)
        )
        return path
    }

    private func offsetPoints() -> (CGPoint, CGPoint) {
        guard offset != 0 else { return (from, to) }
        let dx = to.x - from.x, dy = to.y - from.y
        let len = max(1, sqrt(dx * dx + dy * dy))
        let nx = -dy / len * offset, ny = dx / len * offset
        return (
            CGPoint(x: from.x + nx, y: from.y + ny),
            CGPoint(x: to.x + nx, y: to.y + ny)
        )
    }
}

/// Arrow head shape drawn at the target end of a directed edge
private struct ArrowHead: Shape {
    let from: CGPoint
    let to: CGPoint
    let offset: CGFloat
    let size: CGFloat

    init(from: CGPoint, to: CGPoint, offset: CGFloat = 0, size: CGFloat = 8) {
        self.from = from
        self.to = to
        self.offset = offset
        self.size = size
    }

    func path(in rect: CGRect) -> Path {
        let (f, t) = offsetPoints()
        // Direction vector near the endpoint
        let dx = t.x - f.x, dy = t.y - f.y
        let len = max(1, sqrt(dx * dx + dy * dy))
        let ux = dx / len, uy = dy / len
        // Perpendicular
        let px = -uy * size * 0.5, py = ux * size * 0.5
        // Arrow tip at t, two base points behind
        let base = CGPoint(x: t.x - ux * size, y: t.y - uy * size)

        var path = Path()
        path.move(to: t)
        path.addLine(to: CGPoint(x: base.x + px, y: base.y + py))
        path.addLine(to: CGPoint(x: base.x - px, y: base.y - py))
        path.closeSubpath()
        return path
    }

    private func offsetPoints() -> (CGPoint, CGPoint) {
        guard offset != 0 else { return (from, to) }
        let dx = to.x - from.x, dy = to.y - from.y
        let len = max(1, sqrt(dx * dx + dy * dy))
        let nx = -dy / len * offset, ny = dx / len * offset
        return (
            CGPoint(x: from.x + nx, y: from.y + ny),
            CGPoint(x: to.x + nx, y: to.y + ny)
        )
    }
}

// MARK: - Canvas Drop Delegate

private struct CanvasDropDelegate: DropDelegate {
    let appState: AppState
    let viewport: ViewportState
    let canvasToWorld: (CGPoint) -> CGPoint

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [UTType.plainText]).first else { return false }
        let worldPoint = canvasToWorld(info.location)
        provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { data, _ in
            guard let data = data as? Data,
                  let rawId = String(data: data, encoding: .utf8),
                  rawId.hasPrefix("moodboard-song:") else { return }
            let songRawId = String(rawId.dropFirst("moodboard-song:".count))
            let songId = SongID(rawValue: songRawId)
            Task { @MainActor in
                appState.send(.moodboard(.addSongNode(songId, position: worldPoint)))
            }
        }
        return true
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.plainText])
    }
}
