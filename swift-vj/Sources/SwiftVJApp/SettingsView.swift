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
    
    // Folder paths with sensible defaults
    @AppStorage("shaderDirectory") private var shaderDirectory = SettingsView.defaultShaderDirectory
    @AppStorage("imagesCacheDir") private var imagesCacheDir = SettingsView.defaultImagesCacheDir
    @AppStorage("lyricsCacheDir") private var lyricsCacheDir = SettingsView.defaultLyricsCacheDir
    @AppStorage("pipelineCacheDir") private var pipelineCacheDir = SettingsView.defaultPipelineCacheDir
    @AppStorage("songImagesDir") private var songImagesDir = SettingsView.defaultSongImagesDir
    
    // Default paths based on repository structure and macOS conventions
    private static var defaultShaderDirectory: String {
        // Try to find synesthesia-shaders relative to the repo
        let fm = FileManager.default
        let currentDir = fm.currentDirectoryPath
        let repoShaders = (currentDir as NSString).appendingPathComponent("../synesthesia-shaders")
        if fm.fileExists(atPath: repoShaders) {
            return (repoShaders as NSString).standardizingPath
        }
        return ""
    }
    
    private static var defaultImagesCacheDir: String {
        Config.cacheDirectory.appendingPathComponent("images").path
    }
    
    private static var defaultLyricsCacheDir: String {
        Config.cacheDirectory.appendingPathComponent("lyrics").path
    }
    
    private static var defaultPipelineCacheDir: String {
        Config.cacheDirectory.appendingPathComponent("pipeline").path
    }
    
    private static var defaultSongImagesDir: String {
        // Try to find data/song_images relative to repo, fallback to app support
        let fm = FileManager.default
        let currentDir = fm.currentDirectoryPath
        let repoImages = (currentDir as NSString).appendingPathComponent("../data/song_images")
        if fm.fileExists(atPath: repoImages) {
            return (repoImages as NSString).standardizingPath
        }
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("SwiftVJ/song_images").path
    }
    
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
                Section("Shader Directories") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Shader Directory", text: $shaderDirectory, prompt: Text(Self.defaultShaderDirectory))
                                .textFieldStyle(.roundedBorder)
                            Button("Browse...") {
                                selectFolder { url in
                                    shaderDirectory = url.path
                                }
                            }
                            Button("Reset") {
                                shaderDirectory = Self.defaultShaderDirectory
                            }
                            .disabled(shaderDirectory == Self.defaultShaderDirectory)
                        }
                        Text("Default: \(Self.defaultShaderDirectory.isEmpty ? "Not found" : Self.defaultShaderDirectory)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Image Directories") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Song Images Directory", text: $songImagesDir, prompt: Text(Self.defaultSongImagesDir))
                                .textFieldStyle(.roundedBorder)
                            Button("Browse...") {
                                selectFolder { url in
                                    songImagesDir = url.path
                                }
                            }
                            Button("Reset") {
                                songImagesDir = Self.defaultSongImagesDir
                            }
                            .disabled(songImagesDir == Self.defaultSongImagesDir)
                        }
                        Text("Default: \(Self.defaultSongImagesDir)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Images Cache", text: $imagesCacheDir, prompt: Text(Self.defaultImagesCacheDir))
                                .textFieldStyle(.roundedBorder)
                            Button("Browse...") {
                                selectFolder { url in
                                    imagesCacheDir = url.path
                                }
                            }
                            Button("Reset") {
                                imagesCacheDir = Self.defaultImagesCacheDir
                            }
                            .disabled(imagesCacheDir == Self.defaultImagesCacheDir)
                        }
                        Text("Default: \(Self.defaultImagesCacheDir)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Cache Directories") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Lyrics Cache", text: $lyricsCacheDir, prompt: Text(Self.defaultLyricsCacheDir))
                                .textFieldStyle(.roundedBorder)
                            Button("Browse...") {
                                selectFolder { url in
                                    lyricsCacheDir = url.path
                                }
                            }
                            Button("Reset") {
                                lyricsCacheDir = Self.defaultLyricsCacheDir
                            }
                            .disabled(lyricsCacheDir == Self.defaultLyricsCacheDir)
                        }
                        Text("Default: \(Self.defaultLyricsCacheDir)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Pipeline Cache", text: $pipelineCacheDir, prompt: Text(Self.defaultPipelineCacheDir))
                                .textFieldStyle(.roundedBorder)
                            Button("Browse...") {
                                selectFolder { url in
                                    pipelineCacheDir = url.path
                                }
                            }
                            Button("Reset") {
                                pipelineCacheDir = Self.defaultPipelineCacheDir
                            }
                            .disabled(pipelineCacheDir == Self.defaultPipelineCacheDir)
                        }
                        Text("Default: \(Self.defaultPipelineCacheDir)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Button("Clear All Caches") {
                        clearAllCaches()
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
                    LabeledContent("Magic", value: "11111")
                }

                Section("Forward Targets") {
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
        .frame(minWidth: 700, idealWidth: 800, maxWidth: 900, minHeight: 600, idealHeight: 700, maxHeight: 800)
    }
    
    private func clearAllCaches() {
        let fm = FileManager.default
        let paths = [lyricsCacheDir, pipelineCacheDir, imagesCacheDir].compactMap { path -> URL? in
            path.isEmpty ? nil : URL(fileURLWithPath: path)
        }
        
        for path in paths {
            try? fm.removeItem(at: path)
            try? fm.createDirectory(at: path, withIntermediateDirectories: true)
        }
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
