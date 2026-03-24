// NodeHandleView - Connection handle dots on moodboard nodes for edge drawing

import SwiftUI
import SwiftVJCore

/// Overlay that adds drag handles to a node for drawing edges.
/// Drag from a handle → preview line follows cursor → drop on target node → edge created.
struct NodeHandleView: View {
    let nodeId: String
    let nodeSize: CGFloat
    let onStartDrag: (String) -> Void
    let onDragMoved: (CGPoint) -> Void
    let onEndDrag: (CGPoint) -> Void

    @State private var isDragging = false

    private let handleSize: CGFloat = 12

    var body: some View {
        ZStack {
            handleDot.position(x: nodeSize, y: nodeSize / 2)
            handleDot.position(x: nodeSize / 2, y: nodeSize)
            handleDot.position(x: 0, y: nodeSize / 2)
            handleDot.position(x: nodeSize / 2, y: 0)
        }
        .frame(width: nodeSize, height: nodeSize)
        .allowsHitTesting(true)
    }

    private var handleDot: some View {
        Circle()
            .fill(isDragging ? Color.accentColor : Color.white.opacity(0.7))
            .frame(width: handleSize, height: handleSize)
            .overlay(
                Circle()
                    .stroke(Color.accentColor, lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.3), radius: 2)
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            onStartDrag(nodeId)
                        }
                        onDragMoved(value.location)
                    }
                    .onEnded { value in
                        isDragging = false
                        onEndDrag(value.location)
                    }
            )
    }
}
