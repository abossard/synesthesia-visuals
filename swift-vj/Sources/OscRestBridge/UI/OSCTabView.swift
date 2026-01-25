// OSCTabView.swift - OSC messages tab UI

import SwiftUI

struct OSCTabView: View {
    let state: BridgeStateSnapshot
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with counts
            HStack {
                Label("\(state.stats.totalOscReceived) total", systemImage: "antenna.radiowaves.left.and.right")
                Spacer()
                if state.stats.totalOscUnknown > 0 {
                    Label("\(state.stats.totalOscUnknown) unknown", systemImage: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                }
                Spacer()
                Text(String(format: "%.1f msg/s", state.stats.oscRate))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            // Message list
            List {
                ForEach(state.recentOsc.reversed()) { record in
                    OSCMessageRow(record: record)
                }
            }
            .listStyle(.plain)
        }
    }
}

struct OSCMessageRow: View {
    let record: OSCMessageRecord
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Timestamp
                Text(formatTime(record.timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Value
                Text(String(format: "%.2f", record.value))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.blue)
            }
            
            // Path
            Text(record.path)
                .font(.caption.monospaced())
            
            // Parsed route or error
            if let parsed = record.parsed {
                parsedRouteView(parsed)
                    .font(.caption)
                    .foregroundColor(.green)
            } else if let reason = record.unknownReason {
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private func parsedRouteView(_ route: ParsedOSCRoute) -> some View {
        switch route {
        case .scene(let slot, let name):
            Label("Scene: \(name) on slot \(slot)", systemImage: "lightbulb")
        case .oneshot(let slot, let name):
            Label("Oneshot: \(name) on slot \(slot)", systemImage: "bolt")
        case .blackout(let slot):
            Label("Blackout on slot \(slot)", systemImage: "moon")
        case .param(let slot, let name):
            Label("Param: \(name) on slot \(slot)", systemImage: "slider.horizontal.3")
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}
