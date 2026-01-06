// ShaderBrowserView - Browse and select shaders with management features
// Phase 4: SwiftUI Shell

import SwiftUI
import SwiftVJCore
import Metal

// Use SwiftVJCore.ShaderInfo to avoid conflict with Rendering/RenderingTypes.swift
typealias CoreShaderInfo = SwiftVJCore.ShaderInfo

struct ShaderBrowserView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var selectedFolder: String = "ALL"
    @State private var shaders: [CoreShaderInfo] = []
    @State private var availableFolders: [String] = []
    @State private var selectedShaders: Set<String> = []
    @State private var enabledShaders: Set<String> = []
    @State private var isAnalyzing: Bool = false
    @State private var analysisProgress: Double = 0
    @State private var currentAnalysisShader: String = ""
    @State private var showingAnalysisModal: Bool = false
    @State private var selectedAnalysis: ShaderAnalysis? = nil
    @State private var refreshId = UUID() // Forces grid refresh after analysis
    
    var filteredShaders: [CoreShaderInfo] {
        shaders.filter { shader in
            let matchesSearch = searchText.isEmpty || 
                shader.name.localizedCaseInsensitiveContains(searchText) ||
                shader.mood.localizedCaseInsensitiveContains(searchText)
            let matchesFolder = selectedFolder == "ALL" || shader.folder == selectedFolder
            return matchesSearch && matchesFolder
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Action buttons bar
            HStack(spacing: 12) {
                Button(action: { Task { await loadShaders() } }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                
                Spacer()
                
                Button(action: { startAnalyze() }) {
                    Label("Analyze", systemImage: "sparkle.magnifyingglass")
                }
                .disabled(selectedShaders.isEmpty || isAnalyzing)
            }
            .padding()
            .background(.bar)
            
            Divider()
            
            // Progress indicator
            if isAnalyzing {
                VStack(spacing: 4) {
                    HStack {
                        Text("Analyzing...")
                        Spacer()
                        Text(currentAnalysisShader)
                            .foregroundColor(.secondary)
                    }
                    ProgressView(value: analysisProgress)
                }
                .padding()
                .background(.quaternary)
            }
            
            // Search and filter bar
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search shaders...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(.quaternary)
                .cornerRadius(8)
                
                // Folder filter (dynamically populated from available folders)
                Picker("Folder", selection: $selectedFolder) {
                    Text("ALL").tag("ALL")
                    ForEach(availableFolders, id: \.self) { folder in
                        Text(folder).tag(folder)
                    }
                }
                .pickerStyle(.segmented)
                .frame(minWidth: 150)
                
                Spacer()
                
                Text("\(filteredShaders.count) shaders | \(selectedShaders.count) selected")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(.bar)
            
            Divider()
            
            // Shader grid
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 16)
                ], spacing: 16) {
                    ForEach(filteredShaders, id: \.name) { shader in
                        ShaderCardEnhanced(
                            shader: shader,
                            isSelected: appState.selectedShader == shader.name,
                            isChecked: selectedShaders.contains(shader.name),
                            isEnabled: enabledShaders.contains(shader.name),
                            refreshId: refreshId,
                            onTap: {
                                Task {
                                    await appState.selectShader(shader.name)
                                }
                            },
                            onCheck: {
                                toggleSelection(shader.name)
                            },
                            onEnable: {
                                toggleEnabled(shader.name)
                            },
                            onShowAnalysis: {
                                showAnalysis(for: shader.name)
                            }
                        )
                    }
                }
                .padding()
            }
        }
        .task {
            await loadShaders()
            loadEnabledStates()
        }
        .sheet(isPresented: $showingAnalysisModal) {
            if let analysis = selectedAnalysis {
                ShaderAnalysisModal(analysis: analysis)
            }
        }
    }
    
    private func loadShaders() async {
        appState.log("Loading shaders from swift-vj/Shaders...", level: .debug)
        
        // Get shaders from module
        if let module = appState.shadersModule {
            // Always reload from Shaders directory
            let shadersDir = findShadersDirectory()
            if let dir = shadersDir {
                appState.log("Loading shaders from: \(dir.path)", level: .debug)
                let count = await module.loadAllShaderFiles(from: dir)
                appState.log("Found \(count) shaders", level: .info)
            } else {
                appState.log("Could not find Shaders directory", level: .warning)
            }
            
            shaders = await module.allShaders
            availableFolders = await module.availableFolders
            
            // Log folder breakdown
            for folder in availableFolders {
                let folderCount = shaders.filter { $0.folder == folder }.count
                appState.log("  \(folder): \(folderCount) shaders", level: .info)
            }
        }
        
        // If still empty, show message
        if shaders.isEmpty {
            appState.log("No shaders found in Shaders directory.", level: .warning)
        }
    }
    
    /// Find the Shaders directory in known locations
    private func findShadersDirectory() -> URL? {
        let fileManager = FileManager.default
        
        // Check user-configured shaderDirectory from settings
        let configuredPath = UserDefaults.standard.string(forKey: "shaderDirectory") ?? ""
        if !configuredPath.isEmpty {
            let configuredURL = URL(fileURLWithPath: configuredPath)
            if fileManager.fileExists(atPath: configuredURL.path) {
                return configuredURL
            }
        }
        
        // Try relative to the executable (for development)
        let executableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        
        // Go up from executable to find swift-vj/Shaders
        var currentURL = executableURL.deletingLastPathComponent()
        for _ in 0..<10 {
            let shadersURL = currentURL.appendingPathComponent("Shaders")
            if fileManager.fileExists(atPath: shadersURL.appendingPathComponent("glsl").path) {
                return shadersURL
            }
            
            // Also check swift-vj/Shaders
            let swiftVJShaders = currentURL.appendingPathComponent("swift-vj/Shaders")
            if fileManager.fileExists(atPath: swiftVJShaders.appendingPathComponent("glsl").path) {
                return swiftVJShaders
            }
            
            currentURL = currentURL.deletingLastPathComponent()
        }
        
        // Fallback: hardcoded development path
        let devPaths = [
            URL(fileURLWithPath: "/Users/abossard/Desktop/projects/synesthesia-visuals/swift-vj/Shaders"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("swift-vj/Shaders"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Shaders")
        ]
        
        for devPath in devPaths {
            if fileManager.fileExists(atPath: devPath.appendingPathComponent("glsl").path) {
                return devPath
            }
        }
        
        return nil
    }
    
    private func loadEnabledStates() {
        // Load enabled states from UserDefaults
        if let saved = UserDefaults.standard.dictionary(forKey: "enabledShaders") as? [String: Bool] {
            enabledShaders = Set(saved.filter { $0.value }.map { $0.key })
        } else {
            // All enabled by default
            enabledShaders = Set(shaders.map { $0.name })
        }
    }
    
    private func saveEnabledStates() {
        let dict = Dictionary(uniqueKeysWithValues: shaders.map { ($0.name, enabledShaders.contains($0.name)) })
        UserDefaults.standard.set(dict, forKey: "enabledShaders")
    }
    
    private func toggleSelection(_ shaderName: String) {
        if selectedShaders.contains(shaderName) {
            selectedShaders.remove(shaderName)
        } else {
            selectedShaders.insert(shaderName)
        }
    }
    
    private func toggleEnabled(_ shaderName: String) {
        if enabledShaders.contains(shaderName) {
            enabledShaders.remove(shaderName)
        } else {
            enabledShaders.insert(shaderName)
        }
        saveEnabledStates()
    }
    
    // MARK: - Unified Analyze Function
    
    /// Start analysis: screenshot capture + AI analysis
    /// 1. Loads shader, waits 1s, captures screenshot
    /// 2. If black, waits 5s more and retries
    /// 3. If still black, marks as "black" status
    /// 4. If not black, runs AI analysis on source + screenshot
    private func startAnalyze() {
        Task {
            let startTime = Date()
            isAnalyzing = true
            analysisProgress = 0
            
            let shadersToAnalyze = Array(selectedShaders)
            let total = shadersToAnalyze.count
            
            appState.log("═══════════════════════════════════════════════════════════════", level: .info)
            appState.log("🔬 STARTING ANALYSIS for \(total) shader(s)", level: .info)
            appState.log("═══════════════════════════════════════════════════════════════", level: .info)
            
            // Verify render engine is available (auto-started on app launch)
            guard let renderEngine = appState.renderEngine, renderEngine.isRunning else {
                appState.log("✗ Render engine not running - please wait for initialization", level: .error)
                isAnalyzing = false
                return
            }
            
            // Create utilities
            let screenshotCapture = await ShaderScreenshotCapture(logger: { message, level in
                Task { @MainActor in
                    self.appState.log(message, level: level)
                }
            })
            
            let lmStudioClient = await LMStudioClient(logger: { message, level in
                Task { @MainActor in
                    self.appState.log(message, level: level)
                }
            })
            
            // Check if LM Studio is available (for AI analysis)
            let aiAvailable = await lmStudioClient.isAvailable()
            if !aiAvailable {
                appState.log("⚠️ LM Studio not available - will mark black shaders only", level: .warning)
                appState.log("ℹ️ Start LM Studio with: lms server start --port 1234", level: .info)
            }
            
            var successCount = 0
            var blackCount = 0
            var errorCount = 0
            
            for (index, shaderName) in shadersToAnalyze.enumerated() {
                let shaderStartTime = Date()
                currentAnalysisShader = shaderName
                
                appState.log("───────────────────────────────────────────────────────────────", level: .info)
                appState.log("📍 [\(index+1)/\(total)] \(shaderName)", level: .info)
                appState.log("───────────────────────────────────────────────────────────────", level: .info)
                
                guard let shader = shaders.first(where: { $0.name == shaderName }) else {
                    appState.log("  ✗ Shader not found in list", level: .error)
                    errorCount += 1
                    analysisProgress = Double(index + 1) / Double(total)
                    continue
                }
                
                // Get paths
                let shaderPath = URL(fileURLWithPath: shader.path)
                let shaderDir = shaderPath.deletingLastPathComponent()
                let baseName = shaderPath.deletingPathExtension().lastPathComponent
                let screenshotPath = shaderDir.appendingPathComponent("\(baseName).png")
                let analysisPath = shaderDir.appendingPathComponent("\(baseName).analysis.json")
                
                // STEP 1: Load shader
                appState.log("  ▶ Loading shader...", level: .info)
                await appState.selectShader(shaderName)
                
                // STEP 2: Wait 1 second, take screenshot
                appState.log("  ⏳ Waiting 1s for shader to initialize...", level: .info)
                try? await Task.sleep(for: .seconds(1))
                
                var isBlack = true
                var captureSuccess = false
                
                // First capture attempt
                appState.log("  📸 Capturing screenshot (attempt 1/2)...", level: .info)
                let firstCaptureResult = await captureAndCheckBlack(shader: shader, screenshotPath: screenshotPath, screenshotCapture: screenshotCapture)
                
                switch firstCaptureResult {
                case .success(let black):
                    captureSuccess = true
                    isBlack = black
                    if black {
                        appState.log("  ⚠️ Screenshot is BLACK - waiting 5s for retry...", level: .warning)
                        try? await Task.sleep(for: .seconds(5))
                        
                        // Second capture attempt
                        appState.log("  📸 Capturing screenshot (attempt 2/2)...", level: .info)
                        let secondCaptureResult = await captureAndCheckBlack(shader: shader, screenshotPath: screenshotPath, screenshotCapture: screenshotCapture)
                        
                        switch secondCaptureResult {
                        case .success(let stillBlack):
                            isBlack = stillBlack
                            if stillBlack {
                                appState.log("  ⚠️ Still BLACK after 6s total wait", level: .warning)
                            } else {
                                appState.log("  ✓ Screenshot now shows content", level: .info)
                            }
                        case .failure:
                            appState.log("  ✗ Second capture failed", level: .error)
                        }
                    } else {
                        appState.log("  ✓ Screenshot captured successfully", level: .info)
                    }
                case .failure:
                    captureSuccess = false
                    appState.log("  ✗ Screenshot capture failed", level: .error)
                }
                
                // STEP 3: Handle black screenshot
                if isBlack {
                    appState.log("  🏷️ Marking shader as BLACK", level: .warning)
                    await saveBlackAnalysis(to: analysisPath, shaderName: shaderName)
                    blackCount += 1
                    
                    let elapsed = Date().timeIntervalSince(shaderStartTime)
                    appState.log("  ⏱️ Completed in \(String(format: "%.1f", elapsed))s (marked as black)", level: .info)
                    analysisProgress = Double(index + 1) / Double(total)
                    continue
                }
                
                // STEP 4: Run AI analysis if available
                if aiAvailable && captureSuccess {
                    appState.log("  🤖 Running AI analysis on source + screenshot...", level: .info)
                    
                    // Load shader source
                    guard let sourceContent = loadShaderSource(from: shaderPath) else {
                        appState.log("  ⚠️ Could not load shader source, skipping AI analysis", level: .warning)
                        successCount += 1  // Screenshot was successful at least
                        
                        let elapsed = Date().timeIntervalSince(shaderStartTime)
                        appState.log("  ⏱️ Completed in \(String(format: "%.1f", elapsed))s (screenshot only)", level: .info)
                        analysisProgress = Double(index + 1) / Double(total)
                        continue
                    }
                    
                    appState.log("  📝 Source: \(sourceContent.count) chars", level: .debug)
                    appState.log("  🖼️ Screenshot: \(screenshotPath.lastPathComponent)", level: .debug)
                    
                    let aiStartTime = Date()
                    if let analysis = await lmStudioClient.analyzeShader(
                        shaderName: shaderName,
                        shaderSource: sourceContent,
                        screenshotPath: screenshotPath
                    ) {
                        let aiElapsed = Date().timeIntervalSince(aiStartTime)
                        appState.log("  ✓ AI analysis completed in \(String(format: "%.1f", aiElapsed))s", level: .info)
                        
                        // Save analysis
                        if await saveAnalysisJSON(analysis, to: analysisPath, shaderName: shaderName) {
                            appState.log("  💾 Saved: \(analysisPath.lastPathComponent)", level: .info)
                            successCount += 1
                        } else {
                            appState.log("  ✗ Failed to save analysis JSON", level: .error)
                            errorCount += 1
                        }
                    } else {
                        appState.log("  ✗ AI analysis failed", level: .error)
                        errorCount += 1
                    }
                } else if captureSuccess {
                    // No AI available but screenshot worked
                    appState.log("  ℹ️ Screenshot saved (no AI analysis)", level: .info)
                    successCount += 1
                }
                
                let elapsed = Date().timeIntervalSince(shaderStartTime)
                appState.log("  ⏱️ Completed in \(String(format: "%.1f", elapsed))s", level: .info)
                analysisProgress = Double(index + 1) / Double(total)
                
                // Refresh grid to show new screenshot
                refreshId = UUID()
            }
            
            let totalElapsed = Date().timeIntervalSince(startTime)
            
            isAnalyzing = false
            currentAnalysisShader = ""
            
            // Final refresh to ensure all screenshots are shown
            refreshId = UUID()
            
            appState.log("═══════════════════════════════════════════════════════════════", level: .info)
            appState.log("✅ ANALYSIS COMPLETE", level: .info)
            appState.log("   Success: \(successCount)", level: .info)
            appState.log("   Black:   \(blackCount)", level: .info)
            appState.log("   Errors:  \(errorCount)", level: .info)
            appState.log("   Total time: \(String(format: "%.1f", totalElapsed))s", level: .info)
            appState.log("═══════════════════════════════════════════════════════════════", level: .info)
            
            await loadShaders()
        }
    }
    
    /// Capture screenshot and check if it's black
    private func captureAndCheckBlack(
        shader: CoreShaderInfo,
        screenshotPath: URL,
        screenshotCapture: ShaderScreenshotCapture
    ) async -> CaptureResult {
        guard let renderEngine = appState.renderEngine else {
            appState.log("    ✗ Render engine not available", level: .error)
            return .failure
        }
        
        guard let headlessRenderer = renderEngine.headlessRenderer else {
            appState.log("    ✗ Headless renderer not available", level: .error)
            return .failure
        }
        
        guard let shaderTexture = headlessRenderer.shaderRenderer.texture else {
            appState.log("    ✗ Shader texture not available", level: .error)
            return .failure
        }
        
        // Capture texture and get black detection result
        let (success, isBlack) = await screenshotCapture.captureTextureWithBlackCheck(
            shaderTexture,
            outputPath: screenshotPath,
            shaderName: shader.name
        )
        
        if success {
            return .success(isBlack: isBlack)
        } else {
            return .failure
        }
    }
    
    /// Save analysis JSON marking shader as black
    private func saveBlackAnalysis(to path: URL, shaderName: String) async {
        let analysis = ShaderAnalysisResult(
            title: shaderName,
            description: "Shader renders black or empty output",
            mood: "black",
            energy: 0.0,
            colors: ["black"],
            effects: [],
            geometry: [],
            objects: [],
            complexity: "unknown",
            visualMetadata: ["status": "black", "reason": "Renders black after 6 second wait"]
        )
        
        _ = await saveAnalysisJSON(analysis, to: path, shaderName: shaderName)
    }
    
    /// Capture screenshot result
    private enum CaptureResult {
        case success(isBlack: Bool)
        case failure
    }
    
    /// Find shader source file in directory
    private func findShaderSourceFile(in directory: URL, shaderName: String) -> URL? {
        let possibleFiles = [
            directory.appendingPathComponent("main.glsl"),
            directory.appendingPathComponent("\(shaderName).glsl"),
            directory.appendingPathComponent("fragment.glsl"),
            directory.appendingPathComponent("renderpasses/main.glsl")
        ]
        
        for file in possibleFiles {
            if FileManager.default.fileExists(atPath: file.path) {
                return file
            }
        }
        
        return nil
    }
    
    /// Find screenshot file for a shader
    private func findScreenshot(for shader: CoreShaderInfo) -> URL? {
        let shaderPath = URL(fileURLWithPath: shader.path)
        let shaderDir = shaderPath.deletingLastPathComponent()
        let shaderName = shaderPath.deletingPathExtension().lastPathComponent
        
        // Check for existing screenshot
        let possibleFiles = [
            shaderDir.appendingPathComponent("\(shaderName).png"),
            shaderDir.appendingPathComponent("screenshot.png"),
            shaderDir.appendingPathComponent("preview.png")
        ]
        
        for file in possibleFiles {
            if FileManager.default.fileExists(atPath: file.path) {
                return file
            }
        }
        
        return nil
    }
    
    /// Load shader source code from file
    private func loadShaderSource(from url: URL?) -> String? {
        guard let url = url else { return nil }
        
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            appState.log("  ✗ Failed to load shader source: \(error.localizedDescription)", level: .error)
            return nil
        }
    }
    
    /// Save analysis result to JSON file
    private func saveAnalysisJSON(_ analysis: ShaderAnalysisResult, to url: URL, shaderName: String) async -> Bool {
        do {
            // Ensure parent directory exists
            let parentDir = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parentDir.path) {
                try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(analysis)
            
            try jsonData.write(to: url)
            
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            let fileSizeKB = Double(fileSize) / 1024.0
            
            appState.log("  💾 JSON saved: \(String(format: "%.1f", fileSizeKB)) KB", level: .debug)
            return true
        } catch {
            appState.log("  ✗ Failed to save analysis JSON: \(error.localizedDescription)", level: .error)
            return false
        }
    }
    
    private func showAnalysis(for shaderName: String) {
        // TODO: Load analysis from JSON file
        // For now, create demo analysis
        selectedAnalysis = ShaderAnalysis(
            shaderName: shaderName,
            title: shaderName.replacingOccurrences(of: "_", with: " ").capitalized,
            description: "A beautiful shader with dynamic effects and audio-reactive elements.",
            mood: "energetic",
            energy: 0.8,
            colors: ["neon", "cyan", "purple"],
            effects: ["geometric", "pulsating", "flow"],
            geometry: ["triangles", "pyramids"],
            objects: ["particles", "shapes"],
            complexity: "high",
            visualMetadata: [
                "contrast": "high",
                "saturation": "vibrant",
                "motion": "fast",
                "symmetry": "radial"
            ]
        )
        showingAnalysisModal = true
    }
}

// MARK: - Shared Extensions

extension SwiftVJCore.ShaderRating {
    var qualityColor: Color {
        switch self {
        case .best: return .green
        case .good: return .blue
        case .normal: return .orange
        case .mask: return .gray
        case .skip: return .red
        }
    }
    
    var displayName: String {
        switch self {
        case .best: return "BEST"
        case .good: return "GOOD"
        case .normal: return "OK"
        case .mask: return "MASK"
        case .skip: return "SKIP"
        }
    }
}

struct ShaderCardEnhanced: View {
    let shader: CoreShaderInfo
    let isSelected: Bool
    let isChecked: Bool
    let isEnabled: Bool
    let refreshId: UUID // Forces screenshot reload when changed
    let onTap: () -> Void
    let onCheck: () -> Void
    let onEnable: () -> Void
    let onShowAnalysis: () -> Void
    
    @State private var screenshotImage: NSImage?
    @State private var analysisData: ShaderAnalysisResult?
    @State private var hasAnalysis: Bool = false
    
    /// Find screenshot path for this shader
    private var screenshotPath: URL? {
        let shaderPath = URL(fileURLWithPath: shader.path)
        let shaderDir = shaderPath.deletingLastPathComponent()
        let shaderName = shaderPath.deletingPathExtension().lastPathComponent
        
        let possibleFiles = [
            shaderDir.appendingPathComponent("\(shaderName).png"),
            shaderDir.appendingPathComponent("screenshot.png"),
            shaderDir.appendingPathComponent("preview.png")
        ]
        
        return possibleFiles.first { FileManager.default.fileExists(atPath: $0.path) }
    }
    
    /// Find analysis.json path for this shader
    private var analysisPath: URL? {
        let shaderPath = URL(fileURLWithPath: shader.path)
        let shaderDir = shaderPath.deletingLastPathComponent()
        let shaderName = shaderPath.deletingPathExtension().lastPathComponent
        
        let path = shaderDir.appendingPathComponent("\(shaderName).analysis.json")
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row with checkbox and enable toggle
            HStack {
                Button(action: onCheck) {
                    Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                        .foregroundColor(isChecked ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { _ in onEnable() }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .scaleEffect(0.8)
            }
            
            // Preview screenshot or placeholder
            ZStack {
                if let image = screenshotImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 120)
                        .clipped()
                        .cornerRadius(8)
                } else {
                    // Placeholder when no screenshot
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [.purple.opacity(0.6), .blue.opacity(0.4), .cyan.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 120)
                        .overlay {
                            VStack {
                                Image(systemName: "sparkles")
                                    .font(.largeTitle)
                                    .foregroundColor(.white.opacity(0.5))
                                
                                Image(systemName: "camera.fill")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.3))
                                    .padding(4)
                                    .background(.black.opacity(0.3))
                                    .cornerRadius(4)
                            }
                        }
                }
            }
            .onTapGesture(perform: onTap)
            .onAppear { loadScreenshot(); loadAnalysis() }
            .onChange(of: refreshId) { _, _ in loadScreenshot(); loadAnalysis() }
            
            // Name and analysis button
            HStack {
                Text(shader.name.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                Button(action: onShowAnalysis) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            // Quality badge and tags
            HStack {
                // Analysis status badge
                if hasAnalysis {
                    Text("✓ Analyzed")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                } else {
                    Text("Not Analyzed")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.yellow)
                        .foregroundColor(.black)
                        .cornerRadius(4)
                }
                
                Spacer()
                
                // Tags from analysis or shader info
                let displayTags = analysisData?.colors.prefix(2) ?? shader.colors.prefix(2)
                ForEach(Array(displayTags), id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .cornerRadius(2)
                }
            }
        }
        .padding(12)
        .background(isSelected ? Color.blue.opacity(0.15) : Color(.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
        .opacity(isEnabled ? 1.0 : 0.5)
    }
    
    /// Load screenshot from disk
    private func loadScreenshot() {
        guard let path = screenshotPath else {
            screenshotImage = nil
            return
        }
        
        // Load image in background to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            if let image = NSImage(contentsOf: path) {
                DispatchQueue.main.async {
                    self.screenshotImage = image
                }
            }
        }
    }
    
    /// Load analysis JSON from disk
    private func loadAnalysis() {
        guard let path = analysisPath else {
            hasAnalysis = false
            analysisData = nil
            return
        }
        
        hasAnalysis = true
        
        // Load analysis in background
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try Data(contentsOf: path)
                let analysis = try JSONDecoder().decode(ShaderAnalysisResult.self, from: data)
                DispatchQueue.main.async {
                    self.analysisData = analysis
                }
            } catch {
                // File exists but couldn't parse - still mark as analyzed
                DispatchQueue.main.async {
                    self.analysisData = nil
                }
            }
        }
    }
}

struct ShaderAnalysis {
    let shaderName: String
    let title: String
    let description: String
    let mood: String
    let energy: Double
    let colors: [String]
    let effects: [String]
    let geometry: [String]
    let objects: [String]
    let complexity: String
    let visualMetadata: [String: String]
}

struct ShaderAnalysisModal: View {
    let analysis: ShaderAnalysis
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(analysis.title)
                        .font(.title)
                        .fontWeight(.bold)
                    Text(analysis.shaderName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(.bar)
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Description
                    GroupBox("Description") {
                        Text(analysis.description)
                            .padding()
                    }
                    
                    // Mood and Energy
                    HStack(spacing: 20) {
                        GroupBox("Mood") {
                            Text(analysis.mood.capitalized)
                                .font(.title2)
                                .foregroundColor(.blue)
                                .padding()
                        }
                        
                        GroupBox("Energy") {
                            HStack {
                                Text(String(format: "%.1f", analysis.energy))
                                    .font(.title2)
                                    .foregroundColor(.green)
                                ProgressView(value: analysis.energy)
                                    .frame(width: 100)
                            }
                            .padding()
                        }
                        
                        GroupBox("Complexity") {
                            Text(analysis.complexity.capitalized)
                                .font(.title2)
                                .foregroundColor(.orange)
                                .padding()
                        }
                    }
                    
                    // Visual Attributes
                    HStack(alignment: .top, spacing: 20) {
                        GroupBox("Colors") {
                            FlowLayout(spacing: 8) {
                                ForEach(analysis.colors, id: \.self) { color in
                                    Text(color)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(.blue.opacity(0.2))
                                        .cornerRadius(8)
                                }
                            }
                            .padding()
                        }
                        
                        GroupBox("Effects") {
                            FlowLayout(spacing: 8) {
                                ForEach(analysis.effects, id: \.self) { effect in
                                    Text(effect)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(.purple.opacity(0.2))
                                        .cornerRadius(8)
                                }
                            }
                            .padding()
                        }
                    }
                    
                    HStack(alignment: .top, spacing: 20) {
                        GroupBox("Geometry") {
                            FlowLayout(spacing: 8) {
                                ForEach(analysis.geometry, id: \.self) { geom in
                                    Text(geom)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(.green.opacity(0.2))
                                        .cornerRadius(8)
                                }
                            }
                            .padding()
                        }
                        
                        GroupBox("Objects") {
                            FlowLayout(spacing: 8) {
                                ForEach(analysis.objects, id: \.self) { obj in
                                    Text(obj)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(.orange.opacity(0.2))
                                        .cornerRadius(8)
                                }
                            }
                            .padding()
                        }
                    }
                    
                    // Visual Metadata
                    GroupBox("Visual Metadata") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(analysis.visualMetadata.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                                HStack {
                                    Text(key.capitalized + ":")
                                        .fontWeight(.medium)
                                    Text(value)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                            }
                        }
                        .padding()
                    }
                }
                .padding()
            }
        }
        .frame(width: 700, height: 600)
    }
}

// Simple flow layout for tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 10
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > width && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: width, height: y + lineHeight)
        }
    }
}

struct ShaderCard: View {
    let shader: CoreShaderInfo
    let isSelected: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Preview placeholder
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [.purple.opacity(0.6), .blue.opacity(0.4), .cyan.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 120)
                .overlay {
                    Image(systemName: "sparkles")
                        .font(.largeTitle)
                        .foregroundColor(.white.opacity(0.5))
                }
            
            // Name
            Text(shader.name.replacingOccurrences(of: "_", with: " ").capitalized)
                .font(.headline)
                .lineLimit(1)
            
            // Quality badge
            HStack {
                Text(shader.rating.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(shader.rating.qualityColor)
                    .foregroundColor(.white)
                    .cornerRadius(4)
                
                Spacer()
                
                // Tags - use colors array as tags
                ForEach(shader.colors.prefix(2), id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .cornerRadius(2)
                }
            }
        }
        .padding(12)
        .background(isSelected ? Color.blue.opacity(0.15) : Color(.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
    }
}

#Preview {
    ShaderBrowserView()
        .environmentObject(AppState())
        .frame(width: 800, height: 600)
}
