import SwiftUI

enum DragHandle: Equatable {
    case topLeft, topRight, bottomLeft, bottomRight, center
}

struct CalibrationCanvas: View {
    @Binding var calibration: CalibrationModel
    let selectedROI: ROIKey
    let isEditable: Bool

    @State private var activeHandle: DragHandle?
    @State private var originalRect: CGRect?
    @State private var dragOffset: CGSize = .zero

    private let handleRadius: CGFloat = 10  // Hit area for handles

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Draw all stored ROIs
                ForEach(ROIKey.allCases) { key in
                    if let rect = calibration.get(key) {
                        ROIBox(
                            rect: rect,
                            containerSize: geo.size,
                            label: key.label,
                            isSelected: key == selectedROI && isEditable,
                            color: key == selectedROI ? .blue : .green
                        )
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(isEditable ? resizeGesture(in: geo.size) : nil)
            .contextMenu {
                if isEditable {
                    Button("Place ROI at Center") {
                        placeROIAtCenter()
                    }
                }
            }
        }
    }

    /// Determine which handle (if any) is at the given point
    private func hitTestHandle(at point: CGPoint, in size: CGSize) -> DragHandle? {
        guard let rect = calibration.get(selectedROI) else { return nil }
        
        let pixelRect = CGRect(
            x: rect.origin.x * size.width,
            y: rect.origin.y * size.height,
            width: rect.size.width * size.width,
            height: rect.size.height * size.height
        )
        
        let handles: [(DragHandle, CGPoint)] = [
            (.topLeft, CGPoint(x: pixelRect.minX, y: pixelRect.minY)),
            (.topRight, CGPoint(x: pixelRect.maxX, y: pixelRect.minY)),
            (.bottomLeft, CGPoint(x: pixelRect.minX, y: pixelRect.maxY)),
            (.bottomRight, CGPoint(x: pixelRect.maxX, y: pixelRect.maxY)),
            (.center, CGPoint(x: pixelRect.midX, y: pixelRect.midY))
        ]
        
        for (handle, handlePoint) in handles {
            let distance = hypot(point.x - handlePoint.x, point.y - handlePoint.y)
            if distance <= handleRadius {
                return handle
            }
        }
        
        return nil
    }

    private func resizeGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                // On first drag event, determine if we're on a handle
                if activeHandle == nil {
                    if let handle = hitTestHandle(at: value.startLocation, in: size) {
                        activeHandle = handle
                        originalRect = calibration.get(selectedROI)
                    }
                }
                
                // Only proceed if we have an active handle
                guard let handle = activeHandle, let original = originalRect else { return }
                
                let deltaX = value.translation.width / size.width
                let deltaY = value.translation.height / size.height
                
                var newRect = original
                
                switch handle {
                case .topLeft:
                    newRect = CGRect(
                        x: original.origin.x + deltaX,
                        y: original.origin.y + deltaY,
                        width: original.width - deltaX,
                        height: original.height - deltaY
                    )
                case .topRight:
                    newRect = CGRect(
                        x: original.origin.x,
                        y: original.origin.y + deltaY,
                        width: original.width + deltaX,
                        height: original.height - deltaY
                    )
                case .bottomLeft:
                    newRect = CGRect(
                        x: original.origin.x + deltaX,
                        y: original.origin.y,
                        width: original.width - deltaX,
                        height: original.height + deltaY
                    )
                case .bottomRight:
                    newRect = CGRect(
                        x: original.origin.x,
                        y: original.origin.y,
                        width: original.width + deltaX,
                        height: original.height + deltaY
                    )
                case .center:
                    newRect = CGRect(
                        x: original.origin.x + deltaX,
                        y: original.origin.y + deltaY,
                        width: original.width,
                        height: original.height
                    )
                }
                
                // Ensure minimum size and valid bounds
                if newRect.width >= 0.01 && newRect.height >= 0.01 {
                    calibration.set(selectedROI, rect: newRect)
                }
            }
            .onEnded { _ in
                activeHandle = nil
                originalRect = nil
            }
    }

    private func placeROIAtCenter() {
        let centerRect = CGRect(x: 0.3, y: 0.4, width: 0.4, height: 0.2)
        calibration.set(selectedROI, rect: centerRect)
    }
}

private struct ROIBox: View {
    let rect: CGRect
    let containerSize: CGSize
    let label: String
    let isSelected: Bool
    var color: Color = .green
    
    @State private var isHovering: Bool = false

    private var pixelRect: CGRect {
        CGRect(
            x: rect.origin.x * containerSize.width,
            y: rect.origin.y * containerSize.height,
            width: max(rect.size.width * containerSize.width, 20),
            height: max(rect.size.height * containerSize.height, 20)
        )
    }
    
    // When not hovering, make box more transparent so user can see underneath
    private var fillOpacity: Double { isHovering || !isSelected ? 0.2 : 0.05 }
    private var strokeOpacity: Double { isHovering || !isSelected ? 1.0 : 0.5 }

    var body: some View {
        let pr = pixelRect

        ZStack {
            // Fill
            Rectangle()
                .fill(color.opacity(fillOpacity))
                .frame(width: pr.width, height: pr.height)
                .position(x: pr.midX, y: pr.midY)

            // Stroke
            Rectangle()
                .stroke(color.opacity(strokeOpacity), lineWidth: isSelected ? 4 : 2)
                .frame(width: pr.width, height: pr.height)
                .position(x: pr.midX, y: pr.midY)

            // Label - positioned ABOVE the box
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(color)
                .cornerRadius(4)
                .position(x: pr.midX, y: max(pr.minY - 14, 10))

            // Corner handles (ALWAYS visible when selected)
            if isSelected {
                // Top-left
                handleCircle.position(x: pr.minX, y: pr.minY)
                // Top-right
                handleCircle.position(x: pr.maxX, y: pr.minY)
                // Bottom-left
                handleCircle.position(x: pr.minX, y: pr.maxY)
                // Bottom-right
                handleCircle.position(x: pr.maxX, y: pr.maxY)
                // Center
                handleCircle.position(x: pr.midX, y: pr.midY)
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var handleCircle: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 12, height: 12)
            Circle()
                .stroke(Color.blue, lineWidth: 2)
                .frame(width: 12, height: 12)
        }
        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
    }
}
