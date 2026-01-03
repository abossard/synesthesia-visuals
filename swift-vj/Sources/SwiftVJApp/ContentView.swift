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
        case osc = "OSC"
        case logs = "Logs"
        case settings = "Settings"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .master: return "play.circle"
            case .rendering: return "tv"
            case .pipeline: return "arrow.triangle.branch"
            case .shaders: return "sparkles"
            case .osc: return "antenna.radiowaves.left.and.right"
            case .logs: return "doc.text"
            case .settings: return "gearshape"
            }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(SidebarTab.allCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 180)
            
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
                case .osc:
                    OSCDebugView()
                case .logs:
                    LogViewerView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("SwiftVJ")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task {
                        if appState.isRunning {
                            await appState.stop()
                        } else {
                            try? await appState.start()
                        }
                    }
                } label: {
                    Label(appState.isRunning ? "Stop" : "Start",
                          systemImage: appState.isRunning ? "stop.fill" : "play.fill")
                }
                .keyboardShortcut(.space, modifiers: [.command])
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(AppState())
}
