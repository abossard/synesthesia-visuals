// MoodboardCanvasView - Interactive canvas for song node graph

import AppKit
import SwiftUI
import SwiftVJCore
import SongRepository

struct MoodboardCanvasView: View {
    @EnvironmentObject var appState: AppState

    @State private var draggedNodeId: String?
    @State private var dragOffset: CGSize = .zero
    // Gesture anchors — capture initial state to avoid compounding
    @State private var panAnchor: CGPoint = .zero
    @State private var zoomAnchor: Double = 1.0

    private var moodboard: MoodboardSubState { appState.moodboardState }
    private var viewport: ViewportState { moodboard.viewport }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background — tap to deselect
                Color.black.opacity(0.85)
                    .onTapGesture {
                        appState.send(.moodboard(.selectNodes([])))
                    }

                // Edges layer
                edgesLayer(in: geometry)

                // Nodes layer
                nodesLayer(in: geometry)
            }
            .clipped()
            .gesture(panGesture)
            .gesture(zoomGesture)
        }
        .accessibilityIdentifier(A11yID.moodboardCanvas)
    }

    // MARK: - Edges

    @ViewBuilder
    private func edgesLayer(in geometry: GeometryProxy) -> some View {
        let nodePositions = Dictionary(
            uniqueKeysWithValues: moodboard.nodes.map { ($0.id, $0.position) }
        )
        let visRect = visibleRect(in: geometry.size)
        ForEach(moodboard.edges) { edge in
            if let from = nodePositions[edge.sourceId],
               let to = nodePositions[edge.targetId],
               visRect.contains(from) || visRect.contains(to) {
                EdgeShape(
                    from: canvasToScreen(from),
                    to: canvasToScreen(to)
                )
                .stroke(
                    edgeColor(for: edge),
                    style: StrokeStyle(lineWidth: max(1, edge.weight * 2), lineCap: .round)
                )
                .opacity(moodboard.selectedEdgeIds.contains(edge.id) ? 1.0 : 0.4)
            }
        }
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
                let song = lookupSong(for: node)
                let isPreviewingThis = song.map { previewingSongId == $0.id } ?? false

                SongNodeView(
                    node: node,
                    song: song,
                    isSelected: isSelected,
                    isPreviewingThis: isPreviewingThis,
                    isPreviewPlaying: previewPlaying,
                    onPlay: {
                        if let songId = song?.id {
                            appState.send(.preview(.play(songId)))
                        }
                    },
                    onPause: {
                        appState.send(.preview(.pause))
                    }
                )
                    .position(screenPos)
                    .gesture(nodeDragGesture(for: node))
                    .onTapGesture {
                        appState.send(.moodboard(.selectNodes([node.id])))
                    }
                    .onHover { hovering in
                        handleShiftHover(hovering: hovering, song: song)
                    }
            }
        }
    }

    // MARK: - Gestures

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if value.translation == .zero { return }
                // On first drag frame, capture the initial offset
                if panAnchor == .zero && value.translation.width.magnitude < 2 && value.translation.height.magnitude < 2 {
                    panAnchor = viewport.offset
                }
                if panAnchor == .zero { panAnchor = viewport.offset }
            }
            .onEnded { value in
                let newOffset = CGPoint(
                    x: panAnchor.x + value.translation.width / viewport.zoom,
                    y: panAnchor.y + value.translation.height / viewport.zoom
                )
                appState.send(.moodboard(.viewportChanged(
                    ViewportState(offset: newOffset, zoom: viewport.zoom)
                )))
                panAnchor = .zero
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if zoomAnchor == 1.0 {
                    zoomAnchor = viewport.zoom
                }
            }
            .onEnded { value in
                let newZoom = max(0.2, min(5.0, zoomAnchor * value.magnification))
                appState.send(.moodboard(.viewportChanged(
                    ViewportState(offset: viewport.offset, zoom: newZoom)
                )))
                zoomAnchor = 1.0
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

    private func effectivePosition(for node: MoodboardNode) -> CGPoint {
        if draggedNodeId == node.id {
            return CGPoint(
                x: node.position.x + dragOffset.width / viewport.zoom,
                y: node.position.y + dragOffset.height / viewport.zoom
            )
        }
        return node.position
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

    /// Handle shift+hover preview: start playing when hovering with shift held
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

    /// O(1) song lookup dictionary (built once per render)
    private var songLookup: [SongID: Song] {
        Dictionary(uniqueKeysWithValues: appState.songsState.displayedSongs.map { ($0.id, $0) })
    }

    private var filteredNodes: [MoodboardNode] {
        guard let filter = moodboard.activePhaseFilter else {
            return moodboard.nodes
        }
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

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        let controlOffset = abs(to.x - from.x) * 0.4
        path.addCurve(
            to: to,
            control1: CGPoint(x: from.x + controlOffset, y: from.y),
            control2: CGPoint(x: to.x - controlOffset, y: to.y)
        )
        return path
    }
}
