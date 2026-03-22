// MoodboardLibraryPanel - Song library browser for the moodboard canvas

import SwiftUI
import SwiftVJCore
import SongRepository
import ShaderRepository

struct MoodboardLibraryPanel: View {
    @EnvironmentObject var appState: AppState

    @State private var searchText = ""
    @State private var selectedPhase: Phase?

    private var moodboard: MoodboardSubState { appState.moodboardState }

    private var songs: [Song] {
        appState.songsState.displayedSongs
    }

    private var filteredSongs: [Song] {
        var result = songs
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(query) ||
                $0.artist.lowercased().contains(query)
            }
        }
        if let phase = selectedPhase {
            result = result.filter { $0.phase == phase }
        }
        return result
    }

    private var nodeIdsOnCanvas: Set<String> {
        Set(moodboard.nodes.compactMap { $0.songId?.rawValue })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchField
            phaseFilterBar
            Divider()
            songList
            Divider()
            addAllButton
        }
        .frame(width: 250)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .accessibilityIdentifier(A11yID.moodboardLibrary)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("Library", systemImage: "music.note.list")
                .font(.headline)
            Spacer()
            Button {
                appState.send(.moodboard(.toggleLibraryPanel))
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
            TextField("Search songs…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Phase Filters

    private var phaseFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                phaseChip(nil, label: "All")
                ForEach(Phase.allCases, id: \.self) { phase in
                    phaseChip(phase, label: phase.displayName)
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 4)
    }

    private func phaseChip(_ phase: Phase?, label: String) -> some View {
        let isActive = selectedPhase == phase
        return Button {
            selectedPhase = phase
        } label: {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isActive ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.15))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Song List

    private var songList: some View {
        List {
            ForEach(filteredSongs) { song in
                songRow(song)
                    .onTapGesture {
                        appState.send(.moodboard(.showSongDetail(song.id)))
                    }
            }
        }
        .listStyle(.plain)
        .overlay {
            if filteredSongs.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "music.note")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("No songs found")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func songRow(_ song: Song) -> some View {
        let isOnCanvas = nodeIdsOnCanvas.contains(song.id.rawValue)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(song.artist)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)

            if let phase = song.phase {
                Text(phase.displayName)
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(phaseColor(phase).opacity(0.2))
                    .foregroundStyle(phaseColor(phase))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            if isOnCanvas {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                    .help("On canvas")
            }

            Button {
                addSongToCanvas(song)
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(isOnCanvas ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.accentColor))
            }
            .buttonStyle(.plain)
            .disabled(isOnCanvas)
            .help("Add to canvas")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    // MARK: - Add All

    private var addAllButton: some View {
        Button {
            for song in filteredSongs where !nodeIdsOnCanvas.contains(song.id.rawValue) {
                addSongToCanvas(song)
            }
        } label: {
            Label("Add All Filtered (\(filteredSongs.count))", systemImage: "plus.rectangle.on.rectangle")
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(8)
        .disabled(filteredSongs.isEmpty)
    }

    // MARK: - Helpers

    private func addSongToCanvas(_ song: Song) {
        let x = CGFloat.random(in: 100...600)
        let y = CGFloat.random(in: 100...400)
        appState.send(.moodboard(.addSongNode(song.id, position: CGPoint(x: x, y: y))))
    }

    private func phaseColor(_ phase: Phase) -> Color {
        switch phase {
        case .disco: return .cyan
        case .buildup: return .yellow
        case .peak: return .red
        case .release: return .blue
        case .feature: return .purple
        }
    }
}
