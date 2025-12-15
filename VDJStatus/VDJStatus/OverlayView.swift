import SwiftUI
import CoreGraphics

struct OverlayView: View {
    let frame: CGImage?
    let calibration: CalibrationModel
    let detection: DetectionResult?
    
    var body: some View {
        ZStack {
            // Semi-transparent background when calibrating
            Color.black.opacity(0.2)
            
            // Draw calibration boxes if available
            GeometryReader { geo in
                ForEach(ROIKey.allCases) { key in
                    if let rect = calibration.get(key) {
                        let x = rect.origin.x * geo.size.width
                        let y = rect.origin.y * geo.size.height
                        let w = rect.size.width * geo.size.width
                        let h = rect.size.height * geo.size.height
                        
                        Rectangle()
                            .stroke(Color.green, lineWidth: 2)
                            .frame(width: w, height: h)
                            .position(x: x + w/2, y: y + h/2)
                            .overlay(
                                Text(key.label)
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(4)
                                    .background(Color.green)
                                    .cornerRadius(4)
                                    .position(x: x + 5, y: y + 5),
                                alignment: .topLeading
                            )
                    }
                }
                
                // Draw detection results overlay
                if let detection = detection {
                    VStack(alignment: .leading) {
                        if let master = detection.masterDeck {
                            Text("Master: Deck \(master)")
                                .foregroundColor(.yellow)
                                .font(.headline)
                        }
                        
                        if let artist = detection.deck1.artist, let title = detection.deck1.title {
                            Text("D1: \(artist) - \(title)")
                                .foregroundColor(.cyan)
                                .font(.caption)
                        }
                        
                        if let artist = detection.deck2.artist, let title = detection.deck2.title {
                            Text("D2: \(artist) - \(title)")
                                .foregroundColor(Color(red: 1, green: 0, blue: 1))
                                .font(.caption)
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(8)
                    .position(x: geo.size.width / 2, y: 50)
                }
            }
        }
    }
}
