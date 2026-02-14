// PipelineStatusView - Step-by-step progress display
// Phase 4: SwiftUI Shell

import SwiftUI
import SwiftVJCore

struct PipelineStatusView: View {
    @EnvironmentObject var appState: AppState
    
    // Pipeline step definitions - must match PipelineModule step names
    let pipelineStepDefs: [(name: String, icon: String)] = [
        ("lyrics", "text.quote"),
        ("ai", "brain"),
        ("shaders", "sparkles"),
        ("images", "photo.on.rectangle"),
        ("osc", "antenna.radiowaves.left.and.right")
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
                            details: step?.details ?? [],
                            timestamp: step?.timestamp,
                            isExpanded: appState.pipelineExpandedSteps.contains(stepDef.name),
                            onToggle: { appState.togglePipelineStepExpansion(stepDef.name) }
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
                        // Lyrics
                        HStack {
                            Label("Lyrics", systemImage: result.lyricsFound ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundColor(result.lyricsFound ? .green : .secondary)
                            Spacer()
                            if result.lyricsFound {
                                Text("\(result.lyricsLineCount) lines")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // Keywords (if any)
                        if !result.keywords.isEmpty {
                            HStack(alignment: .top) {
                                Label("Keywords", systemImage: "tag")
                                    .foregroundColor(.blue)
                                Spacer()
                                Text(result.keywords.prefix(5).joined(separator: ", "))
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                                    .lineLimit(2)
                                    .frame(maxWidth: 200, alignment: .trailing)
                            }
                        }
                        
                        // Themes (if any)
                        if !result.themes.isEmpty {
                            HStack(alignment: .top) {
                                Label("Themes", systemImage: "lightbulb")
                                    .foregroundColor(.cyan)
                                Spacer()
                                Text(result.themes.prefix(3).joined(separator: ", "))
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                                    .frame(maxWidth: 150, alignment: .trailing)
                            }
                        }
                        
                        // Mood
                        HStack {
                            Label("Mood", systemImage: "face.smiling")
                                .foregroundColor(.yellow)
                            Spacer()
                            Text(result.mood)
                                .foregroundColor(.secondary)
                        }
                        
                        // Energy & Valence
                        HStack {
                            Label("Energy", systemImage: "bolt.fill")
                                .foregroundColor(.orange)
                            ProgressView(value: result.energy)
                                .frame(width: 80)
                            Text(String(format: "%.1f", result.energy))
                                .foregroundColor(.secondary)
                                .frame(width: 30)
                            
                            Spacer()
                            
                            Label("Valence", systemImage: "heart.fill")
                                .foregroundColor(.pink)
                            ProgressView(value: (result.valence + 1) / 2)  // -1..1 → 0..1
                                .frame(width: 80)
                            Text(String(format: "%.1f", result.valence))
                                .foregroundColor(.secondary)
                                .frame(width: 30)
                        }
                        
                        Divider()
                        
                        // Shader
                        HStack {
                            Label("Shader", systemImage: "sparkles")
                                .foregroundColor(result.shaderMatched ? .purple : .secondary)
                            Spacer()
                            if result.shaderMatched {
                                Text(result.shaderName)
                                    .foregroundColor(.secondary)
                                Text("(\(String(format: "%.0f%%", result.shaderScore * 100)))")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            } else {
                                Text("No match")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // Images
                        HStack {
                            Label("Images", systemImage: "photo.on.rectangle")
                                .foregroundColor(result.imagesFound ? .green : .secondary)
                            Spacer()
                            if result.imagesFound {
                                Text("\(result.imagesCount) images")
                                    .foregroundColor(.secondary)
                            } else {
                                Text("None fetched")
                                    .foregroundColor(.secondary)
                            }
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
    let details: [String]
    let timestamp: Date?
    let isExpanded: Bool
    let onToggle: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
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
                
                // Details disclosure
                Button(action: onToggle) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                
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
            .contentShape(Rectangle())
            .onTapGesture {
                onToggle()
            }
            
            // Details panel (collapsible)
            if isExpanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if details.isEmpty {
                            Text("No details yet.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(Array(details.enumerated()), id: \.offset) { item in
                                Text(item.element)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(4)
                .frame(maxHeight: details.count > 12 ? 220 : nil)
            }
        }
    }
    
    var statusColor: Color {
        switch status.lowercased() {
        case let s where s.hasPrefix("✓"): return .green
        case "running": return .blue
        case let s where s.hasPrefix("✗"): return .orange  // Ran but no result
        case let s where s.contains("error"): return .red
        default: return .secondary
        }
    }
    
    @ViewBuilder
    var statusBadge: some View {
        HStack(spacing: 4) {
            if status == "running" {
                ProgressView()
                    .scaleEffect(0.6)
                Text("Running")
            } else if status.hasPrefix("✓") {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text(status)  // Shows "✓ 42 lines" etc
            } else if status.hasPrefix("✗") {
                Image(systemName: "minus.circle")
                    .foregroundColor(.orange)
                Text(String(status.dropFirst(2)))  // Remove "✗ " prefix, shows "Not found" etc
            } else if status.lowercased().contains("error") {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text(status)
            } else {
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
