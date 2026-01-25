// OscRestBridgeDebugView.swift - Main debug UI
// SwiftUI views for monitoring and debugging the bridge

import SwiftUI

public struct OscRestBridgeDebugView: View {
    let service: OscRestBridgeService
    @State private var selectedTab: Tab = .config
    @State private var state: BridgeStateSnapshot?
    @State private var refreshTask: Task<Void, Never>?
    
    private enum Tab: String, CaseIterable {
        case config = "Config"
        case osc = "OSC"
        case rest = "REST"
        case stats = "Stats"
        case state = "State"
    }
    
    public init(service: OscRestBridgeService) {
        self.service = service
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            Picker("Tab", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            Divider()
            
            // Tab content
            Group {
                if let state = state {
                    switch selectedTab {
                    case .config:
                        ConfigTabView(state: state, service: service)
                    case .osc:
                        OSCTabView(state: state)
                    case .rest:
                        RESTTabView(state: state)
                    case .stats:
                        StatsTabView(state: state)
                    case .state:
                        StateTabView(state: state, service: service)
                    }
                } else {
                    ProgressView("Loading...")
                }
            }
        }
        .task {
            // Refresh state periodically
            refreshTask = Task {
                while !Task.isCancelled {
                    state = await service.getState()
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        }
        .onDisappear {
            refreshTask?.cancel()
        }
    }
}

// MARK: - Preview

#if DEBUG
struct OscRestBridgeDebugView_Previews: PreviewProvider {
    static var previews: some View {
        OscRestBridgeDebugView(service: createDefaultBridgeService())
            .frame(width: 800, height: 600)
    }
}
#endif
