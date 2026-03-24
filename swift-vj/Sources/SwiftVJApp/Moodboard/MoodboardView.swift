// MoodboardView - Container view for the moodboard canvas and panels

import AppKit
import SwiftUI
import SwiftVJCore

struct MoodboardView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            MoodboardToolbar()
            PreviewBarView()
            PhaseFlowBarView()

            HSplitView {
                // Left: Library panel
                if appState.moodboardState.libraryPanelOpen {
                    MoodboardLibraryPanel()
                }

                // Center: Canvas
                MoodboardCanvasView()
                    .frame(minWidth: 400, minHeight: 300)

                // Right: Detail panel or Tag Manager
                if appState.moodboardState.tagManagerPanelOpen {
                    TagManagerPanel()
                } else if appState.moodboardState.detailPanelSongId != nil {
                    MoodboardDetailPanel()
                }
            }
        }
        .background(MoodboardKeyHandler())
        .onAppear {
            appState.send(.moodboard(.loadFromSongs))
            appState.send(.moodboard(.loadBoardList))
        }
    }
}

// MARK: - Keyboard Handler

/// NSViewRepresentable that monitors key events for preview playback controls.
/// Space = play/pause, Shift+Space = stop, Shift+Arrow = seek ±15s
private struct MoodboardKeyHandler: NSViewRepresentable {
    @EnvironmentObject var appState: AppState

    func makeNSView(context: Context) -> MoodboardKeyView {
        let view = MoodboardKeyView()
        view.onKeyDown = { [weak appState] event in
            guard let appState else { return false }
            return Self.handleKey(event: event, appState: appState)
        }
        return view
    }

    func updateNSView(_ nsView: MoodboardKeyView, context: Context) {
        nsView.onKeyDown = { [weak appState] event in
            guard let appState else { return false }
            return Self.handleKey(event: event, appState: appState)
        }
    }

    static func handleKey(event: NSEvent, appState: AppState) -> Bool {
        let hasShift = event.modifierFlags.contains(.shift)
        let hasCmd = event.modifierFlags.contains(.command)

        switch event.keyCode {
        case 0 where hasCmd: // Cmd-A → select all nodes
            let allIds = Set(appState.moodboardState.nodes.map(\.id))
            appState.send(.moodboard(.selectNodes(allIds)))
            return true

        case 49: // Space
            if hasShift {
                // Shift+Space → stop
                appState.send(.preview(.stop))
            } else {
                handleSpaceBar(appState: appState)
            }
            return true

        case 123 where hasShift: // Shift+Left arrow → seek -15s with wraparound
            seekRelative(seconds: -15, appState: appState)
            return true

        case 124 where hasShift: // Shift+Right arrow → seek +15s with wraparound
            seekRelative(seconds: 15, appState: appState)
            return true

        default:
            return false
        }
    }

    private static func handleSpaceBar(appState: AppState) {
        let preview = appState.previewState
        let selectedIds = appState.moodboardState.selectedNodeIds

        if selectedIds.isEmpty {
            // No selection → stop playback
            if preview.currentSongId != nil {
                appState.send(.preview(.stop))
            }
            return
        }

        // Find the selected song node's SongID
        let selectedSongId = appState.moodboardState.nodes
            .first(where: { selectedIds.contains($0.id) && $0.songId != nil })?.songId

        guard let songId = selectedSongId else {
            // Selected node isn't a song → stop
            if preview.currentSongId != nil {
                appState.send(.preview(.stop))
            }
            return
        }

        if preview.currentSongId == songId {
            // Same song selected → toggle play/pause
            if preview.isPlaying {
                appState.send(.preview(.pause))
            } else {
                appState.send(.preview(.resume))
            }
        } else {
            // Different song selected → play it
            appState.send(.preview(.play(songId)))
        }
    }

    private static func seekRelative(seconds: Double, appState: AppState) {
        let preview = appState.previewState
        guard preview.currentSongId != nil, preview.duration > 0 else { return }
        var newPos = preview.currentPosition + seconds
        // Wraparound
        if newPos < 0 { newPos += preview.duration }
        if newPos >= preview.duration { newPos -= preview.duration }
        newPos = max(0, min(newPos, preview.duration))
        appState.send(.preview(.seekTo(newPos)))
    }
}

/// NSView subclass that accepts first responder and forwards key events
private final class MoodboardKeyView: NSView {
    var onKeyDown: ((NSEvent) -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true {
            return // consumed
        }
        super.keyDown(with: event)
    }
}

// MARK: - Toolbar

private struct MoodboardToolbar: View {
    @EnvironmentObject var appState: AppState

    @State private var boardName: String = ""
    @State private var showSaveSheet = false
    @State private var showLoadSheet = false
    @State private var showAddTagPopover = false
    @State private var newTagLabel = ""
    @State private var newTagCategory: TagCategory = .genre

    private var moodboard: MoodboardSubState { appState.moodboardState }

    var body: some View {
        HStack(spacing: 8) {
            // Board name display
            if let name = moodboard.currentBoardName {
                Text(name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
            } else {
                Text("Untitled Board")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // Save status
            if moodboard.saveStatus == .saving {
                ProgressView()
                    .controlSize(.mini)
            }

            Spacer()

            // Add tag node button
            Button {
                showAddTagPopover.toggle()
            } label: {
                Label("Add Tag", systemImage: "tag.fill")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .popover(isPresented: $showAddTagPopover) {
                addTagPopover
            }

            Divider()
                .frame(height: 16)

            // Board management buttons
            Button {
                appState.send(.moodboard(.newBoard))
            } label: {
                Label("New", systemImage: "plus.square")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("New empty board")

            Button {
                boardName = moodboard.currentBoardName ?? ""
                showSaveSheet = true
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Save board")

            Button {
                showLoadSheet = true
            } label: {
                Label("Load", systemImage: "square.and.arrow.up")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Load board")

            Divider()
                .frame(height: 16)

            // Layout picker
            Menu {
                Button {
                    appState.send(.moodboard(.applyLayout(.auto)))
                } label: {
                    Label("Auto Layout", systemImage: "circle.grid.3x3")
                }
                Button {
                    appState.send(.moodboard(.applyLayout(.flow)))
                } label: {
                    Label("Flow Layout", systemImage: "arrow.right.square")
                }
                Button {
                    appState.send(.moodboard(.applyLayout(.grouped)))
                } label: {
                    Label("Grouped Layout", systemImage: "rectangle.3.group")
                }
            } label: {
                Label("Layout", systemImage: "square.grid.3x1.below.line.grid.1x2")
                    .font(.system(size: 11))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 80)
            .help("Auto-arrange nodes")

            Divider()
                .frame(height: 16)

            // Library toggle
            Button {
                appState.send(.moodboard(.toggleLibraryPanel))
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 12))
                    .foregroundStyle(moodboard.libraryPanelOpen ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .help("Toggle library")

            // Tag manager toggle
            Button {
                appState.send(.moodboard(.toggleTagManagerPanel))
            } label: {
                Image(systemName: "tag.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(moodboard.tagManagerPanelOpen ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .help("Toggle tag manager")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .sheet(isPresented: $showSaveSheet) {
            saveBoardSheet
        }
        .sheet(isPresented: $showLoadSheet) {
            loadBoardSheet
        }
    }

    // MARK: - Add Tag Popover

    private var addTagPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Tag Node")
                .font(.headline)

            Picker("Category", selection: $newTagCategory) {
                Text("Genre").tag(TagCategory.genre)
                Text("Mood").tag(TagCategory.mood)
                Text("Phase").tag(TagCategory.phase)
                Text("Topic").tag(TagCategory.topic)
                Text("Custom").tag(TagCategory.custom)
            }
            .pickerStyle(.segmented)

            TextField("Label…", text: $newTagLabel)
                .textFieldStyle(.roundedBorder)
                .onSubmit { addTag() }

            HStack {
                Spacer()
                Button("Cancel") { showAddTagPopover = false }
                    .buttonStyle(.bordered)
                Button("Add") { addTag() }
                    .buttonStyle(.borderedProminent)
                    .disabled(newTagLabel.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 260)
    }

    private func addTag() {
        let label = newTagLabel.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { return }
        let x = CGFloat.random(in: 200...500)
        let y = CGFloat.random(in: 150...350)
        appState.send(.moodboard(.addTagNode(label: label, category: newTagCategory, position: CGPoint(x: x, y: y))))
        newTagLabel = ""
        showAddTagPopover = false
    }

    // MARK: - Save Sheet

    private var saveBoardSheet: some View {
        VStack(spacing: 16) {
            Text("Save Board")
                .font(.title2.bold())

            TextField("Board name", text: $boardName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

            HStack {
                Button("Cancel") { showSaveSheet = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    let name = boardName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    appState.send(.moodboard(.saveBoard(name: name)))
                    showSaveSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(boardName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .frame(width: 300)
        }
        .padding(24)
    }

    // MARK: - Load Sheet

    private var loadBoardSheet: some View {
        VStack(spacing: 12) {
            Text("Load Board")
                .font(.title2.bold())

            if moodboard.savedBoards.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                    Text("No saved boards")
                        .foregroundStyle(.secondary)
                }
                .frame(height: 120)
            } else {
                List {
                    ForEach(moodboard.savedBoards) { board in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(board.name)
                                    .font(.system(size: 13, weight: .medium))
                                HStack(spacing: 8) {
                                    Text("\(board.nodeCount) nodes")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                    Text(board.updatedAt, style: .relative)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            Button {
                                appState.send(.moodboard(.loadBoard(id: board.id)))
                                showLoadSheet = false
                            } label: {
                                Text("Load")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.bordered)

                            Button {
                                appState.send(.moodboard(.deleteBoard(id: board.id)))
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .frame(width: 400, height: 250)
            }

            HStack {
                Spacer()
                Button("Close") { showLoadSheet = false }
                    .keyboardShortcut(.cancelAction)
            }
            .frame(width: 400)
        }
        .padding(24)
        .onAppear {
            appState.send(.moodboard(.loadBoardList))
        }
    }
}
