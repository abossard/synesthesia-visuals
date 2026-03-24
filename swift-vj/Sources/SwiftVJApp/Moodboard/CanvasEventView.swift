// CanvasEventView — NSViewRepresentable that captures scroll-wheel and keyboard
// WITHOUT intercepting mouse clicks/drags (so SwiftUI gestures work on nodes).

import AppKit
import SwiftUI

/// Callbacks the hosting SwiftUI view supplies.
struct CanvasEventCallbacks {
    /// Scroll delta in points + whether scrolling has ended (for commit).
    var onScroll: (_ dx: CGFloat, _ dy: CGFloat, _ isEnded: Bool) -> Void = { _, _, _ in }
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

/// NSView that captures keyboard via first responder and scroll via local event monitor.
/// Returns nil from hitTest so it NEVER intercepts mouse clicks/drags — SwiftUI gestures work.
final class CanvasNSView: NSView {
    var callbacks = CanvasEventCallbacks()
    private var scrollMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
        installMonitors()
    }

    override func removeFromSuperview() {
        removeMonitors()
        super.removeFromSuperview()
    }

    // Don't intercept mouse events — let SwiftUI handle clicks/drags on nodes
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func keyDown(with event: NSEvent) {
        if callbacks.onKeyDown(event) { return }
        super.keyDown(with: event)
    }

    private func installMonitors() {
        removeMonitors()
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            let loc = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(loc) else { return event }
            let isEnded = event.phase == .ended || event.phase == .cancelled
                || (event.phase == [] && event.momentumPhase == .ended)
            self.callbacks.onScroll(event.scrollingDeltaX, event.scrollingDeltaY, isEnded)
            return nil
        }
    }

    private func removeMonitors() {
        if let m = scrollMonitor { NSEvent.removeMonitor(m); scrollMonitor = nil }
    }
}
