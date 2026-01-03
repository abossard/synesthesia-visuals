// MasterControlView - Playback status and controls
// Phase 4: SwiftUI Shell

import SwiftUI
import SwiftVJCore

struct MasterControlView: View {
    @EnvironmentObject var appState: AppState
    
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
                                        Image(systemName: "music.note")
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
                                    Text(formatDuration(track.duration))
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                
                                Spacer()
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
                                .frame(width: 100, height: 70)
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
                            Text("Source: \(appState.playbackSource.uppercased())")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                }
                
                // Timing Controls
                GroupBox("Timing Adjustment") {
                    VStack(spacing: 16) {
                        HStack {
                            Text("Offset:")
                                .foregroundColor(.secondary)
                            Text("\(appState.timingOffsetMs) ms")
                                .font(.title2)
                                .fontWeight(.medium)
                                .monospacedDigit()
                            Spacer()
                        }
                        
                        HStack(spacing: 12) {
                            ForEach([-100, -50, -10, 10, 50, 100], id: \.self) { delta in
                                Button {
                                    appState.adjustTiming(delta)
                                } label: {
                                    Text(delta > 0 ? "+\(delta)" : "\(delta)")
                                        .monospacedDigit()
                                }
                                .buttonStyle(.bordered)
                            }
                            
                            Spacer()
                            
                            Button("Reset") {
                                let current = appState.timingOffsetMs
                                appState.adjustTiming(-current)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
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
        .frame(width: 700, height: 600)
}
