import SwiftUI

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @State private var selectedROI: ROIKey = .d1Artist
    @State private var detectionTimer: Timer?
    @State private var isRunning = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Window selection
            VStack(alignment: .leading) {
                Text("Select VirtualDJ Window")
                    .font(.headline)
                
                HStack {
                    Picker("Window", selection: $app.selectedWindowID) {
                        Text("None").tag(nil as UInt32?)
                        ForEach(app.windows) { win in
                            Text("\(win.appName): \(win.title)").tag(win.id as UInt32?)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    Button("Refresh") {
                        app.refreshWindows()
                    }
                }
            }
            
            Divider()
            
            // Capture controls
            HStack {
                Button(isRunning ? "Stop Capture" : "Start Capture") {
                    if isRunning {
                        stopDetection()
                    } else {
                        startDetection()
                    }
                }
                .disabled(app.selectedWindowID == nil)
                
                Toggle("Show Overlay", isOn: $app.overlayEnabled)
                Toggle("Calibrate", isOn: $app.calibrating)
            }
            
            Divider()
            
            // Calibration
            VStack(alignment: .leading) {
                Text("Calibration")
                    .font(.headline)
                
                Picker("ROI", selection: $selectedROI) {
                    ForEach(ROIKey.allCases) { key in
                        Text(key.label).tag(key)
                    }
                }
                
                HStack {
                    Button("Load") {
                        app.loadCalibration()
                    }
                    Button("Save") {
                        app.saveCalibration()
                    }
                }
                
                if let rect = app.calibration.get(selectedROI) {
                    Text("x: \(rect.origin.x, specifier: "%.3f"), y: \(rect.origin.y, specifier: "%.3f"), w: \(rect.size.width, specifier: "%.3f"), h: \(rect.size.height, specifier: "%.3f")")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            // OSC Settings
            VStack(alignment: .leading) {
                Text("OSC Output")
                    .font(.headline)
                
                HStack {
                    TextField("Host", text: $app.oscHost)
                        .frame(width: 120)
                    TextField("Port", value: $app.oscPort, format: .number)
                        .frame(width: 80)
                    Toggle("Enabled", isOn: $app.oscEnabled)
                }
            }
            
            Divider()
            
            // Detection results
            VStack(alignment: .leading) {
                Text("Detection Results")
                    .font(.headline)
                
                if let detection = app.detection {
                    Text("Master Deck: \(detection.masterDeck.map { "Deck \($0)" } ?? "Unknown")")
                        .font(.subheadline)
                    
                    HStack(spacing: 20) {
                        DeckInfoView(title: "Deck 1", deck: detection.deck1)
                        DeckInfoView(title: "Deck 2", deck: detection.deck2)
                    }
                } else {
                    Text("No detection data")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            app.refreshWindows()
            app.loadCalibration()
        }
    }
    
    private func startDetection() {
        app.startCapture()
        isRunning = true
        
        // Run detection every 0.5 seconds (2 fps)
        detectionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                app.runDetectionOnce()
            }
        }
    }
    
    private func stopDetection() {
        detectionTimer?.invalidate()
        detectionTimer = nil
        app.stopCapture()
        isRunning = false
    }
}

struct DeckInfoView: View {
    let title: String
    let deck: DeckDetection
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            
            Group {
                if let artist = deck.artist {
                    Text("Artist: \(artist)").font(.caption)
                }
                if let trackTitle = deck.title {
                    Text("Title: \(trackTitle)").font(.caption)
                }
                if let elapsed = deck.elapsedSeconds {
                    Text("Time: \(Int(elapsed / 60)):\(String(format: "%02d", Int(elapsed) % 60))").font(.caption)
                }
                if let fader = deck.faderKnobPos {
                    Text("Fader: \(fader, specifier: "%.2f")").font(.caption)
                }
                if let conf = deck.faderConfidence {
                    Text("Confidence: \(conf, specifier: "%.2f")").font(.caption)
                }
            }
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
