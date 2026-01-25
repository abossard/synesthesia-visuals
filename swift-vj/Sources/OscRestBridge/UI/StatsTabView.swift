// StatsTabView.swift - Statistics tab UI

import SwiftUI

struct StatsTabView: View {
    let state: BridgeStateSnapshot
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Overall Stats
                GroupBox("Overall Statistics") {
                    VStack(spacing: 12) {
                        StatRow(label: "OSC Received", value: "\(state.stats.totalOscReceived)")
                        StatRow(label: "OSC Unknown", value: "\(state.stats.totalOscUnknown)")
                        StatRow(label: "REST Planned", value: "\(state.stats.totalRestPlanned)")
                        StatRow(label: "REST Sent", value: "\(state.stats.totalRestSent)")
                        StatRow(label: "REST Failures", value: "\(state.stats.totalRestFailures)")
                    }
                }
                .padding()
                
                // Rates
                GroupBox("Rates") {
                    VStack(spacing: 12) {
                        StatRow(label: "OSC Rate", value: String(format: "%.1f msg/s", state.stats.oscRate))
                        StatRow(label: "HTTP Rate", value: String(format: "%.1f req/s", state.stats.httpRate))
                    }
                }
                .padding()
                
                // Scene Activations
                if !state.stats.sceneActivations.isEmpty {
                    GroupBox("Scene Activations") {
                        VStack(spacing: 8) {
                            ForEach(Array(state.stats.sceneActivations.sorted(by: { $0.value > $1.value })), id: \.key) { name, count in
                                HStack {
                                    Text(name)
                                    Spacer()
                                    Text("\(count)")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding()
                }
                
                // Oneshot Triggers
                if !state.stats.oneshotTriggers.isEmpty {
                    GroupBox("Oneshot Triggers") {
                        VStack(spacing: 8) {
                            ForEach(Array(state.stats.oneshotTriggers.sorted(by: { $0.value > $1.value })), id: \.key) { name, count in
                                HStack {
                                    Text(name)
                                    Spacer()
                                    Text("\(count)")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding()
                }
                
                // Param Updates
                if !state.stats.paramUpdates.isEmpty {
                    GroupBox("Parameter Updates") {
                        VStack(spacing: 8) {
                            ForEach(Array(state.stats.paramUpdates.sorted(by: { $0.value > $1.value })), id: \.key) { name, count in
                                HStack {
                                    Text(name)
                                    Spacer()
                                    Text("\(count)")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding()
                }
                
                // Slot Messages
                if !state.stats.slotMessages.isEmpty {
                    GroupBox("Messages per Slot") {
                        VStack(spacing: 8) {
                            ForEach(Array(state.stats.slotMessages.sorted(by: { $0.key < $1.key })), id: \.key) { slot, count in
                                HStack {
                                    Text("Slot \(slot)")
                                    Spacer()
                                    Text("\(count)")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .bold()
        }
    }
}
