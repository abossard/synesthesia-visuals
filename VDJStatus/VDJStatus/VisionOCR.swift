import Foundation
import Vision

enum VisionOCR {
    /// Recognize text, returning strings only (legacy)
    static func recognizeText(in cgImage: CGImage,
                              fast: Bool = true,
                              languageCorrection: Bool = false) async -> [String] {
        let results = await recognizeTextWithBoxes(in: cgImage, fast: fast, languageCorrection: languageCorrection)
        return results.map { $0.0 }
    }
    
    /// Recognize text with bounding boxes
    /// Returns array of (text, boundingBox) where boundingBox is in Vision coordinates:
    /// - Normalized 0-1 within the input image
    /// - Origin at bottom-left (Vision's native format)
    static func recognizeTextWithBoxes(in cgImage: CGImage,
                                       fast: Bool = true,
                                       languageCorrection: Bool = false) async -> [(String, CGRect)] {
        await withCheckedContinuation { cont in
            let req = VNRecognizeTextRequest { request, _ in
                let results: [(String, CGRect)] = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { observation in
                        guard let candidate = observation.topCandidates(1).first else { return nil }
                        return (candidate.string, observation.boundingBox)
                    } ?? []
                cont.resume(returning: results)
            }

            req.recognitionLevel = fast ? .fast : .accurate
            req.usesLanguageCorrection = languageCorrection

            // For timers, restricting languages often improves stability.
            req.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([req])
            } catch {
                cont.resume(returning: [])
            }
        }
    }
}
