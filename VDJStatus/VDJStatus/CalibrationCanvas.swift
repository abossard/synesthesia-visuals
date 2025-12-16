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
                // ALWAYS show a default ROI box if none exists yet (so user can see something)
                if calibration.get(selectedROI) == nil && isEditable {
                    defaultROIPlaceholder(in: geo.size)
                }

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

                // In-progress drag rect
                if let rect = currentRect {
                    ROIBox(
                        rect: rect,
                        containerSize: geo.size,
                        label: selectedROI.label,
                        isSelected: true,
                        color: .orange
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(isEditable ? dragGesture(in: geo.size) : nil)
            .contextMenu {
                if isEditable {
                    Button("Place ROI at Center") {
                        placeROIAtCenter()
                    }
                    Button("Reset All ROIs") {
                        resetAllROIs()
                    }
                }
            }
            .onTapGesture(count: 2) {
                if isEditable {
                    placeROIAtCenter()
                }
            }
        }
    }

    private func defaultROIPlaceholder(in size: CGSize) -> some View {
        let centerRect = CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.3)
        return ROIBox(
            rect: centerRect,
            containerSize: size,
            label: "\(selectedROI.label) (click to place)",
            isSelected: true,
            color: .orange.opacity(0.5)
        )
        .allowsHitTesting(false)
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 5)
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
                if let rect = currentRect, rect.width > 0.02, rect.height > 0.02 {
                    calibration.set(selectedROI, rect: rect)
                }
                dragStart = nil
                currentRect = nil
            }
    }

    private func placeROIAtCenter() {
        let centerRect = CGRect(x: 0.3, y: 0.4, width: 0.4, height: 0.2)
        calibration.set(selectedROI, rect: centerRect)
    }

    private func resetAllROIs() {
        for key in ROIKey.allCases {
            let yOffset = Double(key.hashValue % 4) * 0.15
            let defaultRect = CGRect(x: 0.1, y: 0.1 + yOffset, width: 0.3, height: 0.1)
            calibration.set(key, rect: defaultRect)
        }
    }
}

private struct ROIBox: View {
    let rect: CGRect
    let containerSize: CGSize
    let label: String
    let isSelected: Bool
    var color: Color = .green

    private var pixelRect: CGRect {
        CGRect(
            x: rect.origin.x * containerSize.width,
            y: rect.origin.y * containerSize.height,
            width: max(rect.size.width * containerSize.width, 20),
            height: max(rect.size.height * containerSize.height, 20)
        )
    }

    var body: some View {
        let pr = pixelRect

        ZStack {
            // Fill
            Rectangle()
                .fill(color.opacity(0.2))
                .frame(width: pr.width, height: pr.height)
                .position(x: pr.midX, y: pr.midY)

            // Stroke
            Rectangle()
                .stroke(color, lineWidth: isSelected ? 4 : 2)
                .frame(width: pr.width, height: pr.height)
                .position(x: pr.midX, y: pr.midY)

            // Label
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(color)
                .cornerRadius(4)
                .position(x: pr.minX + 50, y: pr.minY + 12)

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
    }

    private var handleCircle: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 20, height: 20)
            Circle()
                .stroke(Color.blue, lineWidth: 3)
                .frame(width: 20, height: 20)
        }
        .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 2)
    }
}
