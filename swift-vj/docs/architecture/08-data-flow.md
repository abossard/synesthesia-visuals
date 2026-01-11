# SwiftVJ Data Flow

## Overview

This document describes the end-to-end data flows in SwiftVJ, from user actions and external events to rendered output. Each flow is documented with sequence diagrams, data transformations, and performance characteristics.

---

## Primary Data Flows

### 1. Track Change Detection and Processing

**Trigger:** New track plays in VirtualDJ

**Flow:** VDJ → SwiftVJ → Pipeline → External Apps

```mermaid
sequenceDiagram
    participant VDJ as VirtualDJ
    participant OSC as OSCHub
    participant VDJMon as VDJMonitor
    participant Playback as PlaybackModule
    participant Pipeline as PipelineModule
    participant Lyrics as LyricsModule
    participant AI as AIModule
    participant Shaders as ShadersModule
    participant Images as ImagesModule
    participant Syn as Synesthesia
    
    Note over VDJ: User loads new track
    VDJ->>OSC: /deck/1/get_title "New Song"
    VDJ->>OSC: /deck/1/get_artist "Artist Name"
    OSC->>VDJMon: handleOSC(address, values)
    VDJMon->>VDJMon: Update deck1State
    VDJMon->>VDJMon: Detect track change
    Playback->>VDJMon: poll (1 Hz)
    VDJMon-->>Playback: PlaybackState (new track)
    Playback->>Playback: Compare with previous
    Note over Playback: Track changed!
    Playback->>Pipeline: trackChangeCallback(track)
    
    Note over Pipeline: Check cache
    Pipeline->>Pipeline: resultCache[track.key]?
    alt Cache hit
        Pipeline-->>Playback: Cached PipelineResult
    else Cache miss
        Note over Pipeline: Process pipeline
        
        par Lyrics Fetching
            Pipeline->>Lyrics: fetch lyrics
            Lyrics->>LRCLIB: HTTP GET
            LRCLIB-->>Lyrics: LRC string
            Lyrics->>Lyrics: parseLRC()
            Lyrics->>Lyrics: analyzeLyrics()
            Lyrics-->>Pipeline: LyricLine[]
        and AI Analysis
            Pipeline->>AI: analyze song
            AI->>LMStudio: HTTP POST (chat completion)
            LMStudio-->>AI: JSON response
            AI->>AI: Parse SongAnalysis
            AI-->>Pipeline: SongAnalysis
        end
        
        Note over Pipeline: Sequential steps
        Pipeline->>Shaders: match shader
        Shaders->>Shaders: Calculate distances
        Shaders-->>Pipeline: ShaderMatchResult
        
        Pipeline->>Images: search images
        Images->>Images: Check cache
        alt Cached
            Images-->>Pipeline: Cached ImageResult
        else Not cached
            Images->>DuckDuckGo: HTTP scrape
            DuckDuckGo-->>Images: Image URLs
            Images->>Images: Download images
            Images-->>Pipeline: ImageResult
        end
        
        Pipeline->>Pipeline: Build PipelineResult
        Pipeline->>Pipeline: Cache result
        
        Note over Pipeline: Send to external apps
        Pipeline->>OSC: sendToSynesthesia(/shader/load)
        OSC->>Syn: OSC message
        Pipeline->>OSC: sendToSynesthesia(/image/folder)
        OSC->>Syn: OSC message
    end
```

**Data Transformations:**

1. **OSC → Domain:**
   - OSC strings → `Track(artist, title, album, duration, bpm)`

2. **LRC → Domain:**
   - LRC string → `[LyricLine(timeSec, text)]`
   - Refrain detection → `isRefrain` flag added
   - Keyword extraction → `keywords` field populated

3. **AI → Domain:**
   - JSON response → `SongAnalysis(keywords, themes, mood, categories)`
   - Categories → `SongCategories(scores, primaryMood, estimatedEnergy, estimatedValence)`

4. **Shader Matching:**
   - `(energy, valence)` → Euclidean distance to each shader
   - Top match → `ShaderMatchResult(name, path, score)`

5. **Images:**
   - Query string → DuckDuckGo scrape
   - URLs → Downloaded files
   - Files → `ImageResult(images, folder, source)`

6. **Pipeline Result:**
   - All intermediate results → `PipelineResult(artist, title, ...all fields...)`
   - Serialized to JSON → Cached on disk

**Performance:**
- **Typical:** 3-5 seconds (parallel lyrics + AI)
- **Cached:** < 10ms (disk read + deserialization)
- **Bottleneck:** AI analysis (~2s with 3B model)

**Error Handling:**
- Missing lyrics → Continue with AI analysis
- AI failure → Use default categories (energy=0.5, valence=0)
- Shader match failure → Random shader selection
- Image search failure → Use cached images if available

---

### 2. Launchpad Button Press to Visual Effect

**Trigger:** User presses Launchpad button

**Flow:** Hardware → MIDI → FSM → OSC → Synesthesia → LED Feedback

```mermaid
sequenceDiagram
    participant LP as Launchpad<br/>Hardware
    participant MIDI as MIDIManager
    participant FSM as LaunchpadFSM
    participant Exec as EffectExecutor
    participant OSC as OSCHub
    participant Syn as Synesthesia
    participant App as SwiftVJApp
    
    Note over LP: User presses button
    LP->>MIDI: MIDI Note On (144, note, velocity)
    MIDI->>MIDI: Parse to MIDIMessage
    MIDI->>FSM: handleMIDIMessage(.noteOn(note, vel))
    FSM->>FSM: noteToGrid(note) → (col, row)
    FSM->>FSM: Get current bank role
    
    alt Scene Bank
        FSM->>FSM: Get scene behavior
        FSM->>Exec: executeEffect(oscAction)
        Exec->>OSC: sendToSynesthesia(address, args)
        OSC->>Syn: /scenes/3/load
        Note over Syn: Scene loads
        Syn-->>OSC: /scenes/3/active 1.0
        OSC->>LP Module: receiveOscEvent
        LP Module->>FSM: updateFromOsc
        FSM->>FSM: Update activeScenes
        FSM->>MIDI: updateLED(col, row, green)
        MIDI->>LP: MIDI Note On (LED)
        Note over LP: LED lights green
    else Control Bank
        FSM->>FSM: Get control behavior
        FSM->>Exec: executeEffect(oscAction, value)
        Exec->>OSC: sendToSynesthesia(address, [value])
        OSC->>Syn: /controls/global/brightness 0.8
    end
    
    Note over App: Update UI state
    LP Module->>App: onStateChange(newState)
    App->>App: Update @Published launchpadState
```

**Data Transformations:**

1. **MIDI → Domain:**
   - MIDI bytes `(144, 57, 127)` → `MIDIMessage.noteOn(note: 57, velocity: 127)`
   - Note 57 → Grid `(col: 6, row: 4)` via `noteToGrid()`

2. **Grid → Behavior:**
   - `(col, row)` → Lookup in `state.pads[ButtonId(col, row)]`
   - Behavior → `PadBehavior(mode, oscAction, onColor, offColor)`

3. **Behavior → OSC:**
   - `oscAction: OscCommand(address, args)` → OSC message
   - `OscArg` enum → OSCKit `OSCValue`

4. **OSC Feedback → LED:**
   - `/scenes/3/active 1.0` → Scene 3 is active
   - Update `activeScenes` set
   - Compute LED color (green if active, dim if inactive)
   - `LaunchpadColor` enum → MIDI velocity value

**Performance:**
- **Latency:** < 10ms (button press → LED update)
- **MIDI Processing:** < 1ms
- **OSC Send:** < 1ms (local UDP)
- **Synesthesia Processing:** ~5-10ms
- **LED Update:** < 1ms

**Modes:**
- **Toggle:** Button alternates on/off, sends OSC on each press
- **Momentary:** OSC sent on press, release sends off value
- **Scene:** Activates scene, deactivates previous (mutually exclusive)

---

### 3. Audio Reactive Rendering

**Trigger:** Synesthesia sends audio levels (60 Hz)

**Flow:** Synesthesia → SwiftVJ → Metal Rendering → Syphon Output

```mermaid
sequenceDiagram
    participant Syn as Synesthesia
    participant OSC as OSCHub
    participant Audio as SynesthesiaAudioProcessor
    participant Engine as RenderEngine
    participant Shader as ShaderManager
    participant Image as ImageManager
    participant Metal as Metal GPU
    participant Syphon as SyphonSender
    participant Magic as Magic Music Visuals
    
    Note over Syn: Audio analysis (60 Hz)
    loop 60 Hz
        Syn->>OSC: /audio/levels [7 floats]
        OSC->>Audio: handleOSCFast (nonisolated)
        Audio->>Audio: Atomic update (NSLock)
        Note over Audio: No MainActor hop
    end
    
    Note over Engine: Render loop (60 fps)
    loop 60 fps
        Engine->>Audio: getLatestLevels()
        Audio-->>Engine: AudioState
        
        Engine->>Shader: getCurrentShader()
        Shader-->>Engine: ShaderInfo
        
        Engine->>Image: getCurrentImage()
        Image-->>Engine: ImageDisplayState
        
        Note over Engine: Update uniforms
        Engine->>Engine: Build uniform buffer
        Engine->>Engine: Set shader parameters
        
        Note over Engine: Render shader pass
        Engine->>Metal: Encode render commands
        Metal->>Metal: Execute shader
        Metal-->>Engine: Rendered texture
        
        Note over Engine: Composite images
        Engine->>Engine: Crossfade current → next
        Engine->>Metal: Blend images
        Metal-->>Engine: Composited texture
        
        Note over Engine: Render lyrics (optional)
        Engine->>Engine: Get current lyric line
        Engine->>Metal: Draw text overlay
        Metal-->>Engine: Final frame
        
        Note over Engine: Output
        Engine->>Syphon: publishFrame(texture)
        Syphon->>Syphon: IOSurface share
        Syphon-->>Magic: Syphon frame available
        Note over Magic: Renders frame
    end
```

**Data Transformations:**

1. **OSC → Audio State:**
   - `/audio/levels [f1, f2, ..., f7]` → `AudioState(levels: [Float], ...)`
   - 7 bands: sub-bass, bass, low-mid, mid, high-mid, presence, air

2. **Audio State → Shader Uniforms:**
   - `AudioState.levels[1]` (bass) → `uniform float bass_level`
   - `AudioState.rms` → `uniform float overall_level`
   - `AudioState.spectrum` → `uniform sampler1D spectrum_texture`

3. **Image State → Textures:**
   - `currentImageURL` → Load to `MTLTexture`
   - `nextImageURL` → Load to `MTLTexture`
   - `crossfadeProgress` (0.0-1.0) → Blend factor

4. **Shader Execution:**
   - Vertex shader → Full-screen quad
   - Fragment shader → Per-pixel color
   - Uniforms + Textures → Final color output

5. **Syphon Output:**
   - `MTLTexture` → IOSurface-backed texture
   - IOSurface → Shared memory (zero-copy)
   - Other apps read same memory

**Performance:**
- **Audio OSC Rate:** ~1000 messages/sec
- **Render Frame Rate:** 60 fps (16.67ms per frame)
- **Frame Budget:**
  - Shader execution: ~10ms
  - Image compositing: ~2ms
  - Lyrics rendering: ~1ms
  - Syphon publish: ~1ms
  - Overhead: ~2ms
- **Typical Frame Time:** ~14ms (within budget)

**Optimization:**
- **Nonisolated Audio Path:** Avoids 1000+ MainActor hops/sec
- **Atomic Updates:** NSLock instead of actor re-entrancy
- **Shader Caching:** Pre-compiled Metal shaders
- **Texture Pooling:** Reuse textures across frames
- **IOSurface Sharing:** Zero-copy Syphon output

---

### 4. Manual Shader Selection

**Trigger:** User selects shader in UI

**Flow:** SwiftUI → AppState → RenderEngine → Synesthesia

```mermaid
sequenceDiagram
    participant User
    participant UI as ShaderBrowserView
    participant App as AppState
    participant Engine as RenderEngine
    participant Shader as ShaderManager
    participant OSC as OSCHub
    participant Syn as Synesthesia
    
    Note over User: Clicks shader in browser
    User->>UI: Tap "Particle Storm"
    UI->>App: selectShader("particle_storm")
    App->>App: selectedShader = "particle_storm"
    Note over App: Persist to UserDefaults
    App->>App: UserDefaults.set(shader, key)
    
    Note over App: Sync to render engine
    App->>Engine: shaderManager.selectShader(name)
    Engine->>Shader: selectShader(name)
    Shader->>Shader: Load shader from repo
    Shader->>Shader: Compile Metal pipeline
    Shader->>Shader: currentShader = shaderInfo
    Shader-->>Engine: Success
    
    Note over App: Send to Synesthesia
    App->>OSC: sendToMagic(/shader/load, [name, 0.5, 0.0])
    OSC->>Syn: OSC message
    Note over Syn: Loads shader
    
    Note over Engine: Render loop picks up new shader
    Engine->>Shader: getCurrentShader()
    Shader-->>Engine: ShaderInfo (particle_storm)
    Engine->>Engine: Render with new shader
```

**Data Transformations:**

1. **UI → Domain:**
   - Button tap → `String` shader name
   - Name → Lookup in shader repository

2. **Shader Loading:**
   - Name → `ShaderInfo` (metadata)
   - GLSL file → MSL wrapper generation
   - MSL → Metal library compilation
   - Library → `MTLRenderPipelineState`

3. **State Sync:**
   - `selectedShader` (AppState) → UserDefaults persistence
   - AppState → RenderEngine (via observer)
   - RenderEngine → Metal pipeline update

**Performance:**
- **UI Response:** < 50ms
- **Shader Compilation:** ~100-500ms (first time)
- **Cached Compilation:** < 10ms
- **Pipeline Switch:** < 5ms

---

### 5. VDJ Playback Position Polling

**Trigger:** Timer (1 Hz polling)

**Flow:** SwiftVJ → VDJ → SwiftVJ → UI Update

```mermaid
sequenceDiagram
    participant Timer
    participant App as SwiftVJApp
    participant OSC as OSCHub
    participant VDJ
    participant VDJMon as VDJMonitor
    participant Playback as PlaybackModule
    
    Note over Timer: 1 second elapsed
    Timer->>App: Timer fires
    App->>OSC: sendToVDJ(/vdj/query/deck/1/song_pos)
    OSC->>VDJ: OSC message
    VDJ-->>OSC: /deck/1/song_pos 0.456
    OSC->>VDJMon: handleOSC(address, values)
    VDJMon->>VDJMon: deck1State.position = 0.456
    
    Note over Playback: Next poll cycle
    Playback->>VDJMon: poll()
    VDJMon->>VDJMon: Get active deck
    VDJMon->>VDJMon: Build PlaybackState
    VDJMon-->>Playback: PlaybackState
    
    Playback->>Playback: Compare with previous
    Note over Playback: Position changed
    Playback->>App: positionUpdateCallback(position, isPlaying)
    App->>App: playbackPosition = position
    App->>App: isPlaying = true
    Note over App: SwiftUI auto-updates
```

**Data Transformations:**

1. **Query → Response:**
   - `/vdj/query/deck/1/song_pos` → `/deck/1/song_pos [0.456]`
   - Normalized position (0.0-1.0)

2. **Position → Time:**
   - `position * track.duration` → Absolute time (seconds)
   - Used for lyrics timing, image auto-advance

3. **Deck Selection:**
   - Check `deck1State.isAudible` and `deck2State.isAudible`
   - Fallback to crossfader position (< 0.5 = deck1)
   - Select active deck → `PlaybackState`

**Performance:**
- **Query Rate:** 1 Hz (not time-critical)
- **VDJ Response:** < 10ms
- **State Update:** < 1ms
- **UI Update:** Next frame (16.67ms)

---

### 6. Image Auto-Advance (Beat-Sync)

**Trigger:** Beat counter from Synesthesia

**Flow:** Synesthesia → SwiftVJ → Image Crossfade

```mermaid
sequenceDiagram
    participant Syn as Synesthesia
    participant OSC as OSCHub
    participant Audio as SynesthesiaAudioProcessor
    participant Engine as RenderEngine
    participant Image as ImageManager
    
    Note over Syn: Beat detected
    Syn->>OSC: /audio/beat 42
    OSC->>Audio: handleOSCFast
    Audio->>Audio: beatCount = 42
    
    Note over Engine: Render loop
    Engine->>Audio: getLatestLevels()
    Audio-->>Engine: AudioState (beatCount: 42)
    
    Engine->>Image: checkBeatAdvance(beatCount)
    Image->>Image: lastBeat = 38
    Image->>Image: beatsPerChange = 8
    Image->>Image: 42 - 38 >= 8?
    alt Time to advance
        Image->>Image: nextIndex = (current + 1) % count
        Image->>Image: state.currentImageURL = images[nextIndex]
        Image->>Image: state.nextImageURL = images[nextIndex + 1]
        Image->>Image: state.crossfadeProgress = 0.0
        Image->>Image: state.isFading = true
        Image->>Image: lastBeat = 42
    end
    
    Note over Engine: Render with crossfade
    Engine->>Engine: progress += deltaTime / fadeDuration
    Engine->>Engine: mix(current, next, progress)
```

**Data Transformations:**

1. **Beat Counter:**
   - OSC `[42]` → `beatCount: Int`
   - Monotonically increasing

2. **Beat Difference:**
   - `currentBeat - lastAdvanceBeat` → Beats elapsed
   - `>= beatsPerChange` → Trigger advance

3. **Crossfade:**
   - `progress: 0.0 → 1.0` over fade duration (e.g. 0.5 seconds)
   - `mix(currentImage, nextImage, progress)` → Blended output

**Performance:**
- **Beat Rate:** ~120 BPM = 2 beats/sec
- **Advance Check:** Every frame (60 fps)
- **Crossfade Duration:** ~30 frames (0.5 sec @ 60 fps)

---

## State Management Data Flow

### AppState Updates

```mermaid
graph LR
    User[User Action] --> UI[SwiftUI View]
    UI --> AppState[@Published Properties]
    
    VDJ[VDJ OSC] --> Playback[PlaybackModule]
    Playback --> Callback[Callback to AppState]
    Callback --> AppState
    
    Pipeline[PipelineModule] --> Callback
    Launchpad[LaunchpadModule] --> Callback
    
    AppState --> SwiftUI[SwiftUI Auto-Update]
    
    style AppState fill:#ff6b6b
```

**Published Properties:**
- `currentTrack: Track?`
- `playbackPosition: Double`
- `isPlaying: Bool`
- `selectedShader: String?`
- `pipelineResult: PipelineResult?`
- `launchpadState: ControllerState?`

**Update Sources:**
1. **User Actions:** Direct `@Published` updates
2. **Module Callbacks:** Async tasks update `@Published` on MainActor
3. **OSC Events:** Forwarded through modules → callbacks → AppState

---

## Cache Data Flow

### Pipeline Result Caching

```mermaid
sequenceDiagram
    participant Pipeline as PipelineModule
    participant Memory as In-Memory Cache
    participant Disk as JSON File Cache
    
    Note over Pipeline: Startup
    Pipeline->>Disk: Load cache from disk
    Disk-->>Pipeline: PipelineCacheData
    Pipeline->>Memory: Populate resultCache
    
    Note over Pipeline: Process track
    Pipeline->>Memory: resultCache[track.key]?
    alt Cache hit
        Memory-->>Pipeline: PipelineResult (instant)
    else Cache miss
        Pipeline->>Pipeline: Process pipeline (3-5 sec)
        Pipeline->>Memory: resultCache[track.key] = result
        Pipeline->>Disk: Schedule save
    end
    
    Note over Pipeline: Shutdown
    Pipeline->>Memory: Get all entries
    Memory-->>Pipeline: [CacheEntry]
    Pipeline->>Disk: Save as JSON
```

**Cache Key:** `"\(artist)::\(title)"` (from `Track.key`)

**TTL:** 7 days (configurable)

**Serialization:** JSON via `Codable`

**Storage:** `~/Library/Application Support/SwiftVJ/pipeline/pipeline_cache.json`

---

## Performance Bottlenecks

### Identified Bottlenecks

1. **AI Analysis:** ~2 seconds (using llama-3.2-3b-instruct)
   - **Mitigation:** Parallel execution with lyrics fetch
   - **Alternative:** Smaller model (1B) or GPU acceleration

2. **Image Download:** ~1-3 seconds (DuckDuckGo scrape + download)
   - **Mitigation:** Background task, don't block pipeline
   - **Alternative:** Pre-download popular artists

3. **Shader Compilation:** ~100-500ms (first load)
   - **Mitigation:** Pre-compile to `.metallib`
   - **Alternative:** Lazy compilation in background

4. **Audio OSC Flood:** ~1000 messages/sec
   - **Mitigation:** Nonisolated fast path (no MainActor)
   - **Alternative:** Batch messages (OSC bundles)

---

## Conclusion

SwiftVJ's data flows demonstrate:

1. **Clear Separation:** Domain → Adapters → Modules → App
2. **Async Orchestration:** Pipeline coordinates independent tasks
3. **Low-Latency Paths:** Audio and MIDI optimized for real-time
4. **Graceful Degradation:** Missing data doesn't block pipeline
5. **Smart Caching:** Avoid redundant network/AI calls

**Key Optimization:** Nonisolated audio path avoids 1000+ MainActor hops/sec while maintaining thread safety via NSLock.

**Future Improvements:**
- Unidirectional data flow (eliminate callbacks)
- Reactive pipelines (Combine publishers)
- Distributed caching (multi-machine setups)
- WebSocket OSC (remote VJ control)
