// ContentView - Main window with sidebar navigation
// Phase 4: SwiftUI Shell + Phase 6: Rendering Integration

import SwiftUI
import SwiftVJCore

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: SidebarTab = .master

    enum SidebarTab: String, CaseIterable, Identifiable {
        case master = "Master"
        case rendering = "Rendering"
        case pipeline = "Pipeline"
        case shaders = "Shaders"
        case songs = "Songs"
        case osc = "OSC"
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
            case .osc: return "antenna.radiowaves.left.and.right"
            case .ledfx: return "lightbulb.led"
            case .launchpad: return "square.grid.3x3.fill"
            case .logs: return "doc.text"
            case .settings: return "gearshape"
            }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(SidebarTab.allCases, id: \.self) { tab in
                            let isSelected = selectedTab == tab
                            let traits: AccessibilityTraits = isSelected ? [.isButton, .isSelected] : .isButton
                            Button {
                                selectedTab = tab
                            } label: {
                                Label(tab.rawValue, systemImage: tab.icon)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 8)
                            }
                            .buttonStyle(.plain)
                            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                            .accessibilityIdentifier(A11yID.sidebarTab(tab.rawValue))
                            .accessibilityLabel(tab.rawValue)
                            .accessibilityAddTraits(traits)
                        }
                    }
                    .padding(6)
                }
                .navigationSplitViewColumnWidth(min: 150, ideal: 180)
                .accessibilityIdentifier(A11yID.sidebarList)
                .accessibilityLabel("Sidebar")
                .accessibilityElement(children: .contain)

                // Status footer in sidebar
                VStack(spacing: 8) {
                    Divider()
                    HStack {
                        Circle()
                            .fill(appState.isRunning ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(appState.isRunning ? "Running" : "Stopped")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
            .accessibilityIdentifier(A11yID.sidebarSection)
            .accessibilityElement(children: .contain)
        } detail: {
            // Main content
            Group {
                switch selectedTab {
                case .master:
                    MasterControlView()
                case .rendering:
                    RenderingView()
                case .pipeline:
                    PipelineStatusView()
                case .shaders:
                    ShaderBrowserView()
                case .songs:
                    SongBrowserView()
                case .osc:
                    OSCContainerView()
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
