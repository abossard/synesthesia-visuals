// TextTiles.swift - Text rendering tiles for lyrics, refrain, and song info
// Port of TextlerMultiTile from Tile.pde

import Foundation
import Metal
import CoreGraphics
import AppKit

// MARK: - Lyrics Tile

/// Displays prev/current/next lyrics with visual hierarchy
/// Port of TextlerMultiTile renderLyrics() from Tile.pde:757-821
final class LyricsTile: TextTile {
    private var state: LyricsDisplayState = .empty

    init(device: MTLDevice) {
        super.init(device: device, config: .lyrics)
    }

    func updateState(_ newState: LyricsDisplayState) {
        state = newState
    }

    override func update(audioState: AudioState, deltaTime: Float) {
        // Fade logic is handled externally via state updates
    }

    override func render(commandBuffer: MTLCommandBuffer) {
        guard let ctx = context else { return }

        clearContext()

        guard state.activeIndex >= 0 else {
            uploadToTexture(commandBuffer: commandBuffer)
            return
        }

        let maxWidth = CGFloat(config.width) * 0.92

        // Get lines
        let prevText = state.prevLine ?? ""
        let currText = state.currentLine ?? ""
        let nextText = state.nextLine ?? ""

        // Auto-size based on longest line
        let allTexts = [prevText, currText, nextText].filter { !$0.isEmpty }
        var autoSize: CGFloat = 72

        for text in allTexts {
            let size = calcAutoFitFontSize(for: text, maxWidth: maxWidth, minSize: 28, maxSize: 96)
            autoSize = min(autoSize, size)
        }
        autoSize = min(autoSize, 96)

        // Previous line: 70% size, 35% opacity, y = 0.28
        if !prevText.isEmpty {
            drawText(
                prevText,
                fontSize: autoSize * 0.7,
                opacity: CGFloat(state.textOpacity) * 0.35,
                yPosition: 0.28,
                context: ctx
            )
        }

        // Current line: 100% size, 100% opacity, y = 0.50
        if !currText.isEmpty {
            drawText(
                currText,
                fontSize: autoSize,
                opacity: CGFloat(state.textOpacity),
                yPosition: 0.50,
                context: ctx
            )
        }

        // Next line: 70% size, 25% opacity, y = 0.72
        if !nextText.isEmpty {
            drawText(
                nextText,
                fontSize: autoSize * 0.7,
                opacity: CGFloat(state.textOpacity) * 0.25,
                yPosition: 0.72,
                context: ctx
            )
        }

        uploadToTexture(commandBuffer: commandBuffer)
    }

    override var statusString: String {
        guard state.activeIndex >= 0 else { return "No lyrics" }
        return "Line \(state.activeIndex + 1)/\(state.lines.count)"
    }
}

// MARK: - Refrain Tile

/// Displays refrain/chorus text (larger, centered)
/// Port of TextlerMultiTile renderRefrain() from Tile.pde:824-851
final class RefrainTile: TextTile {
    private var state: RefrainDisplayState = .empty

    init(device: MTLDevice) {
        super.init(device: device, config: .refrain)
    }

    func updateState(_ newState: RefrainDisplayState) {
        state = newState
    }

    override func update(audioState: AudioState, deltaTime: Float) {
        // Fade logic is handled externally via state updates
    }

    override func render(commandBuffer: MTLCommandBuffer) {
        guard let ctx = context else { return }

        clearContext()

        guard !state.text.isEmpty, state.opacity > 0.01 else {
            uploadToTexture(commandBuffer: commandBuffer)
            return
        }

        let maxWidth = CGFloat(config.width) * 0.85
        let fontSize = calcAutoFitFontSize(for: state.text, maxWidth: maxWidth, minSize: 36, maxSize: 120)

        // Refrain: larger font, centered
        drawText(
            state.text,
            fontSize: fontSize,
            opacity: CGFloat(state.opacity),
            yPosition: 0.50,
            context: ctx
        )

        uploadToTexture(commandBuffer: commandBuffer)
    }

    override var statusString: String {
        state.active ? "Active" : "Inactive"
    }
}

// MARK: - Song Info Tile

/// Displays artist/title with fade-in/hold/fade-out envelope
/// Port of TextlerMultiTile renderSongInfo() from Tile.pde:853-878
final class SongInfoTile: TextTile {
    private var state: SongInfoDisplayState = .empty

    init(device: MTLDevice) {
        super.init(device: device, config: .songInfo)
    }

    func updateState(_ newState: SongInfoDisplayState) {
        state = newState
    }

    override func update(audioState: AudioState, deltaTime: Float) {
        // Fade logic handled via state.computeOpacity()
    }

    override func render(commandBuffer: MTLCommandBuffer) {
        guard let ctx = context else { return }

        clearContext()

        let opacity = state.computeOpacity()
        guard state.active, opacity > 0.01,
              !state.artist.isEmpty || !state.title.isEmpty else {
            uploadToTexture(commandBuffer: commandBuffer)
            return
        }

        let baseFontSize: CGFloat = 72

        // Artist (smaller, above center) - y = 0.42
        if !state.artist.isEmpty {
            let artistSize = calcAutoFitFontSize(
                for: state.artist,
                maxWidth: CGFloat(config.width) * 0.8,
                minSize: 24,
                maxSize: baseFontSize * 0.65
            )
            drawText(
                state.artist,
                fontSize: artistSize,
                opacity: CGFloat(opacity),
                yPosition: 0.42,
                context: ctx
            )
        }

        // Title (larger, below center) - y = 0.55
        if !state.title.isEmpty {
            let titleSize = calcAutoFitFontSize(
                for: state.title,
                maxWidth: CGFloat(config.width) * 0.8,
                minSize: 28,
                maxSize: baseFontSize
            )
            drawText(
                state.title,
                fontSize: titleSize,
                opacity: CGFloat(opacity),
                yPosition: 0.55,
                context: ctx
            )
        }

        uploadToTexture(commandBuffer: commandBuffer)
    }

    override var statusString: String {
        if state.artist.isEmpty && state.title.isEmpty {
            return "No track"
        }
        if !state.artist.isEmpty && !state.title.isEmpty {
            return "\(state.artist) - \(state.title)"
        }
        return state.artist.isEmpty ? state.title : state.artist
    }
}

// MARK: - Text State Manager

/// Manages all text tile states
/// Use this to update lyrics, refrain, and song info from pipeline events
@MainActor
final class TextStateManager: ObservableObject {
    @Published private(set) var lyricsState: LyricsDisplayState = .empty
    @Published private(set) var refrainState: RefrainDisplayState = .empty
    @Published private(set) var songInfoState: SongInfoDisplayState = .empty

    // Internal fade tracking
    private var lyricsLastChangeTime: Date = .distantPast
    private var refrainLastChangeTime: Date = .distantPast
    private var songInfoLastChangeTime: Date = .distantPast

    // Fade parameters
    private let lyricsFadeDelay: Float = 5.0
    private let lyricsFadeDuration: Float = 1.0
    private let refrainFadeDelay: Float = 2.0
    private let refrainFadeDuration: Float = 1.0

    private var updateTimer: Timer?

    init() {}

    func start() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateFades()
            }
        }
    }

    func stop() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    // MARK: - Lyrics

    func setLyrics(_ lines: [LyricLine]) {
        lyricsState = LyricsDisplayState(
            lines: lines,
            activeIndex: lyricsState.activeIndex,
            textOpacity: lyricsState.textOpacity,
            fadeDelayMs: lyricsState.fadeDelayMs,
            fadeDurationMs: lyricsState.fadeDurationMs,
            lastChangeTime: lyricsState.lastChangeTime
        )
    }

    func setActiveLine(_ index: Int) {
        guard index != lyricsState.activeIndex else { return }
        lyricsLastChangeTime = Date()
        lyricsState = LyricsDisplayState(
            lines: lyricsState.lines,
            activeIndex: index,
            textOpacity: 255,
            fadeDelayMs: lyricsState.fadeDelayMs,
            fadeDurationMs: lyricsState.fadeDurationMs,
            lastChangeTime: lyricsLastChangeTime
        )
    }

    func clearLyrics() {
        lyricsState = .empty
    }

    // MARK: - Refrain

    func setRefrain(_ text: String) {
        guard text != refrainState.text else { return }
        refrainLastChangeTime = Date()
        refrainState = RefrainDisplayState(
            text: text,
            opacity: 255,
            active: !text.isEmpty,
            lastChangeTime: refrainLastChangeTime
        )
    }

    func clearRefrain() {
        refrainState = .empty
    }

    // MARK: - Song Info

    func setSongInfo(artist: String, title: String, album: String = "") {
        guard artist != songInfoState.artist || title != songInfoState.title else { return }
        songInfoLastChangeTime = Date()
        songInfoState = SongInfoDisplayState(
            artist: artist,
            title: title,
            album: album,
            opacity: 255,
            displayTime: 0,
            active: !artist.isEmpty || !title.isEmpty,
            lastChangeTime: songInfoLastChangeTime
        )
    }

    func clearSongInfo() {
        songInfoState = .empty
    }

    // MARK: - Fade Updates

    private func updateFades() {
        let now = Date()

        // Update lyrics fade
        let lyricsElapsed = Float(now.timeIntervalSince(lyricsLastChangeTime))
        var lyricsOpacity: Float = 255
        if lyricsElapsed > lyricsFadeDelay {
            let fadeProgress = min(1.0, (lyricsElapsed - lyricsFadeDelay) / lyricsFadeDuration)
            lyricsOpacity = 255 * (1.0 - fadeProgress)
        }
        if lyricsOpacity != lyricsState.textOpacity {
            lyricsState = LyricsDisplayState(
                lines: lyricsState.lines,
                activeIndex: lyricsState.activeIndex,
                textOpacity: lyricsOpacity,
                fadeDelayMs: lyricsState.fadeDelayMs,
                fadeDurationMs: lyricsState.fadeDurationMs,
                lastChangeTime: lyricsState.lastChangeTime
            )
        }

        // Update refrain fade
        let refrainElapsed = Float(now.timeIntervalSince(refrainLastChangeTime))
        var refrainOpacity: Float = 255
        if refrainElapsed > refrainFadeDelay {
            let fadeProgress = min(1.0, (refrainElapsed - refrainFadeDelay) / refrainFadeDuration)
            refrainOpacity = 255 * (1.0 - fadeProgress)
        }
        if refrainOpacity != refrainState.opacity {
            refrainState = RefrainDisplayState(
                text: refrainState.text,
                opacity: refrainOpacity,
                active: refrainState.active,
                lastChangeTime: refrainState.lastChangeTime
            )
        }

        // Update song info display time
        let songInfoElapsed = Float(now.timeIntervalSince(songInfoLastChangeTime))
        if songInfoElapsed != songInfoState.displayTime {
            songInfoState = SongInfoDisplayState(
                artist: songInfoState.artist,
                title: songInfoState.title,
                album: songInfoState.album,
                opacity: songInfoState.opacity,
                displayTime: songInfoElapsed,
                active: songInfoState.active && songInfoElapsed < SongInfoDisplayState.totalDuration,
                lastChangeTime: songInfoState.lastChangeTime
            )
        }
    }
}
