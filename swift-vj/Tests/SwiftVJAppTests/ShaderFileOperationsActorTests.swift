import XCTest
@testable import SwiftVJApp
import SwiftVJCore

final class ShaderFileOperationsActorTests: XCTestCase {
    private var tempDir: URL!
    private var glslDir: URL!
    private var masksDir: URL!
    private let relatedExtensions = ["txt", "png", "analysis.json"]

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShaderFileOperationsActorTests-\(UUID().uuidString)")
        glslDir = tempDir.appendingPathComponent("glsl")
        masksDir = tempDir.appendingPathComponent("masks")
        try FileManager.default.createDirectory(at: glslDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: masksDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    private func makeShader(named name: String, in directory: URL) throws -> ShaderInfo {
        let txt = directory.appendingPathComponent("\(name).txt")
        let png = directory.appendingPathComponent("\(name).png")
        let analysis = directory.appendingPathComponent("\(name).analysis.json")
        try "void main() {}".write(to: txt, atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: png.path, contents: Data([0x89, 0x50, 0x4E, 0x47]))
        try "{}".write(to: analysis, atomically: true, encoding: .utf8)
        return ShaderInfo(name: name, path: txt.path, folder: directory.lastPathComponent)
    }

    func testMoveShadersMovesAllRelatedFiles() async throws {
        let actor = ShaderFileOperationsActor()
        let shader = try makeShader(named: "test_move", in: glslDir)

        let result = await actor.moveShaders(
            names: [shader.name],
            in: [shader],
            to: masksDir,
            relatedExtensions: relatedExtensions
        )

        XCTAssertEqual(result.succeeded, [shader.name])
        XCTAssertTrue(result.failed.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: glslDir.appendingPathComponent("test_move.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: masksDir.appendingPathComponent("test_move.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: masksDir.appendingPathComponent("test_move.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: masksDir.appendingPathComponent("test_move.analysis.json").path))
    }

    func testCopyShadersCopiesAllRelatedFiles() async throws {
        let actor = ShaderFileOperationsActor()
        let shader = try makeShader(named: "test_copy", in: glslDir)
        let exportDir = tempDir.appendingPathComponent("export")
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)

        let result = await actor.copyShaders(
            names: [shader.name],
            in: [shader],
            to: exportDir,
            relatedExtensions: relatedExtensions
        )

        XCTAssertEqual(result.succeeded, [shader.name])
        XCTAssertTrue(result.failed.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: glslDir.appendingPathComponent("test_copy.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportDir.appendingPathComponent("test_copy.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportDir.appendingPathComponent("test_copy.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportDir.appendingPathComponent("test_copy.analysis.json").path))
    }

    func testDeleteShadersRemovesAllRelatedFiles() async throws {
        let actor = ShaderFileOperationsActor()
        let shader = try makeShader(named: "test_delete", in: glslDir)

        let result = await actor.deleteShaders(
            names: [shader.name],
            in: [shader],
            relatedExtensions: relatedExtensions
        )

        XCTAssertEqual(result.succeeded, [shader.name])
        XCTAssertTrue(result.failed.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: glslDir.appendingPathComponent("test_delete.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: glslDir.appendingPathComponent("test_delete.png").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: glslDir.appendingPathComponent("test_delete.analysis.json").path))
    }
}
