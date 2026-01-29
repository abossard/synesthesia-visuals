// OSCContainerView - Container for OSC Debug and OSC Bridge
// Integrates both views with tabs

import SwiftUI
import SwiftVJCore
import OscRestBridge

struct OSCContainerView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: OSCTab = .debug
    
    enum OSCTab: String, CaseIterable, Identifiable {
        case debug = "OSC Debug"
        case bridge = "OSC Bridge"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .debug: return "antenna.radiowaves.left.and.right"
            case .bridge: return "arrow.left.arrow.right"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            Picker("OSC View", selection: $selectedTab) {
                ForEach(OSCTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            Divider()
            
            // Tab content
            Group {
                switch selectedTab {
                case .debug:
                    OSCDebugView()
                case .bridge:
                    if let bridge = appState.oscRestBridge {
                        OscRestBridgeDebugView(service: bridge)
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "arrow.left.arrow.right.slash")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("OSC Bridge not initialized")
                                .font(.title3)
                                .foregroundColor(.secondary)
                            Text("The bridge will be available once the app loads configuration")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    }
                }
            }
        }
    }
}

#Preview {
    OSCContainerView()
        .environmentObject(AppState())
        .frame(width: 900, height: 600)
}
