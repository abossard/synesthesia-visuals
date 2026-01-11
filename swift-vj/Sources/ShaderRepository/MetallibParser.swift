// MetallibParser.swift - Parse Metal library binary to extract shader names
// Pure functions, no state

import Foundation

// MARK: - MetallibParser

/// Parse Metal library binary files to extract function names
public enum MetallibParser {
    
    /// Extract all fragment_* function names from a metallib file
    /// - Parameter url: URL to the .metallib file
    /// - Returns: Array of shader names (without "fragment_" prefix)
    /// - Throws: MetallibError if file cannot be read or parsed
    public static func parseMetallib(at url: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MetallibError.fileNotFound(url)
        }
        
        guard let data = try? Data(contentsOf: url) else {
            throw MetallibError.cannotReadFile(url)
        }
        
        return extractFragmentFunctionNames(from: data)
    }
    
    /// Extract all fragment_* function names from metallib data
    /// - Parameter data: Raw metallib binary data
    /// - Returns: Array of shader names (without "fragment_" prefix)
    public static func extractFragmentFunctionNames(from data: Data) -> [String] {
        let fragmentPrefix = "fragment_".data(using: .utf8)!
        var names: Set<String> = []
        var searchStart = 0
        
        while let range = data.range(of: fragmentPrefix, options: [], in: searchStart..<data.count) {
            let startIndex = range.lowerBound
            var endIndex = range.upperBound
            
            // Read until null byte or non-valid function name character
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
                    names.insert(shaderName)
                }
            }
            
            searchStart = endIndex
        }
        
        return names.sorted()
    }
}

// MARK: - MetallibError

/// Errors from metallib parsing
public enum MetallibError: Error, LocalizedError {
    case fileNotFound(URL)
    case cannotReadFile(URL)
    
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "Metallib file not found: \(url.path)"
        case .cannotReadFile(let url):
            return "Cannot read metallib file: \(url.path)"
        }
    }
}
