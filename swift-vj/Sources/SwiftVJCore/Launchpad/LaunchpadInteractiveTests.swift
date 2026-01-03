// LaunchpadInteractiveTests.swift - Interactive hardware tests
// Phase 5: MIDI Controller
//
// Debug tutorial-style tests for Launchpad Mini MK3
// Run with: swift run SwiftVJ launchpad-test [test_number]
//
// COORDINATE SYSTEM:
// - y=0-7: 8x8 grid (y=0 is bottom row)
// - y=-1: top row (Up, Down, Left, Right, Session, Drums, Keys, User)
// - x=8: scene launch column (right edge)

import Foundation

/// Interactive test runner for Launchpad hardware
public final class LaunchpadInteractiveTests {
    
    // MARK: - Colors
    
    static let OFF = 0
    static let RED = 5
    static let GREEN = 21
    static let BLUE = 45
    static let YELLOW = 13
    static let CYAN = 37
    static let MAGENTA = 53
    static let WHITE = 3
    static let ORANGE = 9
    static let PINK = 57
    
    static let TOP_ROW_NAMES = ["Up", "Down", "Left", "Right", "Session", "Drums", "Keys", "User"]
    
    // MARK: - Properties
    
    private let midi: MIDIManager
    private var receivedMessages: [MIDIMessage] = []
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    
    // MARK: - Init
    
    public init() {
        self.midi = MIDIManager()
    }
    
    // MARK: - Connection
    
    private func connect() -> Bool {
        print("🔌 Connecting to Launchpad...")
        
        midi.enableAutoReconnect(
            messageCallback: { [weak self] message in
                self?.handleMessage(message)
            },
            connectionCallback: { connected, name in
                if connected {
                    print("✅ Connected to: \(name ?? "Launchpad")")
                } else {
                    print("❌ Disconnected")
                }
            }
        )
        
        // Wait a moment for connection
        Thread.sleep(forTimeInterval: 0.5)
        
        if midi.isConnected {
            print("✅ Launchpad connected in PROGRAMMER mode")
            print()
            return true
        } else {
            print("❌ No Launchpad found!")
            print("   Make sure Launchpad is connected and in Programmer mode")
            print("   (Hold Session → Press orange button → Release)")
            return false
        }
    }
    
    private func disconnect() {
        midi.clearAllLeds()
        midi.disableAutoReconnect()
        midi.disconnect()
    }
    
    // MARK: - Message Handling
    
    private func handleMessage(_ message: MIDIMessage) {
        lock.lock()
        receivedMessages.append(message)
        lock.unlock()
        semaphore.signal()
    }
    
    /// Wait for a button press, return ButtonId
    private func waitForPress(timeout: TimeInterval = 30) -> ButtonId? {
        let deadline = Date().addingTimeInterval(timeout)
        
        while Date() < deadline {
            lock.lock()
            let messages = receivedMessages
            receivedMessages.removeAll()
            lock.unlock()
            
            for msg in messages {
                if msg.isPress, let buttonId = msg.buttonId {
                    return buttonId
                }
            }
            
            _ = semaphore.wait(timeout: .now() + 0.1)
        }
        
        return nil
    }
    
    /// Wait for N unique presses
    private func waitForPresses(count: Int, timeout: TimeInterval = 60) -> [ButtonId] {
        var pressed: [ButtonId] = []
        let deadline = Date().addingTimeInterval(timeout)
        
        while pressed.count < count && Date() < deadline {
            if let buttonId = waitForPress(timeout: 1) {
                if !pressed.contains(buttonId) {
                    pressed.append(buttonId)
                }
            }
        }
        
        return pressed
    }
    
    // MARK: - Test Menu
    
    public func run(testNumber: Int? = nil) {
        guard connect() else { return }
        
        defer { disconnect() }
        
        if let num = testNumber {
            runTest(num)
        } else {
            showMenu()
        }
    }
    
    private func showMenu() {
        print()
        print(String(repeating: "=", count: 50))
        print("🎹 LAUNCHPAD MINI MK3 - INTERACTIVE TESTS")
        print(String(repeating: "=", count: 50))
        print()
        print("  1. LED Color Palette")
        print("  2. Button Feedback")
        print("  3. Flash/Blink Mode")
        print("  4. Top Row Detection")
        print("  5. Scene Buttons (Right Column)")
        print("  6. Learn Mode Simulation")
        print("  7. Pad Mode Test (Selector/Toggle/Push)")
        print("  8. Full FSM Test")
        print()
        print("  all - Run all tests")
        print("  q   - Quit")
        print()
        print("Select test: ", terminator: "")
        
        guard let input = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() else {
            return
        }
        
        if input == "q" {
            return
        } else if input == "all" {
            for i in 1...8 {
                runTest(i)
            }
        } else if let num = Int(input), num >= 1, num <= 8 {
            runTest(num)
        } else {
            print("Unknown test: \(input)")
        }
    }
    
    private func runTest(_ number: Int) {
        switch number {
        case 1: test1_colors()
        case 2: test2_buttonFeedback()
        case 3: test3_flashMode()
        case 4: test4_topRow()
        case 5: test5_sceneButtons()
        case 6: test6_learnModeSimulation()
        case 7: test7_padModes()
        case 8: test8_fullFSM()
        default: print("Unknown test: \(number)")
        }
    }
    
    // ==========================================================================
    // TEST 1: LED Color Palette
    // ==========================================================================
    
    private func test1_colors() {
        print()
        print(String(repeating: "=", count: 50))
        print("TEST 1: LED Color Palette")
        print(String(repeating: "=", count: 50))
        print()
        print("Displaying colors 0-63 on the grid...")
        print("Each row is 8 consecutive colors.")
        print()
        
        // Display colors 0-63
        for row in 0..<8 {
            for col in 0..<8 {
                let color = row * 8 + col
                let padId = ButtonId(x: col, y: row)
                midi.setLed(padId: padId, color: color)
            }
        }
        
        print("Color map (page 1):")
        print("  Row 0 (bottom): colors 0-7")
        print("  Row 7 (top): colors 56-63")
        print()
        print("Press any pad to see colors 64-127...")
        _ = waitForPress()
        
        // Display colors 64-127
        for row in 0..<8 {
            for col in 0..<8 {
                let color = 64 + row * 8 + col
                let padId = ButtonId(x: col, y: row)
                midi.setLed(padId: padId, color: color)
            }
        }
        
        print("Color map (page 2): colors 64-127")
        print("Press any pad to finish...")
        _ = waitForPress()
        
        midi.clearAllLeds()
        print("✅ Color test complete!")
    }
    
    // ==========================================================================
    // TEST 2: Button Feedback
    // ==========================================================================
    
    private func test2_buttonFeedback() {
        print()
        print(String(repeating: "=", count: 50))
        print("TEST 2: Button Feedback")
        print(String(repeating: "=", count: 50))
        print()
        print("Press any pad - it will light up!")
        print("Press 10 different pads to complete the test.")
        print()
        
        let colors = [Self.RED, Self.GREEN, Self.BLUE, Self.YELLOW, Self.CYAN,
                      Self.MAGENTA, Self.ORANGE, Self.PINK, Self.WHITE, 45]
        var pressedCount = 0
        var pressedPads: Set<ButtonId> = []
        
        while pressedCount < 10 {
            if let buttonId = waitForPress() {
                if buttonId.isGrid && !pressedPads.contains(buttonId) {
                    pressedPads.insert(buttonId)
                    let color = colors[pressedCount]
                    midi.setLed(padId: buttonId, color: color)
                    pressedCount += 1
                    print("  Pad \(buttonId) pressed - color \(color) [\(pressedCount)/10]")
                }
            }
        }
        
        print()
        print("✅ Button feedback test complete!")
        print("Press any pad to clear and continue...")
        _ = waitForPress()
        midi.clearAllLeds()
    }
    
    // ==========================================================================
    // TEST 3: Flash Mode
    // ==========================================================================
    
    private func test3_flashMode() {
        print()
        print(String(repeating: "=", count: 50))
        print("TEST 3: Flash/Blink Mode (Simulated)")
        print(String(repeating: "=", count: 50))
        print()
        print("Blinking alternating pads manually...")
        print("(Launchpad native flash uses SysEx, we simulate with timer)")
        print()
        
        // Light initial pattern
        for row in 0..<8 {
            for col in 0..<8 {
                let color = (row + col) % 2 == 0 ? Self.RED : Self.BLUE
                midi.setLed(padId: ButtonId(x: col, y: row), color: color)
            }
        }
        
        print("Red/Blue checkerboard pattern displayed.")
        print("Simulating blink (5 cycles)...")
        
        for cycle in 0..<5 {
            Thread.sleep(forTimeInterval: 0.3)
            // Toggle red pads
            for row in 0..<8 {
                for col in 0..<8 {
                    if (row + col) % 2 == 0 {
                        let color = cycle % 2 == 0 ? Self.OFF : Self.RED
                        midi.setLed(padId: ButtonId(x: col, y: row), color: color)
                    }
                }
            }
            print("  Cycle \(cycle + 1)/5")
        }
        
        print()
        print("Press any pad to continue...")
        _ = waitForPress()
        midi.clearAllLeds()
        print("✅ Flash mode test complete!")
    }
    
    // ==========================================================================
    // TEST 4: Top Row Detection
    // ==========================================================================
    
    private func test4_topRow() {
        print()
        print(String(repeating: "=", count: 50))
        print("TEST 4: Top Row Detection (Control Buttons)")
        print(String(repeating: "=", count: 50))
        print()
        print("TOP ROW BUTTONS (above the 8x8 grid):")
        print("  x=0: Up       x=4: Session")
        print("  x=1: Down     x=5: Drums")
        print("  x=2: Left     x=6: Keys")
        print("  x=3: Right    x=7: User")
        print()
        print("⚠️  Note: Top row uses CC messages, not Note messages")
        print("    Current MIDIManager may not detect them correctly")
        print()
        
        // Light top grid row for reference
        for col in 0..<8 {
            midi.setLed(padId: ButtonId(x: col, y: 7), color: Self.CYAN)
        }
        print("Grid row 7 (top of 8x8) lit cyan for reference.")
        print()
        print("Press the TOP ROW buttons (ABOVE the cyan row)...")
        print("If detected, they will be y=-1 in our coordinate system.")
        print()
        print("Press any grid pad to finish this test...")
        
        while let buttonId = waitForPress() {
            if buttonId.isTopRow {
                let name = buttonId.x < 8 ? Self.TOP_ROW_NAMES[buttonId.x] : "x=\(buttonId.x)"
                print("  ✅ TOP ROW detected: \(buttonId) = \(name)")
            } else if buttonId.isGrid {
                print("  → Grid pad pressed, ending test")
                break
            } else {
                print("  ℹ️ Button: \(buttonId)")
            }
        }
        
        midi.clearAllLeds()
        print("✅ Top row detection test complete!")
    }
    
    // ==========================================================================
    // TEST 5: Scene Buttons (Right Column)
    // ==========================================================================
    
    private func test5_sceneButtons() {
        print()
        print(String(repeating: "=", count: 50))
        print("TEST 5: Scene Buttons (Right Column)")
        print(String(repeating: "=", count: 50))
        print()
        print("Scene launch buttons are x=8 (rightmost column)")
        print()
        
        // Light rightmost grid column for reference
        for row in 0..<8 {
            midi.setLed(padId: ButtonId(x: 7, y: row), color: Self.ORANGE)
        }
        print("Grid column 7 (rightmost of 8x8) lit orange for reference.")
        print()
        print("Press 4 scene buttons (to the RIGHT of orange column)...")
        print()
        
        var detected = 0
        while detected < 4 {
            if let buttonId = waitForPress() {
                if buttonId.isSceneButton {
                    detected += 1
                    print("  ✅ SCENE BUTTON detected: \(buttonId) (row \(buttonId.y)) [\(detected)/4]")
                } else if buttonId.isGrid {
                    print("  ℹ️ Grid pad: \(buttonId) (not scene button)")
                }
            }
        }
        
        midi.clearAllLeds()
        print("✅ Scene button detection complete!")
    }
    
    // ==========================================================================
    // TEST 6: Learn Mode Simulation
    // ==========================================================================
    
    private func test6_learnModeSimulation() {
        print()
        print(String(repeating: "=", count: 50))
        print("TEST 6: Learn Mode Simulation")
        print(String(repeating: "=", count: 50))
        print()
        print("This simulates the learn mode workflow:")
        print("  1. Enter learn mode (all pads pulse)")
        print("  2. Press a pad to select it")
        print("  3. 'Record' an OSC address (simulated)")
        print("  4. Confirm mapping")
        print()
        
        // Simulate learn mode: pulse all pads
        print("LEARN MODE: All pads pulsing (simulated)...")
        for row in 0..<8 {
            for col in 0..<8 {
                midi.setLed(padId: ButtonId(x: col, y: row), color: 1)  // Dim white
            }
        }
        
        print("Press a pad to select it for mapping...")
        if let selectedPad = waitForPress() {
            print("  → Selected: \(selectedPad)")
            midi.setLed(padId: selectedPad, color: Self.YELLOW)
            
            print()
            print("Simulating OSC event recording...")
            print("  (In real use, you'd trigger an OSC event from Synesthesia/VDJ)")
            Thread.sleep(forTimeInterval: 0.5)
            print("  → 'Recorded' OSC: /scene/1/load")
            
            midi.setLed(padId: selectedPad, color: Self.GREEN)
            print()
            print("Mapping confirmed! Pad \(selectedPad) → /scene/1/load")
        }
        
        print()
        print("Press any pad to finish...")
        _ = waitForPress()
        midi.clearAllLeds()
        print("✅ Learn mode simulation complete!")
    }
    
    // ==========================================================================
    // TEST 7: Pad Mode Test
    // ==========================================================================
    
    private func test7_padModes() {
        print()
        print(String(repeating: "=", count: 50))
        print("TEST 7: Pad Mode Test (Selector/Toggle/Push)")
        print(String(repeating: "=", count: 50))
        print()
        
        // Setup 3 pads in different modes
        let selectorPad = ButtonId(x: 0, y: 0)
        let togglePad = ButtonId(x: 2, y: 0)
        let pushPad = ButtonId(x: 4, y: 0)
        
        print("Setting up test pads on bottom row:")
        print("  (0,0) = SELECTOR (radio button behavior)")
        print("  (2,0) = TOGGLE (on/off)")
        print("  (4,0) = PUSH (momentary)")
        print()
        
        // Initial state
        midi.setLed(padId: selectorPad, color: Self.RED)
        midi.setLed(padId: togglePad, color: Self.GREEN)
        midi.setLed(padId: pushPad, color: Self.BLUE)
        
        var toggleState = false
        
        print("Press each pad to see mode behavior:")
        print("  - SELECTOR: turns on, stays on (would deactivate others in group)")
        print("  - TOGGLE: alternates on/off")
        print("  - PUSH: bright while held, dim on release")
        print()
        print("Press grid pad at (7,7) to finish...")
        
        while let buttonId = waitForPress() {
            if buttonId == ButtonId(x: 7, y: 7) {
                print("  → Exit requested")
                break
            }
            
            if buttonId == selectorPad {
                midi.setLed(padId: selectorPad, color: Self.RED + 1)  // Bright
                print("  SELECTOR: activated (would deactivate others in group)")
            } else if buttonId == togglePad {
                toggleState.toggle()
                let color = toggleState ? Self.GREEN + 1 : Self.GREEN - 1
                midi.setLed(padId: togglePad, color: color)
                print("  TOGGLE: now \(toggleState ? "ON" : "OFF")")
            } else if buttonId == pushPad {
                midi.setLed(padId: pushPad, color: Self.BLUE + 1)  // Bright
                print("  PUSH: pressed (would send 1.0)")
                Thread.sleep(forTimeInterval: 0.2)
                midi.setLed(padId: pushPad, color: Self.BLUE - 1)  // Dim
                print("  PUSH: released (would send 0.0)")
            }
        }
        
        midi.clearAllLeds()
        print("✅ Pad mode test complete!")
    }
    
    // ==========================================================================
    // TEST 8: Full FSM Test
    // ==========================================================================
    
    private func test8_fullFSM() {
        print()
        print(String(repeating: "=", count: 50))
        print("TEST 8: Full FSM Test (with LaunchpadModule)")
        print(String(repeating: "=", count: 50))
        print()
        
        // Disconnect our direct connection
        midi.disableAutoReconnect()
        midi.disconnect()
        Thread.sleep(forTimeInterval: 0.3)
        
        // Create module with OSC logging
        var oscLog: [String] = []
        let module = LaunchpadModule(
            oscSender: { command in
                oscLog.append("OSC → \(command.address) \(command.args)")
                print("  📤 OSC: \(command.address) \(command.args)")
            }
        )
        
        print("Starting LaunchpadModule...")
        let connected = module.start()
        
        if !connected {
            print("❌ LaunchpadModule failed to connect")
            print("   Waiting for device...")
            Thread.sleep(forTimeInterval: 2)
        }
        
        let status = module.getStatus()
        print("Status: enabled=\(status.isEnabled), device=\(status.deviceName ?? "none")")
        print()
        
        if status.isEnabled {
            print("Testing pad press flow...")
            print("  1. Configure pad (0,0) as SELECTOR")
            print("  2. Configure pad (1,0) as TOGGLE")
            print()
            
            // Configure pads programmatically
            let behavior1 = PadBehavior(
                padId: ButtonId(x: 0, y: 0),
                mode: .selector,
                group: .scenes,
                idleColor: LaunchpadColor.red.velocities.normal,
                activeColor: LaunchpadColor.red.velocities.bright,
                oscAction: OscCommand(address: "/test/selector", args: [.float(1.0)])
            )
            module.configurePad(ButtonId(x: 0, y: 0), behavior: behavior1)
            
            let behavior2 = PadBehavior(
                padId: ButtonId(x: 1, y: 0),
                mode: .toggle,
                idleColor: LaunchpadColor.green.velocities.normal,
                activeColor: LaunchpadColor.green.velocities.bright,
                oscOn: OscCommand(address: "/test/toggle", args: [.float(1.0)]),
                oscOff: OscCommand(address: "/test/toggle", args: [.float(0.0)])
            )
            module.configurePad(ButtonId(x: 1, y: 0), behavior: behavior2)
            
            print("Pads configured! Press them to see OSC output.")
            print("Press any other pad to continue to learn mode test...")
            print()
            print("(Waiting 10 seconds for pad presses...)")
            Thread.sleep(forTimeInterval: 10)
            
            print()
            print("Testing learn mode...")
            module.startLearnMode()
            print("Learn mode started - FSM should be in .waitingForPad state")
            
            Thread.sleep(forTimeInterval: 3)
            
            module.stopLearnMode()
            print("Learn mode stopped")
        }
        
        print()
        print("OSC messages sent during test:")
        for msg in oscLog {
            print("  \(msg)")
        }
        
        module.stop()
        print()
        print("✅ Full FSM test complete!")
        
        // Reconnect for any remaining tests
        Thread.sleep(forTimeInterval: 0.3)
    }
}

// MARK: - Entry Point

/// Run interactive tests from command line
public func runLaunchpadInteractiveTests(testNumber: Int? = nil) {
    let tests = LaunchpadInteractiveTests()
    tests.run(testNumber: testNumber)
}
