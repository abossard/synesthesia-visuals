// KaraokeLyricsPanel.swift - Full lyrics display with playhead and position
// Shows all lyrics, highlights current line, and displays playback position

import SwiftUI
import SwiftVJCore

// MARK: - Karaoke Lyrics Panel

/// Panel view showing full lyrics with current position and playhead indicator
struct KaraokeLyricsPanel: View {
    @ObservedObject var karaokeEngine: KaraokeEngine
    let playbackPosition: Double
    let isPlaying: Bool

    @State private var autoScroll: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            contentView
            Divider()
            footerView
        }
        .frame(minWidth: 400, minHeight: 500)
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        if karaokeEngine.displayState.hasLyrics {
            lyricsListView
        } else {
            emptyStateView
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Karaoke Lyrics")
                    .font(.headline)

                if karaokeEngine.displayState.hasLyrics {
                    Text("\(karaokeEngine.displayState.totalLines) lines")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatTime(playbackPosition))
                    .font(.system(.title2, design: .monospaced))
                    .fontWeight(.medium)

                HStack(spacing: 4) {
                    Circle()
                        .fill(isPlaying ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(isPlaying ? "Playing" : "Paused")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Lyrics List View

    private var lyricsListView: some View {
        LyricsScrollView(
            karaokeEngine: karaokeEngine,
            playbackPosition: playbackPosition,
            autoScroll: autoScroll
        )
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Lyrics Loaded")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Lyrics will appear here when a song with\nLRC data is playing")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Button("Load Test Lyrics") {
                karaokeEngine.loadTestLyrics()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Footer View

    private var footerView: some View {
        HStack {
            Toggle("Auto-scroll", isOn: $autoScroll)
                .toggleStyle(.checkbox)

            Spacer()

            if karaokeEngine.displayState.hasLyrics {
                progressSection
            }

            Spacer()

            navigationButtons
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var progressSection: some View {
        HStack {
            ProgressView(
                value: Double(max(0, karaokeEngine.activeLineIndex + 1)),
                total: Double(karaokeEngine.displayState.totalLines)
            )
            .frame(width: 100)

            Text(karaokeEngine.displayState.progressText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var navigationButtons: some View {
        HStack(spacing: 8) {
            Button {
                karaokeEngine.previousLine()
            } label: {
                Image(systemName: "backward.fill")
            }
            .buttonStyle(.bordered)
            .disabled(!karaokeEngine.displayState.hasLyrics)

            Button {
                karaokeEngine.nextLine()
            } label: {
                Image(systemName: "forward.fill")
            }
            .buttonStyle(.bordered)
            .disabled(!karaokeEngine.displayState.hasLyrics)
        }
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", mins, secs, ms)
    }
}

// MARK: - Lyrics Scroll View (extracted to help type checker)

private struct LyricsScrollView: View {
    @ObservedObject var karaokeEngine: KaraokeEngine
    let playbackPosition: Double
    let autoScroll: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                lyricsContent
            }
            .onChange(of: karaokeEngine.activeLineIndex) { _, newIndex in
                scrollToLine(newIndex, proxy: proxy)
            }
            .onAppear {
                scrollToLine(karaokeEngine.activeLineIndex, proxy: proxy)
            }
        }
    }

    private var lyricsContent: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<karaokeEngine.allLines.count, id: \.self) { index in
                makeLineRow(index: index)
            }
        }
        .padding(.vertical, 8)
    }

    private func makeLineRow(index: Int) -> some View {
        let line = karaokeEngine.allLines[index]
        let activeIndex = karaokeEngine.activeLineIndex

        return KaraokeLyricRow(
            line: line,
            index: index,
            isActive: index == activeIndex,
            isUpcoming: index == activeIndex + 1,
            isPast: index < activeIndex
        )
        .id(index)
    }

    private func scrollToLine(_ index: Int, proxy: ScrollViewProxy) {
        if autoScroll && index >= 0 {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(index, anchor: .center)
            }
        }
    }
}

// MARK: - Karaoke Lyric Row

private struct KaraokeLyricRow: View {
    let line: LyricLine
    let index: Int
    let isActive: Bool
    let isUpcoming: Bool
    let isPast: Bool

    var body: some View {
        HStack(spacing: 12) {
            playheadIndicator
            timecodeText
            lyricText
            Spacer()
            lineNumber
        }
        .padding(.horizontal, 16)
        .padding(.vertical, isActive ? 12 : 8)
        .background(backgroundColor)
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var playheadIndicator: some View {
        if isActive {
            Image(systemName: "play.fill")
                .font(.system(size: 10))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Color.blue)
                .clipShape(Circle())
        } else if isUpcoming {
            Circle()
                .strokeBorder(Color.blue.opacity(0.5), lineWidth: 1.5)
                .frame(width: 16, height: 16)
        } else if isPast {
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
        } else {
            Circle()
                .strokeBorder(Color.gray.opacity(0.3), lineWidth: 1)
                .frame(width: 16, height: 16)
        }
    }

    private var timecodeText: some View {
        Text(formatTimecode(line.timeSec))
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(isActive ? .primary : .secondary)
            .frame(width: 50, alignment: .trailing)
    }

    private var lyricText: some View {
        Text(line.text)
            .font(.system(size: isActive ? 16 : 14, weight: isActive ? .semibold : .regular))
            .foregroundStyle(textColor)
            .lineLimit(2)
    }

    private var lineNumber: some View {
        Text("\(index + 1)")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
            .frame(width: 24)
    }

    // MARK: - Computed Properties

    private var textColor: Color {
        if isActive { return .primary }
        if isUpcoming { return .blue }
        if isPast { return .secondary }
        return .primary.opacity(0.7)
    }

    private var backgroundColor: Color {
        if isActive { return Color.blue.opacity(0.15) }
        if isUpcoming { return Color.blue.opacity(0.05) }
        return Color.clear
    }

    private func formatTimecode(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Standalone Window View

/// Wrapper for presenting KaraokeLyricsPanel in its own window
struct KaraokeLyricsPanelWindow: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if let karaokeEngine = appState.renderEngine?.karaokeEngine {
                KaraokeLyricsPanel(
                    karaokeEngine: karaokeEngine,
                    playbackPosition: appState.playbackPosition,
                    isPlaying: appState.isPlaying
                )
            } else {
                noEngineView
            }
        }
    }

    private var noEngineView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Render Engine Not Running")
                .font(.headline)

            Text("Start the render engine to view karaoke lyrics")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 400, minHeight: 300)
        .padding()
    }
}

// MARK: - Preview

#Preview("Karaoke Lyrics Panel") {
    let engine = KaraokeEngine()
    engine.loadTestLyrics()

    return KaraokeLyricsPanel(
        karaokeEngine: engine,
        playbackPosition: 12.5,
        isPlaying: true
    )
    .frame(width: 500, height: 600)
}

#Preview("Empty State") {
    KaraokeLyricsPanel(
        karaokeEngine: KaraokeEngine(),
        playbackPosition: 0,
        isPlaying: false
    )
    .frame(width: 500, height: 600)
}
