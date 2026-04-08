import Foundation
import Metal
import SyphonKit

@available(macOS 15.0, *)
final class SyphonOutput {
    private let sender: SyphonSender
    private(set) var isRunning = false

    init?(device: MTLDevice, name: String) {
        guard let sender = SyphonSender.create(name: name, device: device) else {
            return nil
        }
        self.sender = sender
        self.isRunning = true
    }

    func publish(texture: MTLTexture, commandBuffer: MTLCommandBuffer, flipped: Bool) {
        sender.publish(texture: texture, commandBuffer: commandBuffer, flipped: flipped)
    }

    func stop() {
        sender.stop()
        isRunning = false
    }
}
