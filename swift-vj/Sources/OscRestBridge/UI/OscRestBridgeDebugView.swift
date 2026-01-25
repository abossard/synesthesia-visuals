// OscRestBridgeDebugView.swift - Main debug UI
// SwiftUI views for monitoring and debugging the bridge

import SwiftUI

public struct OscRestBridgeDebugView: View {
    let service: OscRestBridgeService
    @State private var state: BridgeStateSnapshot?
    @State private var refreshTask: Task<Void, Never>?
    @State private var showingFilePicker = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var expandedSections: Set<String> = ["config", "status"]
    
    public init(service: OscRestBridgeService) {
        self.service = service
    }
    
    public var body: some View {
        HSplitView {
            // Left: Config and Status
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    configSection
                    statusSection
                    actionsSection
                }
                .padding()
            }
            .frame(minWidth: 300, idealWidth: 350)
            
            // Right: Live Activity
            VStack(spacing: 0) {
                // Stats header
                statsHeaderView
                
                Divider()
                
                // Activity lists
                HSplitView {
                    // OSC Messages
                    oscMessagesView
                        .frame(minWidth: 250)
                    
                    // REST Requests
                    restRequestsView
                        .frame(minWidth: 250)
                }
            }
        }
        .task {
            // Only refresh when view is active
            refreshTask = Task {
                while !Task.isCancelled {
                    state = await service.getState()
                    try? await Task.sleep(for: .milliseconds(1000)) // Reduced from 500ms
                }
            }
        }
        .onDisappear {
            // Stop polling when view is not visible
            refreshTask?.cancel()
            refreshTask = nil
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.yaml],
            allowsMultipleSelection: false
        ) { result in
            Task {
                do {
                    let url = try result.get().first!
                    try await service.loadConfig(from: url)
                    successMessage = "Config loaded"
                    errorMessage = nil
                } catch {
                    errorMessage = error.localizedDescription
                    successMessage = nil
                }
            }
        }
    }
    
    // MARK: - Config Section
    
    private var configSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Configuration")
                    .font(.headline)
                Spacer()
                Button(action: { showingFilePicker = true }) {
                    Label("Load YAML", systemImage: "folder")
                }
                .buttonStyle(.bordered)
            }
            
            if let state = state {
                switch state.configStatus {
                case .notLoaded:
                    Label("No configuration loaded", systemImage: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                        .font(.caption)
                    
                case .valid(let summary):
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Valid", systemImage: "checkmark.circle")
                            .foregroundColor(.green)
                            .font(.caption)
                        
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                            GridRow {
                                Text("Base URL:").foregroundColor(.secondary)
                                Text(summary.baseUrl).font(.system(.caption, design: .monospaced))
                            }
                            GridRow {
                                Text("OSC Port:").foregroundColor(.secondary)
                                Text("\(summary.oscPort)").font(.system(.caption, design: .monospaced))
                            }
                            GridRow {
                                Text("Slots:").foregroundColor(.secondary)
                                Text("\(summary.slotCount)").font(.caption)
                            }
                            GridRow {
                                Text("Scenes:").foregroundColor(.secondary)
                                Text("\(summary.sceneCount)").font(.caption)
                            }
                            GridRow {
                                Text("Oneshots:").foregroundColor(.secondary)
                                Text("\(summary.oneshotCount)").font(.caption)
                            }
                            GridRow {
                                Text("Params:").foregroundColor(.secondary)
                                Text("\(summary.paramCount)").font(.caption)
                            }
                        }
                        .font(.caption)
                    }
                    
                case .invalid(let errors):
                    Label("Invalid (\(errors.count) errors)", systemImage: "xmark.circle")
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            
            // Messages
            if let error = errorMessage {
                Label(error, systemImage: "xmark.circle")
                    .foregroundColor(.red)
                    .font(.caption)
            }
            if let success = successMessage {
                Label(success, systemImage: "checkmark.circle")
                    .foregroundColor(.green)
                    .font(.caption)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
    
    // MARK: - Status Section
    
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Status")
                .font(.headline)
            
            if let state = state {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Circle()
                            .fill(state.isRunning ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(state.isRunning ? "Running" : "Stopped")
                            .font(.caption)
                    }
                    
                    HStack {
                        Text("Dry Run")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { state.dryRun },
                            set: { newValue in
                                Task {
                                    await service.setDryRun(newValue)
                                }
                            }
                        ))
                        .labelsHidden()
                    }
                    
                    // Slot states (compact)
                    if !state.slotState.isEmpty {
                        Divider()
                        Text("Slots").font(.caption).foregroundColor(.secondary)
                        ForEach(Array(state.slotState.sorted(by: { $0.key < $1.key })), id: \.key) { slot, slotState in
                            HStack(spacing: 6) {
                                Text(slot).font(.caption.monospaced()).foregroundColor(.secondary)
                                if slotState.blackoutActive {
                                    Image(systemName: "moon.fill").font(.caption).foregroundColor(.blue)
                                }
                                if let scene = slotState.lastActiveSceneName {
                                    Text(scene).font(.caption).lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
    
    // MARK: - Actions Section
    
    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Actions")
                .font(.headline)
            
            HStack(spacing: 8) {
                Button("Clear Stats") {
                    Task { await service.clearStats() }
                }
                .buttonStyle(.bordered)
                
                Button("Clear Buffers") {
                    Task { await service.clearBuffers() }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
    
    // MARK: - Stats Header
    
    private var statsHeaderView: some View {
        HStack(spacing: 16) {
            if let state = state {
                StatBadge(label: "OSC", value: "\(state.stats.totalOscReceived)", rate: state.stats.oscRate)
                Divider().frame(height: 20)
                StatBadge(label: "REST", value: "\(state.stats.totalRestSent)", rate: state.stats.httpRate)
                Divider().frame(height: 20)
                StatBadge(label: "Errors", value: "\(state.stats.totalOscUnknown + state.stats.totalRestFailures)", color: .orange)
            }
            Spacer()
        }
        .padding()
        .background(.bar)
    }
    
    // MARK: - OSC Messages View
    
    private var oscMessagesView: some View {
        VStack(spacing: 0) {
            HStack {
                Label("OSC Messages", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.1))
            
            List {
                if let state = state {
                    ForEach(state.recentOsc.reversed().prefix(50)) { record in
                        OSCMessageRow(record: record)
                            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    }
                }
            }
            .listStyle(.plain)
        }
    }
    
    // MARK: - REST Requests View
    
    private var restRequestsView: some View {
        VStack(spacing: 0) {
            HStack {
                Label("REST Requests", systemImage: "arrow.up.arrow.down")
                    .font(.caption)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.1))
            
            List {
                if let state = state {
                    ForEach(state.recentHttp.reversed().prefix(50)) { record in
                        HTTPRequestRow(record: record)
                            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - Supporting Views

struct StatBadge: View {
    let label: String
    let value: String
    var rate: Double = 0
    var color: Color = .blue
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            HStack(spacing: 4) {
                Text(value).font(.system(.body, design: .monospaced)).foregroundColor(color)
                if rate > 0 {
                    Text(String(format: "%.1f/s", rate))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct OSCMessageRow: View {
    let record: OSCMessageRecord
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(formatTime(record.timestamp))
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .leading)
                
                Text(record.path)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                
                Text(String(format: "%.2f", record.value))
                    .font(.caption2.monospaced())
                    .foregroundColor(.blue)
            }
            
            if let parsed = record.parsed {
                parsedRouteLabel(parsed)
                    .font(.caption2)
                    .foregroundColor(.green)
            } else if let reason = record.unknownReason {
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .padding(.vertical, 2)
    }
    
    @ViewBuilder
    private func parsedRouteLabel(_ route: ParsedOSCRoute) -> some View {
        switch route {
        case .scene(let slot, let name):
            Text("→ Scene: \(name) [\(slot)]")
        case .oneshot(let slot, let name):
            Text("→ Oneshot: \(name) [\(slot)]")
        case .blackout(let slot):
            Text("→ Blackout [\(slot)]")
        case .param(let slot, let name):
            Text("→ Param: \(name) [\(slot)]")
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

struct HTTPRequestRow: View {
    let record: HTTPRequestRecord
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(formatTime(record.timestamp))
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .leading)
                
                Text(record.method)
                    .font(.caption.bold().monospaced())
                    .foregroundColor(.blue)
                    .frame(width: 40, alignment: .leading)
                
                if let status = record.statusCode {
                    statusBadge(status)
                } else if record.planned {
                    Text("DRY").font(.caption2).foregroundColor(.purple)
                } else if record.error != nil {
                    Text("ERR").font(.caption2).foregroundColor(.red)
                }
            }
            
            Text(record.url)
                .font(.caption2.monospaced())
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            if let error = record.error {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
    
    @ViewBuilder
    private func statusBadge(_ code: Int) -> some View {
        let color: Color
        if (200..<300).contains(code) {
            color = .green
        } else if (400..<500).contains(code) {
            color = .orange
        } else {
            color = .red
        }
        
        Text("\(code)")
            .font(.caption2.bold())
            .foregroundColor(color)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#if DEBUG
struct OscRestBridgeDebugView_Previews: PreviewProvider {
    static var previews: some View {
        OscRestBridgeDebugView(service: createDefaultBridgeService())
            .frame(width: 900, height: 600)
    }
}
#endif

extension UTType {
    static var yaml: UTType {
        UTType(filenameExtension: "yaml") ?? UTType(filenameExtension: "yml") ?? .plainText
    }
}

