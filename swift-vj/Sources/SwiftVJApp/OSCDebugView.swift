// OSCDebugView - OSC message log and test sender
// Phase 4: SwiftUI Shell

import SwiftUI
import SwiftVJCore
import OSCKit
import AppKit

struct OSCDebugView: View {
    @EnvironmentObject var appState: AppState
    @State private var testAddress = "/test/message"
    @State private var testArg1 = "hello"
    @State private var testArg2 = "1.0"
    @State private var selectedMessageIDs: Set<UUID> = []
    
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

    private var visibleMessages: [OSCLogEntry] {
        let sorted = appState.oscMessages.values.sorted { $0.address < $1.address }
        if appState.oscAudioMessagesEnabled { return sorted }
        return sorted.filter { !$0.address.hasPrefix("/audio/") }
    }

    private func selectedMessagesPayload() -> String? {
        guard !selectedMessageIDs.isEmpty else { return nil }
        let byID = Dictionary(uniqueKeysWithValues: visibleMessages.map { ($0.id, $0) })
        let rows = selectedMessageIDs.compactMap { byID[$0] }.sorted { $0.address < $1.address }
        guard !rows.isEmpty else { return nil }
        return rows
            .map { "\($0.timestamp.ISO8601Format()) \($0.address) \($0.args.joined(separator: ", "))" }
        .joined(separator: "\n")
    }

    private func selectedMessagesProviders() -> [NSItemProvider] {
        guard let payload = selectedMessagesPayload() else { return [] }
        return [NSItemProvider(object: payload as NSString)]
    }

    private func copySelectedMessages() {
        guard let payload = selectedMessagesPayload() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
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
                    Toggle(isOn: appState.oscAudioMessagesEnabledBinding) {
                        Label("Audio", systemImage: "waveform")
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .tint(appState.oscAudioMessagesEnabled ? .orange : .gray)
                }
                .padding(8)
                .background(.quaternary)
                .cornerRadius(8)
                .padding()
                
                Divider()
                
                // Latest message per address (select rows, Cmd-C to copy full payload with args)
                List(visibleMessages, selection: $selectedMessageIDs) { msg in
                    OSCMessageRow(message: msg, groupColor: groupColor(extractGroup(from: msg.address)))
                        .tag(msg.id)
                }
                .listStyle(.plain)
                .onCopyCommand { selectedMessagesProviders() }
                
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
        }
        .onDisappear {
            appState.setOscDebugEnabled(false)
            // Free memory - clear captured messages when view hidden
            appState.clearOscMessages()
            selectedMessageIDs.removeAll()
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
                .lineLimit(1)
            
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(groupColor.opacity(0.05))
        .cornerRadius(4)
        .contextMenu {
            Button("Copy Message") {
                copyMessageToClipboard()
            }
        }
    }

    private func copyMessageToClipboard() {
        let payload = "\(message.timestamp.ISO8601Format()) \(message.address) \(message.args.joined(separator: ", "))"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
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
