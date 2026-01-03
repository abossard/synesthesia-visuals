// PipelineStatusView - Step-by-step progress display
// Phase 4: SwiftUI Shell

import SwiftUI
import SwiftVJCore

struct PipelineStatusView: View {
    @EnvironmentObject var appState: AppState
    
    // Pipeline step definitions
    let pipelineStepDefs: [(name: String, icon: String)] = [
        ("detect_track", "music.note"),
        ("fetch_lyrics", "text.quote"),
        ("parse_lrc", "doc.text"),
        ("analyze_refrain", "repeat"),
        ("extract_keywords", "tag"),
        ("categorize_song", "brain"),
        ("match_shader", "sparkles"),
        ("fetch_images", "photo.on.rectangle"),
        ("broadcast_osc", "antenna.radiowaves.left.and.right")
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with current track
            if let track = appState.currentTrack {
                HStack {
                    Image(systemName: "music.note")
                        .foregroundColor(.blue)
                    Text("\(track.artist) - \(track.title)")
                        .font(.headline)
                    Spacer()
                    if let result = appState.pipelineResult {
                        Text("\(result.totalTimeMs)ms")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary)
                            .cornerRadius(4)
                    }
                }
                .padding()
                .background(.bar)
            }
            
            Divider()
            
            // Pipeline steps
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(pipelineStepDefs, id: \.name) { stepDef in
                        let step = appState.pipelineSteps.first { $0.name == stepDef.name }
                        PipelineStepRow(
                            name: stepDef.name,
                            icon: stepDef.icon,
                            status: step?.status ?? "pending",
                            timestamp: step?.timestamp
                        )
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Result summary
            if let result = appState.pipelineResult {
                GroupBox("Result") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Lyrics", systemImage: result.lyricsFound ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundColor(result.lyricsFound ? .green : .secondary)
                            Spacer()
                            if result.lyricsFound {
                                Text("\(result.lyricsLineCount) lines")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if result.shaderMatched {
                            HStack {
                                Label("Shader", systemImage: "sparkles")
                                    .foregroundColor(.purple)
                                Spacer()
                                Text(result.shaderName)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        HStack {
                            Label("Energy", systemImage: "bolt.fill")
                                .foregroundColor(.orange)
                            Spacer()
                            Text(String(format: "%.2f", result.energy))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Label("Valence", systemImage: "face.smiling")
                                .foregroundColor(.yellow)
                            Spacer()
                            Text(String(format: "%.2f", result.valence))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                }
                .padding()
            }
        }
    }
}

struct PipelineStepRow: View {
    let name: String
    let icon: String
    let status: String
    let timestamp: Date?
    
    var body: some View {
        HStack {
            // Icon
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(statusColor)
            
            // Name
            Text(name.replacingOccurrences(of: "_", with: " ").capitalized)
                .frame(width: 150, alignment: .leading)
            
            // Status
            statusBadge
            
            Spacer()
            
            // Timestamp
            if let timestamp = timestamp {
                Text(timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(status == "running" ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(8)
    }
    
    var statusColor: Color {
        switch status {
        case "complete", "completed": return .green
        case "running": return .blue
        case "skipped": return .orange
        case "error": return .red
        default: return .secondary
        }
    }
    
    @ViewBuilder
    var statusBadge: some View {
        HStack(spacing: 4) {
            switch status {
            case "running":
                ProgressView()
                    .scaleEffect(0.6)
                Text("Running")
            case "complete", "completed":
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Complete")
            case "skipped":
                Image(systemName: "arrow.right.circle")
                    .foregroundColor(.orange)
                Text("Skipped")
            case "error":
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text("Error")
            default:
                Image(systemName: "circle")
                    .foregroundColor(.secondary)
                Text("Pending")
            }
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary)
        .cornerRadius(4)
    }
}

#Preview {
    PipelineStatusView()
        .environmentObject(AppState())
        .frame(width: 600, height: 500)
}
