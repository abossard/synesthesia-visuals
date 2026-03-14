// LaunchpadYAMLConfigTests.swift - E2E tests for YAML config loading
//
// Tests YAML parsing, validation, error messages, and runtime conversion

import XCTest
import Yams
@testable import SwiftVJCore

final class LaunchpadYAMLConfigTests: XCTestCase {
    
    // MARK: - Basic Loading Tests
    
    func test_loadBundled_succeeds() throws {
        // When: Load the bundled config
        let config = try LaunchpadConfigLoader.loadBundled()
        
        // Then: Basic structure is valid
        XCTAssertEqual(config.version, 1)
        XCTAssertFalse(config.colors.isEmpty)
        XCTAssertFalse(config.groups.isEmpty)
        XCTAssertEqual(config.global.bankButtons.count, 8)
    }
    
    func test_loadBundled_hasAllBanks() throws {
        let config = try LaunchpadConfigLoader.loadBundled()
        
        // All 8 banks should be accessible
        for i in 0..<8 {
            XCTAssertNotNil(config.bank(i), "Bank \(i) should exist")
        }
        XCTAssertNil(config.bank(8), "Bank 8 should not exist")
        XCTAssertNil(config.bank(-1), "Bank -1 should not exist")
    }
    
    // MARK: - Color Resolution Tests
    
    func test_colorResolution() throws {
        let config = try LaunchpadConfigLoader.loadBundled()
        
        // Known colors should resolve to LaunchpadColor cases
        XCTAssertEqual(config.color("red"), .red)
        XCTAssertEqual(config.color("green"), .green)
        XCTAssertEqual(config.color("blue"), .blue)
        XCTAssertEqual(config.color("off"), .off)
        
        // Unknown color returns .off
        XCTAssertEqual(config.color("nonexistent"), .off)
    }
    
    // MARK: - Group Tests
    
    func test_staticGroupItems() throws {
        let config = try LaunchpadConfigLoader.loadBundled()
        
        // Playlists is a static group
        let playlists = config.groupItems("playlists")
        XCTAssertEqual(playlists.count, 8)
        XCTAssertEqual(playlists[0], "Chill Vibes")
        XCTAssertEqual(playlists[1], "High Energy")
    }
    
    func test_dynamicGroupItems_returnsEmpty() throws {
        let config = try LaunchpadConfigLoader.loadBundled()
        
        // Dynamic groups return empty until populated at runtime
        let scenes = config.groupItems("scenes")
        XCTAssertTrue(scenes.isEmpty)
    }
    
    // MARK: - Bank 0 Fixed Pads Tests
    
    func test_bank0_hasFixedPads() throws {
        let config = try LaunchpadConfigLoader.loadBundled()
        
        // Bank 0 should have fixed pads
        let bank0 = config.bank0
        XCTAssertFalse(bank0.pads.isEmpty)
        
        // Row 7 should have 8 playlist selectors
        let row7Pads = bank0.pads.filter { $0.y == 7 }
        XCTAssertEqual(row7Pads.count, 8)
        
        // All row 7 pads should be selectors
        for pad in row7Pads {
            XCTAssertEqual(pad.mode, "selector")
            XCTAssertEqual(pad.group, "playlists")
        }
    }
    
    func test_bank0_playbackControls() throws {
        let config = try LaunchpadConfigLoader.loadBundled()
        let bank0 = config.bank0
        
        // Row 6 should have playback controls
        let row6Pads = bank0.pads.filter { $0.y == 6 }
        
        // Find specific controls
        let playPad = row6Pads.first { $0.x == 0 }
        XCTAssertEqual(playPad?.mode, "toggle")
        XCTAssertEqual(playPad?.label, "Play")
        XCTAssertNotNil(playPad?.oscOn)
        XCTAssertNotNil(playPad?.oscOff)
        
        let nextPad = row6Pads.first { $0.x == 3 }
        XCTAssertEqual(nextPad?.mode, "oneShot")
        XCTAssertEqual(nextPad?.label, "Next")
        XCTAssertEqual(nextPad?.osc?.address, "/playlist/next")
        let pos1Pad = row6Pads.first { $0.x == 4 }
        XCTAssertEqual(pos1Pad?.mode, "oneShot")
        XCTAssertEqual(pos1Pad?.label, "Pos 1")
        XCTAssertEqual(pos1Pad?.osc?.address, "/playlist/position")
    }
    
    func test_bank0_programmableRows() throws {
        let config = try LaunchpadConfigLoader.loadBundled()
        
        // Bank0 now fully fixed
        XCTAssertEqual(config.bank0.programmableRows, [])
        for row in 0..<8 {
          XCTAssertFalse(config.bank0.isRowProgrammable(row), "Row \(row) should be fixed")
        }
    }
    
    // MARK: - Banks 1-7 Tests (with example pads)
    
    func test_banks1to7_haveExamplePads() throws {
        let config = try LaunchpadConfigLoader.loadBundled()
        
        // Bank 1 (Synesthesia): scene/preset selectors on rows 6-7
        let bank1 = config.bank(1)!
        XCTAssertEqual(bank1.programmableRows, [0, 1, 2, 3, 4])
        XCTAssertTrue(bank1.pads.count > 0, "Bank 1 should have example pads")
        
        // Bank 7 (Custom): mostly empty, just panic + save
        let bank7 = config.bank(7)!
        XCTAssertEqual(bank7.programmableRows, [0, 1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(bank7.pads.count, 2, "Bank 7 should have 2 example pads")
    }
    
    // MARK: - Behavior Conversion Tests
    
    func test_selectorBehavior_conversion() throws {
        let config = try LaunchpadConfigLoader.loadBundled()
        
        // Get first playlist selector
        let selectorPad = config.bank0.pads.first { $0.x == 0 && $0.y == 7 }!
        let behavior = config.toBehavior(pad: selectorPad)
        
        XCTAssertEqual(behavior.padId.x, 0)
        XCTAssertEqual(behavior.padId.y, 7)
        XCTAssertEqual(behavior.mode, .selector)
        XCTAssertEqual(behavior.label, "Chill Vibes")
        XCTAssertEqual(behavior.oscAction?.address, "/playlist/select")
        XCTAssertEqual(behavior.oscAction?.args.first, .string("Chill Vibes"))
    }
    
    func test_toggleBehavior_conversion() throws {
        let config = try LaunchpadConfigLoader.loadBundled()
        
        // Get Play toggle
        let togglePad = config.bank0.pads.first { $0.x == 0 && $0.y == 6 }!
        let behavior = config.toBehavior(pad: togglePad)
        
        XCTAssertEqual(behavior.mode, .toggle)
        XCTAssertEqual(behavior.label, "Play")
        XCTAssertEqual(behavior.oscOn?.address, "/playlist/play")
        XCTAssertEqual(behavior.oscOn?.args.first, .int(1))
        XCTAssertEqual(behavior.oscOff?.address, "/playlist/play")
        XCTAssertEqual(behavior.oscOff?.args.first, .int(0))
    }
    
    func test_oneShotBehavior_conversion() throws {
        let config = try LaunchpadConfigLoader.loadBundled()
        
        // Get Next oneShot
        let oneShotPad = config.bank0.pads.first { $0.x == 3 && $0.y == 6 }!
        let behavior = config.toBehavior(pad: oneShotPad)
        
        XCTAssertEqual(behavior.mode, .oneShot)
        XCTAssertEqual(behavior.label, "Next")
        XCTAssertEqual(behavior.oscAction?.address, "/playlist/next")
    }
    
    func test_bankBehaviors_allPads() throws {
        let config = try LaunchpadConfigLoader.loadBundled()
        
        let behaviors = config.bankBehaviors(0)
        
        // Should have all fixed pads
        XCTAssertEqual(behaviors.count, 63)  // full 8x8 minus one pad in row0
        
        // Check specific pads exist
        XCTAssertNotNil(behaviors[ButtonId(x: 0, y: 7)])  // First playlist
        XCTAssertNotNil(behaviors[ButtonId(x: 7, y: 7)])  // Last playlist
        XCTAssertNotNil(behaviors[ButtonId(x: 0, y: 6)])  // Play
    }
    
    // MARK: - Fixed Pad Detection Tests
    
    func test_isFixed_bank0() throws {
        let config = try LaunchpadConfigLoader.loadBundled()
        
        // Fixed pads
        XCTAssertTrue(config.isFixed(bank: 0, x: 0, y: 7))  // Playlist
        XCTAssertTrue(config.isFixed(bank: 0, x: 0, y: 6))  // Play
        
        // All pads are fixed in bank0
        XCTAssertTrue(config.isFixed(bank: 0, x: 0, y: 0))
        XCTAssertTrue(config.isFixed(bank: 0, x: 1, y: 6))
    }
    
    func test_isFixed_programmableBanks() throws {
        let config = try LaunchpadConfigLoader.loadBundled()
        
        // Banks 1-7 now have example pads on some rows
        // Check that programmable rows are truly programmable
        for bankIndex in 1..<8 {
            guard let bank = config.bank(bankIndex) else { continue }
            for row in bank.programmableRows {
                for x in 0..<8 {
                    // Only check pads not defined in the pads array
                    if !bank.pads.contains(where: { $0.x == x && $0.y == row }) {
                        XCTAssertFalse(config.isFixed(bank: bankIndex, x: x, y: row),
                                       "Bank \(bankIndex) pad (\(x),\(row)) should be programmable")
                    }
                }
            }
        }
    }
    
    // MARK: - Global Config Tests
    
    func test_globalBankButtons() throws {
        let config = try LaunchpadConfigLoader.loadBundled()
        
        XCTAssertEqual(config.global.bankButtons.count, 8)
        
        // Check first bank button
        let first = config.global.bankButtons[0]
        XCTAssertEqual(first.cc, 91)
        XCTAssertEqual(first.bank, 0)
        XCTAssertEqual(first.name, "Live")
        
        // Check last bank button
        let last = config.global.bankButtons[7]
        XCTAssertEqual(last.cc, 98)
        XCTAssertEqual(last.bank, 7)
    }
    
    func test_globalSceneButtons() throws {
        let config = try LaunchpadConfigLoader.loadBundled()
        
        XCTAssertEqual(config.global.sceneButtons.count, 7)
        let record = config.global.sceneButtons.first { $0.function == "record" }
        XCTAssertEqual(record?.note, 89)
        let shift = config.global.sceneButtons.first { $0.function == "shift" }
        XCTAssertEqual(shift?.note, 69)
        let page = config.global.sceneButtons.first { $0.function == "page" }
        XCTAssertEqual(page?.note, 79)
        let configurable = config.global.sceneButtons.filter { $0.function == "configurable" }
        XCTAssertEqual(configurable.count, 4)
        XCTAssertEqual(Set(configurable.map { $0.note }), Set([29,39,49,59]))
    }
    
    // MARK: - Error Handling Tests
    
    func test_parseError_missingRequiredField() {
        let invalidYAML = """
        version: 1
        colors:
          off: 0
        # Missing 'groups', 'global', 'bank0', etc.
        """
        
        XCTAssertThrowsError(try LaunchpadConfigLoader.load(from: invalidYAML)) { error in
            let desc = error.localizedDescription
            XCTAssertTrue(desc.contains("Missing required key") || desc.contains("keyNotFound"),
                         "Error should mention missing key: \(desc)")
        }
    }
    
    func test_parseError_invalidColorReference() {
        let invalidYAML = """
        version: 1
        colors:
          off: 0
          red: 5
        groups:
          test:
            type: static
            items: []
        global:
          bankButtons: []
          sceneButtons: []
        bank0:
          name: "Test"
          purpose: "Test"
          pads:
            - { x: 0, y: 0, mode: oneShot, idleColor: nonexistent, activeColor: red }
          programmableRows: []
        bank1:
          name: "B1"
          purpose: "P"
          pads: []
          programmableRows: []
        bank2:
          name: "B2"
          purpose: "P"
          pads: []
          programmableRows: []
        bank3:
          name: "B3"
          purpose: "P"
          pads: []
          programmableRows: []
        bank4:
          name: "B4"
          purpose: "P"
          pads: []
          programmableRows: []
        bank5:
          name: "B5"
          purpose: "P"
          pads: []
          programmableRows: []
        bank6:
          name: "B6"
          purpose: "P"
          pads: []
          programmableRows: []
        bank7:
          name: "B7"
          purpose: "P"
          pads: []
          programmableRows: []
        """
        
        XCTAssertThrowsError(try LaunchpadConfigLoader.load(from: invalidYAML)) { error in
            let desc = error.localizedDescription
            XCTAssertTrue(desc.contains("unknown idleColor 'nonexistent'"),
                         "Error should mention unknown color: \(desc)")
        }
    }
    
    func test_parseError_selectorMissingGroup() {
        let invalidYAML = """
        version: 1
        colors:
          off: 0
        groups: {}
        global:
          bankButtons: []
          sceneButtons: []
        bank0:
          name: "Test"
          purpose: "Test"
          pads:
            - { x: 0, y: 0, mode: selector, index: 0 }
          programmableRows: []
        bank1:
          name: "B1"
          purpose: "P"
          pads: []
          programmableRows: []
        bank2:
          name: "B2"
          purpose: "P"
          pads: []
          programmableRows: []
        bank3:
          name: "B3"
          purpose: "P"
          pads: []
          programmableRows: []
        bank4:
          name: "B4"
          purpose: "P"
          pads: []
          programmableRows: []
        bank5:
          name: "B5"
          purpose: "P"
          pads: []
          programmableRows: []
        bank6:
          name: "B6"
          purpose: "P"
          pads: []
          programmableRows: []
        bank7:
          name: "B7"
          purpose: "P"
          pads: []
          programmableRows: []
        """
        
        XCTAssertThrowsError(try LaunchpadConfigLoader.load(from: invalidYAML)) { error in
            let desc = error.localizedDescription
            XCTAssertTrue(desc.contains("selector mode requires 'group'"),
                         "Error should mention missing group: \(desc)")
        }
    }
    
    func test_parseError_toggleMissingOscOn() {
        let invalidYAML = """
        version: 1
        colors:
          off: 0
        groups: {}
        global:
          bankButtons: []
          sceneButtons: []
        bank0:
          name: "Test"
          purpose: "Test"
          pads:
            - x: 0
              y: 0
              mode: toggle
              oscOff: { address: "/test" }
          programmableRows: []
        bank1:
          name: "B1"
          purpose: "P"
          pads: []
          programmableRows: []
        bank2:
          name: "B2"
          purpose: "P"
          pads: []
          programmableRows: []
        bank3:
          name: "B3"
          purpose: "P"
          pads: []
          programmableRows: []
        bank4:
          name: "B4"
          purpose: "P"
          pads: []
          programmableRows: []
        bank5:
          name: "B5"
          purpose: "P"
          pads: []
          programmableRows: []
        bank6:
          name: "B6"
          purpose: "P"
          pads: []
          programmableRows: []
        bank7:
          name: "B7"
          purpose: "P"
          pads: []
          programmableRows: []
        """
        
        XCTAssertThrowsError(try LaunchpadConfigLoader.load(from: invalidYAML)) { error in
            let desc = error.localizedDescription
            XCTAssertTrue(desc.contains("toggle mode requires 'oscOn' and 'oscOff'"),
                         "Error should mention missing oscOn: \(desc)")
        }
    }
    
    // MARK: - YAMLArg Tests
    
    func test_yamlArg_decodesAllTypes() throws {
        let yaml = """
        intVal: 42
        floatVal: 3.14
        stringVal: "hello"
        boolVal: true
        """
        
        struct TestContainer: Codable {
            let intVal: YAMLArg
            let floatVal: YAMLArg
            let stringVal: YAMLArg
            let boolVal: YAMLArg
        }
        
        let decoder = YAMLDecoder()
        let result = try decoder.decode(TestContainer.self, from: yaml)
        
        XCTAssertEqual(result.intVal, .int(42))
        XCTAssertEqual(result.floatVal, .float(3.14))
        XCTAssertEqual(result.stringVal, .string("hello"))
        XCTAssertEqual(result.boolVal, .bool(true))
    }
    
    func test_yamlArg_toOscArg() throws {
        XCTAssertEqual(YAMLArg.int(42).toOscArg(), OscArg.int(42))
        XCTAssertEqual(YAMLArg.float(3.14).toOscArg(), OscArg.float(3.14))
        XCTAssertEqual(YAMLArg.string("test").toOscArg(), OscArg.string("test"))
        XCTAssertEqual(YAMLArg.bool(true).toOscArg(), OscArg.bool(true))
    }
    
    // MARK: - GlobalLayout Helper Tests
    
    func test_globalLayout_bankButtonCCs() throws {
        let config = try LaunchpadConfigLoader.loadBundled()
        
        // Should have 8 bank buttons
        XCTAssertEqual(config.bankButtonCCs.count, 8)
        XCTAssertEqual(config.bankButtonCCs, [91, 92, 93, 94, 95, 96, 97, 98])
    }
    
    func test_globalLayout_isBankCC() throws {
        let config = try LaunchpadConfigLoader.loadBundled()
        
        XCTAssertTrue(config.isBankCC(91))
        XCTAssertTrue(config.isBankCC(98))
        XCTAssertFalse(config.isBankCC(90))
        XCTAssertFalse(config.isBankCC(99))
    }
    
    func test_globalLayout_bankIndexFromCC() throws {
        let config = try LaunchpadConfigLoader.loadBundled()
        
        XCTAssertEqual(config.bankIndex(fromCC: 91), 0)
        XCTAssertEqual(config.bankIndex(fromCC: 98), 7)
        XCTAssertNil(config.bankIndex(fromCC: 99))
    }
    
    func test_globalLayout_isFixedSceneNote() throws {
        let config = try LaunchpadConfigLoader.loadBundled()
        
        XCTAssertTrue(config.isFixedSceneNote(89))   // record button
        XCTAssertTrue(config.isFixedSceneNote(69))   // shift button
        XCTAssertTrue(config.isFixedSceneNote(39))   // configurable
    }
    
    func test_globalLayout_sceneButtonFunction() throws {
        let config = try LaunchpadConfigLoader.loadBundled()
        
        XCTAssertEqual(config.sceneButtonFunction(89), "record")
        XCTAssertEqual(config.sceneButtonFunction(69), "shift")
        XCTAssertEqual(config.sceneButtonFunction(79), "page")
        XCTAssertEqual(config.sceneButtonFunction(29), "configurable")
        XCTAssertEqual(config.sceneButtonFunction(39), "configurable")
        XCTAssertEqual(config.sceneButtonFunction(49), "configurable")
        XCTAssertEqual(config.sceneButtonFunction(59), "configurable")
    }
    
    func test_bankName_andPurpose() throws {
        let config = try LaunchpadConfigLoader.loadBundled()
        
      XCTAssertEqual(config.bankName(0), "Live")
      XCTAssertEqual(config.bankName(1), "Presets")
      XCTAssertEqual(config.bankPurpose(0), "Live performance scenes")
    }

    func test_bankRoles_includeMetaAndSceneControls() throws {
        let config = try LaunchpadConfigLoader.loadBundled()

        XCTAssertEqual(config.bankRole(5), .meta)
        XCTAssertEqual(config.bankRole(6), .params)
    }

    func test_dynamicColorCyclePalette_loadedFromYAML() throws {
        let config = try LaunchpadConfigLoader.loadBundled()

        let palette = config.dynamic?.colorCyclePalette
        XCTAssertNotNil(palette)
        XCTAssertEqual(palette?.count, 12)
        XCTAssertEqual(palette?.first?.name, "white")
        XCTAssertEqual(palette?.first?.rgb, [1.0, 1.0, 1.0])
    }
    
    // MARK: - DynamicGroupStore Tests
    
    func test_dynamicGroupStore_updateAndRetrieve() async {
        let store = DynamicGroupStore()
        
        // Initially empty
        let initial = await store.items(for: "$synesthesia/scenes")
        XCTAssertTrue(initial.isEmpty)
        
        // Update
        await store.update(source: "$synesthesia/scenes", items: ["Scene1", "Scene2", "Scene3"])
        
        // Retrieve
        let items = await store.items(for: "$synesthesia/scenes")
        XCTAssertEqual(items, ["Scene1", "Scene2", "Scene3"])
    }
    
    func test_dynamicGroupStore_clear() async {
        let store = DynamicGroupStore()
        
        await store.update(source: "$synesthesia/scenes", items: ["Scene1"])
        await store.clear()
        
        let items = await store.items(for: "$synesthesia/scenes")
        XCTAssertTrue(items.isEmpty)
    }

    func test_dynamicControlStore_itemsExcludeMetadata() async {
        let store = DynamicControlStore()
        await store.update(address: "/controls/meta/playbackmode", args: [.float(1.0)])
        await store.update(address: "/controls/meta/playbackmode/numoptions", args: [.int(4)])
        await store.update(address: "/controls/meta/playbackmode/label", args: [.string("shuffle")])

        let items = await store.items()
        XCTAssertEqual(items, ["/controls/meta/playbackmode"])
    }

    func test_dynamicControlStore_metadataRemainsReadable() async {
        let store = DynamicControlStore()
        await store.update(address: "/controls/meta/playbackmode/numoptions", args: [.int(4)])

        let metadata = await store.value(address: "/controls/meta/playbackmode/numoptions")
        XCTAssertEqual(metadata, [.int(4)])
    }
    
    func test_groupItemsAsync_staticGroup() async throws {
        let config = try LaunchpadConfigLoader.loadBundled()
        
        // Static group should return items synchronously
        let items = await config.groupItemsAsync("playlists")
        XCTAssertEqual(items.count, 8)
        XCTAssertEqual(items.first, "Chill Vibes")
    }
    
    func test_groupItemsAsync_dynamicGroup() async throws {
        let config = try LaunchpadConfigLoader.loadBundled()
        
        // Before populating store, dynamic group returns empty
        let emptyItems = await config.groupItemsAsync("scenes")
        XCTAssertTrue(emptyItems.isEmpty)
        
        // Populate store
        await DynamicGroupStore.shared.update(source: "$synesthesia/scenes", items: ["TestScene"])
        
        // Now should return populated items
        let items = await config.groupItemsAsync("scenes")
        XCTAssertEqual(items, ["TestScene"])
        
        // Cleanup
        await DynamicGroupStore.shared.clear()
    }
}
