import SwiftUI

struct CalibrationCanvas: View {
    @Binding var calibration: CalibrationModel
    let selectedROI: ROIKey
    let frameSize: CGSize
    
    @State private var dragStart: CGPoint?
    @State private var currentRect: CGRect?
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Draw all calibrated ROIs
                ForEach(ROIKey.allCases) { key in
                    if let rect = calibration.get(key) {
                        ROIRectangle(
                            rect: rect,
                            size: geo.size,
                            label: key.label,
                            isSelected: key == selectedROI,
                            color: key == selectedROI ? .blue : .green
                        )
                    }
                }
                
                // Draw in-progress rect
                if let rect = currentRect {
                    ROIRectangle(
                        rect: rect,
                        size: geo.size,
                        label: selectedROI.label,
                        isSelected: true,
                        color: .yellow
                    )
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStart == nil {
                            dragStart = value.startLocation
                        }
                        
                        let start = dragStart!
                        let end = value.location
                        
                        let x = min(start.x, end.x) / geo.size.width
                        let y = min(start.y, end.y) / geo.size.height
                        let w = abs(end.x - start.x) / geo.size.width
                        let h = abs(end.y - start.y) / geo.size.height
                        
                        currentRect = CGRect(x: x, y: y, width: w, height: h)
                    }
                    .onEnded { _ in
                        if let rect = currentRect {
                            calibration.set(selectedROI, rect: rect)
                        }
                        dragStart = nil
                        currentRect = nil
                    }
            )
        }
    }
}

struct ROIRectangle: View {
    let rect: CGRect
    let size: CGSize
    let label: String
    let isSelected: Bool
    let color: Color
    
    var body: some View {
        let x = rect.origin.x * size.width
        let y = rect.origin.y * size.height
        let w = rect.size.width * size.width
        let h = rect.size.height * size.height
        
        Rectangle()
            .stroke(color, lineWidth: isSelected ? 3 : 2)
            .background(color.opacity(0.1))
            .frame(width: w, height: h)
            .position(x: x + w/2, y: y + h/2)
            .overlay(
                Text(label)
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(4)
                    .background(color)
                    .cornerRadius(4)
                    .position(x: x + 5, y: y + 5),
                alignment: .topLeading
            )
    }
}
