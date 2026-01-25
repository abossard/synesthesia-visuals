// StateTabView.swift - State and controls tab UI

import SwiftUI

struct StateTabView: View {
    let state: BridgeStateSnapshot
    let service: OscRestBridgeService
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Service Status
                GroupBox("Service Status") {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Running")
                                .foregroundColor(.secondary)
                            Spacer()
                            if state.isRunning {
                                Label("Yes", systemImage: "checkmark.circle")
                                    .foregroundColor(.green)
                            } else {
                                Label("No", systemImage: "xmark.circle")
                                    .foregroundColor(.red)
                            }
                        }
                        
                        HStack {
                            Text("Dry Run")
                                .foregroundColor(.secondary)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { state.dryRun },
                                set: { newValue in
                                    Task {
                                        await service.setDryRun(newValue)
                                    }
                                }
                            ))
                        }
                    }
                }
                .padding()
                
                // Slot States
                if !state.slotState.isEmpty {
                    GroupBox("Slot States") {
                        VStack(spacing: 16) {
                            ForEach(Array(state.slotState.sorted(by: { $0.key < $1.key })), id: \.key) { slot, slotState in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Slot \(slot)")
                                        .font(.headline)
                                    
                                    HStack {
                                        Text("Blackout Active")
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        if slotState.blackoutActive {
                                            Image(systemName: "moon.fill")
                                                .foregroundColor(.blue)
                                        } else {
                                            Image(systemName: "moon")
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    if let lastScene = slotState.lastActiveSceneName {
                                        HStack {
                                            Text("Last Active Scene")
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Text(lastScene)
                                                .bold()
                                        }
                                    }
                                    
                                    if let lastTime = slotState.lastSceneChangeTime {
                                        HStack {
                                            Text("Last Change")
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Text(formatTime(lastTime))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                                
                                if slot != state.slotState.keys.sorted().last {
                                    Divider()
                                }
                            }
                        }
                    }
                    .padding()
                }
                
                // Actions
                GroupBox("Actions") {
                    VStack(spacing: 12) {
                        Button("Clear Statistics") {
                            Task {
                                await service.clearStats()
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Clear Buffers") {
                            Task {
                                await service.clearBuffers()
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Clear Slot States") {
                            Task {
                                await service.clearSlotStates()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
