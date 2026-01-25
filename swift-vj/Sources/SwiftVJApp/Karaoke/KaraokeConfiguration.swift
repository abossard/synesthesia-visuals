// KaraokeConfiguration.swift - Configurable parameters for karaoke display
// All values have sensible defaults and can be adjusted via sliders

import SwiftUI

// MARK: - Easing Functions

/// Easing function types for smooth animations
enum EasingFunction: String, Sendable, Codable, CaseIterable, Identifiable {
    case linear = "Linear"
    case easeInQuad = "Ease In"
    case easeOutQuad = "Ease Out"
    case easeInOutQuad = "Ease In/Out"
    case easeOutCubic = "Ease Out Cubic"
    case easeOutBack = "Overshoot"

    var id: String { rawValue }

    /// Apply the easing function to a normalized time value (0-1)
    func apply(_ t: Double) -> Double {
        switch self {
        case .linear:
            return t
        case .easeInQuad:
            return t * t
        case .easeOutQuad:
            return 1 - (1 - t) * (1 - t)
        case .easeInOutQuad:
            return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        case .easeOutCubic:
            return 1 - pow(1 - t, 3)
        case .easeOutBack:
            let c1 = 1.70158
            let c3 = c1 + 1
            return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
        }
    }
}

// MARK: - Karaoke Configuration

/// All configurable parameters for karaoke display with sensible defaults
struct KaraokeConfiguration: Sendable, Equatable, Codable {

    // MARK: - Y Positions (relative, 0.0 = top, 1.0 = bottom)

    /// Y position for the previous line (fading out above)
    var prevLineY: CGFloat = 0.28

    /// Y position for the current line (centered, full white)
    var currentLineY: CGFloat = 0.50

    /// Y position for the next line (dimmed, below)
    var nextLineY: CGFloat = 0.72

    /// Y position where new next line slides in from (off-screen bottom)
    var newNextEntryY: CGFloat = 0.95

    // MARK: - Font Sizes

    /// Font size for the current (active) line
    var currentFontSize: CGFloat = 72

    /// Font size for the next (preview) line
    var nextFontSize: CGFloat = 42

    /// Font size for the previous (exiting) line
    var prevFontSize: CGFloat = 36

    // MARK: - Opacities (0.0 = invisible, 1.0 = full white)

    /// Opacity for the current line (full white)
    var currentLineOpacity: Double = 1.0

    /// Opacity for the next line (dimmed)
    var nextLineOpacity: Double = 0.4

    /// Opacity for the previous line at start of exit animation
    var prevLineOpacity: Double = 0.3

    // MARK: - Transition Timing

    /// Duration of the line transition animation in seconds
    var transitionDuration: TimeInterval = 0.6

    /// Easing function for transitions
    var easing: EasingFunction = .easeOutCubic

    /// Pre-roll time in seconds (start transition slightly before timecode)
    var prerollTime: TimeInterval = 0.1

    // MARK: - Text Appearance

    /// Font weight (light, regular, medium, semibold, bold, heavy, black)
    var fontWeight: Font.Weight = .bold

    /// Font design (default, rounded, serif, monospaced)
    var fontDesign: Font.Design = .rounded

    /// Text shadow radius for readability
    var textShadowRadius: CGFloat = 4

    /// Text shadow opacity
    var textShadowOpacity: Double = 0.5

    /// Maximum line width (relative to canvas width, 0.0-1.0)
    var maxLineWidthRatio: CGFloat = 0.9

    // MARK: - Animation Mode

    /// Per-glyph animation mode for text transitions
    var animationMode: TextAnimationMode = .waveDissolve

    // MARK: - Canvas Size (for absolute positioning)

    /// Reference canvas width
    var canvasWidth: CGFloat = 1280

    /// Reference canvas height
    var canvasHeight: CGFloat = 720

    // MARK: - Computed Properties

    /// Absolute Y position for previous line
    var prevLineYAbsolute: CGFloat { prevLineY * canvasHeight }

    /// Absolute Y position for current line
    var currentLineYAbsolute: CGFloat { currentLineY * canvasHeight }

    /// Absolute Y position for next line
    var nextLineYAbsolute: CGFloat { nextLineY * canvasHeight }

    /// Absolute Y position for new next entry
    var newNextEntryYAbsolute: CGFloat { newNextEntryY * canvasHeight }

    /// Center X position
    var centerX: CGFloat { canvasWidth / 2 }

    /// Maximum line width in pixels
    var maxLineWidth: CGFloat { canvasWidth * maxLineWidthRatio }

    // MARK: - Presets

    /// Default configuration
    static let `default` = KaraokeConfiguration()

    /// Compact preset - smaller fonts, tighter spacing
    static let compact = KaraokeConfiguration(
        prevLineY: 0.30,
        currentLineY: 0.48,
        nextLineY: 0.66,
        currentFontSize: 56,
        nextFontSize: 32,
        prevFontSize: 28,
        transitionDuration: 0.5
    )

    /// Dramatic preset - large fonts, slower transitions
    static let dramatic = KaraokeConfiguration(
        currentFontSize: 96,
        nextFontSize: 54,
        prevFontSize: 42,
        transitionDuration: 0.8,
        easing: .easeOutBack,
        animationMode: .springBounce
    )

    /// Subtle preset - low contrast, fast transitions
    static let subtle = KaraokeConfiguration(
        currentLineOpacity: 0.95,
        nextLineOpacity: 0.3,
        prevLineOpacity: 0.15,
        transitionDuration: 0.4,
        animationMode: .fadeInOut
    )

    /// Clean preset - no animations, instant transitions
    static let clean = KaraokeConfiguration(
        transitionDuration: 0.3,
        textShadowRadius: 2,
        textShadowOpacity: 0.3,
        animationMode: .instant
    )

    // MARK: - Immutable Updates

    func withAnimationMode(_ mode: TextAnimationMode) -> KaraokeConfiguration {
        var copy = self
        copy.animationMode = mode
        return copy
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case prevLineY, currentLineY, nextLineY, newNextEntryY
        case currentFontSize, nextFontSize, prevFontSize
        case currentLineOpacity, nextLineOpacity, prevLineOpacity
        case transitionDuration, easing, prerollTime
        case textShadowRadius, textShadowOpacity, maxLineWidthRatio
        case animationMode
        case canvasWidth, canvasHeight
    }

    // Custom coding for Font.Weight and Font.Design (not directly Codable)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        prevLineY = try container.decodeIfPresent(CGFloat.self, forKey: .prevLineY) ?? 0.28
        currentLineY = try container.decodeIfPresent(CGFloat.self, forKey: .currentLineY) ?? 0.50
        nextLineY = try container.decodeIfPresent(CGFloat.self, forKey: .nextLineY) ?? 0.72
        newNextEntryY = try container.decodeIfPresent(CGFloat.self, forKey: .newNextEntryY) ?? 0.95

        currentFontSize = try container.decodeIfPresent(CGFloat.self, forKey: .currentFontSize) ?? 72
        nextFontSize = try container.decodeIfPresent(CGFloat.self, forKey: .nextFontSize) ?? 42
        prevFontSize = try container.decodeIfPresent(CGFloat.self, forKey: .prevFontSize) ?? 36

        currentLineOpacity = try container.decodeIfPresent(Double.self, forKey: .currentLineOpacity) ?? 1.0
        nextLineOpacity = try container.decodeIfPresent(Double.self, forKey: .nextLineOpacity) ?? 0.4
        prevLineOpacity = try container.decodeIfPresent(Double.self, forKey: .prevLineOpacity) ?? 0.3

        transitionDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .transitionDuration) ?? 0.6
        easing = try container.decodeIfPresent(EasingFunction.self, forKey: .easing) ?? .easeOutCubic
        prerollTime = try container.decodeIfPresent(TimeInterval.self, forKey: .prerollTime) ?? 0.1

        textShadowRadius = try container.decodeIfPresent(CGFloat.self, forKey: .textShadowRadius) ?? 4
        textShadowOpacity = try container.decodeIfPresent(Double.self, forKey: .textShadowOpacity) ?? 0.5
        maxLineWidthRatio = try container.decodeIfPresent(CGFloat.self, forKey: .maxLineWidthRatio) ?? 0.9

        animationMode = try container.decodeIfPresent(TextAnimationMode.self, forKey: .animationMode) ?? .waveDissolve

        canvasWidth = try container.decodeIfPresent(CGFloat.self, forKey: .canvasWidth) ?? 1280
        canvasHeight = try container.decodeIfPresent(CGFloat.self, forKey: .canvasHeight) ?? 720

        fontWeight = .bold
        fontDesign = .rounded
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(prevLineY, forKey: .prevLineY)
        try container.encode(currentLineY, forKey: .currentLineY)
        try container.encode(nextLineY, forKey: .nextLineY)
        try container.encode(newNextEntryY, forKey: .newNextEntryY)

        try container.encode(currentFontSize, forKey: .currentFontSize)
        try container.encode(nextFontSize, forKey: .nextFontSize)
        try container.encode(prevFontSize, forKey: .prevFontSize)

        try container.encode(currentLineOpacity, forKey: .currentLineOpacity)
        try container.encode(nextLineOpacity, forKey: .nextLineOpacity)
        try container.encode(prevLineOpacity, forKey: .prevLineOpacity)

        try container.encode(transitionDuration, forKey: .transitionDuration)
        try container.encode(easing, forKey: .easing)
        try container.encode(prerollTime, forKey: .prerollTime)

        try container.encode(textShadowRadius, forKey: .textShadowRadius)
        try container.encode(textShadowOpacity, forKey: .textShadowOpacity)
        try container.encode(maxLineWidthRatio, forKey: .maxLineWidthRatio)

        try container.encode(animationMode, forKey: .animationMode)

        try container.encode(canvasWidth, forKey: .canvasWidth)
        try container.encode(canvasHeight, forKey: .canvasHeight)
    }

    // Default memberwise init
    init(
        prevLineY: CGFloat = 0.28,
        currentLineY: CGFloat = 0.50,
        nextLineY: CGFloat = 0.72,
        newNextEntryY: CGFloat = 0.95,
        currentFontSize: CGFloat = 72,
        nextFontSize: CGFloat = 42,
        prevFontSize: CGFloat = 36,
        currentLineOpacity: Double = 1.0,
        nextLineOpacity: Double = 0.4,
        prevLineOpacity: Double = 0.3,
        transitionDuration: TimeInterval = 0.6,
        easing: EasingFunction = .easeOutCubic,
        prerollTime: TimeInterval = 0.1,
        fontWeight: Font.Weight = .bold,
        fontDesign: Font.Design = .rounded,
        textShadowRadius: CGFloat = 4,
        textShadowOpacity: Double = 0.5,
        maxLineWidthRatio: CGFloat = 0.9,
        animationMode: TextAnimationMode = .waveDissolve,
        canvasWidth: CGFloat = 1280,
        canvasHeight: CGFloat = 720
    ) {
        self.prevLineY = prevLineY
        self.currentLineY = currentLineY
        self.nextLineY = nextLineY
        self.newNextEntryY = newNextEntryY
        self.currentFontSize = currentFontSize
        self.nextFontSize = nextFontSize
        self.prevFontSize = prevFontSize
        self.currentLineOpacity = currentLineOpacity
        self.nextLineOpacity = nextLineOpacity
        self.prevLineOpacity = prevLineOpacity
        self.transitionDuration = transitionDuration
        self.easing = easing
        self.prerollTime = prerollTime
        self.fontWeight = fontWeight
        self.fontDesign = fontDesign
        self.textShadowRadius = textShadowRadius
        self.textShadowOpacity = textShadowOpacity
        self.maxLineWidthRatio = maxLineWidthRatio
        self.animationMode = animationMode
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
    }
}

// MARK: - TextAnimationMode Codable Extension

extension TextAnimationMode: Codable {}
