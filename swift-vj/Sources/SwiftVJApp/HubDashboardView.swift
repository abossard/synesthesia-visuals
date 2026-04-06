// HubDashboardView - Unified Hub Dashboard merging OSC Debug + Bridge Status
// Three-panel layout: Status Sidebar | Message Log | Actions Panel

import SwiftUI
import SwiftVJCore
import OscRestBridge
import OSCKit
import AppKit

struct HubDashboardView: View {
    @EnvironmentObject var appState: AppState

    @State private var hubMessages: [HubMessage] = []
    @State private var filterText: String = ""
    @State private var activeSourceFilters: Set<HubMessageSource> = Set(HubMessageSource.allCases)
    @State private var bridgeSnapshot: BridgeStateSnapshot?
    @State private var refreshTask: Task<Void, Never>?

    // Test sender state
    @State private var testAddress = "/test/message"
    @State private var testArg1 = "hello"
    @State private var testArg2 = "1.0"

    private var bridge: OscRestBridgeService? { appState.oscRestBridge }

    private var oscBridgeConfig: OSCBridgeConfig { .default }

    private var filteredMessages: [HubMessage] {
        hubMessages.filter { msg in
            guard activeSourceFilters.contains(msg.source) else { return false }
            if filterText.isEmpty { return true }
            let query = filterText.lowercased()
            return msg.title.lowercased().contains(query)
                || msg.detail.lowercased().contains(query)
        }
    }

    var body: some View {
        HSplitView {
            statusSidebar
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)

            messageLog
                .frame(minWidth: 350)

            actionsPanel
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)
        }
        .onAppear {
            appState.setOscDebugEnabled(true)
            startPolling()
        }
        .onDisappear {
            appState.setOscDebugEnabled(false)
            appState.clearOscMessages()
            refreshTask?.cancel()
            refreshTask = nil
        }
    }

    // MARK: - Left: Status Sidebar

    private var statusSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // OSC Hub card
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("OSC Hub", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.caption.bold())

                        let stats = appState.oscHub.stats()
                        let running = stats["running"] as? Bool ?? false
                        let received = stats["messagesReceived"] as? Int ?? 0

                        statusDot("Status", running ? "Running" : "Stopped", isGood: running)
                        statusDot("VDJ Port", "\(appState.oscHub.vdjReceivePort)", isGood: running)
                        statusDot("Received", "\(received)", isGood: received > 0)
                        statusDot("Addresses", "\(appState.oscMessages.count)", isGood: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }

                // OS2L Connection card
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("OS2L", systemImage: "point.3.connected.trianglepath.dotted")
                            .font(.caption.bold())

                        if let snapshot = bridgeSnapshot {
                            statusDot("Bridge", snapshot.isRunning ? "Running" : "Stopped", isGood: snapshot.isRunning)
                            statusDot("Dry Run", snapshot.dryRun ? "Yes" : "No", isGood: !snapshot.dryRun)

                            switch snapshot.configStatus {
                            case .notLoaded:
                                statusDot("Config", "Not Loaded", isGood: false)
                            case .valid(let summary):
                                statusDot("Config", "Valid", isGood: true)
                                HStack(spacing: 8) {
                                    miniStat("Slots", summary.slotCount)
                                    miniStat("Scenes", summary.sceneCount)
                                }
                                .padding(.leading, 16)
                            case .invalid(let errors):
                                statusDot("Config", "\(errors.count) errors", isGood: false)
                            }
                        } else if bridge != nil {
                            Text("Loading…")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            statusDot("Status", "Not Started", isGood: false)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }

                // LedFX Bridge card
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("LedFX Bridge", systemImage: "lightbulb.led")
                            .font(.caption.bold())

                        if let snapshot = bridgeSnapshot {
                            statusDot("REST Sent", "\(snapshot.stats.totalRestSent)", isGood: true)
                            statusDot("REST Fails", "\(snapshot.stats.totalRestFailures)",
                                      isGood: snapshot.stats.totalRestFailures == 0)
                        } else {
                            statusDot("Status", bridge != nil ? "Active" : "Inactive", isGood: bridge != nil)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }

                // Ports summary
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Ports", systemImage: "network")
                            .font(.caption.bold())

                        let ports = oscBridgeConfig.ports
                        portLine("OS2L Listen", "\(ports.os2lListen)")
                        portLine("OS2L Forward", "\(ports.os2lForward)")
                        portLine("OSC VDJ In", "\(ports.oscVdjIn)")
                        portLine("LedFX API", ports.ledFXAPI)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }

                Spacer()
            }
            .padding(10)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Center: Message Log

    private var messageLog: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundColor(.secondary)
                TextField("Filter messages…", text: $filterText)
                    .textFieldStyle(.plain)

                if !filterText.isEmpty {
                    Button { filterText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Divider().frame(height: 20)

                ForEach(HubMessageSource.allCases, id: \.self) { source in
                    Toggle(isOn: Binding(
                        get: { activeSourceFilters.contains(source) },
                        set: { isOn in
                            if isOn { activeSourceFilters.insert(source) }
                            else { activeSourceFilters.remove(source) }
                        }
                    )) {
                        Text(source.rawValue)
                            .font(.caption2)
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .tint(sourceColor(source))
                }
            }
            .padding(8)
            .background(.quaternary)
            .cornerRadius(8)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            // Message list
            ScrollViewReader { proxy in
                List(filteredMessages) { msg in
                    HubMessageRow(message: msg)
                        .id(msg.id)
                }
                .listStyle(.plain)
                .onChange(of: filteredMessages.last?.id) { _, newValue in
                    if let id = newValue {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Stats bar
            HStack {
                Text("\(filteredMessages.count) messages")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                Spacer()

                ForEach(HubMessageSource.allCases, id: \.self) { source in
                    let count = hubMessages.filter { $0.source == source }.count
                    HStack(spacing: 2) {
                        Circle()
                            .fill(sourceColor(source))
                            .frame(width: 6, height: 6)
                        Text("\(source.rawValue): \(count)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                Divider().frame(height: 14)

                Button {
                    Task {
                        await appState.hubLog.clear()
                        hubMessages = []
                    }
                    appState.clearOscMessages()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.bar)
        }
    }

    // MARK: - Right: Actions Panel

    private var actionsPanel: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Test OSC sender
                GroupBox("Send Test Message") {
                    VStack(alignment: .leading, spacing: 10) {
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
                            Button { sendTestMessage() } label: {
                                Label("Send", systemImage: "paperplane.fill")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(8)
                }

                // Quick Actions
                GroupBox("Quick Actions") {
                    VStack(alignment: .leading, spacing: 6) {
                        QuickOSCButton(address: "/shader/load", args: ["neon_giza", "0.8", "0.5"]) {
                            sendQuickMessage($0, args: $1)
                        }
                        QuickOSCButton(address: "/textler/track", args: ["1", "demo", "Artist", "Title"]) {
                            sendQuickMessage($0, args: $1)
                        }
                        QuickOSCButton(address: "/audio/beat/onbeat", args: ["1"]) {
                            sendQuickMessage($0, args: $1)
                        }
                    }
                    .padding(8)
                }

                // LedFX Mappings
                GroupBox("OS2L → LedFX (\(oscBridgeConfig.os2lToLedFX.count))") {
                    VStack(spacing: 0) {
                        if oscBridgeConfig.os2lToLedFX.isEmpty {
                            Text("No mappings")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(8)
                        } else {
                            ForEach(Array(oscBridgeConfig.os2lToLedFX.enumerated()), id: \.offset) { _, mapping in
                                HStack(spacing: 6) {
                                    Text(mapping.os2lButtonName)
                                        .font(.caption.monospaced())
                                        .lineLimit(1)
                                    Image(systemName: "arrow.right")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(mapping.targetName)
                                        .font(.caption.monospaced())
                                        .lineLimit(1)
                                    Spacer()
                                    Text(mapping.isScene ? "Scene" : "Playlist")
                                        .font(.caption2)
                                        .foregroundStyle(mapping.isScene ? .orange : .blue)
                                }
                                .padding(.vertical, 3)
                                .padding(.horizontal, 6)
                            }
                        }
                    }
                    .padding(4)
                }

                // Connection status
                GroupBox("Connection Status") {
                    VStack(alignment: .leading, spacing: 6) {
                        StatusRow(label: "VDJ Receive", value: "\(appState.oscHub.vdjReceivePort)", isActive: true)
                        StatusRow(label: "Forward: Magic", value: "11111", isActive: true)
                        StatusRow(label: "VirtualDJ", value: "9009", isActive: true)
                    }
                    .padding(8)
                }

                Spacer()
            }
            .padding(10)
        }
    }

    // MARK: - Helpers

    private func sourceColor(_ source: HubMessageSource) -> Color {
        switch source {
        case .osc: return .green
        case .os2l: return .blue
        case .rest: return .orange
        }
    }

    private func statusDot(_ label: String, _ value: String, isGood: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isGood ? Color.green : Color.red)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.caption2.monospaced())
                .lineLimit(1)
        }
    }

    private func miniStat(_ label: String, _ count: Int) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text("\(count)")
                .font(.caption2.monospaced().bold())
        }
    }

    private func portLine(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.caption2.monospaced())
                .lineLimit(1)
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

    // MARK: - Polling

    private func startPolling() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                let log = appState.hubLog
                hubMessages = await log.getMessages()
                if let b = bridge {
                    bridgeSnapshot = await b.getState()
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
}

// MARK: - Hub Message Row

private struct HubMessageRow: View {
    let message: HubMessage

    private var sourceColor: Color {
        switch message.source {
        case .osc: return .green
        case .os2l: return .blue
        case .rest: return .orange
        }
    }

    private var directionIcon: String {
        message.isIncoming ? "arrow.down.left" : "arrow.up.right"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // Source badge
            HStack(spacing: 3) {
                Image(systemName: directionIcon)
                    .font(.system(size: 8))
                Text(message.source.rawValue)
                    .font(.caption2.bold())
            }
            .foregroundColor(sourceColor)
            .frame(width: 52)

            // Timestamp
            Text(message.timestamp, style: .time)
                .font(.caption2.monospaced())
                .foregroundColor(.secondary)
                .frame(width: 65)

            // Title + detail
            VStack(alignment: .leading, spacing: 1) {
                Text(message.title)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                if !message.detail.isEmpty {
                    Text(message.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(sourceColor.opacity(0.04))
        .cornerRadius(4)
        .contextMenu {
            Button("Copy") {
                let text = "\(message.timestamp.ISO8601Format()) [\(message.source.rawValue)] \(message.title) \(message.detail)"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
    }
}

