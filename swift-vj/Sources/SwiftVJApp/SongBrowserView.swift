// SongBrowserView - Browse, search, and manage saved songs
// Songs management UI for the VJ app

import SwiftUI
import SwiftVJCore
import SongRepository
import AppKit

struct SongBrowserView: View {
    @EnvironmentObject var appState: AppState

    // Local UI state
    @State private var searchText = ""
    @State private var selectedMood: String? = nil
    @State private var selectedPhase: Phase? = nil
    @State private var sortOrder: SongSortOrder = .recentlyPlayed
    @State private var showDeleteConfirm = false
    @State private var songToDelete: Song? = nil
    @State private var selectedSong: Song? = nil

    var body: some View {
        HSplitView {
            // Left: Song list with filters
            VStack(spacing: 0) {
                // Search bar
                searchBar

                // Filter toolbar
                filterToolbar

                // Statistics header
                statisticsHeader

                Divider()

                // Song list
                songList
            }
            .frame(minWidth: 350, idealWidth: 400)

            // Right: Song detail
            songDetailView
        }
        .onAppear {
            loadSongs()
        }
        .onChange(of: appState.songsState.displayedSongs) { _, newSongs in
            if let current = selectedSong,
               let updated = newSongs.first(where: { $0.id == current.id }) {
                selectedSong = updated
            }
        }
        .alert("Delete Song?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let song = songToDelete {
                    deleteSong(song)
                }
            }
        } message: {
            if let song = songToDelete {
                Text("Delete \"\(song.displayName)\" from the database? This cannot be undone.")
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search songs...", text: $searchText)
                .textFieldStyle(.plain)
                .onSubmit {
                    performSearch()
                }

            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    clearFilter()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color(.textBackgroundColor))
        .cornerRadius(8)
        .padding()
    }

    // MARK: - Filter Toolbar

    private var filterToolbar: some View {
        VStack(alignment: .leading, spacing: 12) {
            currentPhaseSelector

            ViewThatFits {
                HStack(alignment: .center, spacing: 12) {
                    moodPicker
                    phasePicker
                    sortPicker
                    Spacer(minLength: 0)
                    applyButton
                    clearAllCachesButton
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        moodPicker
                        phasePicker
                    }
                    HStack(spacing: 12) {
                        sortPicker
                        applyButton
                        clearAllCachesButton
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(.windowBackgroundColor).opacity(0.5))
        .cornerRadius(10)
        .padding(.horizontal)
    }

    private var currentPhaseSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Current Phase")
                .font(.caption)
                .foregroundColor(.secondary)

            Picker("Current Phase", selection: appState.phaseBinding) {
                Text("None").tag(nil as Phase?)
                ForEach(Phase.allCases, id: \.self) { phase in
                    Label(phase.displayName, systemImage: phase.iconName)
                        .tag(phase as Phase?)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var moodPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Mood")
                .font(.caption)
                .foregroundColor(.secondary)

            Picker("Mood", selection: $selectedMood) {
                Text("All Moods").tag(nil as String?)
                ForEach(availableMoods, id: \.self) { mood in
                    Text(mood.capitalized).tag(mood as String?)
                }
            }
            .frame(minWidth: 160)
        }
    }

    private var phasePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Phase")
                .font(.caption)
                .foregroundColor(.secondary)

            Picker("Phase", selection: $selectedPhase) {
                Text("All Phases").tag(nil as Phase?)
                ForEach(Phase.allCases, id: \.self) { phase in
                    Label(phase.displayName, systemImage: phase.iconName)
                        .tag(phase as Phase?)
                }
            }
            .frame(minWidth: 160)
        }
    }

    private var sortPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sort")
                .font(.caption)
                .foregroundColor(.secondary)

            Picker("Sort", selection: $sortOrder) {
                ForEach(SongSortOrder.allCases, id: \.self) { order in
                    Label(order.rawValue, systemImage: order.iconName)
                        .tag(order)
                }
            }
            .frame(minWidth: 150)
        }
    }

    private var applyButton: some View {
        Button(action: applyFilters) {
            Label("Apply", systemImage: "line.3.horizontal.decrease.circle")
        }
        .buttonStyle(.bordered)
    }

    private var clearAllCachesButton: some View {
        Button(action: clearAllCaches) {
            Label("Clear All Caches", systemImage: "trash.circle")
        }
        .buttonStyle(.bordered)
        .tint(.orange)
    }

    // MARK: - Statistics Header

    private var statisticsHeader: some View {
        HStack(spacing: 16) {
            if let stats = appState.songsState.statistics {
                StatBadge(label: "Total", value: "\(stats.totalCount)", color: .blue)
                StatBadge(label: "Complete", value: "\(stats.completeCount)", color: .green)
                StatBadge(label: "Lyrics", value: "\(stats.withLyricsCount)", color: .purple)
                StatBadge(label: "Images", value: "\(stats.withImagesCount)", color: .orange)
            } else {
                StatBadge(label: "Total", value: "\(appState.songsState.totalCount)", color: .blue)
            }

            Spacer()

            if appState.songsState.isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Song List

    private var songList: some View {
        List(displayedSongs, selection: $selectedSong) { song in
            SongRowView(
                song: song,
                isSelected: selectedSong?.id == song.id,
                isReanalyzing: appState.songsState.reanalyzingSongId == song.id,
                onSelect: { selectSong(song) },
                onDelete: { confirmDelete(song) },
                onReanalyze: { reanalyze(song) }
            )
            .tag(song)
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    // MARK: - Song Detail View

    @ViewBuilder
    private var songDetailView: some View {
        if let song = selectedSong {
            SongDetailView(
                song: song,
                onShaderChange: { shader in updateShader(song, shader) },
                onReanalyze: { reanalyze(song) },
                onDelete: { confirmDelete(song) },
                onDeleteImage: { url in deleteImageFile(for: song, url) },
                onClearCache: { clearCache(song) }
            )
        } else {
            VStack {
                Image(systemName: "music.note.list")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("Select a song to view details")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Computed Properties

    private var displayedSongs: [Song] {
        appState.songsState.displayedSongs
    }

    private var availableMoods: [String] {
        let moods = Set(displayedSongs.map { $0.mood }.filter { !$0.isEmpty && $0 != "unknown" })
        return moods.sorted()
    }

    // MARK: - Actions

    private func loadSongs() {
        appState.send(.songs(.load))
    }

    private func performSearch() {
        if searchText.isEmpty {
            clearFilter()
        } else {
            appState.send(.songs(.search(searchText)))
        }
    }

    private func applyFilters() {
        let filter = SongFilter(
            moodFilter: selectedMood,
            phaseFilter: selectedPhase,
            searchQuery: searchText.isEmpty ? nil : searchText
        )
        appState.send(.songs(.applyFilter(filter)))
    }

    private func clearFilter() {
        selectedMood = nil
        selectedPhase = nil
        appState.send(.songs(.clearFilter))
    }

    private func selectSong(_ song: Song) {
        selectedSong = song
        appState.send(.songs(.songSelected(song.id)))
    }

    private func confirmDelete(_ song: Song) {
        songToDelete = song
        showDeleteConfirm = true
    }

    private func deleteSong(_ song: Song) {
        appState.send(.songs(.deleteSong(song.id)))
        if selectedSong?.id == song.id {
            selectedSong = nil
        }
    }

    private func reanalyze(_ song: Song) {
        appState.send(.songs(.requestReanalysis(song.id)))
    }

    private func clearCache(_ song: Song) {
        Task {
            await appState.clearLyricsCache(artist: song.artist, title: song.title)
        }
    }

    private func clearAllCaches() {
        Task {
            await appState.clearAllCaches()
        }
    }

    private func updateShader(_ song: Song, _ shader: String) {
        appState.send(.songs(.setShader(song.id, shader)))
    }

    private func deleteImageFile(for song: Song, _ url: URL) {
        appState.send(.songs(.deleteImage(song.id, url)))

        // Keep local selection in sync for immediate UI feedback
        if selectedSong?.id == song.id {
            let newCount = max(0, (selectedSong?.imagesCount ?? song.imagesCount) - 1)
            selectedSong = songWithImages(song, count: newCount)
        }
    }

    private func songWithImages(_ song: Song, count: Int) -> Song {
        let status: SongStatus = {
            if song.hasLyrics && count > 0 && !(song.analysis?.mood ?? "").isEmpty {
                return .complete
            }
            return .partial
        }()

        return Song(
            id: song.id,
            artist: song.artist,
            title: song.title,
            album: song.album,
            duration: song.duration,
            bpm: song.bpm,
            musicalKey: song.musicalKey,
            analysis: song.analysis,
            status: status,
            selectedShader: song.selectedShader,
            imagesFolderPath: count > 0 ? song.imagesFolderPath : nil,
            imagesCount: count,
            hasLyrics: song.hasLyrics,
            lyricsLineCount: song.lyricsLineCount,
            refrainCount: song.refrainCount,
            createdAt: song.createdAt,
            lastPlayedAt: song.lastPlayedAt,
            lastAnalyzedAt: song.lastAnalyzedAt,
            playCount: song.playCount
        )
    }
}

// MARK: - Supporting Views

struct StatBadge: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .cornerRadius(6)
    }
}

struct SongRowView: View {
    let song: Song
    let isSelected: Bool
    let isReanalyzing: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onReanalyze: () -> Void

    var body: some View {
        HStack {
            // Song info
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Badges
            HStack(spacing: 4) {
                if song.hasLyrics {
                    Badge(text: "Lyrics", color: .green)
                }
                if song.imagesFolderPath != nil && song.imagesCount > 0 {
                    Badge(text: "\(song.imagesCount)", color: .blue, icon: "photo")
                }
                if let phase = song.phase {
                    Badge(text: phase.displayName, color: .purple, icon: phase.iconName)
                }
            }

            // Energy indicator
            EnergyIndicator(energy: song.energyScore)

            // Context menu button
            Menu {
                Button(action: onReanalyze) {
                    Label("Re-analyze", systemImage: "arrow.clockwise")
                }
                Divider()
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 30)

            // Re-analyzing indicator
            if isReanalyzing {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 20)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

struct Badge: View {
    let text: String
    let color: Color
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 2) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.caption2)
            }
            Text(text)
                .font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.2))
        .foregroundColor(color)
        .cornerRadius(4)
    }
}

struct EnergyIndicator: View {
    let energy: Double

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<5) { i in
                Rectangle()
                    .fill(Double(i) / 5.0 < energy ? energyColor : Color.gray.opacity(0.3))
                    .frame(width: 3, height: 12 + Double(i) * 2)
            }
        }
        .frame(width: 24)
    }

    private var energyColor: Color {
        if energy > 0.7 { return .red }
        if energy > 0.4 { return .orange }
        return .green
    }
}

struct SongDetailView: View {
    let song: Song
    let onShaderChange: (String) -> Void
    let onReanalyze: () -> Void
    let onDelete: () -> Void
    let onDeleteImage: (URL) -> Void
    let onClearCache: () -> Void

    @State private var imageURLs: [URL] = []
    @State private var imageToDelete: URL? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                songHeader

                Divider()

                // Analysis section
                if let analysis = song.analysis {
                    analysisSection(analysis)
                    Divider()
                }

                // Shader section
                shaderSection

                Divider()

                // Images section
                imagesSection

                Divider()

                // Actions
                actionsSection
            }
            .padding()
        }
        .frame(minWidth: 300)
        .onAppear(perform: loadImages)
        .onChange(of: song.id) { _, _ in loadImages() }
        .alert("Delete Image?", isPresented: Binding(
            get: { imageToDelete != nil },
            set: { newValue in if !newValue { imageToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let url = imageToDelete {
                    deleteImage(url)
                }
            }
        } message: {
            Text("Remove this image from disk? This cannot be undone.")
        }
    }

    private var songHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(song.title)
                .font(.title)
                .fontWeight(.bold)

            Text(song.artist)
                .font(.title2)
                .foregroundColor(.secondary)

            if !song.album.isEmpty {
                Text(song.album)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 16) {
                if song.duration > 0 {
                    Label(formatDuration(song.duration), systemImage: "clock")
                }
                if song.bpm > 0 {
                    Label("\(Int(song.bpm)) BPM", systemImage: "metronome")
                }
                if !song.musicalKey.isEmpty {
                    Label(song.musicalKey, systemImage: "music.note")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)

            HStack {
                StatusBadge(status: song.status)
                Spacer()
                Text("Played \(song.playCount) times")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func analysisSection(_ analysis: StoredSongAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Analysis")
                .font(.headline)

            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Mood")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(analysis.mood.capitalized)
                        .font(.body)
                }

                VStack(alignment: .leading) {
                    Text("Energy")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ProgressView(value: analysis.energy)
                        .frame(width: 80)
                }

                VStack(alignment: .leading) {
                    Text("Valence")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.2f", analysis.valence))
                        .font(.body)
                }

                if let phase = analysis.djPhase {
                    VStack(alignment: .leading) {
                        Text("Phase")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Label(phase.displayName, systemImage: phase.iconName)
                            .font(.body)
                    }
                }
            }

            if !analysis.keywords.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keywords")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TagFlowLayout(spacing: 4) {
                        ForEach(analysis.keywords, id: \.self) { keyword in
                            Text(keyword)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                }
            }

            if !analysis.themes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Themes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TagFlowLayout(spacing: 4) {
                        ForEach(analysis.themes, id: \.self) { theme in
                            Text(theme)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.purple.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                }
            }
        }
    }

    private var shaderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shader")
                .font(.headline)

            if let shader = song.selectedShader {
                HStack {
                    Image(systemName: "sparkles")
                    Text(shader)
                        .font(.body)
                }
            } else {
                Text("No shader assigned")
                    .foregroundColor(.secondary)
            }
        }
    }

    private var imageGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 180), spacing: 12)]
    }

    private var imagesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Images")
                .font(.headline)

            if let path = song.imagesFolderPath, song.imagesCount > 0 {
                HStack {
                    Image(systemName: "photo.on.rectangle.angled")
                    Text("\(imageURLs.count) images")
                    Text("in \(URL(fileURLWithPath: path).lastPathComponent)")
                        .foregroundColor(.secondary)
                    Spacer()
                }

                LazyVGrid(columns: imageGridColumns, spacing: 12) {
                    ForEach(imageURLs, id: \.self) { url in
                        if let img = NSImage(contentsOf: url) {
                            ZStack(alignment: .topTrailing) {
                                Color(.textBackgroundColor)

                                Image(nsImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 140)
                                    .clipped()

                                Button {
                                    imageToDelete = url
                                } label: {
                                    Image(systemName: "trash.circle.fill")
                                        .foregroundColor(.red)
                                        .shadow(radius: 2)
                                }
                                .buttonStyle(.plain)
                                .padding(4)
                            }
                            .frame(maxWidth: .infinity, minHeight: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color(.separatorColor).opacity(0.3))
                            )
                        }
                    }
                }
            } else {
                Text("No images")
                    .foregroundColor(.secondary)
            }

            // Lyrics section
            if let lyrics = song.lyricsText, !lyrics.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Lyrics")
                        .font(.headline)
                    ScrollView {
                        Text(lyrics)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 120, maxHeight: 240)
                    .padding(8)
                    .background(Color(.windowBackgroundColor).opacity(0.4))
                    .cornerRadius(8)
                }
            }
        }
    }

    private var actionsSection: some View {
        HStack {
            Button(action: onReanalyze) {
                Label("Re-analyze", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            Button(action: onClearCache) {
                Label("Clear Cache", systemImage: "xmark.bin")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func loadImages() {
        imageURLs = []
        guard let path = song.imagesFolderPath else { return }
        let url = URL(fileURLWithPath: path)
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else { return }
        let allowed = Set(["png", "jpg", "jpeg", "gif", "heic", "tiff"])
        imageURLs = enumerator.compactMap { element in
            guard let fileURL = element as? URL else { return nil }
            return allowed.contains(fileURL.pathExtension.lowercased()) ? fileURL : nil
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func deleteImage(_ url: URL) {
        onDeleteImage(url)
        imageURLs.removeAll { $0 == url }
    }
}

// Simple flow layout for keywords/themes
struct TagFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = flowLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = flowLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func flowLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return (CGSize(width: maxWidth, height: currentY + lineHeight), positions)
    }
}

struct StatusBadge: View {
    let status: SongStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.iconName)
            Text(status.displayName)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.15))
        .foregroundColor(statusColor)
        .cornerRadius(6)
    }

    private var statusColor: Color {
        switch status {
        case .complete: return .green
        case .partial: return .orange
        case .needsReanalysis: return .blue
        case .error: return .red
        }
    }
}

