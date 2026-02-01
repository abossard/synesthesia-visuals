// RESTTabView.swift - REST requests tab UI

import SwiftUI

struct RESTTabView: View {
    let state: BridgeStateSnapshot
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with counts
            HStack {
                Label("\(state.stats.totalRestSent) sent", systemImage: "arrow.up.circle")
                Spacer()
                if state.stats.totalRestFailures > 0 {
                    Label("\(state.stats.totalRestFailures) failed", systemImage: "xmark.circle")
                        .foregroundColor(.red)
                }
                Spacer()
                Text(String(format: "%.1f req/s", state.stats.httpRate))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            // Request list
            List {
                ForEach(state.recentHttp.reversed()) { record in
                    HTTPRequestRow(record: record)
                }
            }
            .listStyle(.plain)
        }
    }
}

struct HTTPRequestRow: View {
    let record: HTTPRequestRecord
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack {
                // Timestamp
                Text(formatTime(record.timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Status badge
                if record.planned {
                    Text("PLANNED")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                } else if let status = record.statusCode {
                    statusBadge(status)
                } else if record.error != nil {
                    Text("ERROR")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.2))
                        .foregroundColor(.red)
                        .cornerRadius(4)
                }
                
                Spacer()
                
                // Expand button
                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            
            // Request line
            HStack {
                Text(record.method)
                    .font(.caption.bold().monospaced())
                    .foregroundColor(.blue)
                Text(record.url)
                    .font(.caption.monospaced())
                    .lineLimit(1)
            }
            
            // Error
            if let error = record.error {
                Label(error, systemImage: "xmark.circle")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            // Expanded details
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if let body = record.bodyPreview {
                        VStack(alignment: .leading) {
                            Text("Request Body:")
                                .font(.caption.bold())
                            Text(body)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .padding(4)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                    
                    if let response = record.responsePreview {
                        VStack(alignment: .leading) {
                            Text("Response:")
                                .font(.caption.bold())
                            Text(response)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .padding(4)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func statusBadge(_ code: Int) -> some View {
        let color: Color = (200..<300).contains(code)
            ? .green
            : (400..<500).contains(code)
                ? .orange
                : .red
        
        return Text("\(code)")
            .font(.caption.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}
