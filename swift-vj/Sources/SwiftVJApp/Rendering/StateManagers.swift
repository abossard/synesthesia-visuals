// StateManagers.swift - Observable state managers for rendering domains

import Foundation
import SwiftUI
import SwiftVJCore

// MARK: - Image State Manager

/// Manages image display state for the image tile renderer.
@MainActor
final class ImageStateManager: ObservableObject {
    @Published var state: ImageDisplayState = .empty
}
