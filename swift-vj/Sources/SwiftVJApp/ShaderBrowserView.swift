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
    @State private var selectedQuality: String = "ALL"
    @State private var shaders: [CoreShaderInfo] = []
    @State private var selectedShaders: Set<String> = []
    @State private var enabledShaders: Set<String> = []
    @State private var showMasks: Bool = false
    @State private var isCapturingScreenshots: Bool = false
    @State private var screenshotProgress: Double = 0
    @State private var currentScreenshotShader: String = ""
    @State private var isAnalyzing: Bool = false
    @State private var analysisProgress: Double = 0
    @State private var currentAnalysisShader: String = ""
    @State private var showingAnalysisModal: Bool = false
    @State private var selectedAnalysis: ShaderAnalysis? = nil
    
    let qualities = ["ALL", "BEST", "GOOD", "OK", "MASK", "SKIP"]
    
    var filteredShaders: [CoreShaderInfo] {
        shaders.filter { shader in
            let matchesSearch = searchText.isEmpty || 
                shader.name.localizedCaseInsensitiveContains(searchText) ||
                shader.mood.localizedCaseInsensitiveContains(searchText)
            let matchesQuality = selectedQuality == "ALL" || ratingName(shader.rating) == selectedQuality
            let matchesType = showMasks ? (shader.rating == .mask) : (shader.rating != .mask)
            return matchesSearch && matchesQuality && matchesType
        }
    }
    
    func ratingName(_ rating: SwiftVJCore.ShaderRating) -> String {
        switch rating {
        case .best: return "BEST"
        case .good: return "GOOD"
        case .normal: return "OK"
        case .mask: return "MASK"
        case .skip: return "SKIP"
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Action buttons bar
            HStack(spacing: 12) {
                Button(action: { Task { await loadShaders() } }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                
                Divider()
                    .frame(height: 20)
                
                Button(action: { toggleShowMasks() }) {
                    Label(showMasks ? "Show Shaders" : "Show Masks", systemImage: showMasks ? "sparkles" : "square.on.circle")
                }
                
                Spacer()
                
                Button(action: { startScreenshotCapture() }) {
                    Label("Make Screenshots", systemImage: "camera")
                }
                .disabled(selectedShaders.isEmpty || isCapturingScreenshots)
                
                Button(action: { startAIAnalysis() }) {
                    Label("AI Analyze", systemImage: "brain.head.profile")
                }
                .disabled(selectedShaders.isEmpty || isAnalyzing)
                
                Divider()
                    .frame(height: 20)
                
                Button(action: { moveToMasks() }) {
                    Label("Move to Masks", systemImage: "arrow.right")
                }
                .disabled(showMasks || selectedShaders.isEmpty)
                
                Button(action: { moveToShaders() }) {
                    Label("Move to Shaders", systemImage: "arrow.left")
                }
                .disabled(!showMasks || selectedShaders.isEmpty)
            }
            .padding()
            .background(.bar)
            
            Divider()
            
            // Progress indicators
            if isCapturingScreenshots {
                VStack(spacing: 4) {
                    HStack {
                        Text("Capturing Screenshots...")
                        Spacer()
                        Text(currentScreenshotShader)
                            .foregroundColor(.secondary)
                    }
                    ProgressView(value: screenshotProgress)
                }
                .padding()
                .background(.quaternary)
            }
            
            if isAnalyzing {
                VStack(spacing: 4) {
                    HStack {
                        Text("Analyzing with AI...")
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
                
                Picker("Quality", selection: $selectedQuality) {
                    ForEach(qualities, id: \.self) { quality in
                        Text(quality).tag(quality)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 380)
                
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
            // First check if shaders are already loaded
            var loadedShaders = await module.allShaders
            
            // If no shaders loaded, load from Shaders directory
            if loadedShaders.isEmpty {
                let shadersDir = findShadersDirectory()
                if let dir = shadersDir {
                    appState.log("Loading shaders from: \(dir.path)", level: .debug)
                    let count = await module.loadAllShaderFiles(from: dir)
                    appState.log("Found \(count) shaders with analysis.json", level: .info)
                    loadedShaders = await module.allShaders
                } else {
                    appState.log("Could not find Shaders directory", level: .warning)
                }
            }
            
            shaders = loadedShaders
            let maskCount = shaders.filter { $0.rating == .mask }.count
            let regularCount = shaders.count - maskCount
            appState.log("Loaded \(shaders.count) shader(s): \(regularCount) regular, \(maskCount) masks", level: .info)
        }
        
        // If still empty, show message
        if shaders.isEmpty {
            appState.log("No shaders with analysis.json found. Run AI analysis first.", level: .warning)
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
    
    private func toggleShowMasks() {
        showMasks.toggle()
        selectedShaders.removeAll()
        appState.log("Switched to \(showMasks ? "masks" : "shaders") view", level: .debug)
    }
    
    private func startScreenshotCapture() {
        Task {
            isCapturingScreenshots = true
            screenshotProgress = 0
            
            let shadersToCapture = Array(selectedShaders)
            let total = shadersToCapture.count
            
            appState.log("🎬 Starting screenshot capture for \(total) shader(s)", level: .info)
            
            var successCount = 0
            var blackScreenshotCount = 0
            var failCount = 0
            
            // Create screenshot capture utility
            let screenshotCapture = await ShaderScreenshotCapture(logger: { message, level in
                Task { @MainActor in
                    self.appState.log(message, level: level)
                }
            })
            
            for (index, shaderName) in shadersToCapture.enumerated() {
                currentScreenshotShader = shaderName
                appState.log("📸 [\(index+1)/\(total)] Capturing \(shaderName)...", level: .info)
                
                // Find shader info
                guard let shader = shaders.first(where: { $0.name == shaderName }) else {
                    appState.log("  ✗ Shader not found in list: \(shaderName)", level: .error)
                    failCount += 1
                    screenshotProgress = Double(index + 1) / Double(total)
                    continue
                }
                
                // Load shader in renderer
                await appState.selectShader(shaderName)
                appState.log("  ⏳ Loaded shader, stabilizing for 5 seconds...", level: .info)
                
                // Wait 5 seconds for shader to stabilize
                try? await Task.sleep(for: .seconds(5))
                
                // Capture screenshot from render engine
                let captureResult = await captureShaderScreenshot(shader, using: screenshotCapture)
                
                switch captureResult {
                case .success(let isBlack):
                    if isBlack {
                        blackScreenshotCount += 1
                    } else {
                        successCount += 1
                    }
                case .failure:
                    failCount += 1
                }
                
                screenshotProgress = Double(index + 1) / Double(total)
            }
            
            isCapturingScreenshots = false
            currentScreenshotShader = ""
            
            appState.log("✅ Screenshot capture complete: \(successCount) successful, \(blackScreenshotCount) black, \(failCount) failed", level: .info)
            
            await loadShaders()
        }
    }
    
    /// Capture screenshot result
    private enum CaptureResult {
        case success(isBlack: Bool)
        case failure
    }
    
    /// Capture screenshot for a shader using the render engine
    /// 
    /// - Parameters:
    ///   - shader: The shader to capture
    ///   - screenshotCapture: The screenshot capture utility
    /// - Returns: Capture result indicating success/failure and if black
    private func captureShaderScreenshot(_ shader: CoreShaderInfo, using screenshotCapture: ShaderScreenshotCapture) async -> CaptureResult {
        // Access render engine's shader renderer texture
        guard let renderEngine = appState.renderEngine else {
            appState.log("  ✗ Render engine not available", level: .error)
            return .failure
        }
        
        guard let headlessRenderer = renderEngine.headlessRenderer else {
            appState.log("  ✗ Headless renderer not available", level: .error)
            return .failure
        }
        
        guard let shaderTexture = headlessRenderer.shaderRenderer.texture else {
            appState.log("  ✗ Shader renderer texture not available", level: .error)
            return .failure
        }
        
        // Determine output path
        let shaderPath = URL(fileURLWithPath: shader.path)
        let shaderDir = shaderPath.deletingLastPathComponent()
        let outputPath = shaderDir.appendingPathComponent("\(shader.name).png")
        
        appState.log("  💾 Saving to: \(outputPath.path)", level: .debug)
        
        // Capture texture to PNG
        let success = await screenshotCapture.captureTexture(shaderTexture, outputPath: outputPath, shaderName: shader.name)
        
        if success {
            // Check if file exists and determine if it's black
            if FileManager.default.fileExists(atPath: outputPath.path) {
                // The screenshotCapture utility already logs black detection
                // We just need to determine the result
                return .success(isBlack: false) // Detailed check done in utility
            } else {
                appState.log("  ⚠️ Screenshot file not found after capture", level: .warning)
                return .failure
            }
        } else {
            return .failure
        }
    }
    
    private func startAIAnalysis() {
        Task {
            isAnalyzing = true
            analysisProgress = 0
            
            let shadersToAnalyze = Array(selectedShaders)
            let total = shadersToAnalyze.count
            
            appState.log("🤖 Starting AI analysis for \(total) shader(s)", level: .info)
            
            var successCount = 0
            var errorCount = 0
            
            // Create LM Studio client
            let lmStudioClient = await LMStudioClient(logger: { message, level in
                Task { @MainActor in
                    self.appState.log(message, level: level)
                }
            })
            
            // Check if LM Studio is available
            let isAvailable = await lmStudioClient.isAvailable()
            if !isAvailable {
                appState.log("  ⚠️ LM Studio is not available. Please start LM Studio server.", level: .warning)
                appState.log("  ℹ️ Start with: lms server start --port 1234", level: .info)
                isAnalyzing = false
                return
            }
            
            for (index, shaderName) in shadersToAnalyze.enumerated() {
                currentAnalysisShader = shaderName
                appState.log("🔍 [\(index+1)/\(total)] Analyzing \(shaderName)...", level: .info)
                
                guard let shader = shaders.first(where: { $0.name == shaderName }) else {
                    appState.log("  ✗ Shader not found in list: \(shaderName)", level: .error)
                    errorCount += 1
                    analysisProgress = Double(index + 1) / Double(total)
                    continue
                }
                
                // Load shader source code
                let shaderPath = URL(fileURLWithPath: shader.path)
                let shaderDir = shaderPath.deletingLastPathComponent()
                
                appState.log("  📂 Loading shader source: \(shaderDir.lastPathComponent)", level: .debug)
                
                // Find GLSL source file
                let sourceFile = findShaderSourceFile(in: shaderDir, shaderName: shaderName)
                guard let source = loadShaderSource(from: sourceFile) else {
                    appState.log("  ⚠️ No shader source file found", level: .warning)
                    errorCount += 1
                    analysisProgress = Double(index + 1) / Double(total)
                    continue
                }
                
                // Find screenshot if available
                let screenshotPath = findScreenshot(for: shader)
                if let screenshot = screenshotPath {
                    appState.log("  📷 Found screenshot: \(screenshot.lastPathComponent)", level: .debug)
                } else {
                    appState.log("  ℹ️ No screenshot available (code-only analysis)", level: .debug)
                }
                
                // Analyze with LM Studio
                appState.log("  ⏳ Sending to LM Studio for analysis...", level: .info)
                
                guard let analysis = await lmStudioClient.analyzeShader(
                    shaderName: shaderName,
                    shaderSource: source,
                    screenshotPath: screenshotPath
                ) else {
                    appState.log("  ✗ AI analysis failed", level: .error)
                    errorCount += 1
                    analysisProgress = Double(index + 1) / Double(total)
                    continue
                }
                
                // Save analysis to JSON
                let analysisPath = shaderDir.appendingPathComponent("\(shaderName).analysis.json")
                if await saveAnalysisJSON(analysis, to: analysisPath, shaderName: shaderName) {
                    appState.log("  ✓ Analysis saved: \(analysisPath.lastPathComponent)", level: .info)
                    successCount += 1
                } else {
                    appState.log("  ✗ Failed to save analysis JSON", level: .error)
                    errorCount += 1
                }
                
                analysisProgress = Double(index + 1) / Double(total)
            }
            
            isAnalyzing = false
            currentAnalysisShader = ""
            
            appState.log("✅ AI analysis complete: \(successCount) successful, \(errorCount) failed", level: .info)
            
            await loadShaders()
        }
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
    
    private func moveToMasks() {
        Task {
            let count = selectedShaders.count
            appState.log("🔀 Moving \(count) shader(s) to masks folder", level: .info)
            
            var successCount = 0
            var errorCount = 0
            
            // Determine masks directory
            guard let shadersDir = getShadersDirectory() else {
                appState.log("  ✗ Could not determine shaders directory", level: .error)
                return
            }
            
            let masksDir = shadersDir.deletingLastPathComponent().appendingPathComponent("masks")
            
            // Create masks directory if it doesn't exist
            do {
                if !FileManager.default.fileExists(atPath: masksDir.path) {
                    try FileManager.default.createDirectory(at: masksDir, withIntermediateDirectories: true)
                    appState.log("  📁 Created masks directory: \(masksDir.path)", level: .info)
                }
            } catch {
                appState.log("  ✗ Failed to create masks directory: \(error.localizedDescription)", level: .error)
                return
            }
            
            for shaderName in selectedShaders {
                guard let shader = shaders.first(where: { $0.name == shaderName }) else {
                    appState.log("  ✗ Shader not found: \(shaderName)", level: .error)
                    errorCount += 1
                    continue
                }
                
                let sourceDir = URL(fileURLWithPath: shader.path).deletingLastPathComponent()
                let destDir = masksDir.appendingPathComponent(sourceDir.lastPathComponent)
                
                appState.log("  📦 Copying \(sourceDir.lastPathComponent) to masks/", level: .info)
                
                // Copy shader directory
                do {
                    // Remove destination if it exists
                    if FileManager.default.fileExists(atPath: destDir.path) {
                        try FileManager.default.removeItem(at: destDir)
                        appState.log("    🗑️ Removed existing: \(destDir.lastPathComponent)", level: .debug)
                    }
                    
                    try FileManager.default.copyItem(at: sourceDir, to: destDir)
                    appState.log("    ✓ Copied to: \(destDir.path)", level: .info)
                    
                    // Update rating in analysis.json to "mask"
                    let analysisPath = destDir.appendingPathComponent("\(shaderName).analysis.json")
                    updateAnalysisRating(at: analysisPath, toMask: true)
                    
                    successCount += 1
                } catch {
                    appState.log("    ✗ Copy failed: \(error.localizedDescription)", level: .error)
                    errorCount += 1
                }
            }
            
            appState.log("✅ Move to masks complete: \(successCount) successful, \(errorCount) failed", level: .info)
            selectedShaders.removeAll()
            await loadShaders()
        }
    }
    
    private func moveToShaders() {
        Task {
            let count = selectedShaders.count
            appState.log("🔀 Moving \(count) mask(s) to shaders folder", level: .info)
            
            var successCount = 0
            var errorCount = 0
            
            // Determine directories
            guard let masksDir = getMasksDirectory() else {
                appState.log("  ✗ Could not determine masks directory", level: .error)
                return
            }
            
            let shadersDir = masksDir.deletingLastPathComponent().appendingPathComponent("shaders")
            
            // Create shaders directory if it doesn't exist
            do {
                if !FileManager.default.fileExists(atPath: shadersDir.path) {
                    try FileManager.default.createDirectory(at: shadersDir, withIntermediateDirectories: true)
                    appState.log("  📁 Created shaders directory: \(shadersDir.path)", level: .info)
                }
            } catch {
                appState.log("  ✗ Failed to create shaders directory: \(error.localizedDescription)", level: .error)
                return
            }
            
            for maskName in selectedShaders {
                guard let mask = shaders.first(where: { $0.name == maskName }) else {
                    appState.log("  ✗ Mask not found: \(maskName)", level: .error)
                    errorCount += 1
                    continue
                }
                
                let sourceDir = URL(fileURLWithPath: mask.path).deletingLastPathComponent()
                let destDir = shadersDir.appendingPathComponent(sourceDir.lastPathComponent)
                
                appState.log("  📦 Copying \(sourceDir.lastPathComponent) to shaders/", level: .info)
                
                // Copy mask directory
                do {
                    // Remove destination if it exists
                    if FileManager.default.fileExists(atPath: destDir.path) {
                        try FileManager.default.removeItem(at: destDir)
                        appState.log("    🗑️ Removed existing: \(destDir.lastPathComponent)", level: .debug)
                    }
                    
                    try FileManager.default.copyItem(at: sourceDir, to: destDir)
                    appState.log("    ✓ Copied to: \(destDir.path)", level: .info)
                    
                    // Update rating in analysis.json to remove mask designation
                    let analysisPath = destDir.appendingPathComponent("\(maskName).analysis.json")
                    updateAnalysisRating(at: analysisPath, toMask: false)
                    
                    successCount += 1
                } catch {
                    appState.log("    ✗ Copy failed: \(error.localizedDescription)", level: .error)
                    errorCount += 1
                }
            }
            
            appState.log("✅ Move to shaders complete: \(successCount) successful, \(errorCount) failed", level: .info)
            selectedShaders.removeAll()
            await loadShaders()
        }
    }
    
    /// Get shaders directory from first shader's path
    private func getShadersDirectory() -> URL? {
        guard let firstShader = shaders.first else { return nil }
        let path = URL(fileURLWithPath: firstShader.path).deletingLastPathComponent().deletingLastPathComponent()
        return path
    }
    
    /// Get masks directory
    private func getMasksDirectory() -> URL? {
        guard let firstShader = shaders.first else { return nil }
        let path = URL(fileURLWithPath: firstShader.path).deletingLastPathComponent().deletingLastPathComponent()
        return path
    }
    
    /// Update rating in analysis JSON file
    private func updateAnalysisRating(at path: URL, toMask: Bool) {
        guard FileManager.default.fileExists(atPath: path.path) else {
            appState.log("    ℹ️ No analysis.json found to update", level: .debug)
            return
        }
        
        do {
            let data = try Data(contentsOf: path)
            var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            
            // Update rating field
            if toMask {
                json["rating"] = "mask"
            } else {
                // Restore to a default rating if coming from mask
                json["rating"] = "normal"
            }
            
            let updatedData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try updatedData.write(to: path)
            
            appState.log("    🏷️ Updated rating: \(toMask ? "mask" : "normal")", level: .debug)
        } catch {
            appState.log("    ⚠️ Could not update analysis rating: \(error.localizedDescription)", level: .warning)
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
    let onTap: () -> Void
    let onCheck: () -> Void
    let onEnable: () -> Void
    let onShowAnalysis: () -> Void
    
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
            
            // Preview placeholder / screenshot
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
                        
                        // Screenshot indicator
                        Image(systemName: "camera.fill")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.3))
                            .padding(4)
                            .background(.black.opacity(0.3))
                            .cornerRadius(4)
                    }
                }
                .onTapGesture(perform: onTap)
            
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
                Text(shader.rating.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(shader.rating.qualityColor)
                    .foregroundColor(.white)
                    .cornerRadius(4)
                
                Spacer()
                
                // Tags
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
        .opacity(isEnabled ? 1.0 : 0.5)
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
