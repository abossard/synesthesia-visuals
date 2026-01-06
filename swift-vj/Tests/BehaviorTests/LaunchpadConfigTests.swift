// LaunchpadConfigTests.swift - E2E tests for Launchpad config storage
// Tests file format, save/load round-trip, bank isolation, v1→v2 migration

import XCTest
@testable import SwiftVJCore

final class LaunchpadConfigTests: XCTestCase {
    
    // MARK: - Test Fixtures
    
    private var tempDir: URL!
    private var configPath: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        configPath = tempDir.appendingPathComponent("launchpad-config.json")
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // MARK: - LaunchpadConfigFile Tests
    
    func test_configFile_roundTrip() throws {
        // Given: Some pad configs across multiple banks
        var bankConfigs: [Int: [ButtonId: PadBehavior]] = [:]
        
        let pad1 = ButtonId(x: 2, y: 3)
        let behavior1 = PadBehavior(
            padId: pad1,
            mode: .selector,
            group: .scenes,
            idleColor: LP.off,
            activeColor: LP.green,
            label: "Scene 1",
            oscAction: OscCommand(address: "/scenes/select", args: [.string("scene-1")])
        )
        
        let pad2 = ButtonId(x: 5, y: 6)
        let behavior2 = PadBehavior(
            padId: pad2,
            mode: .toggle,
            idleColor: LP.blue,
            activeColor: LP.cyan,
            label: "FX Toggle",
            oscOn: OscCommand(address: "/fx/strobe", args: [.int(1)]),
            oscOff: OscCommand(address: "/fx/strobe", args: [.int(0)])
        )
        
        bankConfigs[0] = [pad1: behavior1]
        bankConfigs[3] = [pad2: behavior2]
        
        // When: Convert to file format and back
        let configFile = LaunchpadConfigFile(from: bankConfigs)
        let restored = configFile.toBankConfigs()
        
        // Then: Should match original
        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(restored[0]?.count, 1)
        XCTAssertEqual(restored[3]?.count, 1)
        XCTAssertEqual(restored[0]?[pad1]?.label, "Scene 1")
        XCTAssertEqual(restored[3]?[pad2]?.label, "FX Toggle")
    }
    
    func test_configFile_jsonSerialization() throws {
        // Given: A config file
        let pad = ButtonId(x: 1, y: 1)
        let behavior = PadBehavior(
            padId: pad,
            mode: .oneShot,
            activeColor: LP.red,
            label: "Flash",
            oscAction: OscCommand(address: "/flash", args: [])
        )
        
        let bankConfigs: [Int: [ButtonId: PadBehavior]] = [0: [pad: behavior]]
        let configFile = LaunchpadConfigFile(from: bankConfigs)
        
        // When: Encode and decode JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configFile)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(LaunchpadConfigFile.self, from: data)
        
        // Then: Version preserved, data intact
        XCTAssertEqual(decoded.version, LaunchpadConfigFile.currentVersion)
        XCTAssertEqual(decoded.banks.count, 1)
        XCTAssertNotNil(decoded.banks["0"]?["1,1"])
    }
    
    func test_configFile_additionalOscPreserved() throws {
        // Given: Behavior with additionalOsc commands
        let pad = ButtonId(x: 0, y: 0)
        let behavior = PadBehavior(
            padId: pad,
            mode: .selector,
            group: .presets,
            label: "Preset with controls",
            oscAction: OscCommand(address: "/scenes/select", args: [.string("my-scene")]),
            additionalOsc: [
                OscCommand(address: "/controls/brightness", args: [.float(0.8)]),
                OscCommand(address: "/controls/speed", args: [.float(1.5)]),
                OscCommand(address: "/controls/color", args: [.float(0.2), .float(0.5), .float(0.9)])
            ]
        )
        
        let bankConfigs: [Int: [ButtonId: PadBehavior]] = [0: [pad: behavior]]
        let configFile = LaunchpadConfigFile(from: bankConfigs)
        
        // When: JSON round-trip
        let encoder = JSONEncoder()
        let data = try encoder.encode(configFile)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(LaunchpadConfigFile.self, from: data)
        let restored = decoded.toBankConfigs()
        
        // Then: additionalOsc preserved
        let restoredBehavior = restored[0]?[pad]
        XCTAssertNotNil(restoredBehavior)
        XCTAssertEqual(restoredBehavior?.additionalOsc.count, 3)
        XCTAssertEqual(restoredBehavior?.additionalOsc[0].address, "/controls/brightness")
        XCTAssertEqual(restoredBehavior?.additionalOsc[2].address, "/controls/color")
    }
    
    // MARK: - Direct File Save/Load Tests (without EffectExecutor)
    
    func test_directFileSaveLoad_roundTrip() throws {
        // Given: Bank configs to save
        let pad1 = ButtonId(x: 3, y: 4)
        let behavior1 = PadBehavior(
            padId: pad1,
            mode: .selector,
            group: .scenes,
            label: "Test Scene"
        )
        
        let pad2 = ButtonId(x: 0, y: 0)
        let behavior2 = PadBehavior(
            padId: pad2,
            mode: .toggle,
            label: "Bank 5 Toggle"
        )
        
        var bankConfigs: [Int: [ButtonId: PadBehavior]] = [:]
        bankConfigs[0] = [pad1: behavior1]
        bankConfigs[5] = [pad2: behavior2]
        
        // When: Save to file
        let configFile = LaunchpadConfigFile(from: bankConfigs)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configFile)
        try data.write(to: configPath)
        
        // And: Load from file
        let loadedData = try Data(contentsOf: configPath)
        let loadedConfig = try JSONDecoder().decode(LaunchpadConfigFile.self, from: loadedData)
        let restored = loadedConfig.toBankConfigs()
        
        // Then: Both banks restored
        XCTAssertEqual(restored[0]?[pad1]?.label, "Test Scene")
        XCTAssertEqual(restored[5]?[pad2]?.label, "Bank 5 Toggle")
    }
    
    func test_bankIsolation() throws {
        // Given: Different configs for same pad in different banks
        let pad = ButtonId(x: 0, y: 0)
        
        var bankConfigs: [Int: [ButtonId: PadBehavior]] = [:]
        bankConfigs[0] = [pad: PadBehavior(padId: pad, mode: .selector, label: "Bank 0")]
        bankConfigs[1] = [pad: PadBehavior(padId: pad, mode: .toggle, label: "Bank 1")]
        
        // When: Round-trip through file
        let configFile = LaunchpadConfigFile(from: bankConfigs)
        let data = try JSONEncoder().encode(configFile)
        let decoded = try JSONDecoder().decode(LaunchpadConfigFile.self, from: data)
        let restored = decoded.toBankConfigs()
        
        // Then: Each bank has its own config
        XCTAssertEqual(restored[0]?[pad]?.label, "Bank 0")
        XCTAssertEqual(restored[0]?[pad]?.mode, .selector)
        XCTAssertEqual(restored[1]?[pad]?.label, "Bank 1")
        XCTAssertEqual(restored[1]?[pad]?.mode, .toggle)
    }
    
    // MARK: - Legacy v1 Migration Tests
    
    func test_v1FormatParsable() throws {
        // Given: A v1 format config file (flat dict, no version)
        // OscArg synthesized Codable encodes as {"string":{"_0":"value"}}
        let v1Json = """
        {
          "2,3": {
            "padId": { "x": 2, "y": 3 },
            "mode": "selector",
            "group": "scenes",
            "idleColor": 0,
            "activeColor": 21,
            "label": "Legacy Scene",
            "oscAction": { "address": "/scenes/select", "args": [{"string":{"_0":"legacy"}}] },
            "additionalOsc": []
          }
        }
        """
        
        // When: Try to parse as legacy format (flat dict)
        let data = v1Json.data(using: .utf8)!
        let decoder = JSONDecoder()
        
        // Should decode as flat dict (v1 format)
        let legacyDict = try decoder.decode([String: PadBehavior].self, from: data)
        
        // Then: Legacy format worked
        XCTAssertEqual(legacyDict.count, 1)
        XCTAssertEqual(legacyDict["2,3"]?.label, "Legacy Scene")
        XCTAssertEqual(legacyDict["2,3"]?.oscAction?.args.first, .string("legacy"))
    }
    
    // MARK: - File Format Structure Tests
    
    func test_fileFormat_humanReadable() throws {
        // Given: A complete config
        let pad = ButtonId(x: 4, y: 5)
        let behavior = PadBehavior(
            padId: pad,
            mode: .selector,
            group: .scenes,
            idleColor: LP.off,
            activeColor: LP.green,
            label: "My Awesome Scene",
            oscAction: OscCommand(address: "/scenes/select", args: [.string("awesome")]),
            additionalOsc: [
                OscCommand(address: "/controls/intensity", args: [.float(0.75)])
            ]
        )
        
        var bankConfigs: [Int: [ButtonId: PadBehavior]] = [:]
        bankConfigs[2] = [pad: behavior]
        
        let configFile = LaunchpadConfigFile(from: bankConfigs)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configFile)
        try data.write(to: configPath)
        
        // When: Read raw JSON
        let jsonString = try String(contentsOf: configPath, encoding: .utf8)
        
        // Then: Contains expected structure (check key structural elements)
        // Note: JSON encodes forward slashes as \/ so we check for escaped or unescaped
        XCTAssertTrue(jsonString.contains("version"), "Should have version field")
        XCTAssertTrue(jsonString.contains("banks"), "Should have banks field")
        XCTAssertTrue(jsonString.contains("My Awesome Scene"), "Should have label")
        // Check for OSC address (JSON may escape / as \/)
        XCTAssertTrue(jsonString.contains("scenes") && jsonString.contains("select"), "Should have OSC address")
        XCTAssertTrue(jsonString.contains("controls") && jsonString.contains("intensity"), "Should have additionalOsc address")
    }
    
    func test_allBanksSupported() throws {
        // Given: Configs for all 8 banks
        let pad = ButtonId(x: 0, y: 0)
        var bankConfigs: [Int: [ButtonId: PadBehavior]] = [:]
        
        for bank in 0..<8 {
            bankConfigs[bank] = [pad: PadBehavior(padId: pad, mode: .selector, label: "Bank \(bank)")]
        }
        
        // When: Round-trip
        let configFile = LaunchpadConfigFile(from: bankConfigs)
        let data = try JSONEncoder().encode(configFile)
        let decoded = try JSONDecoder().decode(LaunchpadConfigFile.self, from: data)
        let restored = decoded.toBankConfigs()
        
        // Then: All 8 banks preserved
        for bank in 0..<8 {
            XCTAssertEqual(restored[bank]?[pad]?.label, "Bank \(bank)")
        }
    }
    
    // MARK: - OscArg Encoding Tests
    
    func test_oscArg_allTypesEncode() throws {
        // Given: OscCommand with all arg types
        let command = OscCommand(address: "/test", args: [
            .int(42),
            .float(3.14),
            .string("hello"),
            .bool(true)
        ])
        
        let behavior = PadBehavior(
            padId: ButtonId(x: 0, y: 0),
            mode: .oneShot,
            oscAction: command
        )
        
        // When: Encode and decode
        let encoder = JSONEncoder()
        let data = try encoder.encode(behavior)
        let decoded = try JSONDecoder().decode(PadBehavior.self, from: data)
        
        // Then: All args preserved
        let args = decoded.oscAction?.args ?? []
        XCTAssertEqual(args.count, 4)
        XCTAssertEqual(args[0], .int(42))
        XCTAssertEqual(args[1], .float(3.14))
        XCTAssertEqual(args[2], .string("hello"))
        XCTAssertEqual(args[3], .bool(true))
    }
    
    // MARK: - Edge Cases
    
    func test_emptyBankConfigs() throws {
        // Given: Empty config
        let configFile = LaunchpadConfigFile(from: [:])
        
        // When: Round-trip
        let data = try JSONEncoder().encode(configFile)
        let decoded = try JSONDecoder().decode(LaunchpadConfigFile.self, from: data)
        
        // Then: Empty but valid
        XCTAssertEqual(decoded.version, LaunchpadConfigFile.currentVersion)
        XCTAssertEqual(decoded.banks.count, 0)
    }
    
    func test_padWithNoOsc() throws {
        // Given: Pad with no OSC commands (just LED color)
        let behavior = PadBehavior(
            padId: ButtonId(x: 7, y: 7),
            mode: .push,
            idleColor: LP.red,
            activeColor: LP.yellow,
            label: "Indicator Only"
        )
        
        // When: Round-trip
        let data = try JSONEncoder().encode(behavior)
        let decoded = try JSONDecoder().decode(PadBehavior.self, from: data)
        
        // Then: OSC fields nil
        XCTAssertNil(decoded.oscAction)
        XCTAssertNil(decoded.oscOn)
        XCTAssertNil(decoded.oscOff)
        XCTAssertEqual(decoded.additionalOsc.count, 0)
    }
}

