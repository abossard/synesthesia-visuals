// ShaderFileOperationsActor.swift - Serialized filesystem mutations for shader assets

import Foundation
import SwiftVJCore

struct ShaderFileBatchResult: Sendable {
    var succeeded: [String] = []
    var failed: [String: String] = [:]
}

actor ShaderFileOperationsActor {
    func moveShaders(
        names: Set<String>,
        in shaders: [ShaderInfo],
        to destinationDirectory: URL,
        relatedExtensions: [String]
    ) -> ShaderFileBatchResult {
        var result = ShaderFileBatchResult()
        try? FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        for shaderName in names {
            guard let shader = shaders.first(where: { $0.name == shaderName }) else {
                result.failed[shaderName] = "Shader not found"
                continue
            }

            let sourceFile = URL(fileURLWithPath: shader.path)
            let sourceDir = sourceFile.deletingLastPathComponent()
            let baseName = sourceFile.deletingPathExtension().lastPathComponent
            var ok = true

            for ext in relatedExtensions {
                let sourceRelated = sourceDir.appendingPathComponent("\(baseName).\(ext)")
                let destRelated = destinationDirectory.appendingPathComponent("\(baseName).\(ext)")

                guard FileManager.default.fileExists(atPath: sourceRelated.path) else { continue }

                do {
                    if FileManager.default.fileExists(atPath: destRelated.path) {
                        try FileManager.default.removeItem(at: destRelated)
                    }
                    try FileManager.default.moveItem(at: sourceRelated, to: destRelated)
                } catch {
                    ok = false
                    result.failed[shaderName] = error.localizedDescription
                    break
                }
            }

            if ok {
                result.succeeded.append(shaderName)
            }
        }

        return result
    }

    func copyShaders(
        names: Set<String>,
        in shaders: [ShaderInfo],
        to destinationDirectory: URL,
        relatedExtensions: [String]
    ) -> ShaderFileBatchResult {
        var result = ShaderFileBatchResult()
        try? FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        for shaderName in names {
            guard let shader = shaders.first(where: { $0.name == shaderName }) else {
                result.failed[shaderName] = "Shader not found"
                continue
            }

            let sourceFile = URL(fileURLWithPath: shader.path)
            let sourceDir = sourceFile.deletingLastPathComponent()
            let baseName = sourceFile.deletingPathExtension().lastPathComponent
            var copiedAny = false
            var ok = true

            for ext in relatedExtensions {
                let sourceRelated = sourceDir.appendingPathComponent("\(baseName).\(ext)")
                let destRelated = destinationDirectory.appendingPathComponent("\(baseName).\(ext)")

                guard FileManager.default.fileExists(atPath: sourceRelated.path) else { continue }

                do {
                    if FileManager.default.fileExists(atPath: destRelated.path) {
                        try FileManager.default.removeItem(at: destRelated)
                    }
                    try FileManager.default.copyItem(at: sourceRelated, to: destRelated)
                    copiedAny = true
                } catch {
                    ok = false
                    result.failed[shaderName] = error.localizedDescription
                    break
                }
            }

            if ok && copiedAny {
                result.succeeded.append(shaderName)
            } else if ok && !copiedAny {
                result.failed[shaderName] = "No source files found"
            }
        }

        return result
    }

    func deleteShaders(
        names: Set<String>,
        in shaders: [ShaderInfo],
        relatedExtensions: [String]
    ) -> ShaderFileBatchResult {
        var result = ShaderFileBatchResult()

        for shaderName in names {
            guard let shader = shaders.first(where: { $0.name == shaderName }) else {
                result.failed[shaderName] = "Shader not found"
                continue
            }

            let sourceFile = URL(fileURLWithPath: shader.path)
            let sourceDir = sourceFile.deletingLastPathComponent()
            let baseName = sourceFile.deletingPathExtension().lastPathComponent
            var deletedAny = false
            var ok = true

            for ext in relatedExtensions {
                let target = sourceDir.appendingPathComponent("\(baseName).\(ext)")
                guard FileManager.default.fileExists(atPath: target.path) else { continue }

                do {
                    try FileManager.default.removeItem(at: target)
                    deletedAny = true
                } catch {
                    ok = false
                    result.failed[shaderName] = error.localizedDescription
                    break
                }
            }

            if ok && deletedAny {
                result.succeeded.append(shaderName)
            } else if ok && !deletedAny {
                result.failed[shaderName] = "No files to delete"
            }
        }

        return result
    }
}
