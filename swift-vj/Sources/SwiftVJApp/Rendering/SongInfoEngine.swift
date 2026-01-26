import Foundation
import SwiftUI

// MARK: - Song Info Display State

struct SongInfoDisplayState: Sendable, Equatable {
    let artist: String
    let title: String
    let isVisible: Bool
    let transitionProgress: Double
    let isTransitioning: Bool

    static let empty = SongInfoDisplayState(
        artist: "",
        title: "",
        isVisible: false,
        transitionProgress: 0,
        isTransitioning: false
    )

    var hasContent: Bool {
        !artist.isEmpty || !title.isEmpty
    }
}

// MARK: - Song Info Configuration

struct SongInfoConfiguration: Sendable, Equatable {
    var artistY: CGFloat = 0.44
    var titleY: CGFloat = 0.56
    var artistFontSize: CGFloat = 48
    var titleFontSize: CGFloat = 64
    var animationMode: TextAnimationMode = .fadeInOut
    var transitionDuration: TimeInterval = 0.6
    var fontWeight: Font.Weight = .bold
    var fontDesign: Font.Design = .rounded
    var textShadowRadius: CGFloat = 4
    var textShadowOpacity: Double = 0.5
    var maxLineWidthRatio: CGFloat = 0.85
    var canvasWidth: CGFloat = 1280
    var canvasHeight: CGFloat = 720

    var centerX: CGFloat { canvasWidth / 2 }
    var artistYAbsolute: CGFloat { artistY * canvasHeight }
    var titleYAbsolute: CGFloat { titleY * canvasHeight }
    var maxLineWidth: CGFloat { canvasWidth * maxLineWidthRatio }

    static let `default` = SongInfoConfiguration()
}

// MARK: - Song Info Engine

@MainActor
final class SongInfoEngine: ObservableObject {
    @Published private(set) var displayState: SongInfoDisplayState = .empty
    @Published var configuration: SongInfoConfiguration = .default

    private var animationTimer: Timer?
    private var transitionStartTime: Date?
    private var targetVisible: Bool = false

    func show(artist: String, title: String) {
        guard !artist.isEmpty || !title.isEmpty else { return }
        startTransition(artist: artist, title: title, targetVisible: true)
    }

    func hide() {
        guard displayState.hasContent else { return }
        startTransition(artist: displayState.artist, title: displayState.title, targetVisible: false)
    }

    func reset() {
        stopTransitionAnimation()
        displayState = .empty
        targetVisible = false
    }

    private func startTransition(artist: String, title: String, targetVisible: Bool) {
        stopTransitionAnimation()
        self.targetVisible = targetVisible
        transitionStartTime = Date()

        displayState = SongInfoDisplayState(
            artist: artist,
            title: title,
            isVisible: targetVisible,
            transitionProgress: targetVisible ? 0 : 1,
            isTransitioning: true
        )

        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickTransitionAnimation()
            }
        }
    }

    private func tickTransitionAnimation() {
        guard let startTime = transitionStartTime else {
            stopTransitionAnimation()
            return
        }

        let elapsed = Date().timeIntervalSince(startTime)
        let duration = max(0.1, configuration.transitionDuration)
        let t = min(elapsed / duration, 1.0)
        let progress = targetVisible ? t : (1.0 - t)

        displayState = SongInfoDisplayState(
            artist: displayState.artist,
            title: displayState.title,
            isVisible: targetVisible,
            transitionProgress: progress,
            isTransitioning: t < 1.0
        )

        if t >= 1.0 {
            stopTransitionAnimation()
            if !targetVisible {
                displayState = .empty
            }
        }
    }

    private func stopTransitionAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        transitionStartTime = nil
    }
}

// MARK: - Song Info View

struct SongInfoView: View {
    let displayState: SongInfoDisplayState
    let configuration: SongInfoConfiguration

    var body: some View {
        ZStack {
            Color.black

            if displayState.hasContent, displayState.transitionProgress > 0.01 {
                songInfoLine(
                    text: displayState.artist,
                    fontSize: configuration.artistFontSize,
                    yPosition: configuration.artistYAbsolute
                )

                songInfoLine(
                    text: displayState.title,
                    fontSize: configuration.titleFontSize,
                    yPosition: configuration.titleYAbsolute
                )
            }
        }
        .frame(width: configuration.canvasWidth, height: configuration.canvasHeight)
    }

    @ViewBuilder
    private func songInfoLine(text: String, fontSize: CGFloat, yPosition: CGFloat) -> some View {
        if text.isEmpty {
            EmptyView()
        } else {
            let progress = displayState.transitionProgress
            let isExiting = !displayState.isVisible
            let baseText = Text(text)
                .font(.system(size: fontSize, weight: configuration.fontWeight, design: configuration.fontDesign))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: configuration.maxLineWidth)

            Group {
                switch configuration.animationMode {
                case .instant:
                    baseText.opacity(progress)
                case .fadeInOut:
                    baseText.opacity(progress)
                case .waveDissolve:
                    if isExiting {
                        baseText.textRenderer(WaveDissolveRenderer(progress: progress, direction: 1.0))
                    } else {
                        baseText.textRenderer(WaveDissolveRenderer(progress: 1.0 - progress, direction: 1.0))
                            .opacity(progress)
                    }
                case .blurPop:
                    if isExiting {
                        baseText.textRenderer(BlurPopRenderer(progress: 1.0 - progress))
                    } else {
                        baseText.textRenderer(BlurPopRenderer(progress: progress))
                            .opacity(progress)
                    }
                case .springBounce:
                    if isExiting {
                        baseText.textRenderer(SpringBounceRenderer(progress: 1.0 - progress, bounceHeight: -30))
                    } else {
                        baseText.textRenderer(SpringBounceRenderer(progress: progress, bounceHeight: 30))
                            .opacity(progress)
                    }
                case .typewriter:
                    if isExiting {
                        baseText.textRenderer(TypewriterRenderer(progress: 1.0 - progress))
                    } else {
                        baseText.textRenderer(TypewriterRenderer(progress: progress))
                            .opacity(progress)
                    }
                case .glowPulse:
                    baseText.textRenderer(GlowPulseRenderer(intensity: progress))
                        .opacity(progress)
                case .rainbowWave:
                    baseText.textRenderer(RainbowWaveRenderer(phase: progress * 2))
                        .opacity(progress)
                }
            }
            .shadow(
                color: .black.opacity(configuration.textShadowOpacity),
                radius: configuration.textShadowRadius
            )
            .position(x: configuration.centerX, y: yPosition)
        }
    }
}
