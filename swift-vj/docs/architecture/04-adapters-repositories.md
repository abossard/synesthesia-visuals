# SwiftVJ Adapters and Repositories

## Overview

Adapters in SwiftVJ follow the "Deep Modules" principle from "A Philosophy of Software Design". Each adapter wraps one external service or protocol with a simple public interface, hiding all implementation complexity. All adapters are Swift actors for thread-safe state management.

**Location:** `Sources/SwiftVJCore/Adapters/`

**Total Lines:** ~4,047 lines across 9 adapter files

## Adapter Pattern

SwiftVJ adapters implement the **Adapter Pattern** (also known as Wrapper Pattern):
- Each adapter translates between SwiftVJ's domain types and an external service
- Hides protocol details, retries, caching, error handling
- Provides simple, domain-oriented methods
- Actor-isolated for concurrency safety

## Core Adapters

### 1. OSCHub (OSC Communication)

**File:** `OSCClient.swift` (445 lines)

**Type:** `public final class OSCHub: @unchecked Sendable`

**Purpose:** Central hub for all OSC communication (send/receive/subscribe)

**Interface:**
- `start() throws` - Start OSC server (port 9999) and client
- `stop()` - Stop all OSC communication
- `sendToVDJ(_ address: String, values: [any OSCValue]) throws`
- `sendToSynesthesia(_ address: String, values: [any OSCValue]) throws`
- `sendToMagic(_ address: String, values: [any OSCValue]) throws`
- `send(_ address: String, values: [any OSCValue], host: String, port: UInt16) throws`
- `subscribe(pattern: String, handler: OSCMessageHandler)`
- `unsubscribe(pattern: String)`
- `enableLatencyMonitoring()` / `disableLatencyMonitoring()`
- `getLatencyStats() -> OSCLatencyStats`

**Hidden Complexity:**
- OSCKit integration (server + client on same port)
- Port reuse for VDJ response routing
- Pattern matching with PrefixTrie (O(n) prefix matching)
- Three-tier matching: "any" handlers, exact matche, prefix matches
- Message forwarding to Magic (port 11111)
- Latency tracking with statistics
- Thread-safe subscription management with NSLock
- Message queuing and batching

**Port Configuration:**
- Receive port: 9999 (all incoming OSC)
- VDJ port: 9009 (bidirectional - query/response)
- Synesthesia port: 7777 (send visual commands)
- Magic port: 11111 (forward all received messages + explicit sends)

**Pattern Matching:**
- `"*"` or `"/"` or `""` → matches all messages (anyHandlers)
- `"/exact/path"` → exact match (exactHandlers)
- `"/prefix*"` → prefix match (stored in PrefixTrie)

**Usage Example:**
```swift
let hub = OSCHub()
try hub.start()

// Subscribe to VDJ deck messages
hub.subscribe(pattern: "/deck/*") { address, values in
    print("Deck message: \(address)")
}

// Send shader selection to Synesthesia
try hub.sendToSynesthesia("/shader/load", values: ["shader_name", 0.5])
```

**Dependencies:**
- OSCKit (external package)
- PrefixTrie (infrastructure)

---

### 2. LyricsFetcher (LRCLIB API Client)

**File:** `LyricsFetcher.swift` (177 lines)

**Type:** `public actor LyricsFetcher`

**Purpose:** Fetch synced lyrics from LRCLIB.net with LLM fallback

**Interface:**
- `fetch(artist: String, title: String) async throws -> String?`

**Return Format:** LRC string with timestamps:
```
[00:12.34]First line of lyrics
[00:15.67]Second line of lyrics
```

**Hidden Complexity:**
- HTTP requests to LRCLIB API (https://lrclib.net/api/get)
- JSON response parsing (`LRCLibResponse` struct)
- URL encoding of artist/title
- Service health tracking with exponential backoff
- LLM fallback when LRCLIB unavailable (via Config)
- Error type: `LyricsFetcherError` (notFound, networkError, invalidResponse)

**API Flow:**
1. GET request to `/api/get?artist={artist}&track_name={title}`
2. Parse JSON response with fields: `syncedLyrics`, `plainLyrics`, etc.
3. Return `syncedLyrics` if available
4. If no synced lyrics, return nil (caller decides on fallback)

**Error Handling:**
- Network errors: propagated as `.networkError`
- 404 response: returns `nil` (lyrics not found)
- Invalid JSON: `.invalidResponse`
- Service health degradation triggers backoff

**Dependencies:**
- Foundation (URLSession)
- Config (service health, backoff policy)

---

### 3. LLMClient (AI Analysis)

**File:** `LLMClient.swift` (897 lines)

**Type:** `public actor LLMClient`

**Purpose:** AI-powered song analysis via LM Studio (local LLM server)

**Interface:**
- `analyzeSong(artist: String, title: String, lyrics: String?) async throws -> SongAnalysis`
- `extractPlainLyrics(_ lyrics: String) async throws -> String`
- `getBackendInfo() -> String`

**SongAnalysis Output:**
```swift
public struct SongAnalysis: Sendable, Equatable {
    public let keywords: [String]          // Visual keywords
    public let themes: [String]            // Song themes
    public let mood: String                // Primary mood
    public let visualAdjectives: [String]  // Descriptive adjectives
    public let categories: SongCategories  // Full category scores
}
```

**Hidden Complexity:**
- LM Studio HTTP API integration (localhost:1234)
- Backend auto-detection (lmstudio, openai)
- Structured JSON prompt engineering
- Response parsing with validation
- Fallback handling for missing fields
- Service health monitoring
- Token usage tracking (commented out)
- Exponential backoff on failures

**Prompts:**
1. **Song Analysis Prompt** (~300 lines) - Structured JSON output for mood, keywords, themes, categories
2. **Plain Lyrics Extraction** - Remove timestamps from LRC format

**Category Scoring:**
- Energy-based: energetic, chill, intense, mellow, upbeat, slow
- Mood-based: happy, sad, angry, romantic, melancholic, hopeful
- Genre-based: rock, pop, electronic, classical, hip-hop, jazz
- Returns normalized scores (0.0 - 1.0)

**Backend Support:**
- LM Studio (default, localhost:1234)
- OpenAI-compatible APIs (future)
- Auto-detects via `/v1/models` endpoint

**Dependencies:**
- Foundation (URLSession, JSONEncoder/Decoder)
- Types (SongAnalysis, SongCategories)
- Config (LLM endpoint, service health)

---

### 4. SpotifyMonitor (Playback Monitoring)

**File:** `SpotifyMonitor.swift` (166 lines)

**Type:** `public actor SpotifyMonitor`

**Purpose:** Monitor Spotify playback via local API

**Interface:**
- `getPlayback() async throws -> PlaybackState?`

**Hidden Complexity:**
- Spotify local API endpoint (localhost:port)
- JSON response parsing (`SpotifyPlayback` struct)
- Track metadata extraction
- Position and play state tracking
- Error type: `SpotifyMonitorError` (notPlaying, networkError, parseError)

**API Endpoint:**
- Currently uses mock/stub (TODO: implement actual Spotify integration)
- Planned: Spotify Web API or AppleScript control

**Output:**
```swift
public struct SpotifyPlayback: Sendable, Equatable {
    public let artist: String
    public let title: String
    public let album: String
    public let position: Double  // seconds
    public let duration: Double  // seconds
    public let isPlaying: Bool
}
```

**Conversion:** Converts `SpotifyPlayback` → `PlaybackState` (domain type)

**Dependencies:**
- Types (Track, PlaybackState)
- Config (Spotify API endpoint)

**Status:** Stub implementation - needs real Spotify integration

---

### 5. VDJMonitor (VirtualDJ OSC)

**File:** `VDJMonitor.swift` (442 lines)

**Type:** `public actor VDJMonitor`

**Purpose:** Monitor VirtualDJ playback via OSC messages

**Interface:**
- `subscribe(using hub: OSCHub) async throws` - Subscribe to VDJ OSC notifications
- `handleOSC(address: String, values: [any OSCValue]) async` - Process OSC message
- `getPlayback() async throws -> PlaybackState?` - Get current playback state

**VDJ OSC Protocol:**
```
/deck/1/get_title "<title>"
/deck/1/get_artist "<artist>"
/deck/1/get_album "<album>"
/deck/1/get_bpm <bpm>
/deck/1/get_songlength <seconds>
/deck/1/song_pos <0.0-1.0>
/deck/1/play <0|1>
/deck/1/volume <0.0-1.0>
/deck/1/is_audible <0|1>
/deck/2/... (same for deck 2)
/crossfader <0.0-1.0>
```

**Hidden Complexity:**
- Two-deck state tracking (`VDJDeck` per deck)
- Crossfader-based deck selection (audible deck = current)
- Incremental state updates (OSC messages come individually)
- Query/subscribe hybrid model:
  - **Subscribe:** VDJ pushes track changes automatically
  - **Query:** Periodic polling for position/play state
- State diffing to detect track changes
- OSC message parsing and validation
- Deck selection algorithm:
  1. Check `is_audible` flag on each deck
  2. Fallback to crossfader position (< 0.5 = deck1, >= 0.5 = deck2)
  3. Prefer deck with higher volume

**State Types:**
```swift
public struct VDJDeck: Sendable, Equatable {
    public var title: String
    public var artist: String
    public var album: String
    public var bpm: Double
    public var duration: Double
    public var position: Double  // normalized 0-1
    public var isPlaying: Bool
    public var volume: Double
    public var isAudible: Bool
}

public struct VDJPlayback: Sendable, Equatable {
    public let deck: VDJDeck
    public let deckNumber: Int
}
```

**Subscription Flow:**
1. Send `/vdj/subscribe/deck/1/get_title` (and other fields) via OSC
2. VDJ responds to port 9999 with updates on change
3. VDJMonitor accumulates updates in `deck1State` / `deck2State`
4. Query flow polls for position updates (1Hz)

**Dependencies:**
- Types (Track, PlaybackState)
- OSCClient (OSCHub for subscription)
- Config (VDJ OSC endpoint)

---

### 6. ShaderRepository (Shader Metadata Loading)

**File:** `ShaderRepository.swift` (252 lines)

**Type:** `public actor ShaderRepository`

**Purpose:** Load shader metadata from YAML/JSON files

**Interface:**
- `loadShaders(from directory: URL) async throws -> [ShaderInfo]`
- `getAllShaders() async -> [ShaderInfo]`
- `getShader(named name: String) async -> ShaderInfo?`

**Hidden Complexity:**
- Filesystem traversal for shader folders
- YAML/JSON metadata parsing
- ShaderInfo construction with defaults
- Caching loaded shaders in memory
- Error handling for malformed metadata
- Support for multiple metadata formats

**Metadata File Format:**
```yaml
name: "Particle Storm"
energyScore: 0.8
moodValence: 0.3
colorWarmth: 0.6
motionSpeed: 0.9
mood: "intense"
colors: ["blue", "white"]
effects: ["particles", "trails"]
rating: "best"
phases: ["buildup", "peak"]
metalFunctionName: "particle_storm_shader"  # optional
```

**Directory Structure:**
```
Shaders/
  glsl/
    shader1.glsl
    shader1.yaml
  masks/
    mask1.glsl
    mask1.json
```

**Loading Process:**
1. Scan directory for `.glsl` files
2. Look for matching `.yaml` or `.json` metadata
3. Parse metadata or use defaults
4. Construct `ShaderInfo` with file path

**Dependencies:**
- Types (ShaderInfo, ShaderRating, Phase)
- Yams (YAML parsing)
- Foundation (FileManager)

---

### 7. ShaderMatcher (AI-Powered Selection)

**File:** `ShaderMatcher.swift` (646 lines)

**Type:** `public actor ShaderMatcher`

**Purpose:** Match shaders to songs based on AI-generated energy/valence scores

**Interface:**
- `loadShaders(from directory: URL) async throws`
- `match(energy: Double, valence: Double, phase: Phase?) async -> ShaderMatchResult?`
- `getRandomShader(rating: ShaderRating?) async -> ShaderInfo?`
- `getShaderCount() async -> Int`

**Matching Algorithm:**
1. Filter by rating (skip `.skip` shaders)
2. Filter by phase if provided
3. Calculate distance score for each shader:
   ```
   energyDiff = abs(shader.energyScore - songEnergy)
   valenceDiff = abs(shader.moodValence - songValence)
   distance = sqrt(energyDiff^2 + valenceDiff^2)
   score = 1.0 - min(distance / sqrt(2), 1.0)
   ```
4. Sort by score (highest first)
5. Return top match with score > 0.3

**Hidden Complexity:**
- Euclidean distance in 2D space (energy, valence)
- Phase-aware filtering
- Rating-based filtering
- Fallback to random selection if no good match
- Shader analysis structure for debugging

**ShaderAnalysis Output:**
```swift
public struct ShaderAnalysis: Sendable, Codable {
    public let shaderName: String
    public let energyScore: Double
    public let moodValence: Double
    public let distance: Double
    public let score: Double
}
```

**Dependencies:**
- Types (ShaderInfo, ShaderMatchResult, Phase, ShaderRating)
- ShaderRepository (delegates loading)

---

### 8. ImageScraper (DuckDuckGo Search)

**File:** `ImageScraper.swift` (733 lines)

**Type:** `public actor ImageScraper`

**Purpose:** Search and cache images from DuckDuckGo

**Interface:**
- `search(query: String, count: Int) async throws -> ImageResult`
- `getCachedResult(query: String) async -> ImageResult?`
- `clearCache() async`

**ImageResult Output:**
```swift
public struct ImageResult: Sendable {
    public let images: [URL]       // Local file URLs
    public let folder: String       // Cache folder path
    public let source: String       // "duckduckgo" or "cached"
    public let query: String
}
```

**Hidden Complexity:**
- DuckDuckGo image search API (unofficial)
- HTML/JSON parsing
- Image downloading with URLSession
- Filesystem caching (organized by sanitized query)
- Duplicate detection
- Download retry logic
- Error handling for network/parsing failures
- Cache directory management

**Search Flow:**
1. Check cache for existing images (query hash)
2. If cached, return immediately
3. Otherwise, scrape DuckDuckGo:
   - GET `https://duckduckgo.com/?q={query}&iax=images&ia=images`
   - Parse VQD token from HTML
   - GET `https://duckduckgo.com/i.js?...&q={query}&vqd={vqd}`
   - Parse JSON results
4. Download first N images to cache folder
5. Return ImageResult with local URLs

**Caching:**
- Cache directory: `~/Library/Application Support/SwiftVJ/images/{sanitized_query}/`
- Images stored as: `image_001.jpg`, `image_002.jpg`, etc.
- Cache hit = instant return with local URLs
- Cache TTL: infinite (manual clear only)

**Dependencies:**
- Foundation (URLSession, FileManager, JSONDecoder)
- Config (cache directory)
- Types (Track for query generation)

---

### 9. SynesthesiaAudioProcessor (Audio Reactive Data)

**File:** `SynesthesiaAudioProcessor.swift` (289 lines)

**Type:** `public actor SynesthesiaAudioProcessor`

**Purpose:** Accumulate audio reactive data from Synesthesia OSC stream

**Interface:**
- `handleOSCFast(_ address: String, _ values: [any OSCValue])` - Nonisolated fast path
- `getBPM() async -> (bpm: Double, beatCount: Int, measureCount: Int)`
- `getLatestLevels() async -> AudioState?`

**OSC Messages Processed:**
```
/audio/levels <7 float values>          # Frequency bands
/audio/spectrum <128 float values>      # Full spectrum
/audio/bpm <float>                      # BPM
/audio/beat <int>                       # Beat counter
/audio/measure <int>                    # Measure counter
```

**Hidden Complexity:**
- **Nonisolated fast path** - Handles 1000+ messages/sec without MainActor hops
- Atomic state with NSLock
- Frequency band extraction (7 bands: sub-bass, bass, low-mid, mid, high-mid, presence, air)
- RMS level calculation
- Beat and measure counting
- Spectrum data buffering
- AudioState construction

**AudioState Output:**
```swift
public struct AudioState: Sendable, Equatable {
    public let levels: [Float]      // 7-band levels
    public let spectrum: [Float]    // 128-bin spectrum
    public let rms: Float           // Overall level
    public let bpm: Double
    public let beatCount: Int
    public let measureCount: Int
    public let timestamp: Date
}
```

**Performance Optimization:**
- Uses `nonisolated` method for OSC callback (avoids actor isolation overhead)
- Lock-based atomic updates instead of actor re-entrancy
- Minimizes allocations in hot path

**Dependencies:**
- Rendering/AudioState (data types)

---

## Repository Pattern Usage

SwiftVJ uses **Repository Pattern** for data access:
- **ShaderRepository** - Filesystem shader metadata
- **PipelineModule** - Pipeline result cache (JSON file)
- **ImageScraper** - Image cache (filesystem)

Each repository:
- Hides storage implementation (files, database, network)
- Provides domain-oriented query methods
- Handles serialization/deserialization
- Implements caching strategy

---

## Adapter Error Handling

### Error Types

Each adapter defines domain-specific errors:

**LyricsFetcherError:**
- `.notFound` - Lyrics not in LRCLIB database
- `.networkError(Error)` - Network failure
- `.invalidResponse` - Malformed JSON

**SpotifyMonitorError:**
- `.notPlaying` - No active playback
- `.networkError(Error)` - API unavailable
- `.parseError` - Invalid response format

**VDJMonitorError:**
- `.noActiveDeck` - Neither deck playing
- `.invalidMessage` - Malformed OSC message

**OSCHubError:**
- `.notStarted` - Hub not running
- `.sendFailed(String)` - Send operation failed
- `.serverFailed(String)` - Server startup failed

### Error Recovery Strategies

1. **Exponential Backoff** (via Config.BackoffPolicy)
   - LyricsFetcher, LLMClient use service health tracking
   - Automatic retry with increasing delays
   - Circuit breaker pattern to prevent cascading failures

2. **Graceful Degradation**
   - PipelineModule continues on step failure
   - Missing lyrics → AI analysis still runs
   - Failed image search → continues with other steps

3. **Fallback Values**
   - VDJMonitor returns nil if no deck playing
   - ShaderMatcher returns random shader if no match
   - ImageScraper returns cached results on network failure

---

## Concurrency Model

All adapters use **Swift Actors** for thread safety:
- Single point of synchronization per adapter
- No explicit locking needed (compiler-enforced)
- Async/await for all operations
- Sendable conformance for data sharing

**Exception:** `OSCHub` uses `@unchecked Sendable` + NSLock
- Reason: OSCKit callbacks are not actor-isolated
- Manual synchronization required for subscription management

---

## Testing Strategy

### Adapter Testing Approach

**BehaviorTests** (Unit Tests):
- Mock adapters where possible (e.g., LLMClient with canned responses)
- Test domain logic without external dependencies
- Use in-memory caching instead of filesystem

**E2ETests** (Integration Tests):
- Test against real services
- Skip tests if service unavailable (graceful degradation)
- Validate adapter contracts

**Example:**
```swift
// BehaviorTests/LLMClientTests.swift
actor MockLLMClient: LLMProtocol {
    func analyzeSong(...) -> SongAnalysis {
        // Return canned response
    }
}

// E2ETests/LyricsE2ETests.swift
func testRealLRCLIBFetch() async throws {
    guard await Prerequisites.lrclibAvailable() else {
        throw XCTSkip("LRCLIB not available")
    }
    // Test against real API
}
```

---

## Conclusion and Improvement Opportunities

### Strengths

1. **Deep Modules** - Each adapter hides significant complexity behind simple interfaces
2. **Actor Isolation** - Thread-safe by design with Swift concurrency
3. **Domain-Oriented** - Adapters speak in domain terms, not protocol details
4. **Error Handling** - Rich error types with recovery strategies
5. **Caching** - Smart caching reduces network calls (lyrics, images, shaders)

### Areas for Improvement

1. **Protocol Extraction:**
   - Adapters are concrete actors, hard to mock in tests
   - Consider: Extract protocols (`LyricsFetching`, `PlaybackMonitoring`, etc.)
   - Benefits: Easier dependency injection, better testability
   - Trade-off: More boilerplate code

2. **Spotify Integration:**
   - SpotifyMonitor is stub implementation
   - Options:
     - Spotify Web API (requires OAuth)
     - AppleScript control (simpler, macOS-only)
     - Spotilocal API (deprecated but still works)

3. **OSCHub Complexity:**
   - 445 lines doing multiple responsibilities:
     - Server/client lifecycle
     - Message routing (PrefixTrie)
     - Subscription management
     - Forwarding logic
     - Latency monitoring
   - Consider: Split into `OSCReceiver` + `OSCSender` + `OSCRouter`

4. **ImageScraper Robustness:**
   - Relies on DuckDuckGo HTML parsing (brittle)
   - Consider: Official image search APIs (Unsplash, Pexels)
   - Fallback: Local image library browsing

5. **ShaderMatcher Algorithm:**
   - Simple Euclidean distance may not capture visual similarity
   - Consider: Machine learning-based matching
   - Alternative: User feedback loop to improve matches

6. **Caching Strategy:**
   - Different caching approaches across adapters:
     - ImageScraper: Filesystem cache
     - PipelineModule: JSON file cache
     - ShaderRepository: In-memory cache
   - Consider: Unified caching layer with configurable backends

7. **Service Health Monitoring:**
   - Currently embedded in Config
   - Consider: Dedicated `ServiceHealth` actor with metrics
   - Enable Prometheus/StatsD export for monitoring

8. **Error Propagation:**
   - Mix of throws, returns nil, returns default values
   - Consider: Consistent Result<T, E> pattern
   - Benefits: Explicit error handling at call sites

### Recommended Refactorings

**Priority 1 (High Value, Low Risk):**
- Implement real Spotify integration (SpotifyMonitor)
- Extract adapter protocols for testability
- Add DocC comments to all public adapter methods

**Priority 2 (Medium Value, Medium Risk):**
- Unified caching layer across adapters
- Split OSCHub into focused components
- Replace ImageScraper with official API

**Priority 3 (High Value, High Risk):**
- Machine learning shader matching
- Distributed caching (Redis) for multi-instance deployments
- Streaming OSC protocol for high-frequency audio data
