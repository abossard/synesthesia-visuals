// StoreLogView.swift - UI for viewing Store action log
// Efficient debug view for unidirectional data flow insights

import SwiftUI
import SwiftVJCore

/// View displaying Store actions and state changes
public struct StoreLogView: View {
    @ObservedObject var logger: StoreLogger<SwiftVJCore.AppState, AppAction>
    @State private var autoScroll = true

    public init(logger: StoreLogger<SwiftVJCore.AppState, AppAction>) {
        self.logger = logger
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            logList
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            // Filter
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Filter actions...", text: $logger.filter)
                    .textFieldStyle(.plain)
            }
            .padding(6)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(6)

            Spacer()

            // Toggle logging
            Toggle("Log", isOn: $logger.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()

            Circle()
                .fill(logger.isEnabled ? Color.green : Color.gray)
                .frame(width: 8, height: 8)

            // Auto-scroll toggle
            Toggle("Auto-scroll", isOn: $autoScroll)
                .toggleStyle(.checkbox)

            // Clear button
            Button(action: { logger.clear() }) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)

            // Entry count
            Text("\(logger.entryCount)")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            List(logger.filteredEntries) { entry in
                LogEntryRow(entry: entry)
                    .id(entry.id)
            }
            .listStyle(.plain)
            .font(.system(.caption, design: .monospaced))
            .onChange(of: logger.entryCount) { _, _ in
                if autoScroll, let last = logger.entries.last {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

// MARK: - Log Entry Row

struct LogEntryRow: View {
    let entry: ActionLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(formatTime(entry.timestamp))
                .foregroundColor(.secondary)

            // State change indicator
            Text(entry.stateChanged ? "Δ" : "○")
                .foregroundColor(entry.stateChanged ? .orange : .gray)

            // Action
            Text(entry.actionType)
                .fontWeight(.medium)
                .foregroundColor(actionColor)

            Text(entry.actionDetail)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer()

            // Duration
            Text(String(format: "%.2fms", entry.durationMs))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var actionColor: Color {
        let name = entry.actionType.lowercased()
        if name.contains("playback") { return .blue }
        if name.contains("pipeline") { return .purple }
        if name.contains("render") { return .orange }
        if name.contains("launchpad") { return .green }
        if name.contains("audio") { return .cyan }
        if name.contains("ui") { return .gray }
        return .primary
    }

    private func formatTime(_ timestamp: Double) -> String {
        let date = Date(timeIntervalSinceReferenceDate: timestamp)
        let components = Calendar.current.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let ms = (components.nanosecond ?? 0) / 1_000_000
        return String(format: "%02d:%02d:%02d.%03d",
                      components.hour ?? 0,
                      components.minute ?? 0,
                      components.second ?? 0,
                      ms)
    }
}

// MARK: - Preview

#if DEBUG
struct StoreLogView_Previews: PreviewProvider {
    static var previews: some View {
        let logger = StoreLogger<SwiftVJCore.AppState, AppAction>()
        StoreLogView(logger: logger)
            .frame(minWidth: 400, maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
    }
}
#endif
