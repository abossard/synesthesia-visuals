import Foundation
import CoreGraphics

/// OCR result with text and bounding box in full-frame normalized coords (top-left origin, 0-1)
struct OCRDetection: Codable {
    let text: String
    let frameRect: CGRect  // normalized 0-1, top-left origin, in full frame coords
}

struct DeckDetection: Codable {
    var artist: String?
    var title: String?
    var elapsedSeconds: Double?
    var faderKnobPos: Double?   // 0..1 within ROI (top=0)
    var faderConfidence: Double?
    
    // Bounding boxes for detected text (in full-frame normalized coords)
    var artistDetections: [OCRDetection] = []
    var titleDetections: [OCRDetection] = []
    var elapsedDetections: [OCRDetection] = []
    
    // Fader ROI for debug visualization (in full-frame normalized coords)
    var faderROI: CGRect?
}

struct DetectionResult: Codable {
    var deck1: DeckDetection
    var deck2: DeckDetection
    var masterDeck: Int? // 1 or 2
    
    /// All detected text regions for overlay display
    var allDetections: [OCRDetection] {
        deck1.artistDetections + deck1.titleDetections + deck1.elapsedDetections +
        deck2.artistDetections + deck2.titleDetections + deck2.elapsedDetections
    }
}

enum Detector {

    static func detect(frame: CGImage, calibration: CalibrationModel) async -> DetectionResult {
        let d1 = await detectDeck(frame: frame, calibration: calibration,
                                 artistKey: .d1Artist, titleKey: .d1Title, elapsedKey: .d1Elapsed, faderKey: .d1Fader)
        let d2 = await detectDeck(frame: frame, calibration: calibration,
                                 artistKey: .d2Artist, titleKey: .d2Title, elapsedKey: .d2Elapsed, faderKey: .d2Fader)

        let master = chooseMaster(deck1: d1, deck2: d2)
        return DetectionResult(deck1: d1, deck2: d2, masterDeck: master)
    }

    private static func detectDeck(frame: CGImage,
                                   calibration: CalibrationModel,
                                   artistKey: ROIKey, titleKey: ROIKey, elapsedKey: ROIKey, faderKey: ROIKey) async -> DeckDetection {
        var out = DeckDetection()

        if let r = calibration.get(artistKey), let croppedImg = crop(frame, normTopLeftRect: r) {
            let results = await VisionOCR.recognizeTextWithBoxes(in: croppedImg, fast: true, languageCorrection: false)
            out.artist = bestLine(results.map { $0.0 })
            // Convert crop-local Vision boxes to full-frame coords
            let expandedR = expandedROI(r)
            out.artistDetections = results.map { text, visionBox in
                OCRDetection(text: text, frameRect: visionBoxToFrameRect(visionBox, inROI: expandedR))
            }
        }
        if let r = calibration.get(titleKey), let croppedImg = crop(frame, normTopLeftRect: r) {
            let results = await VisionOCR.recognizeTextWithBoxes(in: croppedImg, fast: true, languageCorrection: false)
            out.title = bestLine(results.map { $0.0 })
            let expandedR = expandedROI(r)
            out.titleDetections = results.map { text, visionBox in
                OCRDetection(text: text, frameRect: visionBoxToFrameRect(visionBox, inROI: expandedR))
            }
        }
        if let r = calibration.get(elapsedKey), let croppedImg = crop(frame, normTopLeftRect: r) {
            let results = await VisionOCR.recognizeTextWithBoxes(in: croppedImg, fast: true, languageCorrection: false)
            out.elapsedSeconds = parseElapsedSeconds(results.map { $0.0 })
            let expandedR = expandedROI(r)
            out.elapsedDetections = results.map { text, visionBox in
                OCRDetection(text: text, frameRect: visionBoxToFrameRect(visionBox, inROI: expandedR))
            }
        }
        if let r = calibration.get(faderKey), let croppedImg = crop(frame, normTopLeftRect: r) {
            let (pos, conf) = detectFaderKnob(in: croppedImg,
                                              grayLo: calibration.grayLo,
                                              grayHi: calibration.grayHi,
                                              eqTol: calibration.eqTol,
                                              minHits: calibration.minHits)
            out.faderKnobPos = pos
            out.faderConfidence = conf
            out.faderROI = expandedROI(r)  // Store for debug visualization
        }

        return out
    }
    
    /// Convert Vision bounding box (bottom-left origin, 0-1 within crop) to full-frame coords (top-left origin, 0-1)
    private static func visionBoxToFrameRect(_ visionBox: CGRect, inROI roi: CGRect) -> CGRect {
        // Vision uses bottom-left origin; flip Y
        let flippedY = 1 - visionBox.origin.y - visionBox.height
        
        // Scale from crop-local (0-1) to ROI size, then offset by ROI position
        let frameX = roi.origin.x + visionBox.origin.x * roi.width
        let frameY = roi.origin.y + flippedY * roi.height
        let frameW = visionBox.width * roi.width
        let frameH = visionBox.height * roi.height
        
        return CGRect(x: frameX, y: frameY, width: frameW, height: frameH)
    }

    // Master: lower knob Y (closer to top) = louder (your rule), with confidence gate
    private static func chooseMaster(deck1: DeckDetection, deck2: DeckDetection) -> Int? {
        let c1 = deck1.faderConfidence ?? 0
        let c2 = deck2.faderConfidence ?? 0
        if c1 >= 0.05, c2 >= 0.05,
           let y1 = deck1.faderKnobPos, let y2 = deck2.faderKnobPos {
            if abs(y1 - y2) < 0.02 { return nil }
            return (y1 < y2) ? 1 : 2
        }
        return nil
    }

    private static func bestLine(_ lines: [String]) -> String? {
        // Allow single-char results; text may start anywhere in the ROI box
        let cleaned = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return cleaned.max(by: { $0.count < $1.count })
    }

    private static func parseElapsedSeconds(_ lines: [String]) -> Double? {
        let joined = lines.joined(separator: " ")
            .replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "o", with: "0")
        // Accept: M:SS, MM:SS, M:SS.d
        let patterns = [
            #"(\d+):(\d{2})(?:\.(\d))?"#
        ]
        for p in patterns {
            if let m = joined.range(of: p, options: .regularExpression) {
                let s = String(joined[m])
                return timeStringToSeconds(s)
            }
        }
        return nil
    }

    private static func timeStringToSeconds(_ s: String) -> Double? {
        // "3:56.2"
        let parts = s.split(separator: ":")
        guard parts.count == 2 else { return nil }
        guard let mins = Double(parts[0]) else { return nil }
        let secPart = parts[1]
        let secs = Double(secPart) ?? Double(secPart.split(separator: ".").first ?? "") ?? 0
        return mins * 60 + secs
    }

    // Crop helper: norm rect (top-left origin, 0-1) -> CGImage crop
    // Note: ScreenCaptureKit CGImages use top-left origin, same as our calibration coords
    // Adds 5% padding on each side to capture text that may not start at the box edge
    static func crop(_ img: CGImage, normTopLeftRect r: CGRect) -> CGImage? {
        let W = CGFloat(img.width)
        let H = CGFloat(img.height)
        
        let expanded = expandedROI(r)

        let x = expanded.origin.x * W
        let y = expanded.origin.y * H  // No Y-flip needed: SCK images are top-left origin
        let w = expanded.size.width * W
        let h = expanded.size.height * H

        let rect = CGRect(x: x.rounded(.down), y: y.rounded(.down),
                          width: w.rounded(.down), height: h.rounded(.down))
        return img.cropping(to: rect)
    }
    
    /// Returns the expanded ROI rect (with 5% padding) for coordinate mapping
    static func expandedROI(_ r: CGRect) -> CGRect {
        let padX = r.size.width * 0.05
        let padY = r.size.height * 0.05
        let expandedX = max(0, r.origin.x - padX)
        let expandedY = max(0, r.origin.y - padY)
        let expandedW = min(r.size.width + padX * 2, 1 - expandedX)
        let expandedH = min(r.size.height + padY * 2, 1 - expandedY)
        return CGRect(x: expandedX, y: expandedY, width: expandedW, height: expandedH)
    }

    // Fader knob detection (simple & fast on small ROI):
    // finds row with most "gray" pixels; returns knob Y normalized within ROI (top=0)
    static func detectFaderKnob(in img: CGImage,
                               grayLo: Int, grayHi: Int,
                               eqTol: Int, minHits: Int) -> (Double?, Double) {
        guard let data = img.dataProvider?.data as Data? else { return (nil, 0) }

        let w = img.width
        let h = img.height
        let bpr = img.bytesPerRow
        let bpp = img.bitsPerPixel / 8 // usually 4 (BGRA)

        var bestY: Int = -1
        var bestScore: Int = 0

        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }

            // sample every column (ROI is narrow); could also stride x by 1..2
            for y in 0..<h {
                var score = 0
                for x in 0..<w {
                    let offset = y * bpr + x * bpp
                    if offset + 3 < data.count {
                        let b = Int(base[offset])
                        let g = Int(base[offset + 1])
                        let r = Int(base[offset + 2])
                        
                        // Check if pixel is gray (R≈G≈B) within specified range
                        if grayLo <= r && r <= grayHi &&
                           grayLo <= g && g <= grayHi &&
                           grayLo <= b && b <= grayHi &&
                           abs(r - g) <= eqTol &&
                           abs(g - b) <= eqTol &&
                           abs(r - b) <= eqTol {
                            score += 1
                        }
                    }
                }
                if score > bestScore {
                    bestScore = score
                    bestY = y
                }
            }
        }

        if bestY >= 0 && bestScore >= minHits {
            let normY = Double(bestY) / Double(h)
            let conf = Double(bestScore) / Double(w)  // confidence: ratio of gray pixels
            return (normY, conf)
        }
        return (nil, 0)
    }
}
