import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreImage

struct ShareableWindow: Identifiable {
    let id: UInt32
    let title: String
    let appName: String
}

actor CaptureManager {
    var onFrame: ((CGImage, CGSize) -> Void)?
    var onWindowsChanged: (([ShareableWindow]) -> Void)?

    private var stream: SCStream?
    private let ciContext = CIContext(options: nil)
    private var output: StreamOutput?

    func refreshShareableWindows(preferBundleID: String?) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            var list: [ShareableWindow] = []

            for w in content.windows {
                let appName = w.owningApplication?.applicationName ?? "?"
                let title = w.title ?? ""
                list.append(.init(id: w.windowID, title: title, appName: appName))
            }

            // Optionally sort: prefer VirtualDJ-like
            list.sort {
                let a = ($0.appName + " " + $0.title).lowercased()
                let b = ($1.appName + " " + $1.title).lowercased()
                return a.contains("virtualdj") && !b.contains("virtualdj")
            }

            onWindowsChanged?(list)
        } catch {
            onWindowsChanged?([])
        }
    }

    func startCapturing(windowID: UInt32) async {
        await stop()

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else { return }

            // Capture a single window (desktopIndependentWindow)
            let filter = SCContentFilter(desktopIndependentWindow: window)

            let config = SCStreamConfiguration()
            config.capturesAudio = false
            config.excludesCurrentProcessAudio = true
            // Poll-ish: 2 fps (you can raise/lower). minimumFrameInterval is reciprocal of FPS.
            config.minimumFrameInterval = CMTime(value: 1, timescale: 2)
            config.queueDepth = 1

            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            let out = StreamOutput(ciContext: ciContext) { [weak self] cg, size in
                Task { await self?.emitFrame(cg: cg, size: size) }
            }

            try stream.addStreamOutput(out, type: .screen, sampleHandlerQueue: DispatchQueue(label: "sc.output"))
            self.output = out
            self.stream = stream

            try await stream.startCapture()
        } catch {
            // ignored; user can retry after granting Screen Recording permission
        }
    }

    func stop() async {
        if let stream {
            do { try await stream.stopCapture() } catch {}
        }
        stream = nil
        output = nil
    }

    private func emitFrame(cg: CGImage, size: CGSize) {
        onFrame?(cg, size)
    }
}

final class StreamOutput: NSObject, SCStreamOutput {
    private let ciContext: CIContext
    private let onImage: (CGImage, CGSize) -> Void

    init(ciContext: CIContext, onImage: @escaping (CGImage, CGSize) -> Void) {
        self.ciContext = ciContext
        self.onImage = onImage
    }

    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen,
              let pb = sampleBuffer.imageBuffer else { return }

        let ci = CIImage(cvPixelBuffer: pb)
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        let rect = CGRect(x: 0, y: 0, width: w, height: h)

        if let cg = ciContext.createCGImage(ci, from: rect) {
            onImage(cg, CGSize(width: w, height: h))
        }
    }
}
