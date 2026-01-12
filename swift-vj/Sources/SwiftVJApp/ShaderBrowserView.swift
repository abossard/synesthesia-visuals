// ShaderBrowserView - Browse and select shaders with management features
// Phase 4: SwiftUI Shell

import SwiftUI
import SwiftVJCore
import Metal
import AppKit

// Use SwiftVJCore.ShaderInfo to avoid conflict with Rendering/RenderingTypes.swift
typealias CoreShaderInfo = SwiftVJCore.ShaderInfo

// MARK: - Constants

/// Centralized constants for shader analysis and file management
private enum ShaderConstants {
    // Folder names
    static let allFolders = "ALL"
    static let masksFolder = "masks"
    static let glslFolder = "glsl"
    
    // File extensions
    static let shaderExtension = "txt"
    static let screenshotExtension = "png"
    static let analysisExtension = "analysis.json"
    static let relatedExtensions = ["txt", "png", "analysis.json"]
    
    // GLSL source file names
    static let mainGlsl = "main.glsl"
    static let fragmentGlsl = "fragment.glsl"
    static let renderpassMainGlsl = "renderpasses/main.glsl"
    
    // Screenshot file names
    static let screenshotFilename = "screenshot.png"
    static let previewFilename = "preview.png"
    
    // Metadata keys
    static let statusKey = "status"
    static let reasonKey = "reason"
    
    // Analysis reasons
    static let blackReason = "Renders black after 6 second wait"
    static let monochromaticReason = "Monochrome output detected (low saturation)"
    
    // Badge display
    static let blackBadge = "BLACK"
    static let monoBadge = "MONO"
    
    /// Check if a string indicates "black" status
    static func isBlack(_ value: String) -> Bool {
        value.lowercased() == "black"
    }

    /// Check if a string indicates "monochromatic" status
    static func isMonochromatic(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower == "monochromatic" || lower == "monochrome" || lower == "mask"
    }
}

struct ShaderBrowserView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var selectedFolder: String = ShaderConstants.allFolders
    @State private var shaders: [CoreShaderInfo] = []
    @State private var availableFolders: [String] = []
    @State private var selectedShaders: Set<String> = []
    @State private var isAnalyzing: Bool = false
    @State private var analysisCancelled: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var shaderToDelete: CoreShaderInfo? = nil
    @State private var analysisProgress: Double = 0
    @State private var currentAnalysisShader: String = ""
    @State private var analysisTotal: Int = 0
    @State private var analysisCurrent: Int = 0
    @State private var analysisSuccessCount: Int = 0
    @State private var analysisBlackCount: Int = 0
    @State private var analysisErrorCount: Int = 0
    @State private var showingAnalysisModal: Bool = false
    @State private var showingPreviewModal: Bool = false
    @State private var previewShaderName: String? = nil
    @State private var previousSelectedShaderName: String? = nil
    @State private var selectedAnalysis: ShaderAnalysis? = nil
    @State private var refreshId = UUID() // Forces grid refresh after analysis
    @State private var lastClickedShader: String? = nil // For shift-click range selection
    @State private var badgeFilter: BadgeFilter = .all // Filter by badge type
    @State private var searchResults: [CoreShaderInfo] = []
    @State private var isSearching: Bool = false
    
    /// Badge filter options
    enum BadgeFilter: String, CaseIterable {
        case all = "All"
        case black = "Black"
        case monochromatic = "Monochromatic"
        case analyzed = "Analyzed"
        case notAnalyzed = "Not Analyzed"
    }
    
    var filteredShaders: [CoreShaderInfo] {
        let base: [CoreShaderInfo] = searchText.isEmpty ? shaders : searchResults
        return base.filter { shader in
            let matchesSearch = searchText.isEmpty || 
                shader.name.localizedCaseInsensitiveContains(searchText) ||
                shader.mood.localizedCaseInsensitiveContains(searchText) ||
                shader.colors.joined(separator: " ").localizedCaseInsensitiveContains(searchText) ||
                shader.effects.joined(separator: " ").localizedCaseInsensitiveContains(searchText)
            let matchesFolder = selectedFolder == ShaderConstants.allFolders || shader.folder == selectedFolder
            let matchesBadge = matchesBadgeFilter(shader)
            return matchesSearch && matchesFolder && matchesBadge
        }
        .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
    
    /// Check if shader matches current badge filter
    private func matchesBadgeFilter(_ shader: CoreShaderInfo) -> Bool {
        switch badgeFilter {
        case .all:
            return true
        case .black:
            return getShaderStatus(shader) == .black
        case .monochromatic:
            return getShaderStatus(shader) == .monochromatic
        case .analyzed:
            return hasAnalysisFile(shader) && getShaderStatus(shader) == .normal
        case .notAnalyzed:
            return !hasAnalysisFile(shader)
        }
    }
    
    /// Shader status based on analysis
    enum ShaderStatus {
        case black          // Renders pure black
        case monochromatic  // Black/white/grey only (good for masks)
        case normal         // Has colors
        case unknown        // Not analyzed
    }
    
    /// Check if shader has analysis file
    private func hasAnalysisFile(_ shader: CoreShaderInfo) -> Bool {
        let shaderPath = URL(fileURLWithPath: shader.path)
        let shaderDir = shaderPath.deletingLastPathComponent()
        let baseName = shaderPath.deletingPathExtension().lastPathComponent
        let analysisPath = shaderDir.appendingPathComponent("\(baseName).\(ShaderConstants.analysisExtension)")
        return FileManager.default.fileExists(atPath: analysisPath.path)
    }
    
    /// Get shader status from analysis file
    private func getShaderStatus(_ shader: CoreShaderInfo) -> ShaderStatus {
        let shaderPath = URL(fileURLWithPath: shader.path)
        let shaderDir = shaderPath.deletingLastPathComponent()
        let baseName = shaderPath.deletingPathExtension().lastPathComponent
        let analysisPath = shaderDir.appendingPathComponent("\(baseName).\(ShaderConstants.analysisExtension)")
        
        guard FileManager.default.fileExists(atPath: analysisPath.path),
              let data = try? Data(contentsOf: analysisPath),
              let analysis = try? JSONDecoder().decode(ShaderAnalysisResult.self, from: data) else {
            return .unknown
        }
        
        // Collect all status hints from various sources
        let statusHints: [String] = [
            analysis.visualMetadata[ShaderConstants.statusKey],  // Primary: visual_metadata.status
            analysis.mood                                        // Legacy: mood field
        ].compactMap { $0 } + analysis.colors                    // Legacy: colors array
        
        // Check for black status (any hint matches)
        if statusHints.contains(where: ShaderConstants.isBlack) {
            return .black
        }
        
        // Check for monochromatic status (any hint matches)
        if statusHints.contains(where: ShaderConstants.isMonochromatic) {
            return .monochromatic
        }
        
        return .normal
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Action buttons bar
            HStack(spacing: 12) {
                Button(action: { Task { await reloadAllShaders() } }) {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .help("Reload shaders from disk and metallib")
                .disabled(isAnalyzing)
                
                Divider().frame(height: 20)
                
                // Selection buttons
                Button(action: selectAll) {
                    Label("Select All", systemImage: "checkmark.square.fill")
                }
                .keyboardShortcut("a", modifiers: .command)
                .disabled(isAnalyzing)
                
                Button(action: deselectAll) {
                    Label("Deselect", systemImage: "square")
                }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(isAnalyzing)
                
                Button(action: selectUnanalyzed) {
                    Label("Unanalyzed", systemImage: "exclamationmark.triangle")
                }
                .help("Select all shaders without analysis.json")
                .disabled(isAnalyzing)
                
                Divider().frame(height: 20)
                
                // Move to masks / back
                Button(action: { copySelectedToFolder() }) {
                    Label("Copy to Folder", systemImage: "folder.badge.plus")
                }
                .disabled(selectedShaders.isEmpty || isAnalyzing)
                .help("Copy selected shaders to a folder")

                Button(action: { moveSelectedToMasks() }) {
                    Label("→ Masks", systemImage: "theatermask.and.paintbrush")
                }
                .disabled(selectedShaders.isEmpty || selectedFolder == ShaderConstants.masksFolder || isAnalyzing)
                .help("Move selected shaders to masks folder")
                
                Button(action: { moveSelectedFromMasks() }) {
                    Label("← Shaders", systemImage: "arrow.uturn.backward")
                }
                .disabled(selectedShaders.isEmpty || selectedFolder != ShaderConstants.masksFolder || isAnalyzing)
                .help("Move selected shaders back to Shaders folder")
                
                Divider().frame(height: 20)
                
                // Delete
                Button(role: .destructive, action: { confirmDeleteSelected() }) {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selectedShaders.isEmpty || isAnalyzing)
                .help("Delete selected shaders")
                
                Spacer()
                
                if isAnalyzing {
                    Button(role: .destructive, action: { cancelAnalysis() }) {
                        Label("Cancel", systemImage: "xmark.circle.fill")
                    }
                    .foregroundColor(.red)
                } else {
                    Button(action: { startAnalyze() }) {
                        Label("Analyze", systemImage: "sparkle.magnifyingglass")
                    }
                    .disabled(selectedShaders.isEmpty)
                }
            }
            .padding()
            .background(.bar)
            
            Divider()
            
            // Progress indicator
            if isAnalyzing {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "sparkle.magnifyingglass")
                            .foregroundColor(.blue)
                        Text("Analyzing: \(analysisCurrent)/\(analysisTotal)")
                            .fontWeight(.medium)
                        Spacer()
                        Text(currentAnalysisShader)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    ProgressView(value: analysisProgress)
                        .tint(.blue)
                    
                    HStack(spacing: 16) {
                        Label("\(analysisSuccessCount)", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Label("\(analysisBlackCount)", systemImage: "circle.fill")
                            .foregroundColor(.red)
                        Label("\(analysisErrorCount)", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Spacer()
                        if analysisCancelled {
                            Text("Cancelling...")
                                .foregroundColor(.red)
                                .italic()
                        } else {
                            Text("\(Int(analysisProgress * 100))%")
                                .foregroundColor(.secondary)
                        }
                    }
                    .font(.caption)
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
                
                // Folder filter (dynamically populated from available folders + masks)
                Picker("Folder", selection: $selectedFolder) {
                    Text(ShaderConstants.allFolders).tag(ShaderConstants.allFolders)
                    Text(ShaderConstants.masksFolder).tag(ShaderConstants.masksFolder)
                    ForEach(availableFolders.filter { $0 != ShaderConstants.masksFolder }, id: \.self) { folder in
                        Text(folder).tag(folder)
                    }
                }
                .pickerStyle(.segmented)
                .frame(minWidth: 200)
                
                Divider().frame(height: 20)
                
                // Badge filter
                Picker("Badge", selection: $badgeFilter) {
                    ForEach(BadgeFilter.allCases, id: \.self) { filter in
                        HStack {
                            if filter == .black {
                                Circle().fill(.red).frame(width: 8, height: 8)
                            } else if filter == .monochromatic {
                                Circle().fill(.gray).frame(width: 8, height: 8)
                            }
                            Text(filter.rawValue)
                        }.tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .frame(minWidth: 120)
                
                Spacer()
                
                Text("\(filteredShaders.count) shaders | \(selectedShaders.count) selected")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(.bar)
            .onChange(of: searchText) { _, _ in
                Task { await performSearch(query: searchText) }
            }
            
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
                            shaderStatus: getShaderStatus(shader),
                            refreshId: refreshId,
                            onTap: {
                                Task {
                                    await appState.selectShader(shader.name)
                                }
                            },
                            onCheck: { modifiers in
                                handleCheckClick(shader.name, modifiers: modifiers)
                            },
                            onShowAnalysis: {
                                showAnalysis(for: shader)
                            },
                            onPreview: {
                                appState.log("[Preview] onPreview callback triggered for: \(shader.name)", level: .debug)
                                previewShader(shader)
                            },
                            onDelete: {
                                shaderToDelete = shader
                                showDeleteConfirm = true
                            }
                        )
                    }
                }
                .padding()
            }
        }
        .task {
            await loadShaders()
        }
        .sheet(isPresented: $showingAnalysisModal) {
            if let analysis = selectedAnalysis {
                ShaderAnalysisModal(analysis: analysis)
            }
        }
        .sheet(isPresented: $showingPreviewModal, onDismiss: {
            appState.log("[Preview] Modal dismissed", level: .debug)
            if let prev = previousSelectedShaderName {
                Task { await appState.selectShader(prev) }
            }
            previewShaderName = nil
        }) {
            ShaderPreviewModalContent(
                shaderName: previewShaderName ?? "Preview",
                onClose: { showingPreviewModal = false }
            )
            .environmentObject(appState)
        }
        .alert("Delete Shader?", isPresented: $showDeleteConfirm, presenting: shaderToDelete) { shader in
            Button("Delete", role: .destructive) {
                deleteShader(shader)
            }
            Button("Cancel", role: .cancel) { }
        } message: { shader in
            Text("Are you sure you want to delete \"\(shader.name)\"? This cannot be undone.")
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
        await performSearch(query: searchText)
    }
        /// Perform async search via ShadersModule (includes metadata & analysis)
        private func performSearch(query: String) async {
            // If query is empty, reset to all shaders
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                await MainActor.run {
                    self.searchResults = shaders
                    self.isSearching = false
                }
                return
            }
            guard let module = appState.shadersModule else {
                await MainActor.run {
                    self.searchResults = shaders
                    self.isSearching = false
                }
                return
            }
            await MainActor.run { self.isSearching = true }
            let results = await module.search(query: query, topK: 200)
            let base = shaders
            let matched: [CoreShaderInfo] = results.compactMap { result in
                let baseName = result.name.components(separatedBy: "/").last ?? result.name
                return base.first { info in
                    info.name == result.name || info.name == baseName || info.path.contains(baseName)
                }
            }
            await MainActor.run {
                self.searchResults = matched.isEmpty ? base.filter { $0.name.localizedCaseInsensitiveContains(query) } : matched
                self.isSearching = false
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
    
    private func toggleSelection(_ shaderName: String) {
        if selectedShaders.contains(shaderName) {
            selectedShaders.remove(shaderName)
        } else {
            selectedShaders.insert(shaderName)
        }
        lastClickedShader = shaderName
    }
    
    // MARK: - Selection Actions
    
    /// Select all shaders in current filter
    private func selectAll() {
        selectedShaders = Set(filteredShaders.map { $0.name })
    }
    
    /// Deselect all shaders
    private func deselectAll() {
        selectedShaders.removeAll()
        lastClickedShader = nil
    }
    
    /// Select all shaders that don't have analysis.json
    private func selectUnanalyzed() {
        selectedShaders.removeAll()
        for shader in filteredShaders {
            let shaderPath = URL(fileURLWithPath: shader.path)
            let shaderDir = shaderPath.deletingLastPathComponent()
            let shaderName = shaderPath.deletingPathExtension().lastPathComponent
            let analysisPath = shaderDir.appendingPathComponent("\(shaderName).\(ShaderConstants.analysisExtension)")
            
            if !FileManager.default.fileExists(atPath: analysisPath.path) {
                selectedShaders.insert(shader.name)
            }
        }
        appState.log("Selected \(selectedShaders.count) unanalyzed shaders", level: .info)
    }
    
    /// Handle check click with modifier keys (shift for range, cmd for toggle)
    private func handleCheckClick(_ shaderName: String, modifiers: EventModifiers) {
        if modifiers.contains(.shift), let lastClicked = lastClickedShader {
            // Shift-click: select range between last clicked and current
            selectRange(from: lastClicked, to: shaderName)
        } else if modifiers.contains(.command) {
            // Cmd-click: toggle single item (same as normal click)
            toggleSelection(shaderName)
        } else {
            // Normal click: toggle selection
            toggleSelection(shaderName)
        }
    }
    
    /// Select range of shaders between two names
    private func selectRange(from start: String, to end: String) {
        let names = filteredShaders.map { $0.name }
        guard let startIndex = names.firstIndex(of: start),
              let endIndex = names.firstIndex(of: end) else {
            toggleSelection(end)
            return
        }
        
        let range = min(startIndex, endIndex)...max(startIndex, endIndex)
        for i in range {
            selectedShaders.insert(names[i])
        }
        lastClickedShader = end
    }
    
    // MARK: - File Operations
    
    /// Reload shaders in both browser and render engine
    private func reloadAllShaders() async {
        await loadShaders()
        
        // Also reload in the render engine's shader state manager
        if let shadersDir = findShadersDirectory(),
           let renderEngine = appState.renderEngine {
            // Set shaders directory in state manager (triggers enrichment)
            await MainActor.run {
                renderEngine.shaderManager.setShadersDirectory(shadersDir)
                renderEngine.shaderManager.reload()
            }
            appState.log("Reloaded shaders in ShaderStateManager", level: .debug)
        }
        
        // Also reload in the shaders module
        if let shadersDir = findShadersDirectory(),
           let module = appState.shadersModule {
            _ = await module.loadAllShaderFiles(from: shadersDir)
            appState.log("Reloaded shaders in ShadersModule", level: .debug)
        }
    }
    
    /// Move selected shaders to masks folder (moves .txt, .png, .analysis.json files)
    private func moveSelectedToMasks() {
        guard let shadersDir = findShadersDirectory() else {
            appState.log("Cannot find Shaders directory", level: .error)
            return
        }
        
        // Shaders are in swift-vj/Shaders/glsl/, masks go to swift-vj/Shaders/masks/
        let masksDir = shadersDir.appendingPathComponent(ShaderConstants.masksFolder)
        
        // Create masks folder if it doesn't exist
        try? FileManager.default.createDirectory(at: masksDir, withIntermediateDirectories: true)
        
        var movedCount = 0
        var movedCurrentShader = false
        
        for shaderName in selectedShaders {
            guard let shader = shaders.first(where: { $0.name == shaderName }) else { continue }
            
            // Check if this is the currently rendering shader
            if appState.selectedShader == shaderName {
                movedCurrentShader = true
            }
            
            let shaderFile = URL(fileURLWithPath: shader.path)
            let sourceDir = shaderFile.deletingLastPathComponent()
            let baseName = shaderFile.deletingPathExtension().lastPathComponent
            
            // Move all related files
            var allMoved = true
            
            for ext in ShaderConstants.relatedExtensions {
                let sourceFile = sourceDir.appendingPathComponent("\(baseName).\(ext)")
                let destFile = masksDir.appendingPathComponent("\(baseName).\(ext)")
                
                if FileManager.default.fileExists(atPath: sourceFile.path) {
                    do {
                        try FileManager.default.moveItem(at: sourceFile, to: destFile)
                    } catch {
                        appState.log("Failed to move \(baseName).\(ext): \(error.localizedDescription)", level: .error)
                        allMoved = false
                    }
                }
            }
            
            if allMoved { movedCount += 1 }
        }
        
        appState.log("Moved \(movedCount) shaders to masks folder", level: .info)
        selectedShaders.removeAll()
        
        // Clear current shader if it was moved
        if movedCurrentShader {
            Task {
                await appState.selectShader("")
            }
        }
        
        Task { await reloadAllShaders() }
    }

    /// Copy selected shaders to a user-chosen folder (copies .txt, .png, .analysis.json)
    private func copySelectedToFolder() {
        guard !selectedShaders.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"

        if panel.runModal() == .OK, let destURL = panel.url {
            var copiedShaders: Set<String> = []
            for shaderName in selectedShaders {
                guard let shader = shaders.first(where: { $0.name == shaderName }) else { continue }
                let shaderFile = URL(fileURLWithPath: shader.path)
                let sourceDir = shaderFile.deletingLastPathComponent()
                let baseName = shaderFile.deletingPathExtension().lastPathComponent

                for ext in ShaderConstants.relatedExtensions {
                    let sourceFile = sourceDir.appendingPathComponent("\(baseName).\(ext)")
                    let destFile = destURL.appendingPathComponent("\(baseName).\(ext)")
                    if FileManager.default.fileExists(atPath: sourceFile.path) {
                        // Overwrite if exists
                        if FileManager.default.fileExists(atPath: destFile.path) {
                            try? FileManager.default.removeItem(at: destFile)
                        }
                        do {
                            try FileManager.default.copyItem(at: sourceFile, to: destFile)
                            copiedShaders.insert(shaderName)
                        } catch {
                            appState.log("Failed to copy \(baseName).\(ext): \(error.localizedDescription)", level: .error)
                        }
                    }
                }
            }

            appState.log("Copied \(copiedShaders.count) shader(s) to \(destURL.path)", level: .info)
            Task { await reloadAllShaders() }
        }
    }

    
    /// Move selected shaders from masks back to glsl folder
    private func moveSelectedFromMasks() {
        guard let shadersDir = findShadersDirectory() else {
            appState.log("Cannot find Shaders directory", level: .error)
            return
        }
        
        // Move from swift-vj/Shaders/masks/ to swift-vj/Shaders/glsl/
        let glslDir = shadersDir.appendingPathComponent(ShaderConstants.glslFolder)
        
        var movedCount = 0
        for shaderName in selectedShaders {
            guard let shader = shaders.first(where: { $0.name == shaderName }) else { continue }
            
            let shaderFile = URL(fileURLWithPath: shader.path)
            let sourceDir = shaderFile.deletingLastPathComponent()
            let baseName = shaderFile.deletingPathExtension().lastPathComponent
            
            // Move all related files
            var allMoved = true
            
            for ext in ShaderConstants.relatedExtensions {
                let sourceFile = sourceDir.appendingPathComponent("\(baseName).\(ext)")
                let destFile = glslDir.appendingPathComponent("\(baseName).\(ext)")
                
                if FileManager.default.fileExists(atPath: sourceFile.path) {
                    do {
                        try FileManager.default.moveItem(at: sourceFile, to: destFile)
                    } catch {
                        appState.log("Failed to move \(baseName).\(ext): \(error.localizedDescription)", level: .error)
                        allMoved = false
                    }
                }
            }
            
            if allMoved { movedCount += 1 }
        }
        
        appState.log("Moved \(movedCount) shaders back to glsl folder", level: .info)
        selectedShaders.removeAll()
        Task { await reloadAllShaders() }
    }

    /// Preview a shader in a Syphon-powered modal
    private func previewShader(_ shader: CoreShaderInfo) {
        appState.log("[Preview] 👁 Eye clicked for: \(shader.name)", level: .debug)
        
        // Check if shader is in metallib (renderable)
        let isRenderable = appState.renderEngine?.shaderManager.isRenderable(shader.name) ?? false
        appState.log("[Preview]   • In metallib: \(isRenderable)", level: .debug)
        appState.log("[Preview]   • Current selectedShader: \(appState.selectedShader ?? "nil")", level: .debug)
        
        // Check Syphon server status
        let syphonServers = SyphonOutputManager.shared.serverNames
        appState.log("[Preview]   • Syphon servers: \(syphonServers)", level: .debug)
        
        previousSelectedShaderName = appState.selectedShader
        previewShaderName = shader.name
        
        appState.log("[Preview]   • Setting showingPreviewModal = true", level: .debug)
        showingPreviewModal = true
        
        Task {
            await appState.selectShader(shader.name)
            appState.log("[Preview]   • selectShader completed", level: .debug)
        }
    }
    
    /// Show confirmation for deleting selected shaders
    private func confirmDeleteSelected() {
        // For bulk delete, we use the first selected shader as the prompt
        // In practice user can delete one at a time from card menu
        if let firstName = selectedShaders.first,
           let shader = shaders.first(where: { $0.name == firstName }) {
            shaderToDelete = shader
            showDeleteConfirm = true
        }
    }
    
    /// Delete a shader (removes .txt and associated .png, .analysis.json files)
    private func deleteShader(_ shader: CoreShaderInfo) {
        let shaderFile = URL(fileURLWithPath: shader.path)
        let shaderDir = shaderFile.deletingLastPathComponent()
        let baseName = shaderFile.deletingPathExtension().lastPathComponent
        
        // Check if this is the currently rendering shader
        let wasCurrentShader = appState.selectedShader == shader.name
        
        // Delete all related files
        var deletedAny = false
        
        for ext in ShaderConstants.relatedExtensions {
            let file = shaderDir.appendingPathComponent("\(baseName).\(ext)")
            if FileManager.default.fileExists(atPath: file.path) {
                do {
                    try FileManager.default.removeItem(at: file)
                    deletedAny = true
                } catch {
                    appState.log("Failed to delete \(baseName).\(ext): \(error.localizedDescription)", level: .error)
                }
            }
        }
        
        if deletedAny {
            appState.log("Deleted shader: \(shader.name)", level: .info)
            selectedShaders.remove(shader.name)
            
            // Clear current shader if it was deleted
            if wasCurrentShader {
                Task {
                    await appState.selectShader("")
                }
            }
            
            Task { await reloadAllShaders() }
        }
    }
    
    // MARK: - Unified Analyze Function
    
    /// Cancel ongoing analysis
    private func cancelAnalysis() {
        analysisCancelled = true
        appState.log("⚠️ Analysis cancellation requested...", level: .warning)
    }
    
    /// Start analysis: screenshot capture + AI analysis
    /// 1. Loads shader, waits 1s, captures screenshot
    /// 2. If black, waits 5s more and retries
    /// 3. If still black, marks as "black" status
    /// 4. If not black, runs AI analysis on source + screenshot
    private func startAnalyze() {
        Task {
            let startTime = Date()
            isAnalyzing = true
            analysisCancelled = false
            analysisProgress = 0
            analysisSuccessCount = 0
            analysisBlackCount = 0
            analysisErrorCount = 0
            
            let shadersToAnalyze = Array(selectedShaders)
            let total = shadersToAnalyze.count
            analysisTotal = total
            analysisCurrent = 0
            
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
            let screenshotCapture = ShaderScreenshotCapture(logger: { message, level in
                Task { @MainActor in
                    self.appState.log(message, level: level)
                }
            })
            
            let lmStudioClient = LMStudioClient(logger: { message, level in
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
                // Check for cancellation
                if analysisCancelled {
                    appState.log("⚠️ Analysis cancelled by user", level: .warning)
                    break
                }
                
                let shaderStartTime = Date()
                currentAnalysisShader = shaderName
                analysisCurrent = index + 1
                
                appState.log("───────────────────────────────────────────────────────────────", level: .info)
                appState.log("📍 [\(index+1)/\(total)] \(shaderName)", level: .info)
                appState.log("───────────────────────────────────────────────────────────────", level: .info)
                
                guard let shader = shaders.first(where: { $0.name == shaderName }) else {
                    appState.log("  ✗ Shader not found in list", level: .error)
                    errorCount += 1
                    analysisErrorCount = errorCount
                    analysisProgress = Double(index + 1) / Double(total)
                    continue
                }
                
                // Get paths
                let shaderPath = URL(fileURLWithPath: shader.path)
                let shaderDir = shaderPath.deletingLastPathComponent()
                let baseName = shaderPath.deletingPathExtension().lastPathComponent
                let screenshotPath = shaderDir.appendingPathComponent("\(baseName).\(ShaderConstants.screenshotExtension)")
                let analysisPath = shaderDir.appendingPathComponent("\(baseName).\(ShaderConstants.analysisExtension)")
                
                // Clean up existing files before re-analysis
                if FileManager.default.fileExists(atPath: screenshotPath.path) {
                    try? FileManager.default.removeItem(at: screenshotPath)
                    appState.log("  🗑️ Deleted existing screenshot", level: .debug)
                }
                if FileManager.default.fileExists(atPath: analysisPath.path) {
                    try? FileManager.default.removeItem(at: analysisPath)
                    appState.log("  🗑️ Deleted existing analysis", level: .debug)
                }
                
                // STEP 1: Select shader via AppState (single source of truth - syncs to render engine)
                appState.log("  ▶ Selecting shader '\(shaderName)'...", level: .info)
                await appState.selectShader(shaderName)
                
                // STEP 2: Wait for shader to stabilize and render
                appState.log("  ⏳ Waiting 3s for shader to initialize...", level: .info)
                try? await Task.sleep(for: .seconds(3))
                
                var isBlack = true
                var isMonochrome = false
                var captureSuccess = false
                
                // First capture attempt
                appState.log("  📸 Capturing screenshot (attempt 1/2)...", level: .info)
                let firstCaptureResult = await captureAndCheckBlack(shader: shader, screenshotPath: screenshotPath, screenshotCapture: screenshotCapture)
                
                switch firstCaptureResult {
                case .success(let black, let mono):
                    captureSuccess = true
                    isBlack = black
                    isMonochrome = mono
                    if black {
                        appState.log("  ⚠️ Screenshot is BLACK - waiting 5s for retry...", level: .warning)
                        try? await Task.sleep(for: .seconds(5))
                        
                        // Second capture attempt
                        appState.log("  📸 Capturing screenshot (attempt 2/2)...", level: .info)
                        let secondCaptureResult = await captureAndCheckBlack(shader: shader, screenshotPath: screenshotPath, screenshotCapture: screenshotCapture)
                        
                        switch secondCaptureResult {
                        case .success(let stillBlack, let stillMono):
                            isBlack = stillBlack
                            isMonochrome = stillMono
                            if stillBlack {
                                appState.log("  ⚠️ Still BLACK after 6s total wait", level: .warning)
                            } else {
                                appState.log("  ✓ Screenshot now shows content", level: .info)
                                if stillMono {
                                    appState.log("  🏷️ Detected MONOCHROME shader (mask candidate)", level: .info)
                                }
                            }
                        case .failure:
                            appState.log("  ✗ Second capture failed", level: .error)
                        }
                    } else {
                        appState.log("  ✓ Screenshot captured successfully", level: .info)
                        if mono {
                            appState.log("  🏷️ Detected MONOCHROME shader (mask candidate)", level: .info)
                        }
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
                    analysisBlackCount = blackCount
                    
                    let elapsed = Date().timeIntervalSince(shaderStartTime)
                    appState.log("  ⏱️ Completed in \(String(format: "%.1f", elapsed))s (marked as black)", level: .info)
                    analysisProgress = Double(index + 1) / Double(total)
                    continue
                }
                
                // STEP 3b: Handle monochrome screenshot - mark it but continue to AI analysis
                if isMonochrome && !aiAvailable {
                    appState.log("  🏷️ Marking shader as MONOCHROMATIC", level: .info)
                    await saveMonochromaticAnalysis(to: analysisPath, shaderName: shaderName)
                    successCount += 1
                    analysisSuccessCount = successCount
                    
                    let elapsed = Date().timeIntervalSince(shaderStartTime)
                    appState.log("  ⏱️ Completed in \(String(format: "%.1f", elapsed))s (marked as monochromatic)", level: .info)
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
                        analysisSuccessCount = successCount
                        
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
                            analysisSuccessCount = successCount
                        } else {
                            appState.log("  ✗ Failed to save analysis JSON", level: .error)
                            errorCount += 1
                            analysisErrorCount = errorCount
                        }
                    } else {
                        appState.log("  ✗ AI analysis failed", level: .error)
                        errorCount += 1
                        analysisErrorCount = errorCount
                    }
                } else if captureSuccess {
                    // No AI available but screenshot worked
                    appState.log("  ℹ️ Screenshot saved (no AI analysis)", level: .info)
                    successCount += 1
                    analysisSuccessCount = successCount
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
        
        // Capture texture and get black/monochrome detection result
        let (success, isBlack, isMonochrome) = await screenshotCapture.captureTextureWithBlackCheck(
            shaderTexture,
            outputPath: screenshotPath,
            shaderName: shader.name
        )
        
        if success {
            return .success(isBlack: isBlack, isMonochrome: isMonochrome)
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
            visualMetadata: [
                ShaderConstants.statusKey: "black",
                ShaderConstants.reasonKey: ShaderConstants.blackReason
            ],
            djPhases: nil
        )
        
        _ = await saveAnalysisJSON(analysis, to: path, shaderName: shaderName)
    }
    
    /// Save analysis JSON marking shader as monochromatic
    private func saveMonochromaticAnalysis(to path: URL, shaderName: String) async {
        let analysis = ShaderAnalysisResult(
            title: shaderName,
            description: "Shader renders monochrome (black/white/grey) output - suitable as mask",
            mood: "monochromatic",
            energy: 0.5,
            colors: ["white", "grey", "black"],
            effects: ["monochrome"],
            geometry: [],
            objects: [],
            complexity: "unknown",
            visualMetadata: [
                ShaderConstants.statusKey: "monochromatic",
                ShaderConstants.reasonKey: ShaderConstants.monochromaticReason
            ],
            djPhases: nil
        )
        
        _ = await saveAnalysisJSON(analysis, to: path, shaderName: shaderName)
    }
    
    /// Capture screenshot result
    private enum CaptureResult {
        case success(isBlack: Bool, isMonochrome: Bool)
        case failure
    }
    
    /// Find shader source file in directory
    private func findShaderSourceFile(in directory: URL, shaderName: String) -> URL? {
        let possibleFiles = [
            directory.appendingPathComponent(ShaderConstants.mainGlsl),
            directory.appendingPathComponent("\(shaderName).glsl"),
            directory.appendingPathComponent(ShaderConstants.fragmentGlsl),
            directory.appendingPathComponent(ShaderConstants.renderpassMainGlsl)
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
            shaderDir.appendingPathComponent("\(shaderName).\(ShaderConstants.screenshotExtension)"),
            shaderDir.appendingPathComponent(ShaderConstants.screenshotFilename),
            shaderDir.appendingPathComponent(ShaderConstants.previewFilename)
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
    
    private func showAnalysis(for shader: CoreShaderInfo) {
        // Load analysis from JSON file
        let shaderPath = URL(fileURLWithPath: shader.path)
        let shaderDir = shaderPath.deletingLastPathComponent()
        let baseName = shaderPath.deletingPathExtension().lastPathComponent
        let analysisPath = shaderDir.appendingPathComponent("\(baseName).\(ShaderConstants.analysisExtension)")
        
        // Try to load from file
        if FileManager.default.fileExists(atPath: analysisPath.path),
           let data = try? Data(contentsOf: analysisPath),
           let result = try? JSONDecoder().decode(ShaderAnalysisResult.self, from: data) {
            // Convert ShaderAnalysisResult to ShaderAnalysis
            selectedAnalysis = ShaderAnalysis(
                shaderName: shader.name,
                title: result.title,
                description: result.description,
                mood: result.mood,
                energy: result.energy,
                colors: result.colors,
                effects: result.effects,
                geometry: result.geometry,
                objects: result.objects,
                complexity: result.complexity,
                visualMetadata: result.visualMetadata
            )
        } else {
            // No analysis file - show placeholder
            selectedAnalysis = ShaderAnalysis(
                shaderName: shader.name,
                title: shader.name.replacingOccurrences(of: "_", with: " ").capitalized,
                description: "No analysis available. Run analysis to generate shader metadata.",
                mood: "unknown",
                energy: 0.5,
                colors: [],
                effects: [],
                geometry: [],
                objects: [],
                complexity: "unknown",
                visualMetadata: [:]
            )
        }
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
    let shaderStatus: ShaderBrowserView.ShaderStatus
    let refreshId: UUID // Forces screenshot reload when changed
    let onTap: () -> Void
    let onCheck: (EventModifiers) -> Void
    let onShowAnalysis: () -> Void
    let onPreview: () -> Void
    let onDelete: () -> Void
    
    @State private var screenshotImage: NSImage?
    @State private var analysisData: ShaderAnalysisResult?
    @State private var hasAnalysis: Bool = false
    
    /// Find screenshot path for this shader
    private var screenshotPath: URL? {
        let shaderPath = URL(fileURLWithPath: shader.path)
        let shaderDir = shaderPath.deletingLastPathComponent()
        let shaderName = shaderPath.deletingPathExtension().lastPathComponent
        
        let possibleFiles = [
            shaderDir.appendingPathComponent("\(shaderName).\(ShaderConstants.screenshotExtension)"),
            shaderDir.appendingPathComponent(ShaderConstants.screenshotFilename),
            shaderDir.appendingPathComponent(ShaderConstants.previewFilename)
        ]
        
        return possibleFiles.first { FileManager.default.fileExists(atPath: $0.path) }
    }
    
    /// Find analysis.json path for this shader
    private var analysisPath: URL? {
        let shaderPath = URL(fileURLWithPath: shader.path)
        let shaderDir = shaderPath.deletingLastPathComponent()
        let shaderName = shaderPath.deletingPathExtension().lastPathComponent
        
        let path = shaderDir.appendingPathComponent("\(shaderName).\(ShaderConstants.analysisExtension)")
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row with checkbox and delete button
            HStack {
                // Checkbox with modifier support for shift/cmd click
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .foregroundColor(isChecked ? .blue : .secondary)
                    .onTapGesture {
                        // Capture current modifier keys from NSEvent
                        let modifiers = NSEvent.modifierFlags
                        var eventModifiers: EventModifiers = []
                        if modifiers.contains(.shift) { eventModifiers.insert(.shift) }
                        if modifiers.contains(.command) { eventModifiers.insert(.command) }
                        onCheck(eventModifiers)
                    }
                
                Spacer()

                // Preview button
                Button(action: onPreview) {
                    Image(systemName: "eye")
                        .foregroundColor(.primary.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Preview this shader")

                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Delete this shader")
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

            // Mood & energy
            if let analysis = analysisData {
                HStack(spacing: 8) {
                    if !analysis.mood.isEmpty {
                        Text(analysis.mood.capitalized)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    ProgressView(value: max(0, min(1, analysis.energy)))
                        .progressViewStyle(.linear)
                        .frame(width: 60)
                }
            } else if !shader.mood.isEmpty {
                Text(shader.mood.capitalized)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Quality badge and tags
            HStack {
                // Status badge based on analysis
                switch shaderStatus {
                case .black:
                    Text(ShaderConstants.blackBadge)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                case .monochromatic:
                    Text(ShaderConstants.monoBadge)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                case .normal:
                    Text("✓ Analyzed")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                case .unknown:
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
                let effectTags = analysisData?.effects.prefix(1) ?? shader.effects.prefix(1)
                ForEach(Array(displayTags), id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .cornerRadius(2)
                }
                ForEach(Array(effectTags), id: \.self) { tag in
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
    
    /// Load screenshot from disk
    private func loadScreenshot() {
        // Move ALL file I/O to background thread (including path existence checks)
        DispatchQueue.global(qos: .userInitiated).async {
            let shaderPath = URL(fileURLWithPath: shader.path)
            let shaderDir = shaderPath.deletingLastPathComponent()
            let shaderName = shaderPath.deletingPathExtension().lastPathComponent

            let possibleFiles = [
                shaderDir.appendingPathComponent("\(shaderName).\(ShaderConstants.screenshotExtension)"),
                shaderDir.appendingPathComponent(ShaderConstants.screenshotFilename),
                shaderDir.appendingPathComponent(ShaderConstants.previewFilename)
            ]

            guard let path = possibleFiles.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
                  let image = NSImage(contentsOf: path) else {
                DispatchQueue.main.async {
                    self.screenshotImage = nil
                }
                return
            }

            DispatchQueue.main.async {
                self.screenshotImage = image
            }
        }
    }
    
    /// Load analysis JSON from disk
    private func loadAnalysis() {
        // Move ALL file I/O to background thread (including path existence check)
        DispatchQueue.global(qos: .userInitiated).async {
            let shaderPath = URL(fileURLWithPath: shader.path)
            let shaderDir = shaderPath.deletingLastPathComponent()
            let shaderName = shaderPath.deletingPathExtension().lastPathComponent
            let path = shaderDir.appendingPathComponent("\(shaderName).\(ShaderConstants.analysisExtension)")

            guard FileManager.default.fileExists(atPath: path.path) else {
                DispatchQueue.main.async {
                    self.hasAnalysis = false
                    self.analysisData = nil
                }
                return
            }

            do {
                let data = try Data(contentsOf: path)
                let analysis = try JSONDecoder().decode(ShaderAnalysisResult.self, from: data)
                DispatchQueue.main.async {
                    self.hasAnalysis = true
                    self.analysisData = analysis
                }
            } catch {
                // File exists but couldn't parse - still mark as analyzed
                DispatchQueue.main.async {
                    self.hasAnalysis = true
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

// MARK: - Shader Preview Modal Content

/// Extracted modal content to ensure proper lifecycle for SyphonMTKView
struct ShaderPreviewModalContent: View {
    let shaderName: String
    let onClose: () -> Void
    
    @EnvironmentObject var appState: AppState
    @State private var showSyphonView = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(shaderName)
                    .font(.headline)
                Spacer()
                
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(.bar)

            Divider()

            // Delay Syphon view creation to ensure sheet is fully rendered
            if showSyphonView {
                SyphonMTKView(serverName: "Shader")
                    .aspectRatio(16/9, contentMode: .fit)
                    .frame(minWidth: 640, minHeight: 360)
                    .background(Color.black)
            } else {
                Color.black
                    .aspectRatio(16/9, contentMode: .fit)
                    .frame(minWidth: 640, minHeight: 360)
                    .overlay(
                        ProgressView()
                            .progressViewStyle(.circular)
                    )
            }
        }
        .frame(width: 800, height: 500)
        .onAppear {
            appState.log("[Preview] Modal appeared for: \(shaderName)", level: .debug)
            // Delay Syphon view creation to let sheet animate in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showSyphonView = true
                appState.log("[Preview] SyphonMTKView now enabled", level: .debug)
            }
        }
    }
}

#Preview {
    ShaderBrowserView()
        .environmentObject(AppState())
        .frame(width: 800, height: 600)
}
