// AudioPreviewAdapter - Audio preview playback for song previewing

import AVFoundation

/// Delegate bridge for AVAudioPlayer completion (must be a class for NSObject)
private final class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    var onFinished: (() -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinished?()
    }
}

/// Actor-based audio preview adapter for playing local audio files.
/// Provides position polling and completion callbacks for UDF integration.
public actor AudioPreviewAdapter {
    private var player: AVAudioPlayer?
    private var positionTimer: DispatchSourceTimer?
    private let playerDelegate = AudioPlayerDelegate()

    /// Called on position updates (position, duration) — hop to @MainActor before dispatching
    public var onPositionUpdate: (@Sendable (Double, Double) -> Void)?

    /// Called when playback reaches end of track
    public var onPlaybackFinished: (@Sendable () -> Void)?

    public init() {
        playerDelegate.onFinished = { [weak self] in
            guard let self else { return }
            Task { await self.handlePlaybackFinished() }
        }
    }

    // MARK: - Public API

    /// Set position update and playback finished callbacks
    public func setCallbacks(
        onPosition: @escaping @Sendable (Double, Double) -> Void,
        onFinished: @escaping @Sendable () -> Void
    ) {
        onPositionUpdate = onPosition
        onPlaybackFinished = onFinished
    }

    /// Start playing an audio file from a given position
    public func play(url: URL, startPosition: Double = 0) {
        stopInternal()

        guard FileManager.default.fileExists(atPath: url.path) else {
            print("[AudioPreview] File not found: \(url.path)")
            return
        }

        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.delegate = playerDelegate
            newPlayer.prepareToPlay()

            if startPosition > 0 && startPosition < newPlayer.duration {
                newPlayer.currentTime = startPosition
            }

            newPlayer.play()
            player = newPlayer
            startPositionTimer()
            print("[AudioPreview] Playing: \(url.lastPathComponent) from \(String(format: "%.1f", startPosition))s")
        } catch {
            print("[AudioPreview] Failed to play: \(error.localizedDescription)")
        }
    }

    /// Pause current playback
    public func pause() {
        player?.pause()
        stopPositionTimer()
    }

    /// Resume paused playback
    public func resume() {
        player?.play()
        startPositionTimer()
    }

    /// Stop playback and release resources
    public func stop() {
        stopInternal()
    }

    /// Seek to a position in seconds
    public func seek(to seconds: Double) {
        guard let player else { return }
        let clampedTime = max(0, min(seconds, player.duration))
        player.currentTime = clampedTime
    }

    /// Whether audio is currently playing
    public var isPlaying: Bool {
        player?.isPlaying ?? false
    }

    /// Current playback position in seconds
    public var currentPosition: Double {
        player?.currentTime ?? 0
    }

    /// Total duration of current track in seconds
    public var duration: Double {
        player?.duration ?? 0
    }

    // MARK: - Internal

    private func stopInternal() {
        stopPositionTimer()
        player?.stop()
        player = nil
    }

    private func startPositionTimer() {
        stopPositionTimer()

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            Task {
                await self.firePositionUpdate()
            }
        }
        timer.resume()
        positionTimer = timer
    }

    private func stopPositionTimer() {
        positionTimer?.cancel()
        positionTimer = nil
    }

    private func firePositionUpdate() {
        guard let player, player.isPlaying else { return }
        onPositionUpdate?(player.currentTime, player.duration)
    }

    private func handlePlaybackFinished() {
        stopPositionTimer()
        onPlaybackFinished?()
    }
}
