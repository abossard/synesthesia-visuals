// RealityViewHost.swift
// RealityKitVJKitchenSink
//
// NSViewRepresentable hosting ARView in non-AR mode.
// Reference: https://developer.apple.com/documentation/realitykit/arview/cameramode-swift.enum/nonar

import SwiftUI
import RealityKit
import AppKit

/// Hosts RealityKit's ARView in a SwiftUI context
struct RealityViewHost: NSViewRepresentable {
    @EnvironmentObject var appState: AppState

    func makeNSView(context: Context) -> ARView {
        // Create ARView for 3D rendering
        let arView = ARView(frame: .zero)

        // Enable high quality rendering
        arView.environment.background = .color(.black)

        // Set up the scene coordinator
        context.coordinator.setup(arView: arView, appState: appState)

        return arView
    }

    func updateNSView(_ arView: ARView, context: Context) {
        context.coordinator.updateAppState(appState)
    }

    func makeCoordinator() -> SceneCoordinator {
        SceneCoordinator()
    }
}
