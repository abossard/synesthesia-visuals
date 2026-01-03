// SettingsView - User preferences panel
// Phase 4: SwiftUI Shell

import SwiftUI
import SwiftVJCore

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    
    // Settings state
    @AppStorage("playbackSource") private var playbackSource = "vdj"
    @AppStorage("timingOffsetMs") private var timingOffsetMs = 0
    @AppStorage("startSynesthesia") private var startSynesthesia = false
    @AppStorage("playbackPollInterval") private var playbackPollInterval = 1.0
    @AppStorage("shaderDirectory") private var shaderDirectory = ""
    @AppStorage("imagesCacheDir") private var imagesCacheDir = ""
    
    var body: some View {
        TabView {
            // General
            Form {
                Section("Playback") {
                    Picker("Default Source", selection: $playbackSource) {
                        Text("VirtualDJ").tag("vdj")
                        Text("Spotify").tag("spotify")
                    }
                    .pickerStyle(.segmented)
                    
                    HStack {
                        Text("Poll Interval")
                        Slider(value: $playbackPollInterval, in: 0.1...5.0, step: 0.1)
                        Text("\(playbackPollInterval, specifier: "%.1f")s")
                            .monospacedDigit()
                            .frame(width: 40)
                    }
                    
                    Toggle("Start Synesthesia on launch", isOn: $startSynesthesia)
                }
                
                Section("Timing") {
                    HStack {
                        Text("Lyrics Offset")
                        Spacer()
                        Text("\(timingOffsetMs) ms")
                            .monospacedDigit()
                        Stepper("", value: $timingOffsetMs, in: -2000...2000, step: 10)
                            .labelsHidden()
                    }
                    
                    Button("Reset to 0") {
                        timingOffsetMs = 0
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("General", systemImage: "gearshape")
            }
            
            // Paths
            Form {
                Section("Directories") {
                    HStack {
                        TextField("Shader Directory", text: $shaderDirectory)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                            selectFolder { url in
                                shaderDirectory = url.path
                            }
                        }
                    }
                    
                    HStack {
                        TextField("Images Cache", text: $imagesCacheDir)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                            selectFolder { url in
                                imagesCacheDir = url.path
                            }
                        }
                    }
                }
                
                Section("Cache") {
                    HStack {
                        Text("Lyrics cache")
                        Spacer()
                        Text("~/.cache/swift-vj/lyrics")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Pipeline cache")
                        Spacer()
                        Text("~/.cache/swift-vj/pipeline")
                            .foregroundColor(.secondary)
                    }
                    
                    Button("Clear All Caches") {
                        // TODO: Implement cache clearing
                    }
                    .foregroundColor(.red)
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Paths", systemImage: "folder")
            }
            
            // OSC
            Form {
                Section("Ports") {
                    LabeledContent("Receive Port", value: "9999")
                    LabeledContent("VirtualDJ", value: "9009")
                    LabeledContent("Synesthesia", value: "7777")
                    LabeledContent("Processing", value: "10000")
                    LabeledContent("Magic", value: "11111")
                }
                
                Section("Forward Targets") {
                    Toggle("Forward to Processing", isOn: .constant(true))
                    Toggle("Forward to Magic", isOn: .constant(true))
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("OSC", systemImage: "antenna.radiowaves.left.and.right")
            }
            
            // About
            VStack(spacing: 20) {
                Image(systemName: "sparkles")
                    .font(.system(size: 64))
                    .foregroundColor(.blue)
                
                Text("SwiftVJ")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Version 1.0.0")
                    .foregroundColor(.secondary)
                
                Text("A VJ control application for macOS")
                    .foregroundColor(.secondary)
                
                Divider()
                    .frame(width: 200)
                
                VStack(spacing: 4) {
                    Text("Built with SwiftUI")
                    Text("OSC via OSCKit")
                    Text("LLM via LM Studio")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding(40)
            .tabItem {
                Label("About", systemImage: "info.circle")
            }
        }
        .frame(width: 500, height: 400)
    }
    
    private func selectFolder(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            completion(url)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
