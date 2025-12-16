import Foundation
import Vision

enum VisionOCR {
    /// Recognize text, returning strings only (legacy)
    static func recognizeText(in cgImage: CGImage,
                              languageCorrection: Bool = false) async -> [String] {
        let results = await recognizeTextWithBoxes(in: cgImage, languageCorrection: languageCorrection)
        return results.map { $0.0 }
    }
    
    /// Recognize text with bounding boxes
    /// Returns array of (text, boundingBox) where boundingBox is in Vision coordinates:
    /// - Normalized 0-1 within the input image
    /// - Origin at bottom-left (Vision's native format)
    /// Always uses .accurate recognition level for best results
    static func recognizeTextWithBoxes(in cgImage: CGImage,
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

            // Always use accurate mode for best OCR quality
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = languageCorrection
            
            // Use latest Vision revision for best accuracy (macOS 13+)
            if #available(macOS 13.0, *) {
                req.revision = VNRecognizeTextRequestRevision3
            }
            
            // Extended language list when correction is enabled (helps with artist names)
            // When correction is off, stick to English for speed
            if languageCorrection {
                req.recognitionLanguages = ["en-US", "de-DE", "fr-FR", "es-ES", "it-IT", "pt-BR", "nl-NL"]
            } else {
                req.recognitionLanguages = ["en-US"]
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([req])
            } catch {
                cont.resume(returning: [])
            }
        }
    }
}
