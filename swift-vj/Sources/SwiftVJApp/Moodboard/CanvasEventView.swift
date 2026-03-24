// CanvasEventView — NSViewRepresentable bridging macOS scroll-wheel panning,
// click-to-deselect, and keyboard shortcuts into the moodboard canvas.

import AppKit
import SwiftUI

/// Callbacks the hosting SwiftUI view supplies to the underlying NSView.
struct CanvasEventCallbacks {
    /// Scroll delta in points (already inverted for natural scrolling by AppKit).
    var onScroll: (CGFloat, CGFloat) -> Void = { _, _ in }
    /// Mouse-down on background (not on a node). View should deselect all.
    var onBackgroundClick: () -> Void = {}
    /// Key event. Return true if consumed.
    var onKeyDown: (NSEvent) -> Bool = { _ in false }
}

struct CanvasEventView: NSViewRepresentable {
    var callbacks: CanvasEventCallbacks

    func makeNSView(context: Context) -> CanvasNSView {
        let view = CanvasNSView()
        view.callbacks = callbacks
        return view
    }

    func updateNSView(_ nsView: CanvasNSView, context: Context) {
        nsView.callbacks = callbacks
    }
}

/// NSView subclass that captures scroll-wheel, mouseDown, and keyDown.
final class CanvasNSView: NSView {
    var callbacks = CanvasEventCallbacks()

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func scrollWheel(with event: NSEvent) {
        // scrollingDeltaX/Y are already sign-corrected for natural scroll direction.
        callbacks.onScroll(event.scrollingDeltaX, event.scrollingDeltaY)
    }

    override func mouseDown(with event: NSEvent) {
        // Become first responder on any click so keyboard events route here.
        window?.makeFirstResponder(self)
        callbacks.onBackgroundClick()
    }

    override func keyDown(with event: NSEvent) {
        if callbacks.onKeyDown(event) { return }
        super.keyDown(with: event)
    }
}
