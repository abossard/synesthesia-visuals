// KaraokeView.swift - SwiftUI view for karaoke-style lyrics display
// Renders current line (full white) and next line (dimmed) with smooth transitions

import SwiftUI

// MARK: - Main Karaoke View

/// SwiftUI view for karaoke-style lyrics display
/// Renders 3 lines: current (full white), next (dimmed), with animated transitions
@available(macOS 15.0, *)
struct KaraokeView: View {
    let displayState: KaraokeDisplayState
    let configuration: KaraokeConfiguration
    let beatIntensity: Double

    var body: some View {
        ZStack {
            // Black background
            Color.black

            // Previous line (exiting upward, fading out)
            if displayState.isTransitioning,
               let prevLine = displayState.currentLine {  // Current becomes prev during transition
                exitingLineView(prevLine)
            }

            // Current line (or next becoming current during transition)
            if let currentLine = displayState.isTransitioning
                ? displayState.nextLine  // Next is becoming current
                : displayState.currentLine {
                currentLineView(currentLine)
            }

            // Next line (or upcoming becoming next during transition)
            if let nextLine = displayState.isTransitioning
                ? displayState.upcomingNextLine  // Upcoming is becoming next
                : displayState.nextLine {
                nextLineView(nextLine)
            }

            // Incoming next line (slides in during transition)
            // This is only shown during transition when we have an upcoming line
            // Already handled above in the conditional logic
        }
        .frame(width: configuration.canvasWidth, height: configuration.canvasHeight)
    }

    // MARK: - Current Line View (full white, centered)

    @ViewBuilder
    private func currentLineView(_ text: String) -> some View {
        // Compute values based on transition state
        let fontSize = displayState.isTransitioning
            ? displayState.nextLineFontSize(config: configuration)
            : configuration.currentFontSize

        let yPos = displayState.isTransitioning
            ? displayState.nextLineY(config: configuration)
            : configuration.currentLineYAbsolute

        let opacity = displayState.isTransitioning
            ? displayState.nextLineOpacity(config: configuration)
            : configuration.currentLineOpacity

        karaokeText(
            text: text,
            fontSize: fontSize,
            opacity: opacity,
            yPosition: yPos,
            animationMode: displayState.isTransitioning ? configuration.animationMode : .instant
        )
    }

    // MARK: - Next Line View (dimmed, below)

    @ViewBuilder
    private func nextLineView(_ text: String) -> some View {
        // Compute values based on transition state
        let fontSize = displayState.isTransitioning
            ? displayState.upcomingNextLineFontSize(config: configuration)
            : configuration.nextFontSize

        let yPos = displayState.isTransitioning
            ? displayState.upcomingNextLineY(config: configuration)
            : configuration.nextLineYAbsolute

        let opacity = displayState.isTransitioning
            ? displayState.upcomingNextLineOpacity(config: configuration)
            : configuration.nextLineOpacity

        karaokeText(
            text: text,
            fontSize: fontSize,
            opacity: opacity,
            yPosition: yPos,
            animationMode: .instant  // No per-glyph animation for next line
        )
    }

    // MARK: - Exiting Line View (fading up and out)

    @ViewBuilder
    private func exitingLineView(_ text: String) -> some View {
        let fontSize = displayState.currentLineFontSize(config: configuration)
        let yPos = displayState.currentLineY(config: configuration)
        let opacity = displayState.currentLineOpacity(config: configuration)

        karaokeText(
            text: text,
            fontSize: fontSize,
            opacity: opacity,
            yPosition: yPos,
            animationMode: configuration.animationMode,
            isExiting: true
        )
    }

    // MARK: - Karaoke Text Component

    @ViewBuilder
    private func karaokeText(
        text: String,
        fontSize: CGFloat,
        opacity: Double,
        yPosition: CGFloat,
        animationMode: TextAnimationMode,
        isExiting: Bool = false
    ) -> some View {
        let baseText = Text(text)
            .font(.system(
                size: fontSize,
                weight: configuration.fontWeight,
                design: configuration.fontDesign
            ))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: configuration.maxLineWidth)

        Group {
            switch animationMode {
            case .instant:
                baseText
                    .opacity(opacity)

            case .fadeInOut:
                baseText
                    .opacity(opacity)

            case .waveDissolve:
                if isExiting {
                    baseText
                        .textRenderer(WaveDissolveRenderer(
                            progress: displayState.transitionProgress,
                            direction: 1.0
                        ))
                } else {
                    baseText
                        .textRenderer(WaveDissolveRenderer(
                            progress: 1.0 - displayState.transitionProgress,
                            direction: 1.0
                        ))
                        .opacity(opacity)
                }

            case .blurPop:
                if isExiting {
                    baseText
                        .textRenderer(BlurPopRenderer(progress: 1.0 - displayState.transitionProgress))
                } else {
                    baseText
                        .textRenderer(BlurPopRenderer(progress: displayState.transitionProgress))
                        .opacity(opacity)
                }

            case .springBounce:
                if isExiting {
                    baseText
                        .textRenderer(SpringBounceRenderer(
                            progress: 1.0 - displayState.transitionProgress,
                            bounceHeight: -30
                        ))
                } else {
                    baseText
                        .textRenderer(SpringBounceRenderer(
                            progress: displayState.transitionProgress,
                            bounceHeight: 40
                        ))
                        .opacity(opacity)
                }

            case .typewriter:
                if isExiting {
                    baseText
                        .textRenderer(TypewriterRenderer(progress: 1.0 - displayState.transitionProgress))
                } else {
                    baseText
                        .textRenderer(TypewriterRenderer(progress: displayState.transitionProgress))
                        .opacity(opacity)
                }

            case .glowPulse:
                baseText
                    .textRenderer(GlowPulseRenderer(intensity: beatIntensity * 0.5))
                    .opacity(opacity)

            case .rainbowWave:
                baseText
                    .textRenderer(RainbowWaveRenderer(phase: displayState.transitionProgress * 2))
                    .opacity(opacity)
            }
        }
        .shadow(
            color: .black.opacity(configuration.textShadowOpacity),
            radius: configuration.textShadowRadius
        )
        .position(x: configuration.centerX, y: yPosition)
    }
}

// MARK: - Fallback View for macOS 14

/// Fallback karaoke view for macOS 14 (no TextRenderer API)
struct KaraokeViewFallback: View {
    let displayState: KaraokeDisplayState
    let configuration: KaraokeConfiguration

    var body: some View {
        ZStack {
            Color.black

            // Current line (full white)
            if let currentLine = displayState.currentLine {
                Text(currentLine)
                    .font(.system(
                        size: configuration.currentFontSize,
                        weight: configuration.fontWeight,
                        design: configuration.fontDesign
                    ))
                    .foregroundStyle(.white)
                    .opacity(displayState.isTransitioning
                        ? displayState.currentLineOpacity(config: configuration)
                        : configuration.currentLineOpacity)
                    .shadow(
                        color: .black.opacity(configuration.textShadowOpacity),
                        radius: configuration.textShadowRadius
                    )
                    .position(
                        x: configuration.centerX,
                        y: displayState.isTransitioning
                            ? displayState.currentLineY(config: configuration)
                            : configuration.currentLineYAbsolute
                    )
            }

            // Next line (dimmed)
            if let nextLine = displayState.nextLine {
                Text(nextLine)
                    .font(.system(
                        size: configuration.nextFontSize,
                        weight: configuration.fontWeight,
                        design: configuration.fontDesign
                    ))
                    .foregroundStyle(.white)
                    .opacity(displayState.isTransitioning
                        ? displayState.nextLineOpacity(config: configuration)
                        : configuration.nextLineOpacity)
                    .shadow(
                        color: .black.opacity(configuration.textShadowOpacity * 0.5),
                        radius: configuration.textShadowRadius * 0.5
                    )
                    .position(
                        x: configuration.centerX,
                        y: displayState.isTransitioning
                            ? displayState.nextLineY(config: configuration)
                            : configuration.nextLineYAbsolute
                    )
            }
        }
        .frame(width: configuration.canvasWidth, height: configuration.canvasHeight)
    }
}

// MARK: - View Builder Helper

/// Helper to create the appropriate karaoke view based on OS version
struct KaraokeViewBuilder: View {
    let displayState: KaraokeDisplayState
    let configuration: KaraokeConfiguration
    let beatIntensity: Double

    var body: some View {
        if #available(macOS 15.0, *) {
            KaraokeView(
                displayState: displayState,
                configuration: configuration,
                beatIntensity: beatIntensity
            )
        } else {
            KaraokeViewFallback(
                displayState: displayState,
                configuration: configuration
            )
        }
    }
}

// MARK: - Preview

@available(macOS 15.0, *)
#Preview("Karaoke View - Settled") {
    let state = KaraokeDisplayState(
        prevLine: "This was the previous line",
        currentLine: "This is the current line",
        nextLine: "This is the next line coming up",
        upcomingNextLine: "And this one after that",
        activeIndex: 2,
        totalLines: 10,
        transitionProgress: 0,
        isTransitioning: false
    )

    KaraokeView(
        displayState: state,
        configuration: .default,
        beatIntensity: 0.5
    )
}

@available(macOS 15.0, *)
#Preview("Karaoke View - Mid Transition") {
    let state = KaraokeDisplayState(
        prevLine: "This was the previous line",
        currentLine: "This is the current line",
        nextLine: "This is the next line coming up",
        upcomingNextLine: "And this one after that",
        activeIndex: 2,
        totalLines: 10,
        transitionProgress: 0.5,
        isTransitioning: true
    )

    KaraokeView(
        displayState: state,
        configuration: .default,
        beatIntensity: 0.5
    )
}

@available(macOS 15.0, *)
#Preview("Karaoke View - Dramatic Preset") {
    let state = KaraokeDisplayState(
        prevLine: nil,
        currentLine: "Dancing in the moonlight",
        nextLine: "Everybody feeling warm and bright",
        upcomingNextLine: nil,
        activeIndex: 0,
        totalLines: 5,
        transitionProgress: 0,
        isTransitioning: false
    )

    KaraokeView(
        displayState: state,
        configuration: .dramatic,
        beatIntensity: 0.8
    )
}
