import SwiftUI
import SwiftVJCore
import SongRepository

struct AutomationTimelineView: View {
    @EnvironmentObject var appState: AppState

    @State private var cueTimeSec: Double = 0
    @State private var cueActionType: AutomationCueActionType = .ledfxActivateScene
    @State private var cueValue: String = ""
    @State private var cueTarget: AutomationOSCTarget = .synesthesia
    @State private var cueArgsText: String = ""
    @State private var selectedLaneID: String?
    @State private var newLaneVirtualID: String = "main"
    @State private var lanePointValue: Double = 0.5

    private var songs: [Song] {
        appState.songsState.displayedSongs.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private var selectedSongID: SongID? {
        appState.automationState.selectedSongId
    }

    private var timeline: SongAutomationTimeline {
        appState.automationTimeline(for: selectedSongID) ?? .empty
    }

    private var selectedLane: AutomationValueLane? {
        guard let selectedLaneID else { return timeline.valueLanes.first }
        return timeline.valueLanes.first(where: { $0.id == selectedLaneID }) ?? timeline.valueLanes.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerBar

            if let songID = selectedSongID {
                cueEditor(songID: songID)
                cueList(songID: songID)
                laneEditor(songID: songID)
            } else {
                GroupBox("Timeline") {
                    Text("Choose a song at the top to edit timecoded automation.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .onAppear {
            if appState.songsState.displayedSongs.isEmpty {
                appState.send(.songs(.load))
            }
            cueTimeSec = appState.playbackPosition
            if selectedLaneID == nil {
                selectedLaneID = timeline.valueLanes.first?.id
            }
        }
        .onChange(of: appState.playbackPosition) { _, value in
            cueTimeSec = value
        }
        .onChange(of: selectedSongID) { _, songID in
            if let songID {
                appState.selectAutomationSong(songID)
            }
            selectedLaneID = timeline.valueLanes.first?.id
        }
    }

    private var headerBar: some View {
        GroupBox("Automation Timeline") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Picker("Song", selection: appState.automationSelectedSongBinding) {
                        Text("Current Playback").tag(nil as SongID?)
                        ForEach(songs, id: \.id) { song in
                            Text(song.displayName).tag(song.id as SongID?)
                        }
                    }
                    .frame(minWidth: 320)

                    Button("Use Current") {
                        if let track = appState.currentTrack {
                            let songID = SongID(artist: track.artist, title: track.title)
                            appState.selectAutomationSong(songID)
                        }
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 16) {
                    Toggle("Timecoding On", isOn: appState.automationEnabledBinding)
                        .toggleStyle(.switch)
                    Toggle("Auto Record", isOn: appState.automationAutoRecordBinding)
                        .toggleStyle(.switch)
                    if let songID = selectedSongID {
                        Toggle(
                            "Replay Selected Song",
                            isOn: Binding(
                                get: { appState.automationPlaybackEnabled(songID: songID) },
                                set: { appState.setAutomationPlaybackEnabled(songID: songID, enabled: $0) }
                            )
                        )
                        .toggleStyle(.switch)
                    }
                    Spacer()
                    Text("Playhead: \(String(format: "%.2f", appState.playbackPosition))s")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Auto-record OSC prefixes (comma-separated)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(
                        "/ledfx/, /scenes/, /presets/, /playlist/, /controls/",
                        text: appState.automationAutoRecordPrefixesStringBinding
                    )
                    .textFieldStyle(.roundedBorder)
                    .disabled(!appState.automationState.autoRecordEnabled)
                    Text("Recorder sampling: max 10 Hz, minimum numeric delta 0.01")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let track = appState.currentTrack {
                    Text("Now playing: \(track.artist) - \(track.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func cueEditor(songID: SongID) -> some View {
        GroupBox("Cue Lane") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("t")
                        .font(.caption.monospaced())
                    TextField("sec", value: $cueTimeSec, format: .number.precision(.fractionLength(2)))
                        .frame(width: 90)
                    Picker("Type", selection: $cueActionType) {
                        Text("LedFX Scene").tag(AutomationCueActionType.ledfxActivateScene)
                        Text("LedFX Playlist").tag(AutomationCueActionType.ledfxActivatePlaylist)
                        Text("LedFX Stop").tag(AutomationCueActionType.ledfxStopPlaylist)
                        Text("OSC").tag(AutomationCueActionType.osc)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)

                    if cueActionType == .osc {
                        Picker("Target", selection: $cueTarget) {
                            Text("Synesthesia").tag(AutomationOSCTarget.synesthesia)
                            Text("Magic").tag(AutomationOSCTarget.magic)
                            Text("VDJ").tag(AutomationOSCTarget.vdj)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 140)
                    }

                    TextField(
                        cueActionType == .osc ? "/address" : "Scene / Playlist ID",
                        text: $cueValue
                    )
                    .textFieldStyle(.roundedBorder)
                }

                if cueActionType == .osc {
                    TextField("OSC args (comma-separated)", text: $cueArgsText)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Button("Add Cue @ Playhead") {
                        cueTimeSec = appState.playbackPosition
                        addCue(songID: songID)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(cueActionType != .ledfxStopPlaylist && cueValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Clear Timeline", role: .destructive) {
                        appState.clearAutomationTimeline(songID: songID)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func cueList(songID: SongID) -> some View {
        GroupBox("Cues (\(timeline.cues.count))") {
            if timeline.cues.isEmpty {
                Text("No cues yet. Add manual cues or enable Auto Record.")
                    .foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(timeline.cues) { cue in
                        HStack(spacing: 10) {
                            Text(String(format: "%.2fs", cue.timeSec))
                                .font(.caption.monospacedDigit())
                                .frame(width: 70, alignment: .leading)

                            Text(cueLabel(cue))
                                .lineLimit(1)

                            Spacer()

                            if let source = cue.source, !source.isEmpty {
                                Text(source)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Button(role: .destructive) {
                                appState.removeAutomationCue(songID: songID, cueID: cue.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .frame(minHeight: 120, maxHeight: 180)
            }
        }
    }

    private func laneEditor(songID: SongID) -> some View {
        GroupBox("Value Lane (LedFX Brightness)") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Picker("Lane", selection: Binding(
                        get: { selectedLaneID ?? timeline.valueLanes.first?.id ?? "" },
                        set: { selectedLaneID = $0 }
                    )) {
                        ForEach(timeline.valueLanes, id: \.id) { lane in
                            Text(lane.displayName).tag(lane.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 220)

                    TextField("New virtual id", text: $newLaneVirtualID)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)

                    Button("Add Lane") {
                        addLane(songID: songID)
                    }
                    .buttonStyle(.bordered)
                }

                if let lane = selectedLane {
                    AutomationLaneGraphView(points: lane.points)
                        .frame(height: 180)

                    HStack(spacing: 8) {
                        Text("Point value")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $lanePointValue, in: 0...1)
                        Text(String(format: "%.2f", lanePointValue))
                            .font(.caption.monospacedDigit())
                            .frame(width: 44, alignment: .trailing)
                        Button("Add Point @ Playhead") {
                            appState.addAutomationValuePoint(
                                songID: songID,
                                laneID: lane.id,
                                point: AutomationValuePoint(
                                    timeSec: appState.playbackPosition,
                                    value: lanePointValue
                                )
                            )
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if lane.points.isEmpty {
                        Text("No points yet. Add keyframes from the current playhead.")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        List {
                            ForEach(lane.points.sorted { $0.timeSec < $1.timeSec }) { point in
                                HStack(spacing: 10) {
                                    Text(String(format: "%.2fs", point.timeSec))
                                        .font(.caption.monospacedDigit())
                                        .frame(width: 70, alignment: .leading)
                                    Text(String(format: "%.2f", point.value))
                                        .font(.caption.monospacedDigit())
                                        .frame(width: 48, alignment: .trailing)
                                    Spacer()
                                    Button(role: .destructive) {
                                        appState.removeAutomationValuePoint(
                                            songID: songID,
                                            laneID: lane.id,
                                            pointID: point.id
                                        )
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                        .frame(minHeight: 120, maxHeight: 180)
                    }
                } else {
                    Text("Create a value lane to graph brightness automation.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func cueLabel(_ cue: AutomationCue) -> String {
        switch cue.actionType {
        case .ledfxActivateScene:
            return "LedFX scene: \(cue.value)"
        case .ledfxActivatePlaylist:
            return "LedFX playlist: \(cue.value)"
        case .ledfxStopPlaylist:
            return "LedFX stop playlist"
        case .osc:
            let target = cue.oscTarget?.rawValue ?? "osc"
            return "\(target): \(cue.value)"
        }
    }

    private func addCue(songID: SongID) {
        let normalizedValue = cueValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let cue = AutomationCue(
            timeSec: cueTimeSec,
            actionType: cueActionType,
            value: cueActionType == .ledfxStopPlaylist ? "" : normalizedValue,
            oscTarget: cueActionType == .osc ? cueTarget : nil,
            args: cueActionType == .osc ? parseOSCArgs(cueArgsText) : [],
            source: "manual"
        )
        appState.addAutomationCue(songID: songID, cue: cue)
        cueValue = ""
        cueArgsText = ""
    }

    private func addLane(songID: SongID) {
        let trimmed = newLaneVirtualID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let laneID = "ledfx-brightness:\(trimmed)"
        let lane = AutomationValueLane(
            id: laneID,
            displayName: "Brightness \(trimmed)",
            targetType: .ledfxVirtualBrightness,
            target: trimmed,
            points: []
        )
        appState.addAutomationValueLane(songID: songID, lane: lane)
        selectedLaneID = laneID
    }

    private func parseOSCArgs(_ raw: String) -> [AutomationOSCValue] {
        raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { token in
                if token == "true" { return .bool(true) }
                if token == "false" { return .bool(false) }
                if let intValue = Int(token) { return .int(intValue) }
                if let floatValue = Double(token) { return .float(floatValue) }
                return .string(token)
            }
    }
}

private struct AutomationLaneGraphView: View {
    let points: [AutomationValuePoint]

    var body: some View {
        GeometryReader { proxy in
            let sorted = points.sorted { $0.timeSec < $1.timeSec }
            let maxTime = max(sorted.last?.timeSec ?? 1, 1)

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.textBackgroundColor))

                Path { path in
                    guard !sorted.isEmpty else { return }
                    for (index, point) in sorted.enumerated() {
                        let x = CGFloat(point.timeSec / maxTime) * proxy.size.width
                        let y = (1 - CGFloat(point.value)) * proxy.size.height
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(Color.accentColor, lineWidth: 2)

                ForEach(sorted) { point in
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                        .position(
                            x: CGFloat(point.timeSec / maxTime) * proxy.size.width,
                            y: (1 - CGFloat(point.value)) * proxy.size.height
                        )
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
    }
}
