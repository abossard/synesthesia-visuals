// ShaderBrowserView - Browse and select shaders with management features
// Phase 4: SwiftUI Shell

import SwiftUI
import SwiftVJCore

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
        appState.log("Loading shaders...", level: .debug)
        
        // Get shaders from module
        if let module = appState.shadersModule {
            shaders = await module.allShaders
            let maskCount = shaders.filter { $0.rating == .mask }.count
            let regularCount = shaders.count - maskCount
            appState.log("Loaded \(shaders.count) shader(s): \(regularCount) regular, \(maskCount) masks", level: .info)
        } else {
            // Demo data
            shaders = [
                CoreShaderInfo(name: "neon_giza", path: "", energyScore: 0.8, moodValence: 0.5, mood: "energetic", colors: ["neon", "cyan"], effects: ["geometric", "pyramid"], rating: .best),
                CoreShaderInfo(name: "fluid_noise", path: "", energyScore: 0.5, moodValence: 0.3, mood: "organic", colors: ["blue", "purple"], effects: ["fluid", "flow"], rating: .good),
                CoreShaderInfo(name: "traced_tunnel", path: "", energyScore: 0.7, moodValence: -0.3, mood: "dark", colors: ["dark", "red"], effects: ["raymarching", "tunnel"], rating: .best),
                CoreShaderInfo(name: "vortex_flythrough", path: "", energyScore: 0.9, moodValence: 0.2, mood: "psychedelic", colors: ["rainbow"], effects: ["vortex"], rating: .good),
                CoreShaderInfo(name: "stained_glass", path: "", energyScore: 0.4, moodValence: 0.6, mood: "calm", colors: ["warm"], effects: ["glass", "colorful"], rating: .normal),
                CoreShaderInfo(name: "cosmic_web", path: "", energyScore: 0.6, moodValence: 0.1, mood: "ambient", colors: ["blue", "white"], effects: ["space", "network"], rating: .best),
            ]
            appState.log("Using demo data: \(shaders.count) shader(s)", level: .debug)
        }
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
            
            appState.log("Starting screenshot capture for \(total) shader(s)", level: .info)
            
            var successCount = 0
            var blackScreenshotCount = 0
            
            for (index, shaderName) in shadersToCapture.enumerated() {
                currentScreenshotShader = shaderName
                appState.log("Capturing shader [\(index+1)/\(total)]: \(shaderName)", level: .info)
                
                // Find shader info
                guard let shader = shaders.first(where: { $0.name == shaderName }) else {
                    appState.log("  ✗ Shader not found: \(shaderName)", level: .error)
                    screenshotProgress = Double(index + 1) / Double(total)
                    continue
                }
                
                // TODO: Implement actual screenshot capture
                // 1. Load shader in renderer
                await appState.selectShader(shaderName)
                appState.log("  Loaded shader, stabilizing for 5s...", level: .debug)
                
                // 2. Wait 5 seconds for shader to stabilize
                try? await Task.sleep(for: .seconds(5))
                
                // 3. Capture screenshot
                let screenshotPath = await captureShaderScreenshot(shader)
                
                // 4. Check if screenshot is black
                if let path = screenshotPath {
                    let isBlack = await isScreenshotBlack(path)
                    if isBlack {
                        appState.log("  ⚠️ BLACK SCREENSHOT detected: \(path.lastPathComponent)", level: .warning)
                        blackScreenshotCount += 1
                    } else {
                        appState.log("  ✓ Screenshot saved: \(path.lastPathComponent)", level: .info)
                        successCount += 1
                    }
                } else {
                    appState.log("  ✗ Failed to capture screenshot", level: .error)
                }
                
                screenshotProgress = Double(index + 1) / Double(total)
            }
            
            isCapturingScreenshots = false
            currentScreenshotShader = ""
            
            appState.log("Screenshot capture complete: \(successCount) successful, \(blackScreenshotCount) black, \(total - successCount - blackScreenshotCount) failed", level: .info)
            
            await loadShaders()
        }
    }
    
    private func captureShaderScreenshot(_ shader: CoreShaderInfo) async -> URL? {
        // TODO: Implement actual screenshot capture via renderer
        // For now, simulate by checking if screenshot exists
        
        // Construct potential screenshot paths
        let shaderDir = URL(fileURLWithPath: shader.path).deletingLastPathComponent()
        let screenshotPaths = [
            shaderDir.appendingPathComponent("\(shader.name).png"),
            shaderDir.appendingPathComponent("\(shader.name).jpg"),
            shaderDir.appendingPathComponent("new_scene.png")
        ]
        
        // Check if any screenshot exists
        for path in screenshotPaths {
            if FileManager.default.fileExists(atPath: path.path) {
                return path
            }
        }
        
        // Simulate screenshot capture
        let outputPath = shaderDir.appendingPathComponent("\(shader.name).png")
        appState.log("  Would save to: \(outputPath.path)", level: .debug)
        
        return nil // Return nil for now since we're simulating
    }
    
    private func isScreenshotBlack(_ screenshotPath: URL) async -> Bool {
        // TODO: Implement actual black detection using CoreImage
        // For now, simulate by checking file size or doing basic image analysis
        
        guard FileManager.default.fileExists(atPath: screenshotPath.path) else {
            return false
        }
        
        // Placeholder: In real implementation, would:
        // 1. Load image with NSImage/CGImage
        // 2. Sample pixels across image
        // 3. Calculate average brightness
        // 4. Return true if brightness < threshold (e.g., 0.05)
        
        return false
    }
    
    private func startAIAnalysis() {
        Task {
            isAnalyzing = true
            analysisProgress = 0
            
            let shadersToAnalyze = Array(selectedShaders)
            let total = shadersToAnalyze.count
            
            appState.log("Starting AI analysis for \(total) shader(s)", level: .info)
            
            var successCount = 0
            var errorCount = 0
            
            for (index, shaderName) in shadersToAnalyze.enumerated() {
                currentAnalysisShader = shaderName
                appState.log("Analyzing shader [\(index+1)/\(total)]: \(shaderName)", level: .info)
                
                guard let shader = shaders.first(where: { $0.name == shaderName }) else {
                    appState.log("  ✗ Shader not found: \(shaderName)", level: .error)
                    errorCount += 1
                    analysisProgress = Double(index + 1) / Double(total)
                    continue
                }
                
                // 1. Load shader source code
                let shaderPath = URL(fileURLWithPath: shader.path)
                appState.log("  Loading shader source: \(shaderPath.lastPathComponent)", level: .debug)
                
                // 2. Load screenshot if available
                let screenshotPath = findScreenshot(for: shader)
                if let screenshot = screenshotPath {
                    appState.log("  Found screenshot: \(screenshot.lastPathComponent)", level: .debug)
                } else {
                    appState.log("  No screenshot available", level: .debug)
                }
                
                // 3. Send to LM Studio via AI module
                appState.log("  Sending to LM Studio for analysis...", level: .debug)
                
                // TODO: Call actual AI module
                // let analysis = await appState.aiModule?.analyzeShader(source: shaderSource, screenshot: screenshotPath)
                
                // Simulate analysis
                try? await Task.sleep(for: .seconds(2))
                
                // 4. Save analysis JSON
                let analysisPath = shaderPath.deletingLastPathComponent().appendingPathComponent("\(shaderName).analysis.json")
                appState.log("  ✓ Analysis saved: \(analysisPath.lastPathComponent)", level: .info)
                successCount += 1
                
                analysisProgress = Double(index + 1) / Double(total)
            }
            
            isAnalyzing = false
            currentAnalysisShader = ""
            
            appState.log("AI analysis complete: \(successCount) successful, \(errorCount) failed", level: .info)
            
            await loadShaders()
        }
    }
    
    private func findScreenshot(for shader: CoreShaderInfo) -> URL? {
        let shaderDir = URL(fileURLWithPath: shader.path).deletingLastPathComponent()
        let screenshotPaths = [
            shaderDir.appendingPathComponent("\(shader.name).png"),
            shaderDir.appendingPathComponent("\(shader.name).jpg"),
            shaderDir.appendingPathComponent("new_scene.png")
        ]
        
        for path in screenshotPaths {
            if FileManager.default.fileExists(atPath: path.path) {
                return path
            }
        }
        
        return nil
    }
    
    private func moveToMasks() {
        Task {
            let count = selectedShaders.count
            appState.log("Moving \(count) shader(s) to masks folder", level: .info)
            
            var successCount = 0
            var errorCount = 0
            
            for shaderName in selectedShaders {
                guard let shader = shaders.first(where: { $0.name == shaderName }) else {
                    appState.log("  ✗ Shader not found: \(shaderName)", level: .error)
                    errorCount += 1
                    continue
                }
                
                let sourcePath = URL(fileURLWithPath: shader.path).deletingLastPathComponent()
                
                // TODO: Implement actual file copy
                // 1. Create masks directory if needed
                // 2. Copy shader directory
                // 3. Update rating in copied analysis.json
                
                appState.log("  Would move: \(sourcePath.lastPathComponent) → masks/\(sourcePath.lastPathComponent)", level: .debug)
                successCount += 1
            }
            
            appState.log("Move to masks complete: \(successCount) successful, \(errorCount) failed", level: .info)
            selectedShaders.removeAll()
            await loadShaders()
        }
    }
    
    private func moveToShaders() {
        Task {
            let count = selectedShaders.count
            appState.log("Moving \(count) mask(s) to shaders folder", level: .info)
            
            var successCount = 0
            var errorCount = 0
            
            for maskName in selectedShaders {
                guard let mask = shaders.first(where: { $0.name == maskName }) else {
                    appState.log("  ✗ Mask not found: \(maskName)", level: .error)
                    errorCount += 1
                    continue
                }
                
                let sourcePath = URL(fileURLWithPath: mask.path).deletingLastPathComponent()
                
                // TODO: Implement actual file copy
                // 1. Copy mask directory to shaders
                // 2. Update rating in copied analysis.json
                
                appState.log("  Would move: masks/\(sourcePath.lastPathComponent) → \(sourcePath.lastPathComponent)", level: .debug)
                successCount += 1
            }
            
            appState.log("Move to shaders complete: \(successCount) successful, \(errorCount) failed", level: .info)
            selectedShaders.removeAll()
            await loadShaders()
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
                Text(ratingName(shader.rating))
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(qualityColor(shader.rating))
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
    
    func qualityColor(_ rating: SwiftVJCore.ShaderRating) -> Color {
        switch rating {
        case .best: return .green
        case .good: return .blue
        case .normal: return .orange
        case .mask: return .gray
        case .skip: return .red
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
                Text(ratingName(shader.rating))
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(qualityColor(shader.rating))
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
    
    func qualityColor(_ rating: SwiftVJCore.ShaderRating) -> Color {
        switch rating {
        case .best: return .green
        case .good: return .blue
        case .normal: return .orange
        case .mask: return .gray
        case .skip: return .red
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
}

#Preview {
    ShaderBrowserView()
        .environmentObject(AppState())
        .frame(width: 800, height: 600)
}
