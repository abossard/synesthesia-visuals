import SwiftUI

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @State private var detectionTimer: Timer?
    @State private var selectedROI: ROIKey = .d1Artist

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                WizardProgressView(currentStep: app.wizardStep)

                StepCard(number: 1,
                         title: "Select VirtualDJ Window",
                         subtitle: AppState.WizardStep.selectWindow.subtitle,
                         isActive: app.wizardStep == .selectWindow) {
                    windowSelectionSection
                }

                StepCard(number: 2,
                         title: "Start Capture & Preview",
                         subtitle: AppState.WizardStep.capturePreview.subtitle,
                         isActive: app.wizardStep != .selectWindow) {
                    captureSection
                }

                StepCard(number: 3,
                         title: "Calibrate Regions",
                         subtitle: AppState.WizardStep.calibrate.subtitle,
                         isActive: app.calibrating) {
                    calibrationSection
                }

                StepCard(number: 4,
                         title: "OSC Output",
                         subtitle: "Send detections to Synesthesia",
                         isActive: true) {
                    oscSection
                }

                DetectionSummaryView(detection: app.detection)
            }
            .padding()
        }
        .onAppear {
            app.refreshWindows()
            app.loadCalibration()
        }
        .onDisappear { stopDetection() }
    }

    private var windowSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose the VirtualDJ window to analyze.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Picker("Window", selection: $app.selectedWindowID) {
                    Text("None").tag(nil as UInt32?)
                    ForEach(app.windows) { win in
                        Text("\(win.appName): \(win.title)").tag(win.id as UInt32?)
                    }
                }
                .frame(maxWidth: .infinity)

                Button("Refresh") { app.refreshWindows() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var captureSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Button(app.isCapturing ? "Stop Capture" : "Start Capture") {
                    app.isCapturing ? stopDetection() : startDetection()
                }
                .buttonStyle(.borderedProminent)
                .disabled(app.selectedWindowID == nil)

                if app.isCapturing {
                    Label("Capturing", systemImage: "dot.radiowaves.left.and.right")
                        .foregroundColor(.green)
                } else {
                    Label("Idle", systemImage: "pause")
                        .foregroundColor(.secondary)
                }
            }

            MiniPreviewView(
                calibration: $app.calibration,
                frame: app.latestFrame,
                detection: app.detection,
                selectedROI: selectedROI,
                isCalibrating: app.calibrating
            )
        }
    }

    private var calibrationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(app.calibrating ? "Calibration Mode Enabled" : "Enable Calibration Mode", isOn: $app.calibrating)
                .toggleStyle(.switch)

            Picker("ROI", selection: $selectedROI) {
                ForEach(ROIKey.allCases) { key in
                    Text(key.label).tag(key)
                }
            }

            HStack(spacing: 12) {
                Button("Load") { app.loadCalibration() }
                Button("Save") { app.saveCalibration() }
            }

            if let rect = app.calibration.get(selectedROI) {
                Text("x: \(rect.origin.x, specifier: "%.3f"), y: \(rect.origin.y, specifier: "%.3f"), w: \(rect.size.width, specifier: "%.3f"), h: \(rect.size.height, specifier: "%.3f")")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Text("While calibration mode is on, drag ROI handles directly in the preview above. The preview enlarges for finer control.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private var oscSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                TextField("Host", text: $app.oscHost)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                TextField("Port", value: $app.oscPort, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                Toggle("Enabled", isOn: $app.oscEnabled)
            }
            Text("OSC pushes deck + fader updates to your VJ toolkit.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private func startDetection() {
        app.startCapture()
        detectionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in app.runDetectionOnce() }
        }
    }

    private func stopDetection() {
        detectionTimer?.invalidate()
        detectionTimer = nil
        app.stopCapture()
    }
}

private struct StepCard<Content: View>: View {
    let number: Int
    let title: String
    let subtitle: String
    let isActive: Bool
    let content: Content

    init(number: Int, title: String, subtitle: String, isActive: Bool, @ViewBuilder content: () -> Content) {
        self.number = number
        self.title = title
        self.subtitle = subtitle
        self.isActive = isActive
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(number)")
                    .font(.title3.bold())
                    .frame(width: 32, height: 32)
                    .background(isActive ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.subheadline).foregroundColor(.secondary)
                }
            }
            content
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }
}

private struct WizardProgressView: View {
    let steps = AppState.WizardStep.allCases
    let currentStep: AppState.WizardStep

    var body: some View {
        HStack(spacing: 0) {
            ForEach(steps) { step in
                HStack(spacing: 8) {
                    Circle()
                        .fill(step == currentStep ? Color.accentColor : Color.gray.opacity(0.5))
                        .frame(width: 10, height: 10)
                    Text(step.title)
                        .font(.caption)
                        .foregroundColor(step == currentStep ? .primary : .secondary)
                }
                if step != steps.last {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(maxWidth: .infinity, maxHeight: 1)
                }
            }
        }
        .padding(.horizontal, 8)
    }
}

private struct DetectionSummaryView: View {
    let detection: DetectionResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Detection Results").font(.headline)
            if let detection = detection {
                Text("Master Deck: \(detection.masterDeck.map { "Deck \($0)" } ?? "Unknown")")
                HStack(alignment: .top, spacing: 24) {
                    deckColumn(title: "Deck 1", deck: detection.deck1)
                    deckColumn(title: "Deck 2", deck: detection.deck2)
                }
            } else {
                Text("No detection yet").foregroundColor(.secondary)
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func deckColumn(title: String, deck: DeckDetection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.bold())
            if let artist = deck.artist { Text("Artist: \(artist)").font(.caption) }
            if let trackTitle = deck.title { Text("Title: \(trackTitle)").font(.caption) }
            if let elapsed = deck.elapsedSeconds {
                Text("Time: \(Int(elapsed / 60)):\(String(format: "%02d", Int(elapsed) % 60))").font(.caption)
            }
            if let fader = deck.faderKnobPos { Text("Fader: \(fader, specifier: "%.2f")").font(.caption) }
        }
    }
}
