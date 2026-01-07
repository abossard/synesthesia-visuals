// ShaderRepository - Single source of truth for shader list
// Combines metallib discovery with file-based metadata
// Following A Philosophy of Software Design: deep module with simple interface

import Foundation

// MARK: - Shader Repository

/// Central repository for shader information.
/// Combines two sources:
/// - **Metallib**: Authoritative list of renderable shaders (fragment_* functions)
/// - **File System**: Metadata from .analysis.json files, folder info
///
/// Design: The metallib is the source of truth for what can render.
/// File metadata enriches shaders but doesn't add new ones.
public actor ShaderRepository {
    
    // MARK: - State
    
    private var shaders: [String: ShaderInfo] = [:]
    private var metallibShaderNames: Set<String> = []
    private var shadersDirectory: URL?
    
    // MARK: - Configuration
    
    /// Paths to search for metallib
    public static let metallibSearchPaths: [String] = [
        Bundle.main.bundleURL.appendingPathComponent("Shaders.metallib").path,
        Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Shaders.metallib").path,
        Bundle.main.path(forResource: "Shaders", ofType: "metallib") ?? "",
        // Dev paths - adjust as needed
        "/Users/abossard/Desktop/projects/synesthesia-visuals/swift-vj/Sources/SwiftVJApp/Resources/Shaders.metallib",
        "/Users/abossard/Desktop/projects/synesthesia-visuals/swift-vj/Build/Shaders.metallib"
    ].filter { !$0.isEmpty }
    
    // MARK: - Init
    
    public init() {}
    
    // MARK: - Public API
    
    /// Load shaders from metallib and enrich with file metadata.
    ///
    /// - Parameters:
    ///   - metallibPath: Optional explicit path to metallib. If nil, searches standard paths.
    ///   - shadersDirectory: Directory containing shader folders (glsl/, masks/) with .txt and .analysis.json files
    /// - Returns: Number of shaders loaded
    @discardableResult
    public func load(metallibPath: String? = nil, shadersDirectory: URL? = nil) -> Int {
        self.shadersDirectory = shadersDirectory
        shaders.removeAll()
        metallibShaderNames.removeAll()
        
        // Step 1: Discover renderable shaders from metallib
        let names = discoverFromMetallib(explicitPath: metallibPath)
        metallibShaderNames = Set(names)
        
        // Step 2: Create basic ShaderInfo for each metallib shader
        for name in names {
            shaders[name] = ShaderInfo(
                name: name,
                path: "/metallib/\(name)",
                folder: "glsl",  // Default, may be updated from file system
                metalFunctionName: "fragment_\(name)"
            )
        }
        
        // Step 3: Enrich with file metadata if directory provided
        if let dir = shadersDirectory {
            enrichFromFileSystem(directory: dir)
        }
        
        print("[ShaderRepository] Loaded \(shaders.count) shaders (\(metallibShaderNames.count) from metallib)")
        return shaders.count
    }
    
    /// Reload shaders (call when files change)
    @discardableResult
    public func reload() -> Int {
        load(metallibPath: nil, shadersDirectory: shadersDirectory)
    }
    
    /// Get all shaders (sorted by name)
    public var allShaders: [ShaderInfo] {
        shaders.values.sorted { $0.name < $1.name }
    }
    
    /// Get shaders in a specific folder
    public func shaders(inFolder folder: String) -> [ShaderInfo] {
        shaders.values.filter { $0.folder == folder }.sorted { $0.name < $1.name }
    }
    
    /// Get all unique folder names
    public var availableFolders: [String] {
        Array(Set(shaders.values.map { $0.folder })).sorted()
    }
    
    /// Get shader by name
    public func shader(named name: String) -> ShaderInfo? {
        // Try exact match first
        if let shader = shaders[name] {
            return shader
        }
        // Try without folder prefix
        let baseName = name.components(separatedBy: "/").last ?? name
        return shaders.values.first { $0.name == baseName || $0.name.hasSuffix("/\(baseName)") }
    }
    
    /// Check if shader is renderable (in metallib)
    public func isRenderable(_ name: String) -> Bool {
        let baseName = name.components(separatedBy: "/").last ?? name
        return metallibShaderNames.contains(baseName)
    }
    
    /// Total shader count
    public var count: Int { shaders.count }
    
    // MARK: - Private Implementation
    
    /// Discover shader names from metallib
    private func discoverFromMetallib(explicitPath: String?) -> [String] {
        let searchPaths: [String]
        if let explicit = explicitPath {
            searchPaths = [explicit]
        } else {
            searchPaths = Self.metallibSearchPaths
        }
        
        for path in searchPaths {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            
            // Read metallib as data and extract function names
            // Note: In a full Metal context, we'd use MTLDevice.makeLibrary
            // For now, we use the same approach as ShaderStateManager
            if let names = extractFunctionNames(from: path) {
                print("[ShaderRepository] Loaded metallib from: \(path)")
                return names
            }
        }
        
        print("[ShaderRepository] No metallib found in search paths")
        return []
    }
    
    /// Extract fragment_* function names from metallib
    private func extractFunctionNames(from path: String) -> [String]? {
        // Metallib files contain function names in a specific format
        // We extract them by parsing the binary or using Metal API
        // For simplicity, we'll use the file-based approach that works without Metal device
        
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        
        // Search for "fragment_" prefix in binary - function names are null-terminated strings
        let fragmentPrefix = "fragment_".data(using: .utf8)!
        var names: [String] = []
        var searchStart = 0
        
        while let range = data.range(of: fragmentPrefix, options: [], in: searchStart..<data.count) {
            // Extract the function name (until null terminator or invalid char)
            let startIndex = range.lowerBound
            var endIndex = range.upperBound
            
            // Read until null byte or non-printable character
            while endIndex < data.count {
                let byte = data[endIndex]
                // Valid function name characters: a-z, A-Z, 0-9, _
                let isValid = (byte >= 0x30 && byte <= 0x39) || // 0-9
                             (byte >= 0x41 && byte <= 0x5A) || // A-Z
                             (byte >= 0x61 && byte <= 0x7A) || // a-z
                             byte == 0x5F                       // _
                if !isValid { break }
                endIndex += 1
            }
            
            if let functionName = String(data: data[startIndex..<endIndex], encoding: .utf8),
               functionName.hasPrefix("fragment_"),
               functionName != "fragment_main" {
                let shaderName = String(functionName.dropFirst("fragment_".count))
                if !shaderName.isEmpty {
                    names.append(shaderName)
                }
            }
            
            searchStart = endIndex
        }
        
        return names.isEmpty ? nil : Array(Set(names)).sorted()
    }
    
    /// Enrich shaders with metadata from file system
    private func enrichFromFileSystem(directory: URL) {
        let fileManager = FileManager.default
        
        // Scan subdirectories (glsl/, masks/, etc.)
        guard let subDirs = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        
        for subDirURL in subDirs {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: subDirURL.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }
            
            let folderName = subDirURL.lastPathComponent
            
            // Find all .txt shader files
            guard let contents = try? fileManager.contentsOfDirectory(
                at: subDirURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            
            for fileURL in contents where fileURL.pathExtension == "txt" {
                let shaderName = fileURL.deletingPathExtension().lastPathComponent
                
                // Only enrich if shader exists in metallib
                guard metallibShaderNames.contains(shaderName) else { continue }
                
                // Load analysis if exists
                let analysisURL = fileURL.deletingPathExtension().appendingPathExtension("analysis.json")
                let analysis = loadAnalysis(from: analysisURL)
                
                // Update shader info
                let updated = ShaderInfo(
                    name: shaderName,
                    path: fileURL.path,
                    folder: folderName,
                    energyScore: analysis?.features.energyScore ?? 0.5,
                    moodValence: analysis?.features.moodValence ?? 0.0,
                    colorWarmth: analysis?.features.colorWarmth ?? 0.5,
                    motionSpeed: analysis?.features.motionSpeed ?? 0.5,
                    mood: analysis?.mood ?? "",
                    colors: analysis?.colors ?? [],
                    effects: analysis?.effects ?? [],
                    rating: .normal,
                    metalFunctionName: "fragment_\(shaderName)"
                )
                
                shaders[shaderName] = updated
            }
        }
    }
    
    /// Load analysis JSON
    private func loadAnalysis(from url: URL) -> ShaderAnalysis? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ShaderAnalysis.self, from: data)
    }
}
