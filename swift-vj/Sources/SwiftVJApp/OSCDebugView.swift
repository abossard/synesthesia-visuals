// OSCDebugView - OSC message log and test sender
// Phase 4: SwiftUI Shell

import SwiftUI
import SwiftVJCore
import OSCKit

struct OSCDebugView: View {
    @EnvironmentObject var appState: AppState
    @State private var testAddress = "/test/message"
    @State private var testArg1 = "hello"
    @State private var testArg2 = "1.0"
    @State private var showAudioMessages = false  // Audio messages hidden by default (noisy)
    @State private var expandedGroups: Set<String> = ["shader", "textler", "image", "other"]  // Expanded by default
    @State private var groupedMessagesCache: [(group: String, messages: [OSCLogEntry])] = []

    /// Group OSC messages by category.
    private func rebuildGroupedMessages() {
        let sorted = appState.oscMessages.values.sorted { $0.address < $1.address }

        // Filter audio if hidden
        let filtered = showAudioMessages ? sorted : sorted.filter { !$0.address.hasPrefix("/audio/") }

        // Group by first path component
        var groups: [String: [OSCLogEntry]] = [:]
        for msg in filtered {
            let group = extractGroup(from: msg.address)
            groups[group, default: []].append(msg)
        }

        // Sort groups: audio last (if shown), then alphabetically
        let sortedGroups = groups.keys.sorted { lhs, rhs in
            if lhs == "audio" { return false }
            if rhs == "audio" { return true }
            return lhs < rhs
        }

        groupedMessagesCache = sortedGroups.map { (group: $0, messages: groups[$0] ?? []) }
    }
    
    /// Extract group name from OSC address
    private func extractGroup(from address: String) -> String {
        let parts = address.split(separator: "/").map(String.init)
        guard parts.count >= 1 else { return "other" }
        let first = parts[0].lowercased()
        // Known groups
        if ["audio", "shader", "textler", "image", "vj", "beat", "bpm", "level"].contains(first) {
            return first
        }
        return "other"
    }
    
    /// Color for group header
    private func groupColor(_ group: String) -> Color {
        switch group {
        case "audio": return .orange
        case "shader": return .purple
        case "textler": return .blue
        case "image": return .green
        case "vj": return .pink
        case "beat", "bpm": return .red
        case "level": return .yellow
        default: return .gray
        }
    }
    
    var body: some View {
        HSplitView {
            // Message log (left)
            VStack(spacing: 0) {
                // Filter bar
                HStack {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundColor(.secondary)
                    TextField("Capture filter...", text: appState.oscFilterBinding)
                        .textFieldStyle(.plain)
                        .onChange(of: appState.oscFilter) { _, _ in
                            appState.clearOscMessages()
                        }
                    
                    if !appState.oscFilter.isEmpty {
                        Button {
                            appState.setOscFilter("")
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Divider().frame(height: 20)
                    
                    // Audio toggle
                    Toggle(isOn: $showAudioMessages) {
                        Label("Audio", systemImage: "waveform")
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .tint(showAudioMessages ? .orange : .gray)
                }
                .padding(8)
                .background(.quaternary)
                .cornerRadius(8)
                .padding()
                
                Divider()
                
                // Grouped message list
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(groupedMessagesCache, id: \.group) { group in
                            DisclosureGroup(
                                isExpanded: Binding(
                                    get: { expandedGroups.contains(group.group) },
                                    set: { isExpanded in
                                        if isExpanded {
                                            expandedGroups.insert(group.group)
                                        } else {
                                            expandedGroups.remove(group.group)
                                        }
                                    }
                                )
                            ) {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(group.messages) { msg in
                                        OSCMessageRow(message: msg, groupColor: groupColor(group.group))
                                    }
                                }
                                .padding(.leading, 8)
                            } label: {
                                HStack {
                                    Circle()
                                        .fill(groupColor(group.group))
                                        .frame(width: 10, height: 10)
                                    Text(group.group.uppercased())
                                        .font(.headline)
                                        .foregroundColor(groupColor(group.group))
                                    Text("(\(group.messages.count))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
                
                Divider()
                
                // Stats bar
                HStack {
                    // Hub status
                    let stats = appState.oscHub.stats()
                    let running = stats["running"] as? Bool ?? false
                    let received = stats["messagesReceived"] as? Int ?? 0
                    
                    Image(systemName: running ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                        .foregroundColor(running ? .green : .red)
                    Text(":\(appState.oscHub.receivePort)")
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text("\(received) recv")
                        .font(.caption.monospaced())
                        .foregroundColor(received > 0 ? .primary : .secondary)
                    
                    Divider().frame(height: 14)
                    
                    Text("\(appState.oscMessages.count) addresses (\(appState.oscMessageCount) total)")
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        appState.clearOscMessages()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                }
                .padding()
                .background(.bar)
            }
            .frame(minWidth: 400)
            
            // Test sender (right)
            VStack(spacing: 16) {
                GroupBox("Audio Levels") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let audioManager = appState.renderEngine?.audioManager {
                            AudioVisualizerView(audioManager: audioManager)
                                .frame(height: 60)
                        } else {
                            Text("Audio manager not available")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                }

                GroupBox("Send Test Message") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Address", text: $testAddress)
                            .textFieldStyle(.roundedBorder)
                        
                        HStack {
                            TextField("Arg 1", text: $testArg1)
                                .textFieldStyle(.roundedBorder)
                            TextField("Arg 2", text: $testArg2)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        HStack {
                            Spacer()
                            Button {
                                sendTestMessage()
                            } label: {
                                Label("Send", systemImage: "paperplane.fill")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding()
                }
                
                GroupBox("Quick Actions") {
                    VStack(alignment: .leading, spacing: 8) {
                        QuickOSCButton(address: "/shader/load", args: ["neon_giza", "0.8", "0.5"]) {
                            sendQuickMessage($0, args: $1)
                        }
                        QuickOSCButton(address: "/textler/track", args: ["1", "demo", "Artist", "Title"]) {
                            sendQuickMessage($0, args: $1)
                        }
                        QuickOSCButton(address: "/audio/beat/onbeat", args: ["1"]) {
                            sendQuickMessage($0, args: $1)
                        }
                        QuickOSCButton(address: "/image/folder", args: ["/tmp/images"]) {
                            sendQuickMessage($0, args: $1)
                        }
                    }
                    .padding()
                }
                
                GroupBox("Connection Status") {
                    VStack(alignment: .leading, spacing: 8) {
                        StatusRow(label: "Receive Port", value: "9999", isActive: true)
                        StatusRow(label: "Forward: Magic", value: "11111", isActive: true)
                        StatusRow(label: "VirtualDJ", value: "9009", isActive: true)
                        StatusRow(label: "Synesthesia", value: "7777", isActive: true)
                    }
                    .padding()
                }
                
                Spacer()
            }
            .padding()
            .frame(minWidth: 280, maxWidth: 320)
        }
        .onAppear {
            appState.setOscDebugEnabled(true)
            rebuildGroupedMessages()
        }
        .onChange(of: appState.oscMessageCount) { _, _ in rebuildGroupedMessages() }
        .onChange(of: showAudioMessages) { _, _ in rebuildGroupedMessages() }
        .onDisappear {
            appState.setOscDebugEnabled(false)
            // Free memory - clear captured messages when view hidden
            appState.clearOscMessages()
            groupedMessagesCache = []
        }
    }
    
    private func sendTestMessage() {
        do {
            try appState.oscHub.sendToMagic(testAddress, values: [testArg1, Float(testArg2) ?? Float(0)])
            appState.recordOSCMessage(testAddress, args: [testArg1, testArg2])
        } catch {
            appState.log("OSC send failed: \(error)", level: .error)
        }
    }
    
    private func sendQuickMessage(_ address: String, args: [String]) {
        do {
            let values: [any OSCValue] = args.map { arg -> any OSCValue in
                if let float = Float(arg) { return float }
                if let int = Int32(arg) { return int }
                return arg
            }
            try appState.oscHub.sendToMagic(address, values: values)
            appState.recordOSCMessage(address, args: args)
        } catch {
            appState.log("OSC send failed: \(error)", level: .error)
        }
    }
}

struct OSCMessageRow: View {
    let message: OSCLogEntry
    var groupColor: Color = .blue
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(message.timestamp, style: .time)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 70)
            
            Text(message.address)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(groupColor)
            
            Text(message.args.joined(separator: ", "))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(groupColor.opacity(0.05))
        .cornerRadius(4)
    }
}

struct QuickOSCButton: View {
    let address: String
    let args: [String]
    let action: (String, [String]) -> Void
    
    var body: some View {
        Button {
            action(address, args)
        } label: {
            HStack {
                Text(address)
                    .font(.system(.caption, design: .monospaced))
                Spacer()
                Image(systemName: "arrow.right.circle")
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.bordered)
    }
}

struct StatusRow: View {
    let label: String
    let value: String
    let isActive: Bool
    
    var body: some View {
        HStack {
            Circle()
                .fill(isActive ? .green : .red)
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }
}

#Preview {
    OSCDebugView()
        .environmentObject(AppState())
        .frame(width: 900, height: 600)
}
