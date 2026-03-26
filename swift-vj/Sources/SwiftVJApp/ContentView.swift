// ContentView - Main window with top bar navigation
// Phase 4: SwiftUI Shell + Phase 6: Rendering Integration

import SwiftUI
import SwiftVJCore

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: SidebarTab = .master

    enum SidebarTab: String, CaseIterable, Identifiable {
        case master = "Master"
        case rendering = "Rendering"
        case pipeline = "Performance"
        case shaders = "Shaders"
        case songs = "Songs"
        case automation = "Automation"
        case hub = "Hub"
        case ledfx = "LedFX"
        case launchpad = "Launchpad"
        case logs = "Logs"
        case settings = "Settings"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .master: return "play.circle"
            case .rendering: return "tv"
            case .pipeline: return "arrow.triangle.branch"
            case .shaders: return "sparkles"
            case .songs: return "music.note.list"
            case .automation: return "timeline.selection"
            case .hub: return "network"
            case .ledfx: return "lightbulb.led"
            case .launchpad: return "square.grid.3x3.fill"
            case .logs: return "doc.text"
            case .settings: return "gearshape"
            }
        }
    }

    private var orderedTabs: [SidebarTab] {
        SidebarTab.allCases
    }

    private var tabIndexByTab: [SidebarTab: Int] {
        Dictionary(uniqueKeysWithValues: orderedTabs.enumerated().map { ($1, $0 + 1) })
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Label("SwiftVJ", systemImage: "waveform.path.ecg")
                        .font(.headline)

                    Circle()
                        .fill(appState.isRunning ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(appState.isRunning ? "Running" : "Stopped")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()
                        .frame(height: 20)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(orderedTabs, id: \.self) { tab in
                                let isSelected = selectedTab == tab
                                let traits: AccessibilityTraits = isSelected ? [.isButton, .isSelected] : .isButton
                                Button {
                                    selectedTab = tab
                                } label: {
                                    HStack(spacing: 6) {
                                        if let index = tabIndexByTab[tab], index <= 9 {
                                            Text("\(index)")
                                                .font(.caption2.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                        Label(tab.rawValue, systemImage: tab.icon)
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                }
                                .buttonStyle(.plain)
                                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                                .cornerRadius(6)
                                .contentShape(Rectangle())
                                .accessibilityIdentifier(A11yID.sidebarTab(tab.rawValue))
                                .accessibilityLabel(tab.rawValue)
                                .accessibilityAddTraits(traits)
                                .keyboardShortcut(Self.shortcutKey(for: tab), modifiers: .command)
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.thinMaterial)
                .overlay(alignment: .bottom) {
                    Divider()
                }
                .accessibilityIdentifier(A11yID.sidebarList)
                .accessibilityLabel("Top Navigation")

                Group {
                    switch selectedTab {
                    case .master:
                        MasterControlView()
                    case .rendering:
                        RenderingView()
                    case .pipeline:
                        PerformanceView()
                    case .shaders:
                        ShaderBrowserView()
                    case .songs:
                        SongBrowserView()
                    case .automation:
                        AutomationTimelineView()
                    case .hub:
                        HubDashboardView()
                    case .ledfx:
                        LedFXConfigView()
                    case .launchpad:
                        LaunchpadView()
                    case .logs:
                        LogViewerView()
                    case .settings:
                        SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier(A11yID.detailSection)
                .accessibilityElement(children: .contain)
            }
            .accessibilityIdentifier(A11yID.sidebarSection)
            .accessibilityElement(children: .contain)
        }
        .navigationTitle("SwiftVJ")
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 16) {
                    // Phase selector
                    PhaseToolbarControl(selection: appState.phaseBinding)
                }
            }
        }
        .task {
            // Autostart pipeline when app launches
            try? await appState.start()
        }
        .accessibilityIdentifier(A11yID.mainWindow)
        .accessibilityElement(children: .contain)
    }

    private static func shortcutKey(for tab: SidebarTab) -> KeyEquivalent {
        switch tab {
        case .master: return "1"
        case .rendering: return "2"
        case .pipeline: return "3"
        case .shaders: return "4"
        case .songs: return "5"
        case .automation: return "6"
        case .hub: return "7"
        case .ledfx: return "8"
        case .launchpad: return "9"
        case .logs: return "0"
        case .settings: return "-"
        }
    }
}

// MARK: - Toolbar Controls

private struct PhaseToolbarControl: View {
    @Binding var selection: Phase?

    var body: some View {
        HStack(spacing: 8) {
            Label("Phase", systemImage: "waveform.path.ecg")
                .font(.caption)
                .foregroundColor(.secondary)

            Picker("Phase", selection: $selection) {
                HStack {
                    Image(systemName: "circle.slash")
                    Text("None")
                }.tag(nil as Phase?)
                ForEach(Phase.allCases, id: \.self) { phase in
                    HStack {
                        Image(systemName: phase.iconName)
                        Text(phase.displayName)
                    }.tag(phase as Phase?)
                }
            }
            .pickerStyle(.menu)
            .frame(minWidth: 160)
            .accessibilityIdentifier(A11yID.toolbarPhasePicker)
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(AppState())
}
