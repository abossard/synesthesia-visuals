# Swift-VJ Code Examples

> Code examples extracted from REWRITE_PLAN.md for reference during implementation.

---

## Domain Types

### Launchpad Domain Types

```swift
struct ButtonId: Hashable {
    let x: Int  // 0-8 (8 = right scene column)
    let y: Int  // 0-7 (0 = bottom, 7 = top row)
    func isGrid() -> Bool  // True if x < 8
}

struct OscCommand {
    let address: String
    let args: [Any]
}

struct PadBehavior {
    let padId: ButtonId
    let mode: PadMode
    let group: ButtonGroupType?
    let idleColor: Int
    let activeColor: Int
    let label: String
    let oscOn: OscCommand?   // TOGGLE mode
    let oscOff: OscCommand?  // TOGGLE mode
    let oscAction: OscCommand?  // SELECTOR/ONE_SHOT/PUSH
}

struct PadRuntimeState {
    let isActive: Bool
    let isOn: Bool
    let currentColor: Int
    let blinkEnabled: Bool
    let ledMode: LedMode
}

struct ControllerState {  // Immutable, all transitions return new instance
    let pads: [ButtonId: PadBehavior]
    let padRuntime: [ButtonId: PadRuntimeState]
    let activeSelectorByGroup: [ButtonGroupType: ButtonId?]
    let activeScene: String?
    let activePreset: String?
    let activeColorHue: Double?
    let beatPhase: Double
    let beatPulse: Bool
    let learnState: LearnState
    let blinkOn: Bool
}
```

### Effect System

```swift
enum Effect {
    case sendOsc(OscCommand)
    case setLed(padId: ButtonId, color: Int, blink: Bool)
    case saveConfig
    case log(message: String, level: LogLevel)
}
```

---

## Module Protocol

```swift
protocol Module {
    var isStarted: Bool { get }
    func start() async throws
    func stop() async
    func getStatus() -> [String: Any]
}
```

---

## Registry Pattern

```swift
class ModuleRegistry {
    // Lazy loading
    lazy var osc: OSCModule
    lazy var playback: PlaybackModule
    lazy var lyrics: LyricsModule
    lazy var ai: AIModule
    lazy var shaders: ShadersModule
    lazy var pipeline: PipelineModule

    func startAll() async
    func stopAll() async
    func wireTrackToPipeline(onComplete:)
}
```

---

## Concurrency Model

```swift
// Module as Actor for thread safety
actor PlaybackModule: Module {
    private var state: PlaybackState

    func start() async throws { ... }
    func stop() async { ... }

    // Callbacks via AsyncStream
    var trackChanges: AsyncStream<Track> { ... }
}
```

---

## OSC Library Usage

```swift
// Basic pattern
let client = OSCClient(host: "127.0.0.1", port: 10000)
client.send(OSCMessage(address: "/shader/load", arguments: ["shader_name", 0.5, 0.3]))

let server = OSCServer(port: 9999)
server.setHandler { message in
    // Route to subscribers
}
```

---

## AppleScript Bridge

```swift
func querySpotify() async throws -> PlaybackInfo? {
    let script = NSAppleScript(source: """
        tell application "Spotify"
            if player state is playing then
                return "{\\"artist\\":\\"" & artist of current track & "\\",\\"title\\":\\"" & name of current track & "\\"}"
            end if
        end tell
    """)

    var error: NSDictionary?
    guard let result = script?.executeAndReturnError(&error) else {
        throw SpotifyError.scriptFailed
    }
    return try JSONDecoder().decode(PlaybackInfo.self, from: result.stringValue!.data(using: .utf8)!)
}
```

---

## JSON Caching

```swift
struct CacheManager {
    let cacheDirectory: URL
    let ttl: TimeInterval = 7 * 24 * 3600 // 7 days

    func load<T: Decodable>(key: String) -> T? {
        let url = cacheDirectory.appendingPathComponent("\(key).json")
        guard let data = try? Data(contentsOf: url) else { return nil }

        // Check TTL
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        if let modified = attrs?[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) > ttl {
            return nil
        }

        return try? JSONDecoder().decode(T.self, from: data)
    }

    func save<T: Encodable>(_ value: T, key: String) {
        let data = try? JSONEncoder().encode(value)
        let url = cacheDirectory.appendingPathComponent("\(key).json")
        try? data?.write(to: url)
    }
}
```

---

## Prerequisite System

```swift
enum Prerequisite {
    case vdjRunning
    case vdjPlaying
    case spotifyRunning
    case lmStudioAvailable
    case internetConnection
    case vjUniverseListening
}

class PrerequisiteChecker {
    private static var confirmed: Set<Prerequisite> = []

    static func require(_ prereq: Prerequisite) throws {
        if !confirmed.contains(prereq) {
            guard check(prereq) else {
                throw XCTSkip("Prerequisite not met: \(prereq)")
            }
            confirmed.insert(prereq)
        }
    }

    private static func check(_ prereq: Prerequisite) -> Bool {
        switch prereq {
        case .internetConnection:
            return canConnect(host: "lrclib.net", port: 443)
        case .lmStudioAvailable:
            return isPortOpen(1234)
        case .vdjRunning:
            return isProcessRunning("VirtualDJ")
        // ...
        }
    }
}
```

---

## Service Detection

```swift
struct ServiceDetector {
    static func isPortOpen(_ port: UInt16) -> Bool {
        let socket = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(socket) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    static func isProcessRunning(_ name: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", name]
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    }
}
```

---

## XCTest Integration

```swift
extension XCTestCase {
    func require(_ prerequisite: Prerequisite, file: StaticString = #file, line: UInt = #line) throws {
        try PrerequisiteChecker.require(prerequisite, file: file, line: line)
    }
}

// Usage in test
func test_vdj_detection() async throws {
    try require(.vdjRunning)
    try require(.vdjPlaying)
    // ... test code
}
```

---

## Example Test Cases

```swift
// BehaviorTest: No external deps, tests pure logic
func test_parseLRC_extractsTimingsCorrectly() {
    let lrc = "[00:05.12]Hello world\n[00:10.00]Goodbye"
    let lines = parseLRC(lrc)

    XCTAssertEqual(lines.count, 2)
    XCTAssertEqual(lines[0].timeSec, 5.12, accuracy: 0.01)
    XCTAssertEqual(lines[0].text, "Hello world")
}

// E2ETest: Requires real service
func test_fetchLyrics_returnsLRCForKnownSong() async throws {
    try PrerequisiteChecker.require(.internetConnection)

    let fetcher = LyricsFetcher()
    let lrc = try await fetcher.fetch(artist: "Queen", title: "Bohemian Rhapsody")

    XCTAssertNotNil(lrc)
    XCTAssertTrue(lrc!.contains("["))
}

// E2ETest: Full pipeline
func test_pipeline_processesTrackEndToEnd() async throws {
    try PrerequisiteChecker.require(.internetConnection)

    let pipeline = PipelineModule()
    try await pipeline.start()

    let result = try await pipeline.process(artist: "Queen", title: "Bohemian Rhapsody")

    XCTAssertTrue(result.success)
    XCTAssertTrue(result.stepsCompleted.contains("lyrics"))
}
```

---

## Launchpad Config YAML Format

```yaml
pads:
  "0,0":
    x: 0
    y: 0
    mode: SELECTOR
    group: scenes
    idle_color: 19
    active_color: 22
    label: AlienCavern
    osc_action:
      address: /scenes/AlienCavern
      args: []
```

---

## OSC Message Formats

**Track Info** `/textler/track`:
```
[active: Int, source: String, artist: String, title: String, album: String, duration: Float, hasLyrics: Int]
```

**Lyrics Line** `/textler/lyrics/line`:
```
[index: Int, time: Float, text: String]
```

**Shader Load** `/shader/load`:
```
[name: String, energy: Float, valence: Float]
```

---

*Extracted from REWRITE_PLAN.md for cleaner documentation*
