// JSONPatcher.swift - Pure functions for JSON Pointer patching (RFC 6901)
// Following Grokking Simplicity: pure calculations

import Foundation

public enum JSONPatcher {
    
    public enum PatchError: Error, LocalizedError {
        case invalidPointer(String)
        case targetNotFound(String)
        case invalidOperation(String)
        
        public var errorDescription: String? {
            switch self {
            case .invalidPointer(let msg): return "Invalid pointer: \(msg)"
            case .targetNotFound(let msg): return "Target not found: \(msg)"
            case .invalidOperation(let msg): return "Invalid operation: \(msg)"
            }
        }
    }
    
    // MARK: - Patch Application
    
    /// Apply a sequence of patch operations to a JSON object
    public static func applyPatches(_ ops: [PatchOp], to json: [String: Any], context: TemplateEngine.TemplateContext) throws -> [String: Any] {
        var result = json
        
        for op in ops {
            result = try applyPatch(op, to: result, context: context)
        }
        
        return result
    }
    
    private static func applyPatch(_ op: PatchOp, to json: [String: Any], context: TemplateEngine.TemplateContext) throws -> [String: Any] {
        let pointer = op.pointer
        
        switch op.op {
        case "set":
            guard let value = op.value else {
                throw PatchError.invalidOperation("set operation requires value")
            }
            let substituted = TemplateEngine.substituteJSON(value.value, context: context)
            return try set(pointer: pointer, value: substituted, in: json)
            
        case "merge":
            guard let value = op.value else {
                throw PatchError.invalidOperation("merge operation requires value")
            }
            let substituted = TemplateEngine.substituteJSON(value.value, context: context)
            guard let dict = substituted as? [String: Any] else {
                throw PatchError.invalidOperation("merge requires object value")
            }
            return try merge(pointer: pointer, value: dict, in: json)
            
        case "delete":
            return try delete(pointer: pointer, in: json)
            
        default:
            throw PatchError.invalidOperation("Unknown operation: \(op.op)")
        }
    }
    
    // MARK: - Operations
    
    private static func set(pointer: String, value: Any, in json: [String: Any]) throws -> [String: Any] {
        let parts = parsePointer(pointer)
        guard !parts.isEmpty else { throw PatchError.invalidPointer("Empty pointer") }
        
        var result = json
        try setRecursive(parts: parts, value: value, in: &result)
        return result
    }
    
    private static func setRecursive(parts: [String], value: Any, in json: inout [String: Any]) throws {
        guard let first = parts.first else { return }
        
        if parts.count == 1 {
            // Set at this level
            json[first] = value
        } else {
            // Recurse deeper
            var nested = json[first] as? [String: Any] ?? [:]
            try setRecursive(parts: Array(parts.dropFirst()), value: value, in: &nested)
            json[first] = nested
        }
    }
    
    private static func merge(pointer: String, value: [String: Any], in json: [String: Any]) throws -> [String: Any] {
        let parts = parsePointer(pointer)
        
        var result = json
        try mergeRecursive(parts: parts, value: value, in: &result)
        return result
    }
    
    private static func mergeRecursive(parts: [String], value: [String: Any], in json: inout [String: Any]) throws {
        if parts.isEmpty {
            // Merge at root
            for (key, val) in value {
                json[key] = val
            }
        } else {
            let first = parts[0]
            if parts.count == 1 {
                // Merge at this level
                var existing = json[first] as? [String: Any] ?? [:]
                for (key, val) in value {
                    existing[key] = val
                }
                json[first] = existing
            } else {
                // Recurse deeper
                var nested = json[first] as? [String: Any] ?? [:]
                try mergeRecursive(parts: Array(parts.dropFirst()), value: value, in: &nested)
                json[first] = nested
            }
        }
    }
    
    private static func delete(pointer: String, in json: [String: Any]) throws -> [String: Any] {
        let parts = parsePointer(pointer)
        guard !parts.isEmpty else { throw PatchError.invalidPointer("Empty pointer") }
        
        var result = json
        try deleteRecursive(parts: parts, in: &result)
        return result
    }
    
    private static func deleteRecursive(parts: [String], in json: inout [String: Any]) throws {
        guard let first = parts.first else { return }
        
        if parts.count == 1 {
            json.removeValue(forKey: first)
        } else {
            guard var nested = json[first] as? [String: Any] else { return }
            try deleteRecursive(parts: Array(parts.dropFirst()), in: &nested)
            json[first] = nested
        }
    }
    
    // MARK: - Pointer Parsing
    
    /// Parse JSON Pointer per RFC 6901
    private static func parsePointer(_ pointer: String) -> [String] {
        guard pointer.hasPrefix("/") else { return [] }
        
        let trimmed = String(pointer.dropFirst())
        if trimmed.isEmpty { return [] }
        
        return trimmed.split(separator: "/").map { part in
            String(part)
                .replacingOccurrences(of: "~1", with: "/")
                .replacingOccurrences(of: "~0", with: "~")
        }
    }
}
