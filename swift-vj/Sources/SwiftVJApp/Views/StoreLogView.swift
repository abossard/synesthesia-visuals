// StoreLogView.swift - UI for viewing Store action log and state diffs
// Debug view for observing unidirectional data flow

import SwiftUI
import SwiftVJCore

/// View displaying Store actions and their state changes
public struct StoreLogView: View {
    @ObservedObject var logger: StoreLogger<SwiftVJCore.AppState, AppAction>
    @State private var selectedEntry: ActionLogEntry?
    @State private var autoScroll = true

    public init(logger: StoreLogger<SwiftVJCore.AppState, AppAction>) {
        self.logger = logger
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar

            Divider()

            // Log entries
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

            Image(systemName: logger.isEnabled ? "circle.fill" : "circle")
                .foregroundColor(logger.isEnabled ? .green : .gray)
                .font(.caption)

            // Auto-scroll toggle
            Toggle("Auto-scroll", isOn: $autoScroll)
                .toggleStyle(.checkbox)

            // Clear button
            Button(action: { logger.clear() }) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)

            // Entry count
            Text("\(logger.filteredEntries.count)")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            List(logger.filteredEntries) { entry in
                LogEntryRow(entry: entry, isSelected: selectedEntry?.id == entry.id)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedEntry = selectedEntry?.id == entry.id ? nil : entry
                    }
                    .id(entry.id)
            }
            .listStyle(.plain)
            .onChange(of: logger.entries.count) { _ in
                if autoScroll, let last = logger.entries.last {
                    withAnimation {
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
    let isSelected: Bool

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Action header
            HStack(alignment: .top) {
                Text(Self.timeFormatter.string(from: entry.timestamp))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)

                Text(actionName)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundColor(actionColor)

                Spacer()

                if let duration = entry.duration {
                    Text(String(format: "%.1fms", duration * 1000))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }

                if !entry.diffs.isEmpty {
                    Text("Δ\(entry.diffs.count)")
                        .font(.caption)
                        .padding(.horizontal, 4)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(3)
                }
            }

            // State diffs (expanded when selected)
            if isSelected && !entry.diffs.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(entry.diffs, id: \.path) { diff in
                        HStack(alignment: .top, spacing: 4) {
                            Text("├─")
                                .foregroundColor(.secondary)
                            Text(diff.path)
                                .fontWeight(.medium)
                            Text(diff.oldValue)
                                .foregroundColor(.red.opacity(0.8))
                            Text("→")
                                .foregroundColor(.secondary)
                            Text(diff.newValue)
                                .foregroundColor(.green.opacity(0.8))
                        }
                        .font(.system(.caption, design: .monospaced))
                    }
                }
                .padding(.leading, 20)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
    }

    private var actionName: String {
        // Extract action name from description
        let desc = entry.action
        if let range = desc.range(of: "(") {
            return String(desc[..<range.lowerBound])
        }
        return desc
    }

    private var actionColor: Color {
        let name = actionName.lowercased()
        if name.contains("playback") { return .blue }
        if name.contains("pipeline") { return .purple }
        if name.contains("render") { return .orange }
        if name.contains("launchpad") { return .green }
        if name.contains("audio") { return .cyan }
        if name.contains("ui") { return .gray }
        return .primary
    }
}

// MARK: - Preview

#if DEBUG
struct StoreLogView_Previews: PreviewProvider {
    static var previews: some View {
        let logger = StoreLogger<SwiftVJCore.AppState, AppAction>()
        StoreLogView(logger: logger)
            .frame(width: 600, height: 400)
    }
}
#endif
