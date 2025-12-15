import Foundation
import Vision

enum VisionOCR {
    static func recognizeText(in cgImage: CGImage,
                              fast: Bool = true,
                              languageCorrection: Bool = false) async -> [String] {
        await withCheckedContinuation { cont in
            let req = VNRecognizeTextRequest { request, _ in
                let texts: [String] = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string } ?? []
                cont.resume(returning: texts)
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
