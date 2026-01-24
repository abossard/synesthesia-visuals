// KaraokeDisplayState.swift - Immutable display state for 3-line karaoke view
// Contains all the data needed to render one frame, with interpolation helpers

import SwiftUI

// MARK: - Karaoke Display State

/// Immutable display state for 3-line karaoke view with transition support
struct KaraokeDisplayState: Sendable, Equatable {

    // MARK: - Line Content

    /// The line that just finished (fading out above during transition)
    let prevLine: String?

    /// The currently active line (full white, centered)
    let currentLine: String?

    /// The upcoming line (dimmed, below current)
    let nextLine: String?

    /// The line after next (slides in from bottom during transition)
    let upcomingNextLine: String?

    // MARK: - Position Tracking

    /// Current line index in the lyrics array (-1 if no active line)
    let activeIndex: Int

    /// Total number of lines in the lyrics
    let totalLines: Int

    // MARK: - Transition State

    /// Transition progress: 0.0 = settled, 0.0->1.0 = transitioning
    let transitionProgress: Double

    /// Whether a transition animation is currently running
    let isTransitioning: Bool

    // MARK: - Computed Interpolated Properties

    /// Y position for current line (moves up during transition)
    /// At progress=0: currentLineY, at progress=1: prevLineY
    func currentLineY(config: KaraokeConfiguration) -> CGFloat {
        let eased = config.easing.apply(transitionProgress)
        return interpolate(
            from: config.currentLineYAbsolute,
            to: config.prevLineYAbsolute,
            t: eased
        )
    }

    /// Y position for next line (moves up to become current during transition)
    /// At progress=0: nextLineY, at progress=1: currentLineY
    func nextLineY(config: KaraokeConfiguration) -> CGFloat {
        let eased = config.easing.apply(transitionProgress)
        return interpolate(
            from: config.nextLineYAbsolute,
            to: config.currentLineYAbsolute,
            t: eased
        )
    }

    /// Y position for incoming next line (slides in from bottom during transition)
    /// At progress=0: newNextEntryY, at progress=1: nextLineY
    func upcomingNextLineY(config: KaraokeConfiguration) -> CGFloat {
        let eased = config.easing.apply(transitionProgress)
        return interpolate(
            from: config.newNextEntryYAbsolute,
            to: config.nextLineYAbsolute,
            t: eased
        )
    }

    /// Opacity for current line (fades out during transition)
    /// At progress=0: currentLineOpacity, at progress=1: 0
    func currentLineOpacity(config: KaraokeConfiguration) -> Double {
        let fadeStart = 0.3  // Start fading at 30% through transition
        let adjustedProgress = max(0, (transitionProgress - fadeStart) / (1.0 - fadeStart))
        return config.currentLineOpacity * (1.0 - adjustedProgress)
    }

    /// Opacity for next line (brightens during transition to become current)
    /// At progress=0: nextLineOpacity, at progress=1: currentLineOpacity
    func nextLineOpacity(config: KaraokeConfiguration) -> Double {
        let eased = config.easing.apply(transitionProgress)
        return interpolate(
            from: config.nextLineOpacity,
            to: config.currentLineOpacity,
            t: eased
        )
    }

    /// Opacity for incoming next line (fades in during transition)
    /// At progress=0: 0, at progress=1: nextLineOpacity
    func upcomingNextLineOpacity(config: KaraokeConfiguration) -> Double {
        // Start fading in at 20% through transition
        let fadeStart = 0.2
        let adjustedProgress = max(0, (transitionProgress - fadeStart) / (1.0 - fadeStart))
        return config.nextLineOpacity * adjustedProgress
    }

    /// Font size for current line (shrinks during transition as it moves up)
    /// At progress=0: currentFontSize, at progress=1: prevFontSize
    func currentLineFontSize(config: KaraokeConfiguration) -> CGFloat {
        let eased = config.easing.apply(transitionProgress)
        return interpolate(
            from: config.currentFontSize,
            to: config.prevFontSize,
            t: eased
        )
    }

    /// Font size for next line (grows during transition to become current)
    /// At progress=0: nextFontSize, at progress=1: currentFontSize
    func nextLineFontSize(config: KaraokeConfiguration) -> CGFloat {
        let eased = config.easing.apply(transitionProgress)
        return interpolate(
            from: config.nextFontSize,
            to: config.currentFontSize,
            t: eased
        )
    }

    /// Font size for incoming next line (constant during slide-in)
    func upcomingNextLineFontSize(config: KaraokeConfiguration) -> CGFloat {
        config.nextFontSize
    }

    // MARK: - Progress Information

    /// Progress text like "3 / 42"
    var progressText: String {
        guard activeIndex >= 0 && totalLines > 0 else { return "" }
        return "\(activeIndex + 1) / \(totalLines)"
    }

    /// Progress fraction (0-1)
    var progressFraction: Double {
        guard activeIndex >= 0 && totalLines > 0 else { return 0 }
        return Double(activeIndex) / Double(totalLines - 1)
    }

    // MARK: - Convenience Properties

    /// Whether there are lyrics loaded
    var hasLyrics: Bool {
        totalLines > 0
    }

    /// Whether we're at the last line
    var isLastLine: Bool {
        activeIndex == totalLines - 1
    }

    /// Whether we have a next line to show
    var hasNextLine: Bool {
        nextLine != nil
    }

    // MARK: - Empty State

    static let empty = KaraokeDisplayState(
        prevLine: nil,
        currentLine: nil,
        nextLine: nil,
        upcomingNextLine: nil,
        activeIndex: -1,
        totalLines: 0,
        transitionProgress: 0,
        isTransitioning: false
    )

    // MARK: - State Update Helpers

    /// Create a new state with updated transition progress
    func withTransitionProgress(_ progress: Double) -> KaraokeDisplayState {
        KaraokeDisplayState(
            prevLine: prevLine,
            currentLine: currentLine,
            nextLine: nextLine,
            upcomingNextLine: upcomingNextLine,
            activeIndex: activeIndex,
            totalLines: totalLines,
            transitionProgress: progress,
            isTransitioning: progress > 0 && progress < 1
        )
    }

    /// Create a state for when transition completes (next becomes current)
    func afterTransition() -> KaraokeDisplayState {
        KaraokeDisplayState(
            prevLine: currentLine,
            currentLine: nextLine,
            nextLine: upcomingNextLine,
            upcomingNextLine: nil,
            activeIndex: activeIndex + 1,
            totalLines: totalLines,
            transitionProgress: 0,
            isTransitioning: false
        )
    }

    // MARK: - Private Helpers

    private func interpolate(from: CGFloat, to: CGFloat, t: Double) -> CGFloat {
        from + (to - from) * CGFloat(t)
    }

    private func interpolate(from: Double, to: Double, t: Double) -> Double {
        from + (to - from) * t
    }
}

// MARK: - State Factory

extension KaraokeDisplayState {

    /// Create initial state from lyrics lines at a given index
    static func create(
        lines: [String],
        activeIndex: Int
    ) -> KaraokeDisplayState {
        let safeIndex = max(-1, min(activeIndex, lines.count - 1))

        let prevLine = safeIndex > 0 ? lines[safeIndex - 1] : nil
        let currentLine = safeIndex >= 0 && safeIndex < lines.count ? lines[safeIndex] : nil
        let nextLine = safeIndex + 1 < lines.count ? lines[safeIndex + 1] : nil
        let upcomingNextLine = safeIndex + 2 < lines.count ? lines[safeIndex + 2] : nil

        return KaraokeDisplayState(
            prevLine: prevLine,
            currentLine: currentLine,
            nextLine: nextLine,
            upcomingNextLine: upcomingNextLine,
            activeIndex: safeIndex,
            totalLines: lines.count,
            transitionProgress: 0,
            isTransitioning: false
        )
    }

    /// Create state for starting a transition to the next line
    static func startTransition(
        from currentState: KaraokeDisplayState,
        lines: [String]
    ) -> KaraokeDisplayState {
        let newNextIndex = currentState.activeIndex + 2
        let upcomingNext = newNextIndex < lines.count ? lines[newNextIndex] : nil

        return KaraokeDisplayState(
            prevLine: currentState.prevLine,
            currentLine: currentState.currentLine,
            nextLine: currentState.nextLine,
            upcomingNextLine: upcomingNext,
            activeIndex: currentState.activeIndex,
            totalLines: currentState.totalLines,
            transitionProgress: 0,
            isTransitioning: true
        )
    }
}
