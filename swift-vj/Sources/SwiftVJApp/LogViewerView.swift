// LogViewerView - Application log viewer
// Phase 4: SwiftUI Shell

import SwiftUI

struct LogViewerView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedLevel: LogLevel? = nil
    @State private var searchText = ""
    @State private var autoScroll = true
    
    var filteredLogs: [LogEntry] {
        appState.logEntries.filter { entry in
            let matchesLevel = selectedLevel == nil || entry.level == selectedLevel
            let matchesSearch = searchText.isEmpty || 
                entry.message.localizedCaseInsensitiveContains(searchText)
            return matchesLevel && matchesSearch
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack(spacing: 16) {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search logs...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(.quaternary)
                .cornerRadius(8)
                .frame(maxWidth: 300)
                
                // Level filter
                HStack(spacing: 4) {
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Button {
                            selectedLevel = selectedLevel == level ? nil : level
                        } label: {
                            Text(level.rawValue)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.bordered)
                        .tint(selectedLevel == level ? level.color : .gray)
                    }
                }
                
                Spacer()
                
                // Controls
                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.switch)
                
                Text("\(filteredLogs.count) / \(appState.logEntries.count)")
                    .foregroundColor(.secondary)
                
                Button {
                    appState.logEntries.removeAll()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.borderless)
            }
            .padding()
            .background(.bar)
            
            Divider()
            
            // Log entries
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(filteredLogs) { entry in
                            LogRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
                .onChange(of: appState.logEntries.count) { _, _ in
                    if autoScroll, let last = filteredLogs.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
}

struct LogRow: View {
    let entry: LogEntry
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(entry.timestamp, style: .time)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            
            // Level badge
            Text(entry.level.rawValue)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(entry.level.color)
                .cornerRadius(4)
                .frame(width: 50)
            
            // Message
            Text(entry.message)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(entry.level == .error ? .red : .primary)
                .textSelection(.enabled)
            
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(entry.level == .error ? Color.red.opacity(0.1) : Color.clear)
    }
}

#Preview {
    LogViewerView()
        .environmentObject({
            let state = AppState()
            state.log("Application started", level: .info)
            state.log("Loading shaders...", level: .debug)
            state.log("Found 45 shaders", level: .info)
            state.log("OSC hub started on port 9999", level: .info)
            state.log("VirtualDJ connected", level: .info)
            state.log("Track changed: Queen - Bohemian Rhapsody", level: .info)
            state.log("Fetching lyrics...", level: .debug)
            state.log("Network timeout", level: .warning)
            state.log("Retry successful", level: .info)
            state.log("LM Studio connection failed", level: .error)
            return state
        }())
        .frame(width: 800, height: 500)
}
