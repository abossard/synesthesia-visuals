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
                ForEach(ROIKey.allCases) { key in
                    if let rect = calibration.get(key) {
                        ROIRectangle(
                            rect: rect,
                            size: geo.size,
                            label: key.label,
                            isSelected: key == selectedROI,
                            color: key == selectedROI ? .blue : .green,
                            showHandles: isEditable
                        )
                    }
                }

                if let rect = currentRect {
                    ROIRectangle(
                        rect: rect,
                        size: geo.size,
                        label: selectedROI.label,
                        isSelected: true,
                        color: .orange,
                        showHandles: true
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
                if let rect = currentRect { calibration.set(selectedROI, rect: rect) }
                dragStart = nil
                currentRect = nil
            }
    }
}

private struct ROIRectangle: View {
    let rect: CGRect
    let size: CGSize
    let label: String
    let isSelected: Bool
    let color: Color
    let showHandles: Bool

    private enum HandlePosition: CaseIterable, Identifiable {
        case topLeft, topRight, bottomLeft, bottomRight, center
        var id: Self { self }

        func point(in size: CGSize) -> CGPoint {
            switch self {
            case .topLeft: return .init(x: 0, y: 0)
            case .topRight: return .init(x: size.width, y: 0)
            case .bottomLeft: return .init(x: 0, y: size.height)
            case .bottomRight: return .init(x: size.width, y: size.height)
            case .center: return .init(x: size.width / 2, y: size.height / 2)
            }
        }
    }

    var body: some View {
        let x = rect.origin.x * size.width
        let y = rect.origin.y * size.height
        let w = rect.size.width * size.width
        let h = rect.size.height * size.height

        Rectangle()
            .stroke(color.opacity(isSelected ? 1 : 0.7), lineWidth: isSelected ? 3 : 1.5)
            .background(color.opacity(0.08))
            .frame(width: w, height: h)
            .position(x: x + w / 2, y: y + h / 2)
            .overlay(alignment: .topLeading) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.9))
                    .cornerRadius(5)
                    .padding(6)
            }
            .overlay(alignment: .topLeading) {
                if showHandles && isSelected {
                    GeometryReader { geo in
                        ForEach(HandlePosition.allCases) { pos in
                            Circle()
                                .fill(Color.white)
                                .overlay(Circle().stroke(color, lineWidth: 2))
                                .frame(width: 14, height: 14)
                                .position(pos.point(in: geo.size))
                        }
                    }
                }
            }
    }
}
