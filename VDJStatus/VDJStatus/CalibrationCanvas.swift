import SwiftUI

struct CalibrationCanvas: View {
    @Binding var calibration: CalibrationModel
    let selectedROI: ROIKey
    let isEditable: Bool

    @State private var dragStart: CGPoint?
    @State private var currentRect: CGRect?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Always show all stored ROIs
                ForEach(ROIKey.allCases) { key in
                    if let rect = calibration.get(key) {
                        ROIOverlay(
                            rect: rect,
                            containerSize: geo.size,
                            label: key.label,
                            isSelected: key == selectedROI,
                            showHandles: isEditable && key == selectedROI
                        )
                    }
                }

                // In-progress rect while dragging
                if let rect = currentRect {
                    ROIOverlay(
                        rect: rect,
                        containerSize: geo.size,
                        label: selectedROI.label,
                        isSelected: true,
                        showHandles: true,
                        color: .orange
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(isEditable ? dragGesture(in: geo.size) : nil)
        }
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStart == nil { dragStart = value.startLocation }
                guard let start = dragStart else { return }
                let end = value.location

                let x = min(start.x, end.x) / size.width
                let y = min(start.y, end.y) / size.height
                let w = abs(end.x - start.x) / size.width
                let h = abs(end.y - start.y) / size.height

                currentRect = CGRect(x: x, y: y, width: w, height: h)
            }
            .onEnded { _ in
                if let rect = currentRect, rect.width > 0.01, rect.height > 0.01 {
                    calibration.set(selectedROI, rect: rect)
                }
                dragStart = nil
                currentRect = nil
            }
    }
}

private struct ROIOverlay: View {
    let rect: CGRect
    let containerSize: CGSize
    let label: String
    let isSelected: Bool
    let showHandles: Bool
    var color: Color = .green

    private var pixelRect: CGRect {
        CGRect(
            x: rect.origin.x * containerSize.width,
            y: rect.origin.y * containerSize.height,
            width: rect.size.width * containerSize.width,
            height: rect.size.height * containerSize.height
        )
    }

    var body: some View {
        let pr = pixelRect
        let displayColor = isSelected ? Color.blue : color

        ZStack {
            // Box fill
            Rectangle()
                .fill(displayColor.opacity(0.15))
                .frame(width: pr.width, height: pr.height)
                .position(x: pr.midX, y: pr.midY)

            // Box stroke
            Rectangle()
                .stroke(displayColor, lineWidth: isSelected ? 3 : 2)
                .frame(width: pr.width, height: pr.height)
                .position(x: pr.midX, y: pr.midY)

            // Label badge
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(displayColor)
                .cornerRadius(4)
                .position(x: pr.minX + 8, y: pr.minY + 10)

            // Corner + center handles (only when selected and editing)
            if showHandles {
                ForEach(HandlePosition.allCases, id: \.self) { pos in
                    handleCircle
                        .position(pos.point(in: pr))
                }
            }
        }
    }

    private var handleCircle: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 16, height: 16)
            .overlay(Circle().stroke(Color.blue, lineWidth: 3))
            .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
    }

    private enum HandlePosition: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight, center

        func point(in rect: CGRect) -> CGPoint {
            switch self {
            case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
            case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
            case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
            case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
            case .center: return CGPoint(x: rect.midX, y: rect.midY)
            }
        }
    }
}
