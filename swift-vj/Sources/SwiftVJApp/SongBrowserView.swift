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
    @State private var selectedStatus: SongStatus? = nil
    @State private var sortOrder: SongSortOrder = .recentlyPlayed
    @State private var showDeleteConfirm = false
    @State private var songToDelete: Song? = nil
    @State private var selectedSong: Song? = nil
    @State private var selectedSongIds: Set<Song.ID> = []

    var body: some View {
        HSplitView {
            // Left: Song list with filters
            VStack(spacing: 0) {
                // Scan progress bar (when scanning)
                scanProgressView

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
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    folderScanButton
                }
            }

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
        .onChange(of: selectedMood) { _, _ in applyFilters() }
        .onChange(of: selectedPhase) { _, _ in applyFilters() }
        .onChange(of: selectedStatus) { _, _ in applyFilters() }
        .onChange(of: sortOrder) { _, _ in applyFilters() }
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

    // MARK: - Folder Scan Button

    @ViewBuilder
    private var folderScanButton: some View {
        if let progress = appState.songsState.scanProgress, progress.isScanning {
            Button(action: cancelScan) {
                Label("Cancel Scan", systemImage: "xmark.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        } else {
            Button(action: selectFolderToScan) {
                Label("Scan Folder", systemImage: "folder.badge.plus")
            }
        }
    }

    // MARK: - Scan Progress View

    @ViewBuilder
    private var scanProgressView: some View {
        if let progress = appState.songsState.scanProgress, progress.isScanning {
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.accentColor)
                    Text("Scanning: \(progress.folderName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(progress.current)/\(progress.total)")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                    Button(action: cancelScan) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                ProgressView(value: progress.progress)
                    .progressViewStyle(.linear)

                HStack {
                    Text("\(progress.foundCount) songs found")
                        .font(.caption2)
                        .foregroundColor(.green)
                    Spacer()
                    Text("\(Int(progress.progress * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    // MARK: - Folder Scan Actions

    private func selectFolderToScan() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder containing music files"
        panel.prompt = "Scan"

        if panel.runModal() == .OK, let url = panel.url {
            appState.send(.songs(.scanFolderRequested(url)))
        }
    }

    private func cancelScan() {
        appState.send(.songs(.cancelScanRequested))
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
                    statusPicker
                    sortPicker
                    Spacer(minLength: 0)
                    clearAllCachesButton
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        moodPicker
                        phasePicker
                        statusPicker
                    }
                    HStack(spacing: 12) {
                        sortPicker
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

    private var statusPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Status")
                .font(.caption)
                .foregroundColor(.secondary)

            Picker("Status", selection: $selectedStatus) {
                Text("All").tag(nil as SongStatus?)
                ForEach(SongStatus.allCases, id: \.self) { status in
                    Label(status.displayName, systemImage: status.iconName)
                        .tag(status as SongStatus?)
                }
            }
            .frame(minWidth: 140)
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
        VStack(spacing: 0) {
            // Selection toolbar (shown when items selected)
            if !selectedSongIds.isEmpty {
                selectionToolbar
            }

            List(displayedSongs, id: \.id, selection: $selectedSongIds) { song in
                SongRowView(
                    song: song,
                    isReanalyzing: appState.songsState.reanalyzingSongId == song.id,
                    onDelete: { confirmDelete(song) },
                    onReanalyze: { reanalyze(song) }
                )
                .tag(song.id)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .onChange(of: selectedSongIds) { _, newSelection in
                // Update detail view when single item selected
                if newSelection.count == 1, let id = newSelection.first {
                    selectedSong = displayedSongs.first { $0.id == id }
                }
            }
        }
    }

    private var selectionToolbar: some View {
        HStack(spacing: 12) {
            Text("\(selectedSongIds.count) selected")
                .font(.headline)
                .foregroundColor(.secondary)

            Spacer()

            Button(action: analyzeSelected) {
                Label("Analyze Selected", systemImage: "wand.and.stars")
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)

            Button(action: { selectedSongIds.removeAll() }) {
                Label("Clear", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.windowBackgroundColor).opacity(0.8))
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
            statusFilter: selectedStatus,
            searchQuery: searchText.isEmpty ? nil : searchText
        )
        appState.send(.songs(.applyFilter(filter)))
    }

    private func clearFilter() {
        selectedMood = nil
        selectedPhase = nil
        selectedStatus = nil
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

    private func analyzeSelected() {
        for songId in selectedSongIds {
            appState.send(.songs(.requestReanalysis(songId)))
        }
        // Clear selection after starting analysis
        selectedSongIds.removeAll()
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
    let isReanalyzing: Bool
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
    @State private var imageCache: [URL: NSImage] = [:]
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
                        if let img = imageCache[url] {
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
                        } else {
                            // Placeholder while loading
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(.textBackgroundColor))
                                .frame(maxWidth: .infinity, minHeight: 140)
                                .overlay(ProgressView())
                        }
                    }
                }
            } else {
                Text("No images")
                    .foregroundColor(.secondary)
            }

            // Lyrics section
            Divider()
            LyricsBrowserView(song: song)
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
        imageCache = [:]
        guard let path = song.imagesFolderPath else { return }
        let url = URL(fileURLWithPath: path)
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else { return }
        let allowed = Set(["png", "jpg", "jpeg", "gif", "heic", "tiff"])
        let urls = enumerator.compactMap { element in
            guard let fileURL = element as? URL else { return nil as URL? }
            return allowed.contains(fileURL.pathExtension.lowercased()) ? fileURL : nil
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        
        imageURLs = urls
        
        // Load images asynchronously
        for imageURL in urls {
            DispatchQueue.global(qos: .userInitiated).async {
                if let img = NSImage(contentsOf: imageURL) {
                    DispatchQueue.main.async {
                        imageCache[imageURL] = img
                    }
                }
            }
        }
    }

    private func deleteImage(_ url: URL) {
        onDeleteImage(url)
        imageURLs.removeAll { $0 == url }
        imageCache.removeValue(forKey: url)
    }
}

// MARK: - Lyrics Browser View

struct LyricsBrowserView: View {
    let song: Song
    @State private var isExpanded = false

    private var parsedLines: [(time: Double?, text: String, isRefrain: Bool)] {
        guard let lyrics = song.lyricsText, !lyrics.isEmpty else { return [] }
        return parseLRCLines(lyrics)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with status
            HStack {
                Text("Lyrics")
                    .font(.headline)

                Spacer()

                // Source indicator
                if song.hasLyrics {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.badge.checkmark")
                        Text("Synced (LRCLIB)")
                    }
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(6)
                } else if song.lyricsText != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "text.alignleft")
                        Text("Plain Text")
                    }
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(6)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle")
                        Text("No Lyrics")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                // Stats
                if song.lyricsLineCount > 0 {
                    Text("\(song.lyricsLineCount) lines")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if song.refrainCount > 0 {
                    Text("• \(song.refrainCount) refrains")
                        .font(.caption)
                        .foregroundColor(.purple)
                }

                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.plain)
            }

            // Lyrics content
            if isExpanded || song.lyricsText != nil {
                if !parsedLines.isEmpty {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(parsedLines.enumerated()), id: \.offset) { index, line in
                                LyricLineRow(
                                    index: index,
                                    time: line.time,
                                    text: line.text,
                                    isRefrain: line.isRefrain,
                                    isSynced: song.hasLyrics
                                )
                            }
                        }
                        .padding(8)
                    }
                    .frame(minHeight: isExpanded ? 300 : 150, maxHeight: isExpanded ? 500 : 200)
                    .background(Color(.textBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                } else {
                    Text("No lyrics available")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                }
            }
        }
    }

    /// Parse LRC format lines, extracting timestamps if present
    private func parseLRCLines(_ text: String) -> [(time: Double?, text: String, isRefrain: Bool)] {
        let lines = text.components(separatedBy: .newlines)
        var result: [(time: Double?, text: String, isRefrain: Bool)] = []
        var seenTexts: [String: Int] = [:]

        // First pass: count occurrences
        for line in lines {
            let cleanText = extractText(from: line)
            if !cleanText.isEmpty {
                seenTexts[cleanText, default: 0] += 1
            }
        }

        // Second pass: parse with refrain detection
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let time = extractTime(from: trimmed)
            let text = extractText(from: trimmed)
            guard !text.isEmpty else { continue }

            let isRefrain = (seenTexts[text] ?? 0) >= 3
            result.append((time: time, text: text, isRefrain: isRefrain))
        }

        return result
    }

    private func extractTime(from line: String) -> Double? {
        // Match [mm:ss.xx] or [mm:ss.xxx] format
        let pattern = #"\[(\d+):(\d+)\.(\d+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }

        guard let minRange = Range(match.range(at: 1), in: line),
              let secRange = Range(match.range(at: 2), in: line),
              let msRange = Range(match.range(at: 3), in: line) else {
            return nil
        }

        let min = Double(line[minRange]) ?? 0
        let sec = Double(line[secRange]) ?? 0
        let msStr = String(line[msRange])
        let ms = Double(msStr) ?? 0
        let msDivisor = pow(10.0, Double(msStr.count))

        return min * 60 + sec + ms / msDivisor
    }

    private func extractText(from line: String) -> String {
        // Remove timestamp patterns [mm:ss.xx]
        let pattern = #"\[\d+:\d+\.\d+\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return line.trimmingCharacters(in: .whitespaces)
        }
        let result = regex.stringByReplacingMatches(
            in: line,
            range: NSRange(line.startIndex..., in: line),
            withTemplate: ""
        )
        return result.trimmingCharacters(in: .whitespaces)
    }
}

struct LyricLineRow: View {
    let index: Int
    let time: Double?
    let text: String
    let isRefrain: Bool
    let isSynced: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Line number
            Text("\(index + 1)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 24, alignment: .trailing)

            // Timestamp (if synced)
            if isSynced, let time = time {
                Text(formatTime(time))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.blue)
                    .frame(width: 50, alignment: .leading)
            }

            // Lyric text
            Text(text)
                .font(.body)
                .foregroundColor(isRefrain ? .purple : .primary)
                .fontWeight(isRefrain ? .semibold : .regular)

            if isRefrain {
                Text("♪")
                    .font(.caption)
                    .foregroundColor(.purple)
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .background(isRefrain ? Color.purple.opacity(0.08) : Color.clear)
        .cornerRadius(4)
    }

    private func formatTime(_ seconds: Double) -> String {
        let min = Int(seconds) / 60
        let sec = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", min, sec, ms)
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

