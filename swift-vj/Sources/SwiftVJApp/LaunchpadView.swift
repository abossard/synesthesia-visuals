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
                    
                    // Main Grid Rows (row 7 at top, row 0 at bottom - matches physical Launchpad)
                    ForEach((0..<8).reversed(), id: \.self) { y in
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
                        // Get YAML config for bank names/colors
                        let yamlConfig = appState.launchpadModule?.yamlConfig
                        
                        Group {
                            // Bank indicator with names from YAML
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Bank")
                                        .foregroundColor(.secondary)
                                    ForEach(0..<8, id: \.self) { i in
                                        Circle()
                                            .fill(bankColor(i, isActive: i == state.activeBank, yamlConfig: yamlConfig))
                                            .frame(width: i == state.activeBank ? 14 : 10, height: i == state.activeBank ? 14 : 10)
                                    }
                                }
                                .font(.caption)
                                
                                // Show current bank name
                                Text(bankName(state.activeBank, yamlConfig: yamlConfig))
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(bankColor(state.activeBank, isActive: true, yamlConfig: yamlConfig))
                                    .cornerRadius(4)
                            }
                            
                            DetailRow(label: "Active Scene", value: state.activeScene ?? "-")
                            DetailRow(label: "Active Preset", value: state.activePreset ?? "-")
                            DetailRow(label: "BPM", value: String(format: "%.1f", appState.launchpadStatus?.currentBpm ?? 0.0))
                        }
                        
                        Divider()
                        
                        Text("Learn Mode")
                            .font(.headline)
                        
                        DetailRow(label: "Phase", value: phaseDisplayName(state.learnState.phase))
                        if let selected = state.learnState.selectedPad {
                            DetailRow(label: "Selected Pad", value: "(\(selected.x), \(selected.y)) in Bank \(state.activeBank)")
                        }
                        
                        // Show captured OSC during CONFIG phase (live capture with enable/disable)
                        if state.learnState.phase == .config {
                            let captured = state.learnState.capturedOsc
                            let sceneCount = captured.filter { $0.command.address.hasPrefix("/scenes/") }.count
                            let controlCount = captured.filter { $0.command.address.hasPrefix("/controls/") }.count
                            
                            VStack(alignment: .leading, spacing: 4) {
                                if captured.isEmpty {
                                    Text("Waiting for OSC...")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                        .italic()
                                    Text("Select a scene in Synesthesia")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                } else {
                                    HStack {
                                        if sceneCount > 0 {
                                            Label("\(sceneCount) scene", systemImage: "photo.artframe")
                                                .font(.caption2)
                                                .foregroundColor(.green)
                                        }
                                        if controlCount > 0 {
                                            Label("\(controlCount) controls", systemImage: "slider.horizontal.3")
                                                .font(.caption2)
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                                
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 2) {
                                        ForEach(Array(captured.enumerated()), id: \.element) { idx, osc in
                                            HStack {
                                                // Enable/disable toggle indicator
                                                Image(systemName: osc.isEnabled ? "checkmark.circle.fill" : "circle")
                                                    .foregroundColor(osc.isEnabled ? .green : .gray)
                                                    .font(.caption)
                                                
                                                // Priority label
                                                Text(priorityLabel(osc.priority))
                                                    .font(.system(.caption2, design: .rounded))
                                                    .foregroundColor(priorityColor(osc.priority))
                                                    .frame(width: 16)
                                                
                                                Text(osc.command.address)
                                                    .font(.system(.caption2, design: .monospaced))
                                                    .foregroundColor(osc.isEnabled ? .white : .gray)
                                            }
                                        }
                                    }
                                }
                                .frame(maxHeight: 100)
                                .background(Color.black.opacity(0.3))
                                .cornerRadius(4)
                                
                                // Show current selection details
                                HStack {
                                    Text("Mode:")
                                        .foregroundColor(.secondary)
                                    Text(modeDisplayName(state.learnState.selectedMode))
                                        .font(.system(.caption, design: .monospaced))
                                }
                                .font(.caption)
                                
                                HStack {
                                    Text("Color:")
                                        .foregroundColor(.secondary)
                                    Circle()
                                        .fill(launchpadColorToSwiftUI(state.learnState.selectedColor))
                                        .frame(width: 12, height: 12)
                                }
                                .font(.caption)
                            }
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

// MARK: - Helper Functions

/// Convert learn phase to display name
func phaseDisplayName(_ phase: LearnPhase) -> String {
    switch phase {
    case .idle: return "Idle"
    case .waitPad: return "Select Pad"
    case .config: return "Configure"
    }
}

/// Convert pad mode to display name
func modeDisplayName(_ mode: PadMode?) -> String {
    guard let mode = mode else { return "-" }
    switch mode {
    case .selector: return "Selector"
    case .toggle: return "Toggle"
    case .oneShot: return "One-Shot"
    case .push: return "Push"
    case .increment: return "Increment"
    case .decrement: return "Decrement"
    }
}

/// Helper to convert Launchpad color index to SwiftUI Color (standalone version)
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
    default: return Color(white: 0.3)
    }
}

/// Bank index to SwiftUI Color (uses YAML config if available)
func bankColor(_ index: Int, isActive: Bool, yamlConfig: LaunchpadYAMLConfig?) -> Color {
    // Try YAML config colors first
    if let yaml = yamlConfig,
       let bankButton = yaml.global.bankButtons.first(where: { $0.bank == index }) {
        let colorName = isActive ? bankButton.activeColor : bankButton.idleColor
        let lpColor = yaml.color(colorName)
        return launchpadColorToSwiftUI(lpColor)
    }
    
    // Fallback to hardcoded colors
    let colors: [Color] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink]
    let baseColor = index < colors.count ? colors[index] : .gray
    return isActive ? baseColor : baseColor.opacity(0.3)
}

/// Get bank name from YAML config
func bankName(_ index: Int, yamlConfig: LaunchpadYAMLConfig?) -> String {
    yamlConfig?.bankName(index) ?? "Bank \(index)"
}

/// Get short label for priority level
func priorityLabel(_ priority: Int) -> String {
    switch priority {
    case 1: return "S"   // Scene
    case 2: return "P"   // Preset
    case 3: return "C"   // Control
    default: return "?"
    }
}

/// Get color for priority level
func priorityColor(_ priority: Int) -> Color {
    switch priority {
    case 1: return .red      // Scene - highest priority
    case 2: return .orange   // Preset
    case 3: return .yellow   // Control
    default: return .gray
    }
}
