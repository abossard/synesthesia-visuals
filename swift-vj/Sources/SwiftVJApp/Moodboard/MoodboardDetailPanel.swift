// MoodboardDetailPanel - Song detail and tag editor for the moodboard

import SwiftUI
import SwiftVJCore
import SongRepository
import ShaderRepository

struct MoodboardDetailPanel: View {
    @EnvironmentObject var appState: AppState

    @State private var newTagText = ""
    @State private var newTagCategory: TagCategory = .custom
    @State private var connectionTarget: SongID?
    @State private var connectionType: EdgeType = .custom

    private var moodboard: MoodboardSubState { appState.moodboardState }

    private var songId: SongID? { moodboard.detailPanelSongId }

    private var song: Song? {
        guard let songId else { return nil }
        return appState.songsState.displayedSongs.first { $0.id == songId }
    }

    private var connectedEdges: [MoodboardEdge] {
        guard let songId else { return [] }
        let nodeId = "song:\(songId.rawValue)"
        return moodboard.edges.filter { $0.sourceId == nodeId || $0.targetId == nodeId }
    }

    private var canvasSongs: [Song] {
        let songIds = Set(moodboard.nodes.compactMap { $0.songId })
        return appState.songsState.displayedSongs.filter { songIds.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let song {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        metadataSection(song)
                        Divider()
                        tagsSection(song)
                        Divider()
                        connectionsSection
                        Divider()
                        similarSongsSection
                    }
                    .padding(12)
                }
            } else {
                noSongPlaceholder
            }
        }
        .frame(width: 300)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .accessibilityIdentifier(A11yID.moodboardDetail)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("Song Detail", systemImage: "info.circle")
                .font(.headline)
            Spacer()
            Button {
                appState.send(.moodboard(.showSongDetail(nil)))
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Metadata

    private func metadataSection(_ song: Song) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(song.title)
                .font(.title3.bold())
                .lineLimit(2)
            Text(song.artist)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !song.album.isEmpty {
                Text(song.album)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                if song.bpm > 0 {
                    metadataChip("BPM", value: String(format: "%.0f", song.bpm))
                }
                if !song.musicalKey.isEmpty {
                    metadataChip("Key", value: song.musicalKey)
                }
            }

            // Energy bar
            VStack(alignment: .leading, spacing: 3) {
                Text("Energy")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.2))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(energyGradient(song.energyScore))
                            .frame(width: geo.size.width * song.energyScore)
                    }
                }
                .frame(height: 8)
            }

            if song.mood != "unknown" {
                HStack(spacing: 4) {
                    Text("Mood:")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(song.mood)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func metadataChip(_ label: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
    }

    // MARK: - Tags Section

    private func tagsSection(_ song: Song) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.system(size: 12, weight: .bold))

            // Phase
            if let phase = song.phase {
                tagRow(category: "Phase") {
                    removableTag(
                        label: phase.displayName,
                        color: phaseColor(phase)
                    ) {
                        appState.send(.moodboard(.removeTagFromSong(
                            song.id, label: phase.rawValue, category: .phase
                        )))
                    }
                }
            }

            // Mood
            if song.mood != "unknown" {
                tagRow(category: "Mood") {
                    removableTag(label: song.mood, color: .purple) {
                        appState.send(.moodboard(.removeTagFromSong(
                            song.id, label: song.mood, category: .mood
                        )))
                    }
                }
            }

            // Keywords
            if !song.keywords.isEmpty {
                tagRow(category: "Keywords") {
                    MoodboardFlowLayout(spacing: 4) {
                        ForEach(song.keywords, id: \.self) { keyword in
                            removableTag(label: keyword, color: .orange) {
                                appState.send(.moodboard(.removeTagFromSong(
                                    song.id, label: keyword, category: .custom
                                )))
                            }
                        }
                    }
                }
            }

            // Add tag
            addTagRow(song)
        }
    }

    @ViewBuilder
    private func tagRow<Content: View>(category: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(category)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func removableTag(label: String, color: Color, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }

    private func addTagRow(_ song: Song) -> some View {
        HStack(spacing: 4) {
            Picker("", selection: $newTagCategory) {
                ForEach(TagCategory.allCases, id: \.self) { cat in
                    Text(cat.rawValue.capitalized).tag(cat)
                }
            }
            .labelsHidden()
            .frame(width: 80)

            TextField("New tag…", text: $newTagText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .onSubmit { submitTag(song) }

            Button {
                submitTag(song)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .disabled(newTagText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func submitTag(_ song: Song) {
        let label = newTagText.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { return }
        appState.send(.moodboard(.addTagToSong(song.id, label: label, category: newTagCategory)))
        newTagText = ""
    }

    // MARK: - Connections Section

    @ViewBuilder
    private var connectionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connections")
                .font(.system(size: 12, weight: .bold))

            if connectedEdges.isEmpty {
                Text("No connections")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(connectedEdges) { edge in
                    connectionRow(edge)
                }
            }

            addConnectionRow
        }
    }

    private func connectionRow(_ edge: MoodboardEdge) -> some View {
        let otherNodeId = edge.sourceId == "song:\(songId?.rawValue ?? "")"
            ? edge.targetId : edge.sourceId
        let otherSong = lookupSongForNodeId(otherNodeId)

        return HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(otherSong?.displayName ?? otherNodeId)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(edge.edgeType.rawValue)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text("w: \(String(format: "%.1f", edge.weight))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button {
                appState.send(.moodboard(.removeEdge(edge.id)))
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove connection")
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var addConnectionRow: some View {
        let otherSongs = canvasSongs.filter { $0.id != songId }
        if !otherSongs.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add Connection")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Picker("To", selection: $connectionTarget) {
                        Text("Select…").tag(nil as SongID?)
                        ForEach(otherSongs) { s in
                            Text(s.displayName).tag(s.id as SongID?)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                    Picker("Type", selection: $connectionType) {
                        ForEach(EdgeType.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 80)

                    Button {
                        guard let songId, let target = connectionTarget else { return }
                        appState.send(.moodboard(.connectNodes(
                            sourceId: "song:\(songId.rawValue)",
                            targetId: "song:\(target.rawValue)",
                            edgeType: connectionType,
                            weight: 1.0
                        )))
                        connectionTarget = nil
                    } label: {
                        Image(systemName: "link.badge.plus")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .disabled(connectionTarget == nil)
                }
            }
        }
    }

    // MARK: - Similar Songs

    @ViewBuilder
    private var similarSongsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Similar Songs")
                .font(.system(size: 12, weight: .bold))

            let similar = findSimilarSongs()
            if similar.isEmpty {
                Text("No similar songs found")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(similar, id: \.song.id) { entry in
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.song.title)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Text(entry.song.artist)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text("\(Int(entry.score * 100))%")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }

    // MARK: - No Song Placeholder

    private var noSongPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Select a song to view details")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func lookupSongForNodeId(_ nodeId: String) -> Song? {
        guard nodeId.hasPrefix("song:") else { return nil }
        let rawId = String(nodeId.dropFirst(5))
        return appState.songsState.displayedSongs.first { $0.id.rawValue == rawId }
    }

    private func energyGradient(_ energy: Double) -> LinearGradient {
        let color: Color = energy > 0.7 ? .red : energy > 0.4 ? .orange : .green
        return LinearGradient(
            colors: [color.opacity(0.6), color],
            startPoint: .leading,
            endPoint: .trailing
        )
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

    private struct SimilarEntry {
        let song: Song
        let score: Double
    }

    private func findSimilarSongs() -> [SimilarEntry] {
        guard let song else { return [] }
        let myVector = song.featureVector
        guard myVector.count >= 2 else { return [] }

        return canvasSongs
            .filter { $0.id != song.id }
            .compactMap { other in
                let otherVec = other.featureVector
                guard otherVec.count >= 2 else { return nil }
                let dist = sqrt(zip(myVector, otherVec).map { pow($0 - $1, 2) }.reduce(0, +))
                let score = max(0, 1.0 - dist)
                return SimilarEntry(song: other, score: score)
            }
            .sorted { $0.score > $1.score }
            .prefix(5)
            .map { $0 }
    }
}

// MARK: - Flow Layout

private struct MoodboardFlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        for (i, row) in rows.enumerated() {
            let rowHeight = row.map { subviews[$0].sizeThatFits(.unspecified).height }.max() ?? 0
            height += rowHeight + (i > 0 ? spacing : 0)
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            let rowHeight = row.map { subviews[$0].sizeThatFits(.unspecified).height }.max() ?? 0
            var x = bounds.minX
            for index in row {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[Int]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[Int]] = [[]]
        var currentWidth: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if currentWidth + size.width > maxWidth && !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentWidth = 0
            }
            rows[rows.count - 1].append(index)
            currentWidth += size.width + spacing
        }
        return rows
    }
}
