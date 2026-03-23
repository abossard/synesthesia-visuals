import SwiftUI
import SwiftVJCore
import SongRepository

struct PreviewBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var sliderPosition: Double = 0
    @State private var isDraggingPosition = false
    @State private var startOffset: Double = 0

    private var preview: PreviewSubState { appState.previewState }

    private var currentSong: Song? {
        guard let songId = preview.currentSongId else { return nil }
        return appState.songsState.displayedSongs.first { $0.id == songId }
    }

    var body: some View {
        HStack(spacing: 8) {
            transportControls
            songLabel
            positionSlider
            timeDisplay

            Divider()
                .frame(height: 16)

            previewStartControls
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(.ultraThinMaterial)
        .onAppear {
            sliderPosition = preview.currentPosition
            startOffset = preview.previewStartOffset
        }
    }

    // MARK: - Subviews

    private var transportControls: some View {
        HStack(spacing: 4) {
            Button("Stop", systemImage: "xmark.circle") {
                appState.send(.preview(.stop))
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)

            Button(preview.isPlaying ? "Pause" : "Play",
                   systemImage: preview.isPlaying ? "pause.fill" : "play.fill") {
                appState.send(.preview(preview.isPlaying ? .pause : .resume))
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var songLabel: some View {
        if let song = currentSong {
            Text("\(song.title) — \(song.artist)")
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 80)
        }
    }

    private var positionSlider: some View {
        Slider(value: $sliderPosition,
               in: 0...max(preview.duration, 0.01)) { editing in
            isDraggingPosition = editing
            if !editing {
                appState.send(.preview(.seekTo(sliderPosition)))
            }
        }
        .frame(minWidth: 120)
        .onChange(of: preview.currentPosition) {
            if !isDraggingPosition {
                sliderPosition = preview.currentPosition
            }
        }
    }

    private var timeDisplay: some View {
        Text("\(formatTime(sliderPosition)) / \(formatTime(preview.duration))")
            .font(.system(size: 10))
            .monospacedDigit()
    }

    private var previewStartControls: some View {
        HStack(spacing: 4) {
            Text("Start at")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Slider(value: $startOffset, in: 0...1)
                .frame(width: 80)
                .onChange(of: startOffset) {
                    appState.send(.preview(.setPreviewStart(startOffset)))
                }
                .onChange(of: preview.previewStartOffset) {
                    startOffset = preview.previewStartOffset
                }

            Text("\(Int(startOffset * 100))%")
                .font(.system(size: 10))
                .monospacedDigit()
                .frame(width: 30, alignment: .trailing)
        }
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
