// BridgeStatusView.swift - Bridge system status panel
// Shows OS2L connection, OSC→OS2L rules, OS2L→LedFX mappings, and port config

import SwiftUI
import SwiftVJCore
import OscRestBridge

struct BridgeStatusView: View {
    @EnvironmentObject var appState: AppState

    @State private var bridgeSnapshot: BridgeStateSnapshot?
    @State private var refreshTask: Task<Void, Never>?

    private var bridge: OscRestBridgeService? { appState.oscRestBridge }

    // Use generated config from AppState when available, otherwise fall back to defaults
    private var oscBridgeConfig: OSCBridgeConfig {
        .default
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if bridge == nil {
                    notInitializedBanner
                }

                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 20) {
                    connectionSection
                    portsSection
                }

                os2lToLedFXSection

                if let snapshot = bridgeSnapshot {
                    throughputSection(snapshot.stats)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { startPolling() }
        .onDisappear { refreshTask?.cancel(); refreshTask = nil }
    }

    // MARK: - Grid Layout

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 300), spacing: 20),
            GridItem(.flexible(minimum: 300), spacing: 20),
        ]
    }

    // MARK: - Not Initialized

    private var notInitializedBanner: some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.title3)
                Text("Bridge service not initialized. Start the pipeline or apply LedFX settings to activate.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - OS2L Connection

    private var connectionSection: some View {
        GroupBox("OS2L Connection") {
            VStack(alignment: .leading, spacing: 10) {
                statusRow(
                    label: "Bridge Service",
                    value: bridge != nil ? "Active" : "Not Started",
                    isGood: bridge != nil
                )

                if let snapshot = bridgeSnapshot {
                    statusRow(
                        label: "Status",
                        value: snapshot.isRunning ? "Running" : "Stopped",
                        isGood: snapshot.isRunning
                    )

                    switch snapshot.configStatus {
                    case .notLoaded:
                        statusRow(label: "Config", value: "Not Loaded", isGood: false)
                    case .valid(let summary):
                        statusRow(label: "Config", value: "Valid", isGood: true)
                        HStack(spacing: 16) {
                            statBadge("Slots", summary.slotCount)
                            statBadge("Scenes", summary.sceneCount)
                            statBadge("Params", summary.paramCount)
                            statBadge("Oneshots", summary.oneshotCount)
                        }
                        .padding(.leading, 4)
                    case .invalid(let errors):
                        statusRow(label: "Config", value: "Invalid (\(errors.count) errors)", isGood: false)
                    }

                    statusRow(
                        label: "Dry Run",
                        value: snapshot.dryRun ? "Enabled" : "Disabled",
                        isGood: !snapshot.dryRun
                    )
                } else if bridge != nil {
                    Text("Loading state…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
    }

    // MARK: - Ports

    private var portsSection: some View {
        GroupBox("Ports") {
            VStack(alignment: .leading, spacing: 8) {
                let ports = oscBridgeConfig.ports
                portRow(label: "OS2L Listen", port: ports.os2lListen, detail: "VDJ → SwiftVJ")
                portRow(label: "OS2L Forward", port: ports.os2lForward, detail: "SwiftVJ → QLC+")
                portRow(label: "OSC VDJ In", port: ports.oscVdjIn, detail: "VDJ OSC → SwiftVJ")
                Divider()
                HStack {
                    Image(systemName: "network")
                        .foregroundStyle(.secondary)
                    Text("LedFX API")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .leading)
                    Text(ports.ledFXAPI)
                        .font(.caption.monospaced())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
    }

    // MARK: - OS2L → LedFX Mappings

    private var os2lToLedFXSection: some View {
        GroupBox("OS2L → LedFX Mappings (\(oscBridgeConfig.os2lToLedFX.count))") {
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 0) {
                    ruleHeader("Button Pattern", width: 200)
                    ruleHeader("Target", width: nil)
                    ruleHeader("Type", width: 100)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(Color.secondary.opacity(0.1))

                Divider()

                if oscBridgeConfig.os2lToLedFX.isEmpty {
                    Text("No mappings configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(12)
                } else {
                    ForEach(Array(oscBridgeConfig.os2lToLedFX.enumerated()), id: \.offset) { _, mapping in
                        mappingRow(mapping)
                        Divider()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Throughput

    private func throughputSection(_ stats: BridgeStats) -> some View {
        GroupBox("Throughput") {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 12) {
                statCard("OSC Received", stats.totalOscReceived, rate: stats.oscRate)
                statCard("REST Sent", stats.totalRestSent, rate: stats.httpRate)
                statCard("OSC Unknown", stats.totalOscUnknown, isWarning: stats.totalOscUnknown > 0)
                statCard("REST Failures", stats.totalRestFailures, isWarning: stats.totalRestFailures > 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
    }

    // MARK: - Subviews

    private func statusRow(label: String, value: String, isGood: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isGood ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
        }
    }

    private func portRow(label: String, port: UInt16, detail: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(.secondary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text("\(port)")
                .font(.caption.monospaced())
                .frame(width: 50, alignment: .trailing)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func statBadge(_ label: String, _ count: Int) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.caption.monospaced().bold())
        }
    }

    private func ruleHeader(_ title: String, width: CGFloat?) -> some View {
        Group {
            if let width = width {
                Text(title)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: width, alignment: .leading)
            } else {
                Text(title)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func mappingRow(_ mapping: OSCBridgeConfig.LedFXMappingConfig) -> some View {
        HStack(spacing: 0) {
            Text(mapping.os2lButtonName)
                .font(.caption.monospaced())
                .frame(width: 200, alignment: .leading)
            Text(mapping.targetName)
                .font(.caption.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                Image(systemName: mapping.isScene ? "theatermask.and.paintbrush" : "play.square.stack")
                    .font(.caption2)
                Text(mapping.isScene ? "Scene" : "Playlist")
                    .font(.caption)
            }
            .foregroundStyle(mapping.isScene ? .orange : .blue)
            .frame(width: 100, alignment: .leading)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }

    private func statCard(_ label: String, _ count: Int, rate: Double = 0, isWarning: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(count)")
                    .font(.title3.monospaced().bold())
                    .foregroundStyle(isWarning ? .orange : .primary)
                if rate > 0 {
                    Text(String(format: "%.1f/s", rate))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Polling

    private func startPolling() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                if let bridge = bridge {
                    bridgeSnapshot = await bridge.getState()
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

