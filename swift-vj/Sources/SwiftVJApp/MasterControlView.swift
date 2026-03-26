// MasterControlView - Playback status and controls
// Phase 4: SwiftUI Shell

import SwiftUI
import SwiftVJCore

struct MasterControlView: View {
    @EnvironmentObject var appState: AppState
    @State private var commandLineDraft: String = ""
    @State private var workingDirectoryDraft: String = ""
    @State private var launcherSectionWidth: CGFloat = 0
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Now Playing
                GroupBox("Now Playing") {
                    VStack(alignment: .leading, spacing: 12) {
                        if let track = appState.currentTrack {
                            HStack(alignment: .top, spacing: 16) {
                                // Album art placeholder
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.quaternary)
                                    .frame(width: 80, height: 80)
                                    .overlay {
                                        Image(systemName: appState.isPlaying ? "music.note" : "pause.fill")
                                            .font(.largeTitle)
                                            .foregroundColor(.secondary)
                                    }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(track.title)
                                        .font(.title2)
                                        .fontWeight(.semibold)
                                    Text(track.artist)
                                        .font(.title3)
                                        .foregroundColor(.secondary)
                                    if !track.album.isEmpty {
                                        Text(track.album)
                                            .font(.subheadline)
                                            .foregroundStyle(.tertiary)
                                    }
                                    
                                    // Playback position
                                    HStack(spacing: 8) {
                                        Text(formatDuration(appState.playbackPosition))
                                            .font(.caption)
                                            .monospacedDigit()
                                            .foregroundStyle(.secondary)
                                        
                                        // Progress bar
                                        GeometryReader { geometry in
                                            ZStack(alignment: .leading) {
                                                RoundedRectangle(cornerRadius: 2)
                                                    .fill(.quaternary)
                                                    .frame(height: 4)
                                                
                                                RoundedRectangle(cornerRadius: 2)
                                                    .fill(appState.isPlaying ? .blue : .gray)
                                                    .frame(width: max(0, geometry.size.width * progressRatio(track: track)), height: 4)
                                            }
                                        }
                                        .frame(height: 4)
                                        
                                        Text(formatDuration(track.duration))
                                            .font(.caption)
                                            .monospacedDigit()
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.top, 4)
                                }
                                
                                Spacer()
                                
                                // Play state indicator
                                VStack {
                                    Image(systemName: appState.isPlaying ? "play.fill" : "pause.fill")
                                        .font(.title2)
                                        .foregroundColor(appState.isPlaying ? .green : .orange)
                                    Text(appState.isPlaying ? "Playing" : "Paused")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        } else {
                            HStack {
                                Image(systemName: "music.note.list")
                                    .font(.title)
                                    .foregroundColor(.secondary)
                                Text("No track playing")
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                        }
                    }
                    .padding()
                }
                
                // Playback Source
                GroupBox("Playback Source") {
                    HStack(spacing: 16) {
                        ForEach(["vdj", "spotify"], id: \.self) { source in
                            Button {
                                Task {
                                    await appState.setPlaybackSource(source)
                                }
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: source == "vdj" ? "music.quarternote.3" : "dot.radiowaves.left.and.right")
                                        .font(.title)
                                    Text(source == "vdj" ? "VirtualDJ" : "Spotify")
                                        .font(.caption)
                                }
                                .frame(minWidth: 60, maxWidth: 100, minHeight: 50, maxHeight: 70)
                            }
                            .buttonStyle(.bordered)
                            .tint(appState.playbackSource == source ? .blue : .gray)
                        }
                        
                        Spacer()
                        
                        // Status indicator
                        VStack(alignment: .trailing, spacing: 4) {
                            HStack {
                                Circle()
                                    .fill(appState.isRunning ? .green : .red)
                                    .frame(width: 10, height: 10)
                                Text(appState.isRunning ? "Connected" : "Disconnected")
                            }
                            HStack {
                                Circle()
                                    .fill(appState.ledfxIsRunning ? .green : .red)
                                    .frame(width: 10, height: 10)
                                if appState.ledfxIsRunning {
                                    Text("LedFX Online \(appState.ledfxHealthSummary)")
                                } else {
                                    Text("LedFX Offline")
                                }
                            }
                            Text("Source: \(appState.playbackSource.uppercased())")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("LedFX: \(appState.ledfxBaseURL)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                }

                GroupBox("Renderer") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Render Engine", systemImage: "power.circle.fill")
                                    .font(.headline)
                                Text(appState.renderEnabled ? "ON" : "OFF")
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(appState.renderEnabled ? .green : .secondary)
                                Text("Disables all shader/text/image rendering and Syphon output when OFF.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Toggle("", isOn: appState.renderEnabledBinding)
                                .toggleStyle(.switch)
                                .scaleEffect(1.4)
                                .labelsHidden()
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Syphon Outputs")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(RenderOutput.allCases, id: \.self) { output in
                                HStack {
                                    Text(renderOutputLabel(output))
                                        .font(.caption)
                                    Spacer()
                                    Toggle("", isOn: appState.renderOutputBinding(output))
                                        .labelsHidden()
                                }
                            }
                        }
                    }
                    .padding()
                }

                GroupBox("Launch Control") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            Button {
                                appState.send(.launcher(.launchMissingRequested))
                            } label: {
                                HStack {
                                    Image(systemName: "play.rectangle.fill")
                                    Text(appState.launcherIsLaunchingAll ? "Launching..." : "Launch Missing Controlled Apps")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(appState.launcherIsLaunchingAll || appState.launcherTargets.isEmpty)
                            .accessibilityIdentifier(A11yID.masterLaunchAllButton)

                            Button(role: .destructive) {
                                appState.send(.launcher(.terminateAllRequested))
                            } label: {
                                HStack {
                                    Image(systemName: "stop.fill")
                                    Text("Stop All")
                                        .fontWeight(.semibold)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .disabled(appState.launcherIsLaunchingAll || appState.launcherRunningTargetIDs.isEmpty)
                        }

                        if let summary = appState.launcherLastLaunchSummary, !summary.isEmpty {
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let error = appState.launcherLastError, !error.isEmpty {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        let spacing: CGFloat = 16
                        let hasMeasuredWidth = launcherSectionWidth > 0
                        let usableWidth = max(launcherSectionWidth - spacing, 0)
                        let listColumnWidth = hasMeasuredWidth ? usableWidth * 0.7 : nil
                        let controlsColumnWidth = hasMeasuredWidth ? usableWidth * 0.3 : nil

                        HStack(alignment: .top, spacing: spacing) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Controlled Apps & Commands")
                                    .font(.headline)

                                if appState.launcherTargets.isEmpty {
                                    Text("No controlled apps or commands configured yet.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    VStack(spacing: 8) {
                                        ForEach(appState.launcherTargets) { target in
                                            let isRunning = appState.launcherRunningTargetIDs.contains(target.id)

                                            HStack(alignment: .center, spacing: 12) {
                                                Circle()
                                                    .fill(isRunning ? .green : .gray)
                                                    .frame(width: 8, height: 8)

                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(target.displayName)
                                                        .font(.subheadline.weight(.semibold))
                                                    Text(target.kind == .app
                                                         ? (target.appPath ?? "App")
                                                         : (target.commandLine ?? "Command"))
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                }

                                                Spacer()

                                                Toggle(
                                                    "Auto-Start",
                                                    isOn: Binding(
                                                        get: { target.autoStart },
                                                        set: { enabled in
                                                            appState.send(.launcher(.setAutoStart(id: target.id, enabled: enabled)))
                                                        }
                                                    )
                                                )
                                                .toggleStyle(.switch)
                                                .labelsHidden()

                                                Button("Launch") {
                                                    appState.send(.launcher(.launchTargetRequested(id: target.id)))
                                                }
                                                .buttonStyle(.borderedProminent)
                                                .disabled(appState.launcherIsLaunchingAll)

                                                if target.kind == .app {
                                                    Button("Stop") {
                                                        appState.send(.launcher(.terminateTargetRequested(id: target.id)))
                                                    }
                                                    .buttonStyle(.bordered)
                                                    .disabled(!isRunning || appState.launcherIsLaunchingAll)
                                                }

                                                Button(role: .destructive) {
                                                    appState.send(.launcher(.removeTarget(id: target.id)))
                                                } label: {
                                                    Image(systemName: "trash")
                                                }
                                                .buttonStyle(.bordered)
                                            }
                                            .padding(.vertical, 4)
                                        }
                                    }
                                }
                            }
                            .frame(width: listColumnWidth, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            VStack(alignment: .leading, spacing: 12) {
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                                    .foregroundStyle(.secondary)
                                    .frame(height: 90)
                                    .overlay {
                                        VStack(spacing: 4) {
                                            Image(systemName: "square.and.arrow.down.on.square")
                                            Text("Drag macOS apps here (Spotify.app, Synesthesia.app, etc.)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .dropDestination(for: URL.self) { droppedURLs, _ in
                                        appState.send(.launcher(.addAppTargetsRequested(droppedURLs)))
                                        return true
                                    }
                                    .accessibilityIdentifier(A11yID.masterLaunchDropZone)

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Add Command")
                                        .font(.headline)

                                    TextField("Command line (example: uv run ledfx)", text: $commandLineDraft)
                                        .textFieldStyle(.roundedBorder)

                                    TextField("Working directory (optional, example: ~/Desktop/projects/ledfx)", text: $workingDirectoryDraft)
                                        .textFieldStyle(.roundedBorder)

                                    Button("Add Command Target") {
                                        let cwd = workingDirectoryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                                        appState.send(.launcher(.addCommandTargetRequested(
                                            commandLine: commandLineDraft,
                                            workingDirectory: cwd.isEmpty ? nil : cwd
                                        )))
                                        commandLineDraft = ""
                                        workingDirectoryDraft = ""
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(commandLineDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    .accessibilityIdentifier(A11yID.masterAddCommandButton)
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Quick Add")
                                        .font(.headline)

                                    ForEach(KnownAppTarget.allCases, id: \.rawValue) { known in
                                        let alreadyAdded = appState.launcherTargets.contains {
                                            $0.normalizedIdentity == known.launchTarget.normalizedIdentity
                                        }
                                        Button {
                                            appState.send(.launcher(.addKnownTarget(known)))
                                        } label: {
                                            HStack {
                                                Image(systemName: "plus.circle")
                                                Text(known.launchTarget.displayName)
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(alreadyAdded)
                                    }
                                }
                            }
                            .frame(width: controlsColumnWidth, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            GeometryReader { proxy in
                                Color.clear
                                    .onAppear {
                                        launcherSectionWidth = proxy.size.width
                                    }
                                    .onChange(of: proxy.size.width) { _, newValue in
                                        launcherSectionWidth = newValue
                                    }
                            }
                        }
                    }
                    .padding()
                }
                
                // Quick Stats
                HStack(spacing: 16) {
                    StatCard(title: "Shaders", value: "\(appState.shaderCount)", icon: "sparkles")
                    StatCard(title: "OSC Messages", value: "\(appState.oscMessageCount)", icon: "antenna.radiowaves.left.and.right")
                    StatCard(title: "Log Entries", value: "\(appState.logEntries.count)", icon: "doc.text")
                }
                
                Spacer()
            }
            .padding()
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    private func progressRatio(track: Track) -> Double {
        guard track.duration > 0 else { return 0 }
        return min(1.0, max(0.0, appState.playbackPosition / track.duration))
    }

    private func renderOutputLabel(_ output: RenderOutput) -> String {
        switch output {
        case .shader: return "Shader"
        case .mask: return "Mask"
        case .lyrics: return "Lyrics"
        case .refrain: return "Refrain"
        case .songInfo: return "Song Info"
        case .image: return "Image"
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        GroupBox {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.blue)
                Text(value)
                    .font(.title)
                    .fontWeight(.bold)
                    .monospacedDigit()
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}

#Preview {
    MasterControlView()
        .environmentObject(AppState())
        .frame(minWidth: 500, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
}
