import SwiftUI
import SwiftVJCore
import SongRepository

struct PreviewBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var isDraggingTimeline = false
    @State private var dragPosition: Double = 0

    private var preview: PreviewSubState { appState.previewState }
    private var isActive: Bool { preview.currentSongId != nil }

    private var currentSong: Song? {
        guard let songId = preview.currentSongId else { return nil }
        return appState.songsState.displayedSongs.first { $0.id == songId }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Clickable timeline
            timelineBar

            // Controls row
            HStack(spacing: 8) {
                transportControls
                songLabel
                Spacer()
                timeDisplay

                Divider()
                    .frame(height: 16)

                previewStartControls
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Timeline

    private var timelineBar: some View {
        GeometryReader { geo in
            let duration = max(preview.duration, 0.01)
            let displayPosition = isDraggingTimeline ? dragPosition : preview.currentPosition
            let fraction = displayPosition / duration

            ZStack(alignment: .leading) {
                // Track background
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))

                // Progress fill
                Rectangle()
                    .fill(isActive ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.1))
                    .frame(width: geo.size.width * fraction)

                // Playhead
                if isActive {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2)
                        .offset(x: geo.size.width * fraction - 1)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDraggingTimeline = true
                        let frac = max(0, min(1, value.location.x / geo.size.width))
                        dragPosition = frac * duration
                    }
                    .onEnded { value in
                        let frac = max(0, min(1, value.location.x / geo.size.width))
                        let seekPos = frac * duration
                        appState.send(.preview(.seekTo(seekPos)))
                        isDraggingTimeline = false
                    }
            )
        }
        .frame(height: 6)
    }

    // MARK: - Transport Controls

    private var transportControls: some View {
        HStack(spacing: 6) {
            Button {
                appState.send(.preview(.stop))
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(isActive ? .primary : .tertiary)
            }
            .buttonStyle(.plain)
            .disabled(!isActive)

            Button {
                if preview.isPlaying {
                    appState.send(.preview(.pause))
                } else if preview.currentSongId != nil {
                    appState.send(.preview(.resume))
                }
            } label: {
                Image(systemName: preview.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(isActive ? .primary : .tertiary)
            }
            .buttonStyle(.plain)
            .disabled(!isActive)
        }
    }

    // MARK: - Song Label

    @ViewBuilder
    private var songLabel: some View {
        if let song = currentSong {
            Text("\(song.title) — \(song.artist)")
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 80)
        } else {
            Text("No preview")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Time Display

    private var timeDisplay: some View {
        let pos = isDraggingTimeline ? dragPosition : preview.currentPosition
        return Text("\(formatTime(pos)) / \(formatTime(preview.duration))")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(isActive ? .secondary : .tertiary)
    }

    // MARK: - Preview Start Controls

    private var previewStartControls: some View {
        HStack(spacing: 4) {
            Text("Start")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Stepper(
                value: Binding(
                    get: { preview.previewStartSeconds },
                    set: { appState.send(.preview(.setPreviewStartSeconds($0))) }
                ),
                in: 0...120,
                step: 5
            ) {
                Text("\(preview.previewStartSeconds)s")
                    .font(.system(size: 10, design: .monospaced))
                    .frame(width: 30, alignment: .trailing)
            }
            .controlSize(.mini)
        }
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
