// ConfigTabView.swift - Configuration tab UI

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var yaml: UTType {
        UTType(filenameExtension: "yaml") ?? UTType(filenameExtension: "yml") ?? .plainText
    }
}

struct ConfigTabView: View {
    let state: BridgeStateSnapshot
    let service: OscRestBridgeService
    
    @State private var showingFilePicker = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Actions
                HStack {
                    Button("Load YAML...") {
                        showingFilePicker = true
                    }
                    
                    Button("Reload") {
                        Task {
                            // TODO: Store last URL
                            successMessage = "Config reloaded"
                            errorMessage = nil
                        }
                    }
                    .disabled(!isConfigValid)
                }
                .padding()
                
                Divider()
                
                // Status
                Group {
                    Text("Configuration Status")
                        .font(.headline)
                    
                    switch state.configStatus {
                    case .notLoaded:
                        Label("No configuration loaded", systemImage: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        
                    case .valid(let summary):
                        Label("Configuration valid", systemImage: "checkmark.circle")
                            .foregroundColor(.green)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            InfoRow(label: "Base URL", value: summary.baseUrl)
                            InfoRow(label: "OSC Port", value: "\(summary.oscPort)")
                            InfoRow(label: "Slots", value: "\(summary.slotCount)")
                            InfoRow(label: "Scenes", value: "\(summary.sceneCount)")
                            InfoRow(label: "Oneshots", value: "\(summary.oneshotCount)")
                            InfoRow(label: "Params", value: "\(summary.paramCount)")
                        }
                        .padding(.leading)
                        
                    case .invalid(let errors):
                        Label("Configuration invalid (\(errors.count) errors)", systemImage: "xmark.circle")
                            .foregroundColor(.red)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(errors.enumerated()), id: \.offset) { _, error in
                                HStack(alignment: .top) {
                                    Text("•")
                                    VStack(alignment: .leading) {
                                        Text(error.path).font(.caption).foregroundColor(.secondary)
                                        Text(error.message).font(.caption)
                                    }
                                }
                            }
                        }
                        .padding(.leading)
                    }
                }
                .padding()
                
                // Messages
                if let error = errorMessage {
                    Label(error, systemImage: "xmark.circle")
                        .foregroundColor(.red)
                        .padding()
                }
                
                if let success = successMessage {
                    Label(success, systemImage: "checkmark.circle")
                        .foregroundColor(.green)
                        .padding()
                }
            }
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
    
    private var isConfigValid: Bool {
        if case .valid = state.configStatus {
            return true
        }
        return false
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).bold()
        }
    }
}
