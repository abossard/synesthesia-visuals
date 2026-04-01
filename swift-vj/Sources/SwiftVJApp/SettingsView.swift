// SettingsView - User preferences panel
// Phase 4: SwiftUI Shell

import SwiftUI
import SwiftVJCore
import Darwin
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    
    // Draft settings state (saved only on explicit Save)
    @State private var playbackSource = "vdj"
    @State private var startSynesthesia = false
    @State private var playbackPollInterval = 1.0
    @State private var shaderDirectory = ""
    @State private var imagesCacheDir = ""
    @State private var lyricsCacheDir = ""
    @State private var pipelineCacheDir = ""
    @State private var songImagesDir = ""
    @State private var tachikomaConfigPath = ""
    @State private var ledfxBaseURL = "http://127.0.0.1:8888"
    @State private var oscVDJPort = ""
    @State private var oscSynesthesiaPort = ""
    @State private var oscMagicPort = ""
    @State private var oscVDJReceivePort = ""
    @State private var showRestartNotice = false
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""
    @State private var renderingEnabled = true
    @State private var performanceEnabled = true
    @State private var shadersEnabled = true
    @State private var launchpadEnabled = true
    @State private var songsEnabled = true
    
    // Default paths cached to avoid repeated file system checks
    private struct DefaultPaths {
        static let shaderDirectory: String = {
            if let resolved = ShaderDirectoryLocator.resolve(customPath: UserDefaults.standard.string(forKey: "shaderDirectory")) {
                return resolved.path
            }

            // Try to find synesthesia-shaders relative to the repo
            let fm = FileManager.default
            let currentDir = fm.currentDirectoryPath
            let repoShaders = (currentDir as NSString).appendingPathComponent("../synesthesia-shaders")
            if fm.fileExists(atPath: repoShaders) {
                return (repoShaders as NSString).standardizingPath
            }
            return ""
        }()
        
        static let imagesCacheDir: String = {
            Config.cacheDirectory.appendingPathComponent("images").path
        }()
        
        static let lyricsCacheDir: String = {
            Config.cacheDirectory.appendingPathComponent("lyrics").path
        }()
        
        static let pipelineCacheDir: String = {
            Config.cacheDirectory.appendingPathComponent("pipeline").path
        }()
        
        static let songImagesDir: String = {
            // Try to find data/song_images relative to repo, fallback to app support
            let fm = FileManager.default
            let currentDir = fm.currentDirectoryPath
            let repoImages = (currentDir as NSString).appendingPathComponent("../data/song_images")
            if fm.fileExists(atPath: repoImages) {
                return (repoImages as NSString).standardizingPath
            }
            // Safe unwrap with fallback
            guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                return ""
            }
            return appSupport.appendingPathComponent("SwiftVJ/song_images").path
        }()

        static let tachikomaConfigPath: String = {
            ""
        }()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                GroupBox("Feature Modules") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Disable modules you don't need. Tab visibility updates immediately; module startup changes take effect on restart.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack(spacing: 24) {
                            Toggle("Rendering", isOn: $renderingEnabled)
                            Toggle("Performance", isOn: $performanceEnabled)
                            Toggle("Shaders", isOn: $shadersEnabled)
                            Toggle("Launchpad", isOn: $launchpadEnabled)
                            Toggle("Songs", isOn: $songsEnabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }

                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 24) {
                    GroupBox("Playback") {
                        VStack(alignment: .leading, spacing: 12) {
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }
                    
                    GroupBox("LedFX") {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Base URL", text: $ledfxBaseURL)
                                .textFieldStyle(.roundedBorder)
                            Text("Default: http://127.0.0.1:8888")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }
                    
                    GroupBox("Shader Directories") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField("Shader Directory", text: $shaderDirectory, prompt: Text(DefaultPaths.shaderDirectory))
                                    .textFieldStyle(.roundedBorder)
                                Button("Browse...") {
                                    selectFolder { url in
                                        shaderDirectory = url.path
                                    }
                                }
                                Button("Reset") {
                                    shaderDirectory = DefaultPaths.shaderDirectory
                                }
                                .disabled(shaderDirectory == DefaultPaths.shaderDirectory)
                            }
                            Text("Default: \(DefaultPaths.shaderDirectory.isEmpty ? "Not found" : DefaultPaths.shaderDirectory)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }
                    
                    GroupBox("Image Directories") {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    TextField("Song Images Directory", text: $songImagesDir, prompt: Text(DefaultPaths.songImagesDir))
                                        .textFieldStyle(.roundedBorder)
                                    Button("Browse...") {
                                        selectFolder { url in
                                            songImagesDir = url.path
                                        }
                                    }
                                    Button("Reset") {
                                        songImagesDir = DefaultPaths.songImagesDir
                                    }
                                    .disabled(songImagesDir == DefaultPaths.songImagesDir)
                                }
                                Text("Default: \(DefaultPaths.songImagesDir)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    TextField("Images Cache", text: $imagesCacheDir, prompt: Text(DefaultPaths.imagesCacheDir))
                                        .textFieldStyle(.roundedBorder)
                                    Button("Browse...") {
                                        selectFolder { url in
                                            imagesCacheDir = url.path
                                        }
                                    }
                                    Button("Reset") {
                                        imagesCacheDir = DefaultPaths.imagesCacheDir
                                    }
                                    .disabled(imagesCacheDir == DefaultPaths.imagesCacheDir)
                                }
                                Text("Default: \(DefaultPaths.imagesCacheDir)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }

                    GroupBox("AI / Tachikoma") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField("Config JSON File", text: $tachikomaConfigPath, prompt: Text("Choose tachikoma.json"))
                                    .textFieldStyle(.roundedBorder)
                                Button("Browse...") {
                                    selectFile { url in
                                        tachikomaConfigPath = url.path
                                    }
                                }
                                Button("Clear") {
                                    tachikomaConfigPath = ""
                                }
                                .disabled(tachikomaConfigPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            Text("Required: choose a committed Tachikoma JSON config file")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }
                    
                    GroupBox("Cache Directories") {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    TextField("Lyrics Cache", text: $lyricsCacheDir, prompt: Text(DefaultPaths.lyricsCacheDir))
                                        .textFieldStyle(.roundedBorder)
                                    Button("Browse...") {
                                        selectFolder { url in
                                            lyricsCacheDir = url.path
                                        }
                                    }
                                    Button("Reset") {
                                        lyricsCacheDir = DefaultPaths.lyricsCacheDir
                                    }
                                    .disabled(lyricsCacheDir == DefaultPaths.lyricsCacheDir)
                                }
                                Text("Default: \(DefaultPaths.lyricsCacheDir)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    TextField("Pipeline Cache", text: $pipelineCacheDir, prompt: Text(DefaultPaths.pipelineCacheDir))
                                        .textFieldStyle(.roundedBorder)
                                    Button("Browse...") {
                                        selectFolder { url in
                                            pipelineCacheDir = url.path
                                        }
                                    }
                                    Button("Reset") {
                                        pipelineCacheDir = DefaultPaths.pipelineCacheDir
                                    }
                                    .disabled(pipelineCacheDir == DefaultPaths.pipelineCacheDir)
                                }
                                Text("Default: \(DefaultPaths.pipelineCacheDir)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Button("Clear All Caches") {
                                clearAllCaches()
                            }
                            .foregroundColor(.red)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }
                    
                    GroupBox("OSC Ports") {
                        VStack(alignment: .leading, spacing: 8) {
                            portField(label: "VirtualDJ", value: $oscVDJPort, defaultValue: "\(Config.oscVDJPort)")
                            portField(label: "Synesthesia", value: $oscSynesthesiaPort, defaultValue: "\(Config.oscSynesthesiaPort)")
                            portField(label: "Magic", value: $oscMagicPort, defaultValue: "\(Config.oscMagicPort)")
                            portField(label: "VDJ Receive", value: $oscVDJReceivePort, defaultValue: "\(OSCHub.defaultVdjReceivePort)")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }

                    GroupBox("OSC Forward Targets") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Forward to Magic", isOn: .constant(true))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }
                }
                
                GroupBox("About") {
                    HStack(alignment: .top, spacing: 24) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 48))
                            .foregroundColor(.blue)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("SwiftVJ")
                                .font(.title2)
                                .fontWeight(.semibold)
                            Text("Version 1.0.0")
                                .foregroundColor(.secondary)
                            Text("A VJ control application for macOS")
                                .foregroundColor(.secondary)
                            Divider()
                                .padding(.vertical, 4)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Built with SwiftUI")
                                Text("OSC via OSCKit")
                                Text("LLM via Tachikoma")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }

                Button(action: saveSettings) {
                    Text("Save Settings")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 8)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: loadSettings)
        .alert("Restart Required", isPresented: $showRestartNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Settings have been saved. Restart the app to apply port changes.")
        }
        .alert("Save Failed", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage)
        }
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 320), spacing: 24),
            GridItem(.flexible(minimum: 320), spacing: 24)
        ]
    }
    
    private func clearAllCaches() {
        let fm = FileManager.default
        let paths = [lyricsCacheDir, pipelineCacheDir, imagesCacheDir].compactMap { path -> URL? in
            path.isEmpty ? nil : URL(fileURLWithPath: path)
        }
        
        var errors: [String] = []
        for path in paths {
            do {
                if fm.fileExists(atPath: path.path) {
                    try fm.removeItem(at: path)
                }
                try fm.createDirectory(at: path, withIntermediateDirectories: true)
            } catch {
                errors.append("\(path.lastPathComponent): \(error.localizedDescription)")
            }
        }
        
        if !errors.isEmpty {
            print("Cache clearing errors: \(errors.joined(separator: ", "))")
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

    private func selectFile(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]

        if panel.runModal() == .OK, let url = panel.url {
            completion(url)
        }
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard

        playbackSource = defaults.string(forKey: "playbackSource") ?? "vdj"
        startSynesthesia = defaults.bool(forKey: "startSynesthesia")
        let pollInterval = defaults.double(forKey: "playbackPollInterval")
        playbackPollInterval = pollInterval > 0 ? pollInterval : 1.0

        let storedShaderDir = defaults.string(forKey: "shaderDirectory") ?? ""
        if let resolved = ShaderDirectoryLocator.resolve(customPath: storedShaderDir) {
            shaderDirectory = resolved.path
        } else {
            shaderDirectory = storedShaderDir.isEmpty ? DefaultPaths.shaderDirectory : storedShaderDir
        }

        imagesCacheDir = defaults.string(forKey: "imagesCacheDir") ?? DefaultPaths.imagesCacheDir
        lyricsCacheDir = defaults.string(forKey: "lyricsCacheDir") ?? DefaultPaths.lyricsCacheDir
        pipelineCacheDir = defaults.string(forKey: "pipelineCacheDir") ?? DefaultPaths.pipelineCacheDir
        songImagesDir = defaults.string(forKey: "songImagesDir") ?? DefaultPaths.songImagesDir
        tachikomaConfigPath = defaults.string(forKey: LLMClient.configPathDefaultsKey) ?? ""
        ledfxBaseURL = defaults.string(forKey: "ledfx_baseURL") ?? "http://127.0.0.1:8888"

        let flags = FeatureFlags.load(from: defaults)
        renderingEnabled = flags.renderingEnabled
        performanceEnabled = flags.performanceEnabled
        shadersEnabled = flags.shadersEnabled
        launchpadEnabled = flags.launchpadEnabled
        songsEnabled = flags.songsEnabled

        oscVDJPort = loadPortString(
            defaults,
            key: OSCHub.PortKeys.vdjPort,
            fallback: Config.oscVDJPort
        )
        oscSynesthesiaPort = loadPortString(
            defaults,
            key: OSCHub.PortKeys.synesthesiaPort,
            fallback: Config.oscSynesthesiaPort
        )
        oscMagicPort = loadPortString(
            defaults,
            key: OSCHub.PortKeys.magicPort,
            fallback: Config.oscMagicPort
        )
        oscVDJReceivePort = loadPortString(
            defaults,
            key: OSCHub.PortKeys.vdjReceivePort,
            fallback: OSCHub.defaultVdjReceivePort
        )
    }

    private func saveSettings() {
        guard let vdjPortValue = parsePort(oscVDJPort),
              let synesthesiaPortValue = parsePort(oscSynesthesiaPort),
              let magicPortValue = parsePort(oscMagicPort),
              let vdjReceiveValue = parsePort(oscVDJReceivePort) else {
            saveErrorMessage = "One or more ports are invalid. Use values between 1 and 65535."
            showSaveError = true
            return
        }

        let defaults = UserDefaults.standard
        defaults.set(playbackSource, forKey: "playbackSource")
        defaults.set(startSynesthesia, forKey: "startSynesthesia")
        defaults.set(playbackPollInterval, forKey: "playbackPollInterval")
        defaults.set(shaderDirectory, forKey: "shaderDirectory")
        defaults.set(imagesCacheDir, forKey: "imagesCacheDir")
        defaults.set(lyricsCacheDir, forKey: "lyricsCacheDir")
        defaults.set(pipelineCacheDir, forKey: "pipelineCacheDir")
        defaults.set(songImagesDir, forKey: "songImagesDir")
        let trimmedTachikomaPath = tachikomaConfigPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTachikomaPath.isEmpty else {
            saveErrorMessage = "Tachikoma config file is required."
            showSaveError = true
            return
        }
        guard FileManager.default.fileExists(atPath: trimmedTachikomaPath) else {
            saveErrorMessage = "Tachikoma config file not found: \(trimmedTachikomaPath)"
            showSaveError = true
            return
        }
        defaults.set(trimmedTachikomaPath, forKey: LLMClient.configPathDefaultsKey)
        tachikomaConfigPath = trimmedTachikomaPath
        defaults.set(ledfxBaseURL, forKey: "ledfx_baseURL")

        defaults.set(Int(vdjPortValue), forKey: OSCHub.PortKeys.vdjPort)
        defaults.set(Int(synesthesiaPortValue), forKey: OSCHub.PortKeys.synesthesiaPort)
        defaults.set(Int(magicPortValue), forKey: OSCHub.PortKeys.magicPort)
        defaults.set(Int(vdjReceiveValue), forKey: OSCHub.PortKeys.vdjReceivePort)

        appState.send(.ui(.reloadTachikomaConfig))
        appState.send(.ledfx(.setBaseURL(ledfxBaseURL)))

        let flags = FeatureFlags(
            renderingEnabled: renderingEnabled,
            performanceEnabled: performanceEnabled,
            shadersEnabled: shadersEnabled,
            launchpadEnabled: launchpadEnabled,
            songsEnabled: songsEnabled
        )
        appState.updateFeatureFlags(flags)

        showRestartNotice = true
    }

    private func loadPortString(_ defaults: UserDefaults, key: String, fallback: UInt16) -> String {
        let value = defaults.integer(forKey: key)
        if value > 0 && value <= UInt16.max {
            return String(value)
        }
        return String(fallback)
    }

    private func parsePort(_ value: String) -> UInt16? {
        guard let parsed = UInt16(value.trimmingCharacters(in: .whitespaces)),
              parsed > 0 else {
            return nil
        }
        return parsed
    }

    private func portField(label: String, value: Binding<String>, defaultValue: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(label, text: value)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 180)
            Text("Default: \(defaultValue)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

}

private func canBindUDP(port: UInt16) -> Bool {
    let fd = socket(AF_INET, SOCK_DGRAM, 0)
    guard fd >= 0 else { return false }

    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    addr.sin_addr = in_addr(s_addr: INADDR_ANY)

    let result = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }

    close(fd)
    return result == 0
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
