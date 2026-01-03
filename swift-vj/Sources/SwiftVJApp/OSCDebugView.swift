// OSCDebugView - OSC message log and test sender
// Phase 4: SwiftUI Shell

import SwiftUI
import SwiftVJCore
import OSCKit

struct OSCDebugView: View {
    @EnvironmentObject var appState: AppState
    @State private var filterText = ""
    @State private var testAddress = "/test/message"
    @State private var testArg1 = "hello"
    @State private var testArg2 = "1.0"
    @State private var showSentOnly = false
    @State private var showReceivedOnly = false
    
    var filteredMessages: [OSCLogEntry] {
        appState.oscMessages.filter { msg in
            if filterText.isEmpty { return true }
            return msg.address.localizedCaseInsensitiveContains(filterText)
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
                    TextField("Filter by address...", text: $filterText)
                        .textFieldStyle(.plain)
                    
                    if !filterText.isEmpty {
                        Button {
                            filterText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(.quaternary)
                .cornerRadius(8)
                .padding()
                
                Divider()
                
                // Message list
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(filteredMessages.reversed()) { msg in
                            OSCMessageRow(message: msg)
                        }
                    }
                    .padding(.horizontal)
                }
                
                Divider()
                
                // Stats bar
                HStack {
                    Text("\(appState.oscMessages.count) messages")
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        appState.oscMessages.removeAll()
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
                        StatusRow(label: "Forward: Processing", value: "10000", isActive: true)
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
    }
    
    private func sendTestMessage() {
        do {
            try appState.oscHub.sendToProcessing(testAddress, values: [testArg1, Float(testArg2) ?? Float(0)])
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
            try appState.oscHub.sendToProcessing(address, values: values)
            appState.recordOSCMessage(address, args: args)
        } catch {
            appState.log("OSC send failed: \(error)", level: .error)
        }
    }
}

struct OSCMessageRow: View {
    let message: OSCLogEntry
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(message.timestamp, style: .time)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 70)
            
            Text(message.address)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.blue)
            
            Text(message.args.joined(separator: ", "))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.blue.opacity(0.05))
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
