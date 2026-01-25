// KaraokeEngine.swift - Main karaoke engine for automatic line transitions
// Tracks playback position against LRC timecodes and triggers transitions

import Foundation
import SwiftUI
import SwiftVJCore

// MARK: - Karaoke Engine

/// Main karaoke engine that tracks playback position and triggers line transitions
/// Observable class for SwiftUI integration, MainActor isolated for thread safety
@MainActor
final class KaraokeEngine: ObservableObject {

    // MARK: - Published State

    /// Current display state (immutable snapshot for rendering)
    @Published private(set) var displayState: KaraokeDisplayState = .empty

    /// Whether a transition animation is currently running
    @Published private(set) var isTransitioning: Bool = false

    /// Configurable parameters for karaoke display
    @Published var configuration: KaraokeConfiguration = .default

    // MARK: - Internal State

    /// Loaded lyrics lines with timestamps
    private var lines: [LyricLine] = []

    /// Text-only lines for display (extracted from LyricLine)
    private var lineTexts: [String] = []

    /// Current active line index (-1 if no active line)
    private var currentIndex: Int = -1

    /// Last processed playback position
    private var lastPosition: Double = 0

    /// Timing offset in milliseconds (positive = lyrics earlier)
    var timingOffsetMs: Int = 0

    /// Computed timing offset in seconds
    private var timingOffsetSec: Double { Double(timingOffsetMs) / 1000.0 }

    // MARK: - Animation State

    /// Timer for transition animation
    private var animationTimer: Timer?

    /// Start time of current transition animation
    private var transitionStartTime: Date?

    // MARK: - Initialization

    init() {
        // Start with empty state
    }

    // MARK: - Public API

    /// Load lyrics from LyricLine array (from LyricsModule or pipeline)
    func loadLyrics(_ newLines: [LyricLine]) {
        stopTransitionAnimation()

        lines = newLines
        lineTexts = newLines.map { $0.text }
        currentIndex = -1
        lastPosition = 0

        // Update display state
        updateDisplayState()

        print("[KaraokeEngine] Loaded \(newLines.count) lyrics lines")
    }

    /// Load lyrics from text-only array with timestamps
    func loadLyrics(texts: [String], timestamps: [Double]) {
        guard texts.count == timestamps.count else {
            print("[KaraokeEngine] Error: texts and timestamps count mismatch")
            return
        }

        stopTransitionAnimation()

        lines = zip(texts, timestamps).map { text, time in
            LyricLine(timeSec: time, text: text)
        }
        lineTexts = texts
        currentIndex = -1
        lastPosition = 0

        updateDisplayState()

        print("[KaraokeEngine] Loaded \(texts.count) lyrics lines")
    }

    /// Update with current playback position (call at ~60Hz from render loop)
    func updatePosition(_ position: Double) {
        guard !lines.isEmpty else { return }

        // Apply timing offset and preroll
        let adjustedPosition = position + timingOffsetSec + configuration.prerollTime
        lastPosition = adjustedPosition

        // Find the active line index
        let newIndex = findActiveLineIndex(at: adjustedPosition)

        // Check if we need to transition to a new line
        if newIndex != currentIndex && newIndex >= 0 {
            // Only transition forward (not backward on seek)
            if newIndex > currentIndex || currentIndex == -1 {
                triggerTransition(to: newIndex)
            } else {
                // Seeking backward - jump directly without animation
                currentIndex = newIndex
                updateDisplayState()
            }
        }
    }

    /// Manually advance to next line (for testing or manual control)
    func nextLine() {
        guard !lines.isEmpty else { return }
        let nextIndex = min(currentIndex + 1, lines.count - 1)
        if nextIndex != currentIndex {
            triggerTransition(to: nextIndex)
        }
    }

    /// Manually go to previous line
    func previousLine() {
        guard !lines.isEmpty else { return }
        let prevIndex = max(currentIndex - 1, 0)
        if prevIndex != currentIndex {
            currentIndex = prevIndex
            updateDisplayState()
        }
    }

    /// Jump to specific line index
    func jumpToLine(_ index: Int) {
        guard !lines.isEmpty else { return }
        let safeIndex = max(-1, min(index, lines.count - 1))
        if safeIndex != currentIndex {
            currentIndex = safeIndex
            updateDisplayState()
        }
    }

    /// Reset state (call on track change)
    func reset() {
        stopTransitionAnimation()
        lines = []
        lineTexts = []
        currentIndex = -1
        lastPosition = 0
        displayState = .empty
        isTransitioning = false

        print("[KaraokeEngine] Reset")
    }

    // MARK: - Private Methods

    /// Find the active line index for the given position
    /// Uses the pure function from SwiftVJCore.Functions
    private func findActiveLineIndex(at position: Double) -> Int {
        // Use the existing pure function
        return getActiveLineIndex(lines, position: position)
    }

    /// Trigger a transition animation to the new line
    private func triggerTransition(to newIndex: Int) {
        guard newIndex >= 0 && newIndex < lines.count else { return }

        // Stop any existing animation
        stopTransitionAnimation()

        // Calculate the upcoming next line (the one that will slide in)
        let upcomingNextIndex = newIndex + 1
        let upcomingNextText = upcomingNextIndex < lines.count ? lineTexts[upcomingNextIndex] : nil

        // Create transition start state
        displayState = KaraokeDisplayState(
            prevLine: currentIndex >= 0 && currentIndex < lineTexts.count ? lineTexts[currentIndex] : nil,
            currentLine: displayState.currentLine,  // Keep current for now
            nextLine: lineTexts[newIndex],  // This will become current
            upcomingNextLine: upcomingNextText,  // This will slide in as next
            activeIndex: currentIndex,
            totalLines: lines.count,
            transitionProgress: 0,
            isTransitioning: true
        )

        isTransitioning = true
        currentIndex = newIndex
        transitionStartTime = Date()

        // Start animation timer at ~60fps
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickTransitionAnimation()
            }
        }
    }

    /// Called every frame during transition animation
    private func tickTransitionAnimation() {
        guard let startTime = transitionStartTime else {
            stopTransitionAnimation()
            return
        }

        let elapsed = Date().timeIntervalSince(startTime)
        let duration = configuration.transitionDuration
        let rawProgress = min(elapsed / duration, 1.0)

        // Update display state with new progress
        displayState = KaraokeDisplayState(
            prevLine: displayState.prevLine,
            currentLine: displayState.currentLine,
            nextLine: displayState.nextLine,
            upcomingNextLine: displayState.upcomingNextLine,
            activeIndex: currentIndex,
            totalLines: lines.count,
            transitionProgress: rawProgress,
            isTransitioning: true
        )

        // Check if animation complete
        if rawProgress >= 1.0 {
            completeTransition()
        }
    }

    /// Complete the transition and update to final state
    private func completeTransition() {
        stopTransitionAnimation()

        // Update to settled state (next becomes current)
        updateDisplayState()

        isTransitioning = false
    }

    /// Stop the transition animation timer
    private func stopTransitionAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        transitionStartTime = nil
    }

    /// Update the display state from current index (called when not transitioning)
    private func updateDisplayState() {
        displayState = KaraokeDisplayState.create(
            lines: lineTexts,
            activeIndex: currentIndex
        )
    }
}

// MARK: - Public Accessors for UI

extension KaraokeEngine {

    /// All lyrics lines with timestamps (for lyrics panel display)
    var allLines: [LyricLine] { lines }

    /// Current active line index (0-based, -1 if none)
    var activeLineIndex: Int { currentIndex }

    /// Last known playback position in seconds
    var currentPosition: Double { lastPosition }
}

// MARK: - Debug / Testing Extensions

extension KaraokeEngine {

    /// Get current state for debugging
    var debugInfo: String {
        """
        KaraokeEngine:
          Lines: \(lines.count)
          Current Index: \(currentIndex)
          Is Transitioning: \(isTransitioning)
          Progress: \(displayState.transitionProgress)
          Current Line: \(displayState.currentLine ?? "nil")
          Next Line: \(displayState.nextLine ?? "nil")
        """
    }

    /// Set transition progress manually (for testing/preview)
    func setTransitionProgressForTesting(_ progress: Double) {
        guard !lines.isEmpty else { return }

        let clampedProgress = max(0, min(progress, 1))

        // Create artificial transition state
        let upcomingNextIndex = currentIndex + 2
        let upcomingNextText = upcomingNextIndex < lineTexts.count ? lineTexts[upcomingNextIndex] : nil

        displayState = KaraokeDisplayState(
            prevLine: currentIndex > 0 ? lineTexts[currentIndex - 1] : nil,
            currentLine: currentIndex >= 0 && currentIndex < lineTexts.count ? lineTexts[currentIndex] : nil,
            nextLine: currentIndex + 1 < lineTexts.count ? lineTexts[currentIndex + 1] : nil,
            upcomingNextLine: upcomingNextText,
            activeIndex: currentIndex,
            totalLines: lines.count,
            transitionProgress: clampedProgress,
            isTransitioning: clampedProgress > 0 && clampedProgress < 1
        )

        isTransitioning = clampedProgress > 0 && clampedProgress < 1
    }

    /// Load test lyrics for preview/testing
    func loadTestLyrics() {
        let testLines = [
            "Welcome to the show tonight",
            "We're gonna light up the sky",
            "Dancing under neon lights",
            "Feel the beat and close your eyes",
            "This is where we come alive",
            "Let the music take control",
            "Every heart beats as one",
            "Until the morning sun"
        ]

        let timestamps = [0.0, 4.0, 8.0, 12.0, 16.0, 20.0, 24.0, 28.0]

        loadLyrics(texts: testLines, timestamps: timestamps)
        currentIndex = 2  // Start at line 3 for better preview
        updateDisplayState()
    }
}
