// LaunchpadView.swift - Visualization and control for Launchpad
// Phase 5: MIDI Controller UI

import SwiftUI
import SwiftVJCore

struct LaunchpadView: View {
    @EnvironmentObject var appState: AppState
    @State private var showTestSheet = false
    
    // Grid layout constants
    private let gridSize = 8
    private let spacing: CGFloat = 4
    
    var body: some View {
        VStack(spacing: 20) {
            // Header / Status
            HStack {
                VStack(alignment: .leading) {
                    Text("Launchpad Mini MK3")
                        .font(.title2)
                        .bold()
                    
                    if let status = appState.launchpadStatus {
                        HStack {
                            Circle()
                                .fill(status.isConnected ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(status.isConnected ? "Connected" : "Disconnected")
                                .foregroundColor(.secondary)
                            
                            if let name = status.deviceName {
                                Text("(\(name))")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                    } else {
                        Text("Module not initialized")
                            .foregroundColor(.red)
                    }
                }
                
                Spacer()
                
                // Learn Mode Toggle
                if let status = appState.launchpadStatus, status.isConnected {
                    Button(action: {
                        if status.isLearnMode {
                            appState.launchpadModule?.stopLearnMode()
                        } else {
                            appState.launchpadModule?.startLearnMode()
                        }
                    }) {
                        Label(status.isLearnMode ? "Stop Learn Mode" : "Start Learn Mode", 
                              systemImage: status.isLearnMode ? "recordingtape" : "graduationcap")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(status.isLearnMode ? .red : .blue)
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            
            // Main Grid Visualization
            HStack(alignment: .top, spacing: 20) {
                // 8x8 Grid + Top Row + Right Column
                VStack(spacing: spacing) {
                    // Top Row (CC 91-98)
                    HStack(spacing: spacing) {
                        ForEach(0..<8) { x in
                            PadView(id: ButtonId(x: x, y: -1))
                        }
                        // Empty space for corner
                        Color.clear.frame(width: 30, height: 30)
                    }
                    
                    // Main Grid Rows
                    ForEach(0..<8) { y in
                        HStack(spacing: spacing) {
                            // Grid Pads (0-7)
                            ForEach(0..<8) { x in
                                PadView(id: ButtonId(x: x, y: y))
                            }
                            
                            // Scene Launch Button (Right Column, x=8)
                            PadView(id: ButtonId(x: 8, y: y))
                        }
                    }
                }
                .padding()
                .background(Color.black.opacity(0.2))
                .cornerRadius(12)
                
                // Inspector / Details Panel
                VStack(alignment: .leading, spacing: 16) {
                    Text("Controller State")
                        .font(.headline)
                    
                    if let state = appState.launchpadState {
                        Group {
                            DetailRow(label: "Active Scene", value: state.activeScene ?? "-")
                            DetailRow(label: "Active Preset", value: state.activePreset ?? "-")
                            DetailRow(label: "BPM", value: String(format: "%.1f", appState.launchpadStatus?.currentBpm ?? 0.0))
                            DetailRow(label: "Beat Phase", value: String(format: "%.2f", state.beatPhase))
                        }
                        
                        Divider()
                        
                        Text("Learn Mode")
                            .font(.headline)
                        
                        DetailRow(label: "Phase", value: "\(state.learnState.phase)")
                        if let selected = state.learnState.selectedPad {
                            DetailRow(label: "Selected Pad", value: "(\(selected.x), \(selected.y))")
                        }
                        
                        Divider()
                        
                        Text("Diagnostics")
                            .font(.headline)
                        
                        Button("Run E2E Test Sequence") {
                            showTestSheet = true
                        }
                        .sheet(isPresented: $showTestSheet) {
                            LaunchpadTestView()
                        }
                        
                        Button("Force Programmer Mode") {
                            appState.launchpadModule?.forceProgrammerMode()
                        }
                        
                        Button("Flash All LEDs") {
                            // Simple diagnostic pattern
                            let allPads = (0...8).flatMap { x in (0...8).map { y in ButtonId(x: x, y: y) } }
                            let updates = allPads.map { ($0, LP.red) }
                            appState.launchpadModule?.setLeds(updates)
                            
                            // Clear after delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                let clears = allPads.map { ($0, LP.off) }
                                appState.launchpadModule?.setLeds(clears)
                            }
                        }
                        
                        Button("Rainbow Pattern") {
                            // Simple rainbow
                            let colors = [LP.red, LP.orange, LP.yellow, LP.green, LP.cyan, LP.blue, LP.purple, LP.pink]
                            var updates: [(ButtonId, Int)] = []
                            for y in 0..<8 {
                                for x in 0..<8 {
                                    let colorIndex = (x + y) % colors.count
                                    updates.append((ButtonId(x: x, y: y), colors[colorIndex]))
                                }
                            }
                            appState.launchpadModule?.setLeds(updates)
                        }
                        
                        Button("Clear All") {
                            let allPads = (0...8).flatMap { x in (0...8).map { y in ButtonId(x: x, y: y) } }
                            let clears = allPads.map { ($0, LP.off) }
                            appState.launchpadModule?.setLeds(clears)
                        }
                    }
                    
                    // Always show Diagnostics if connected, even if state is missing
                    if appState.launchpadStatus?.isConnected == true && appState.launchpadState == nil {
                        Divider()
                        Text("Diagnostics (State Missing)")
                            .font(.headline)
                            .foregroundColor(.orange)
                        
                        Button("Force Programmer Mode") {
                            appState.launchpadModule?.forceProgrammerMode()
                        }
                        
                        Button("Flash All LEDs") {
                            let allPads = (0...8).flatMap { x in (0...8).map { y in ButtonId(x: x, y: y) } }
                            let updates = allPads.map { ($0, LP.red) }
                            appState.launchpadModule?.setLeds(updates)
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                let clears = allPads.map { ($0, LP.off) }
                                appState.launchpadModule?.setLeds(clears)
                            }
                        }
                    } else if appState.launchpadState == nil {
                        Text("No state available")
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .frame(width: 250)
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }
        }
        .padding()
    }
}

struct PadView: View {
    let id: ButtonId
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        let runtime = appState.launchpadState?.padRuntime[id]
        let behavior = appState.launchpadState?.pads[id]
        
        // Determine color
        let colorInt = runtime?.currentColor ?? LP.off
        let color = launchpadColorToSwiftUI(colorInt)
        
        // Determine shape
        let isRound = id.isTopRow || id.isSceneButton
        
        ZStack {
            // Base shape
            if isRound {
                Circle()
                    .fill(color)
                    .frame(width: 30, height: 30)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: 30, height: 30)
            }
            
            // Overlay for selection/activity
            if runtime?.isActive == true {
                if isRound {
                    Circle().stroke(Color.white, lineWidth: 2)
                } else {
                    RoundedRectangle(cornerRadius: 4).stroke(Color.white, lineWidth: 2)
                }
            }
            
            // Label (if configured)
            if let label = behavior?.label, !label.isEmpty {
                Text(label.prefix(1))
                    .font(.caption2)
                    .foregroundColor(.black)
            }
        }
        .onTapGesture {
            // Simulate press for testing/manual control
            // In a real app, this might trigger the actual logic via LaunchpadModule
            // For now, just print
            print("Pad tapped: \(id)")
        }
    }
    
    // Helper to convert Launchpad color index to SwiftUI Color
    func launchpadColorToSwiftUI(_ lpColor: Int) -> Color {
        switch lpColor {
        case LP.off: return Color(white: 0.2)
        case LP.red, LP.redDim: return .red
        case LP.orange: return .orange
        case LP.yellow: return .yellow
        case LP.green, LP.greenDim: return .green
        case LP.cyan: return .cyan
        case LP.blue, LP.blueDim: return .blue
        case LP.purple: return .purple
        case LP.pink: return .pink
        case LP.white: return .white
        default: return Color(white: 0.2)
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }
}
