# SwiftVJ Domain Entities

## Overview

SwiftVJ follows the functional core/imperative shell pattern from "Grokking Simplicity". Domain entities are immutable value types (structs/enums) with no dependencies and no side effects. All business logic operates on these pure data structures through pure functions.

**Primary File:** `Sources/SwiftVJCore/Domain/Types.swift`

## Core Domain Entities

### 1. Track (Song Metadata)

**Location:** `Types.swift`

```swift
public struct Track: Sendable, Equatable, Codable
```

**Purpose:** Represents a music track with metadata

**Properties:**
- `artist: String` - Artist name
- `title: String` - Song title
- `album: String` - Album name (optional)
- `duration: Double` - Track length in seconds
- `bpm: Double` - Beats per minute
- `musicalKey: String` - Musical key (e.g., "Am", "C#")

**Computed Properties:**
- `key: String` - Unique identifier: `"\(artist)::\(title)"`
- `displayName: String` - Human-readable: `"\(artist) - \(title)"`

**Usage:**
- Shared across PlaybackModule, PipelineModule, all pipeline steps
- Cache key for lyrics, images, AI analysis
- OSC message payload for track changes

**Immutability:** Fully immutable - all properties are `let`

---

### 2. LyricLine (Timestamped Lyric)

**Location:** `Types.swift`

```swift
public struct LyricLine: Sendable, Equatable, Codable
```

**Purpose:** Single line of lyrics with timing and metadata

**Properties:**
- `timeSec: Double` - When this line should be displayed
- `text: String` - Lyric text content
- `isRefrain: Bool` - Whether this is part of a refrain/chorus
- `keywords: String` - Extracted keywords for visualization

**Methods:**
- `withRefrain(_ isRefrain: Bool) -> LyricLine` - Create copy with refrain flag
- `withKeywords(_ keywords: String) -> LyricLine` - Create copy with keywords

**Usage:**
- LRC parsing (`parseLRC` in Functions.swift)
- Refrain detection (`detectRefrains` in Functions.swift)
- ActiveLineTracker for karaoke timing
- OSC transmission for external displays

**Design Note:** Uses `withX` methods instead of `mutating` for functional immutability

---

### 3. PlaybackState (Current Playback)

**Location:** `Types.swift`

```swift
public struct PlaybackState: Sendable, Equatable
```

**Purpose:** Snapshot of current playback status

**Properties:**
- `track: Track?` - Currently playing track (nil if stopped)
- `position: Double` - Current position in seconds
- `isPlaying: Bool` - Whether track is playing or paused
- `lastUpdate: Date` - When this state was captured
- `source: String` - Source identifier ("vdj", "spotify", etc.)

**Computed Properties:**
- `hasTrack: Bool` - Convenience for track != nil
- `progress: Double` - Normalized progress (0.0 - 1.0)

**Methods:**
- `withPosition(_ position: Double) -> PlaybackState` - Update position
- `withTrack(_ track: Track?) -> PlaybackState` - Update track

**Usage:**
- PlaybackModule maintains current state
- VDJMonitor/SpotifyMonitor produce new states
- SwiftVJApp observes for UI updates

---

### 4. SongCategories (AI Analysis)

**Location:** `Types.swift`

```swift
public struct SongCategory: Sendable, Equatable, Codable, Comparable
public struct SongCategories: Sendable, Equatable, Codable
```

**Purpose:** AI-generated mood/genre categorization

**SongCategory Properties:**
- `name: String` - Category name (e.g., "energetic", "melancholic")
- `score: Double` - Confidence score (0.0 - 1.0)

**SongCategories Properties:**
- `scores: [String: Double]` - All category scores
- `primaryMood: String` - Top-scored category

**Computed Properties:**
- `estimatedEnergy: Double` - Energy level (0.0 - 1.0)
  - High energy: energetic, party, intense, upbeat, dance, hype
  - Low energy: chill, calm, sad, melancholy, ambient, relaxed
- `estimatedValence: Double` - Emotional positivity (-1.0 to 1.0)
  - Positive: happy, joyful, uplifting, fun, love, romantic
  - Negative: sad, dark, angry, melancholy, gloomy, aggressive

**Methods:**
- `getTop(_ n: Int) -> [SongCategory]` - Get top N categories sorted by score
- `score(for category: String) -> Double` - Get score for specific category

**Usage:**
- AIModule produces via LLMClient analysis
- ShaderMatcher uses energy/valence for matching
- PipelineResult includes for caching

---

### 5. PipelineResult (Processing Output)

**Location:** `Types.swift`

```swift
public struct PipelineResult: Sendable, Equatable, Codable
```

**Purpose:** Complete output from track processing pipeline

**Properties (Metadata):**
- `artist: String`
- `title: String`
- `album: String`
- `success: Bool` - Whether pipeline completed successfully

**Properties (Lyrics):**
- `lyricsFound: Bool`
- `lyricsLineCount: Int`
- `lyricsLines: [LyricLine]`
- `refrainLines: [String]`
- `lyricsKeywords: [String]`

**Properties (AI Metadata):**
- `metadataFound: Bool`
- `plainLyrics: String` - Lyrics without timestamps
- `keywords: [String]` - LLM-extracted keywords
- `themes: [String]` - LLM-extracted themes
- `visualAdjectives: [String]` - Visual descriptors

**Properties (AI Analysis):**
- `aiAvailable: Bool`
- `mood: String` - Primary mood category
- `energy: Double` - Energy level
- `valence: Double` - Emotional valence
- `categories: [String: Double]` - Full category scores

**Properties (Shader):**
- `shaderMatched: Bool`
- `shaderName: String`
- `shaderScore: Double` - Match confidence

**Properties (Images):**
- `imagesFound: Bool`
- `imagesFolder: String` - Filesystem path
- `imagesCount: Int`

**Properties (Timing):**
- `stepsCompleted: [String]` - Which steps ran
- `totalTimeMs: Int` - Total processing time

**Usage:**
- PipelineModule returns this as result
- Cached for 7 days to avoid re-processing
- Serialized to JSON for persistence
- Sent via OSC to external apps

---

### 6. PipelineStepStatus (Type-Safe Step Results)

**Location:** `Types.swift`

```swift
public enum PipelineStepStatus: Sendable
```

**Purpose:** Rich, type-safe status for individual pipeline steps

**Cases:**
- `.lyrics(lineCount: Int, refrainCount: Int, keywordCount: Int)`
- `.ai(mood: String, energy: Double, valence: Double, keywords: [String], themes: [String])`
- `.shaders(name: String, score: Double)`
- `.images(count: Int, folder: String, source: String, cached: Bool)`
- `.osc(sent: Bool)`
- `.skipped(reason: String)`
- `.error(message: String)`

**Computed Properties:**
- `displayText: String` - Short UI-friendly string
- `logDetails: [String]` - Detailed log lines

**Usage:**
- PipelineModule fires `onStepComplete` callbacks with this type
- SwiftVJApp displays in PipelineStatusView
- Prevents stringly-typed status codes

**Design Note:** Using enum with associated values for compile-time safety

---

### 7. ShaderInfo (Shader Metadata)

**Location:** `Types.swift`

```swift
public enum ShaderRating: Int, Sendable, Codable, Comparable
public struct ShaderInfo: Sendable, Equatable, Codable
```

**Purpose:** Metadata about a GLSL/Metal shader for matching and rendering

**ShaderRating:**
- `.best = 1` - Highest quality
- `.good = 2` - Good quality
- `.normal = 3` - Standard quality
- `.mask = 4` - Mask/utility shader
- `.skip = 5` - Skip in selection

**ShaderInfo Properties:**
- `name: String` - Shader display name
- `path: String` - Filesystem path
- `folder: String` - Folder categorization (e.g., "glsl", "masks")
- `energyScore: Double` - Energy level (0.0 - 1.0)
- `moodValence: Double` - Emotional tone (-1.0 to 1.0)
- `colorWarmth: Double` - Color temperature (0.0 = cool, 1.0 = warm)
- `motionSpeed: Double` - Animation speed (0.0 = slow, 1.0 = fast)
- `mood: String` - Primary mood descriptor
- `colors: [String]` - Color tags (e.g., ["blue", "purple"])
- `effects: [String]` - Effect tags (e.g., ["particles", "fractal"])
- `rating: ShaderRating` - Quality rating
- `phases: Set<Phase>?` - DJ set phases this fits (optional)
- `metalFunctionName: String?` - Pre-compiled Metal function (nil = runtime compile)

**Usage:**
- ShaderRepository loads from YAML/JSON metadata files
- ShaderMatcher uses energy/valence for matching
- ShadertoyRuntime uses metalFunctionName for rendering
- Phase-aware selection for DJ set flow

---

### 8. ShaderMatchResult (Match Output)

**Location:** `Types.swift`

```swift
public struct ShaderMatchResult: Sendable, Equatable
```

**Purpose:** Result from shader matching algorithm

**Properties:**
- `name: String` - Matched shader name
- `path: String` - Shader file path
- `score: Double` - Match confidence (0.0 - 1.0)
- `energyScore: Double` - Shader's energy
- `moodValence: Double` - Shader's valence
- `mood: String` - Shader's mood

**Usage:**
- ShaderMatcher returns this from `match(energy:valence:)` 
- ShadersModule forwards to PipelineModule
- Includes scoring metadata for debugging/tuning

---

### 9. Phase (DJ Set Phases)

**Location:** `Domain/Phase.swift`

```swift
public enum Phase: String, Sendable, Codable, CaseIterable, Hashable
```

**Purpose:** Phases of a DJ set for context-aware visual selection

**Cases:**
- `.warmup` - Opening (low energy)
- `.buildup` - Rising energy
- `.peak` - Highest energy
- `.breakdown` - Brief rest
- `.cooldown` - Winding down
- `.outro` - Ending

**Static Methods:**
- `from(_ string: String) -> Phase?` - Parse from string

**Usage:**
- ShaderInfo can be tagged with phases
- SwiftVJApp has phase selector (manual or auto-detected)
- Future: LaunchpadModule could have phase-switching banks

**Design Note:** Could be extended with auto-detection based on song analysis

---

### 10. Cache Types

**Location:** `Types.swift`

```swift
public struct CacheEntry: Codable
public struct PipelineCacheData: Codable
```

**Purpose:** Serializable cache structures for pipeline results

**CacheEntry Properties:**
- `key: String` - Track key
- `result: PipelineResult`
- `cachedAt: Date`

**PipelineCacheData Properties:**
- `entries: [CacheEntry]`
- `savedAt: Date`

**Usage:**
- PipelineModule serializes cache to JSON on disk
- 7-day TTL for cached results
- Loaded on module start

---

## Supporting Types (Rendering State)

**Location:** `Sources/SwiftVJCore/Rendering/DisplayStates.swift`

### LyricsDisplayState
- Current/next lyric lines for karaoke display
- Crossfade progress between lines

### RefrainDisplayState
- Refrain text for persistent display
- Visibility flag

### SongInfoDisplayState
- Artist, title, album for song info overlay
- Visibility flag

### ImageDisplayState
- Current/next image URLs
- Crossfade progress
- Cover mode (fill vs. contain)
- Folder navigation state
- Auto-cycle timing (beats per change)

### ShaderDisplayState
- Current shader name
- Shader parameters
- Audio reactive modulation

**Location:** `Sources/SwiftVJCore/Rendering/AudioState.swift`

### AudioState
- Audio frequency band levels
- BPM and beat timing
- Spectrum data
- Used by RenderEngine for audio reactivity

---

## Domain Functions

**Location:** `Sources/SwiftVJCore/Domain/Functions.swift`

### Pure Functions (No Side Effects)

**LRC Parsing:**
- `parseLRC(_ lrc: String) -> [LyricLine]`
  - Parses LRC format (e.g., `[00:12.34]Lyric text`)
  - Returns sorted array of LyricLine

**Lyric Analysis:**
- `analyzeLyrics(_ lines: [LyricLine]) -> [LyricLine]`
  - Detects refrains using similarity scoring
  - Extracts keywords from lyrics
  - Returns updated lines with `isRefrain` and `keywords`

**Refrain Detection:**
- `detectRefrains(_ lines: [LyricLine]) -> [LyricLine]`
  - Implements Jaccard similarity for line matching
  - Groups similar lines as refrains
  - Threshold-based detection

**Keyword Extraction:**
- `extractKeywords(_ text: String) -> String`
  - Filters common words (stop words)
  - Extracts nouns and meaningful words
  - Returns comma-separated keyword list

**Design:** All functions take data, return data. No I/O, no global state, no side effects.

---

## Entity Lifecycle

### Track
1. Created by: VDJMonitor or SpotifyMonitor from OSC/API
2. Flows through: PlaybackModule → PipelineModule → Submodules
3. Persisted in: PipelineResult cache (JSON on disk)

### LyricLine
1. Created by: `parseLRC` from LRCLIB response
2. Enhanced by: `analyzeLyrics` (refrain detection + keyword extraction)
3. Used by: ActiveLineTracker, TextlerOrchestrator
4. Transmitted via: OSC to Synesthesia/Magic for karaoke

### PlaybackState
1. Created by: VDJMonitor/SpotifyMonitor
2. Updated by: PlaybackModule (position interpolation)
3. Observed by: SwiftVJApp (UI binding)
4. Lifetime: Replaced on each poll/update

### PipelineResult
1. Created by: PipelineModule orchestrator
2. Cached in: JSON file (7-day TTL)
3. Returned to: SwiftVJApp for display
4. Transmitted via: OSC to external apps

---

## Data Validation

### Track
- `artist` and `title` required (non-empty)
- `duration` and `bpm` default to 0 (unknown)
- `key` computed property ensures uniqueness

### LyricLine
- `timeSec` must be >= 0
- `text` can be empty (instrumental lines)
- Sorting: Array sorted by `timeSec` in parseLRC

### SongCategories
- `scores` normalized to 0.0-1.0 range
- `primaryMood` computed from highest score
- Energy/valence clamped to valid ranges

### PipelineResult
- All fields have sensible defaults (empty arrays, 0 counts)
- `success` indicates overall pipeline completion
- Individual `*Found` flags track step success

---

## Conclusion and Improvement Opportunities

### Strengths

1. **Pure Immutability** - All domain types are fully immutable value types
2. **Sendable Conformance** - Thread-safe by design for Swift concurrency
3. **Rich Type Safety** - Enums with associated values instead of strings/magic numbers
4. **No Dependencies** - Domain types depend only on Foundation
5. **Comprehensive** - Covers all aspects of VJ workflow (playback, lyrics, AI, shaders, images)

### Areas for Improvement

1. **Validation:**
   - Domain types accept invalid states (e.g., negative `timeSec`, empty `artist`)
   - Consider: Smart constructors or Result-based validation
   - Example: `Track.create(artist:title:)` -> `Result<Track, ValidationError>`

2. **Default Values:**
   - Many optional fields with empty string defaults
   - Consider: Proper Optional usage vs. empty string sentinels
   - Example: `album: String?` instead of `album: String = ""`

3. **Computed Properties:**
   - `SongCategories.estimatedEnergy/Valence` use hardcoded keyword lists
   - Consider: Configuration-driven category mappings
   - Would allow tuning without code changes

4. **Type Explosion:**
   - 20+ types in `Types.swift` (1 file, 487 lines)
   - Consider: Split into multiple files by domain area
   - Example: `TrackTypes.swift`, `LyricsTypes.swift`, `PipelineTypes.swift`

5. **Missing Types:**
   - No dedicated type for OSC messages (using raw arrays)
   - No type for shader parameters/uniforms
   - Consider: Introduce `OSCMessage(address: String, args: [OSCValue])`

6. **Documentation:**
   - Inline comments are sparse
   - Public types need DocC documentation for API reference
   - Example usage snippets would help adoption

7. **Error Handling:**
   - No domain-specific error types
   - Functions return nil/empty on error
   - Consider: `Result` types for operations that can fail

### Recommended Refactorings

**Priority 1 (High Value, Low Risk):**
- Split `Types.swift` into domain-specific files
- Add DocC comments to all public types and methods
- Replace empty string defaults with proper Optionals

**Priority 2 (Medium Value, Medium Risk):**
- Introduce validation layer with smart constructors
- Create dedicated OSC message types
- Add shader parameter value types

**Priority 3 (High Value, High Risk):**
- Consider phantom types for compile-time state validation
- Explore value witnesses for protocol conformance optimization
- Investigate record types (Swift 6 feature) for reduced boilerplate
