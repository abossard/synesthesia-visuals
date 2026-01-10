import SwiftUI
import RealityKit

@available(macOS 15.0, *)
struct RealityViewHost: NSViewRepresentable {
    @ObservedObject var coordinator: SceneCoordinator

    func makeNSView(context: Context) -> ARView {
        coordinator.makeView()
    }

    func updateNSView(_ nsView: ARView, context: Context) {
        coordinator.updateView()
    }
}
