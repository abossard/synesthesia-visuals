import SwiftUI
import CoreGraphics

struct MiniPreviewView: View {
    @Binding var calibration: CalibrationModel
    let frame: CGImage?
    let detection: DetectionResult?
    let selectedROI: ROIKey
    let isCalibrating: Bool

    private var aspectRatio: CGFloat {
        guard let frame else { return 16.0 / 9.0 }
        return CGFloat(frame.width) / CGFloat(frame.height)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(isCalibrating ? "Calibration Preview" : "Mini Preview")
                    .font(.headline)
                Spacer()
                if detection != nil {
                    Text("Live OCR")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    previewLayer(size: geo.size)

                    detectionOverlay
                        .padding(12)

                    CalibrationCanvas(
                        calibration: $calibration,
                        selectedROI: selectedROI,
                        isEditable: isCalibrating
                    )
                    .allowsHitTesting(isCalibrating)
                }
            }
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(maxWidth: isCalibrating ? .infinity : 640)
            .animation(.spring(response: 0.25, dampingFraction: 0.9), value: isCalibrating)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isCalibrating ? Color.orange : Color.gray.opacity(0.4), lineWidth: isCalibrating ? 3 : 1)
            )
        }
    }

    @ViewBuilder
    private func previewLayer(size: CGSize) -> some View {
        if let frame {
            Image(decorative: frame, scale: 1, orientation: .up)
                .resizable()
                .scaledToFit()
                .frame(width: size.width, height: size.height)
                .clipped()
        } else {
            ZStack {
                Color.secondary.opacity(0.1)
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.dashed")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Start capture to see the VirtualDJ window preview")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
            }
        }
    }

    private var detectionOverlay: some View {
        Group {
            if let detection {
                VStack(alignment: .leading, spacing: 4) {
                    if let master = detection.masterDeck {
                        Text("Master Deck: \(master)")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                    if let artist = detection.deck1.artist, let title = detection.deck1.title {
                        Text("D1: \(artist) – \(title)")
                            .font(.caption2)
                            .foregroundColor(.cyan)
                    }
                    if let artist = detection.deck2.artist, let title = detection.deck2.title {
                        Text("D2: \(artist) – \(title)")
                            .font(.caption2)
                            .foregroundColor(Color(red: 1, green: 0.2, blue: 1))
                    }
                }
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}
