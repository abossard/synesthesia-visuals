import SwiftUI

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @State private var detectionTimer: Timer?
    @State private var selectedROI: ROIKey = .d1Artist

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Step 1: Window selection
                GroupBox(label: Label("1. Select VirtualDJ Window", systemImage: "macwindow")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Picker("Window", selection: $app.selectedWindowID) {
                                Text("None").tag(nil as UInt32?)
                                ForEach(app.windows) { win in
                                    Text("\(win.appName): \(win.title)").tag(win.id as UInt32?)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            Button("Refresh") { app.refreshWindows() }
                        }
                        
                        if app.isCapturing {
                            Label("Capturing automatically started", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                    }
                }

                // Step 2: Capture & Preview
                GroupBox(label: Label("2. Capture & Preview", systemImage: "video")) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Button(app.isCapturing ? "Stop Capture" : "Start Capture") {
                                app.isCapturing ? stopDetection() : startDetection()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(app.selectedWindowID == nil)

                            if app.isCapturing {
                                Label("Capturing", systemImage: "dot.radiowaves.left.and.right")
                                    .foregroundColor(.green)
                            }
                        }

                        MiniPreviewView(
                            calibration: $app.calibration,
                            frame: app.latestFrame,
                            detection: app.detection,
                            selectedROI: selectedROI,
                            isCalibrating: app.calibrating
                        )
                        // Note: Removed .id(app.frameCounter) - it was causing drag gestures to cancel
                        // The frame updates automatically via @Published property
                    }
                }

                // Step 3: Calibration
                GroupBox(label: Label("3. Calibrate Regions", systemImage: "crop")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(app.calibrating ? "Calibration Mode ON" : "Enable Calibration Mode", isOn: $app.calibrating)
                            .toggleStyle(.switch)

                        Picker("ROI", selection: $selectedROI) {
                            ForEach(ROIKey.allCases) { key in
                                Text(key.label).tag(key)
                            }
                        }

                        HStack {
                            Button("Load") { app.loadCalibration() }
                            Button("Save") { app.saveCalibration() }
                        }

                        if let rect = app.calibration.get(selectedROI) {
                            Text("x: \(rect.origin.x, specifier: "%.3f"), y: \(rect.origin.y, specifier: "%.3f"), w: \(rect.size.width, specifier: "%.3f"), h: \(rect.size.height, specifier: "%.3f")")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        Text("Language Correction (for non-English artist names):")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Toggle("D1 Artist", isOn: $app.calibration.d1ArtistLangCorrection)
                                    .toggleStyle(.checkbox)
                                    .font(.caption)
                                Toggle("D1 Title", isOn: $app.calibration.d1TitleLangCorrection)
                                    .toggleStyle(.checkbox)
                                    .font(.caption)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Toggle("D2 Artist", isOn: $app.calibration.d2ArtistLangCorrection)
                                    .toggleStyle(.checkbox)
                                    .font(.caption)
                                Toggle("D2 Title", isOn: $app.calibration.d2TitleLangCorrection)
                                    .toggleStyle(.checkbox)
                                    .font(.caption)
                            }
                        }

                        Text("When calibration mode is ON, drag inside the preview above to draw a box around the selected ROI.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                // Step 4: OSC Output
                GroupBox(label: Label("4. OSC Output", systemImage: "network")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            TextField("Host", text: $app.oscHost)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 160)
                            TextField("Port", value: $app.oscPort, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                            Toggle("Enabled", isOn: $app.oscEnabled)
                        }
                    }
                }

                // Detection Results
                GroupBox(label: Label("Detection Results", systemImage: "text.viewfinder")) {
                    if let detection = app.detection {
                        VStack(alignment: .leading, spacing: 8) {
                            // Master deck info with prominent elapsed time
                            HStack(spacing: 16) {
                                Text("Master: \(detection.masterDeck.map { "Deck \($0)" } ?? "?")")
                                    .font(.headline)
                                
                                if let master = detection.masterDeck {
                                    let masterDeck = master == 1 ? detection.deck1 : detection.deck2
                                    if let elapsed = masterDeck.elapsedSeconds {
                                        Text(formatElapsed(elapsed))
                                            .font(.system(.title2, design: .monospaced).bold())
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                            
                            Divider()
                            
                            HStack(alignment: .top, spacing: 24) {
                                deckColumn(title: "Deck 1", deck: detection.deck1, isMaster: detection.masterDeck == 1)
                                deckColumn(title: "Deck 2", deck: detection.deck2, isMaster: detection.masterDeck == 2)
                            }
                            
                            Divider()
                            
                            // Performance metrics
                            HStack(spacing: 16) {
                                Label("OCR: \(app.lastDetectionMs, specifier: "%.0f")ms", systemImage: "gauge.with.dots.needle.bottom.50percent")
                                    .font(.caption)
                                    .foregroundColor(app.lastDetectionMs < 100 ? .green : (app.lastDetectionMs < 200 ? .yellow : .red))
                                
                                Label("Avg: \(app.avgDetectionMs, specifier: "%.0f")ms", systemImage: "chart.line.uptrend.xyaxis")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Label("Frame: \(app.captureLatencyMs, specifier: "%.0f")ms", systemImage: "video")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text("(\(app.frameCounter) frames)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text("No detection yet").foregroundColor(.secondary)
                    }
                }
                
                // FSM State Diagram
                GroupBox(label: Label("State Machine", systemImage: "arrow.triangle.branch")) {
                    FSMDiagramView(state: app.deckStateManager.state, log: app.deckStateManager.transitionLog)
                }
            }
            .padding()
        }
        .frame(minWidth: 700, minHeight: 700)
        .onAppear {
            app.refreshWindowsAndAutoCapture()  // Auto-select last window if found
            app.loadCalibration()
        }
        .onChange(of: app.isCapturing) { capturing in
            // Auto-start detection timer when capture starts
            if capturing && detectionTimer == nil {
                detectionTimer = Timer.scheduledTimer(withTimeInterval: FSMConfig.default.pollInterval, repeats: true) { _ in
                    Task { @MainActor in app.runDetectionOnce() }
                }
            } else if !capturing {
                detectionTimer?.invalidate()
                detectionTimer = nil
            }
        }
        .onDisappear { stopDetection() }
    }

    private func deckColumn(title: String, deck: DeckDetection, isMaster: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline.bold())
                if isMaster {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                }
            }
            if let artist = deck.artist { Text("Artist: \(artist)").font(.caption) }
            if let trackTitle = deck.title { Text("Title: \(trackTitle)").font(.caption) }
            if let elapsed = deck.elapsedSeconds {
                Text("Time: \(formatElapsed(elapsed))")
                    .font(.caption)
                    .foregroundColor(isMaster ? .accentColor : .primary)
            }
            if let fader = deck.faderKnobPos {
                // Fader: 0 = top (100%), 1 = bottom (0%)
                let pct = Int((1.0 - fader) * 100)
                Text("Fader: \(pct)%")
                    .font(.caption)
                    .foregroundColor(pct > 50 ? .green : (pct > 20 ? .yellow : .red))
            }
        }
    }
    
    private func formatElapsed(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func startDetection() {
        app.startCapture()
    }

    private func stopDetection() {
        detectionTimer?.invalidate()
        detectionTimer = nil
        app.stopCapture()
    }
}

// MARK: - FSM Diagram View

struct FSMDiagramView: View {
    let state: MasterState
    let log: [FSMLogEntry]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Visual state diagram
            HStack(spacing: 40) {
                // Deck 1 state box
                deckStateBox(
                    title: "Deck 1",
                    playState: state.deck1.playState,
                    elapsed: state.deck1.elapsedFormatted,
                    faderPct: state.deck1.faderPercent,
                    stableCount: state.deck1.stableCount,
                    isMaster: state.master == 1
                )
                
                // Arrow showing master flow
                VStack(spacing: 4) {
                    if let m = state.master {
                        Image(systemName: m == 1 ? "arrow.left" : "arrow.right")
                            .font(.title2)
                            .foregroundColor(.yellow)
                        Text("MASTER")
                            .font(.caption2.bold())
                            .foregroundColor(.yellow)
                    } else {
                        Image(systemName: "questionmark")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("No Master")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 70)
                
                // Deck 2 state box
                deckStateBox(
                    title: "Deck 2",
                    playState: state.deck2.playState,
                    elapsed: state.deck2.elapsedFormatted,
                    faderPct: state.deck2.faderPercent,
                    stableCount: state.deck2.stableCount,
                    isMaster: state.master == 2
                )
            }
            .frame(maxWidth: .infinity)
            
            Divider()
            
            // Transition log
            VStack(alignment: .leading, spacing: 4) {
                Text("Transition Log")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                
                if log.isEmpty {
                    Text("No transitions yet...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(log.prefix(10)) { entry in
                                HStack(spacing: 8) {
                                    Text(formatTime(entry.timestamp))
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    Text(entry.message)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                }
            }
        }
    }
    
    private func deckStateBox(title: String, playState: DeckPlayState, elapsed: String, faderPct: Int?, stableCount: Int, isMaster: Bool) -> some View {
        VStack(spacing: 6) {
            // Title with master indicator
            HStack {
                Text(title)
                    .font(.headline)
                if isMaster {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                }
            }
            
            // State circle
            ZStack {
                Circle()
                    .fill(stateColor(playState).opacity(0.2))
                    .frame(width: 60, height: 60)
                Circle()
                    .stroke(stateColor(playState), lineWidth: isMaster ? 3 : 1)
                    .frame(width: 60, height: 60)
                
                Text(playState.description)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            
            // Details
            VStack(spacing: 2) {
                Text(elapsed)
                    .font(.system(.caption, design: .monospaced))
                
                if let pct = faderPct {
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(pct > 50 ? Color.green : (pct > 20 ? Color.yellow : Color.red))
                            .frame(width: CGFloat(pct) * 0.5, height: 6)
                        Spacer()
                    }
                    .frame(width: 50)
                    .background(Color.gray.opacity(0.3))
                    .cornerRadius(3)
                    
                    Text("\(pct)%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                if playState != .stopped && stableCount > 0 {
                    Text("stable: \(stableCount)/3")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isMaster ? Color.yellow.opacity(0.1) : Color.gray.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isMaster ? Color.yellow : Color.gray.opacity(0.3), lineWidth: isMaster ? 2 : 1)
        )
    }
    
    private func stateColor(_ state: DeckPlayState) -> Color {
        switch state {
        case .playing: return .green
        case .stopped: return .red
        case .unknown: return .gray
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
