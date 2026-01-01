# VJUniverse Addendum: Visual Rendering for Swift-VJ

> **Source**: `processing-vj/src/VJUniverse/` (~15,000 LOC Processing/Java)
> **Target**: Integrated into Swift-VJ as unified macOS app
> **Key Difference**: No OSC for internal communication - direct module integration

---

## Table of Contents

1. [Architecture Changes](#1-architecture-changes)
2. [Visual Rendering Feature Inventory](#2-visual-rendering-feature-inventory)
3. [Rendering Domain Types](#3-rendering-domain-types)
4. [Tile System Design](#4-tile-system-design)
5. [Audio Reactivity System](#5-audio-reactivity-system)
6. [GLSL Shader Rendering](#6-glsl-shader-rendering)
7. [Text Rendering System](#7-text-rendering-system)
8. [Image Rendering System](#8-image-rendering-system)
9. [Syphon Output](#9-syphon-output)
10. [Implementation Phases (Visual)](#10-implementation-phases-visual)
11. [Metal/Swift Considerations](#11-metalswift-considerations)
12. [Reference Files](#12-reference-files)

---

## 1. Architecture Changes

### 1.1 Unified App (No OSC for Internal Communication)

The Python-VJ control system and VJUniverse rendering system become **one Swift app**:

```
┌─────────────────────────────────────────────────────────────────┐
│                      SwiftUI Application                         │
│    Control Panel │ Shader Preview │ Lyrics │ Visual Outputs     │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│                     Module Registry                              │
│   OSC │ Playback │ Lyrics │ AI │ Shaders │ Pipeline │ Render   │
└────────────────────────────┬────────────────────────────────────┘
                             │
              ┌──────────────┴──────────────┐
              ▼                              ▼
┌─────────────────────────┐    ┌─────────────────────────────────┐
│   Control Modules       │    │   Rendering Engine               │
│   (from python-vj)      │    │   (from VJUniverse)              │
│   - Track detection     │    │   - ShaderTile (GLSL via Metal) │
│   - Lyrics fetching     │────│   - TextTile (lyrics/refrain)   │
│   - AI categorization   │    │   - ImageTile (crossfade)       │
│   - Shader matching     │    │   - TileManager (compositing)   │
└─────────────────────────┘    │   - SyphonOutputs (streaming)   │
                               └─────────────────────────────────┘
```

### 1.2 Direct Integration (No OSC Middleware)

**Before (VJUniverse):**
```
Python-VJ ─OSC→ VJUniverse (port 10000)
           │
           ├─ /textler/track [artist, title, ...]
           ├─ /textler/lyrics/line [index, time, text]
           ├─ /shader/load [name, energy, valence]
           └─ /audio/level/* [bass, mid, high, ...]
```

**After (Swift-VJ):**
```swift
// Direct module-to-module communication
pipelineModule.onTrackProcessed { result in
    renderEngine.lyricsState.setLines(result.lyricsLines)
    renderEngine.shaderTile.loadShader(result.shaderName)
}

playbackModule.onPositionUpdate { position in
    renderEngine.lyricsState.setPosition(position)
}

audioAnalyzer.onLevelsUpdate { levels in
    renderEngine.audioState.update(levels)
}
```

---

## 2. Visual Rendering Feature Inventory

### 2.1 GLSL Shader Rendering

| Feature | Description | VJUniverse Source |
|---------|-------------|-------------------|
| Shader Loading | Load .glsl/.txt/.frag files | `ShaderManager.pde:99-172` |
| GLSL Conversion | Add precision, inject uniforms | `ShaderManager.pde:181-223` |
| Audio Uniforms | bass, mid, highs, kickEnv, beat, etc. | `ShaderManager.pde:254-269` |
| Time Scaling | Audio-reactive time (audioTime) | `SynesthesiaAudioOSC.pde:454-504` |
| Synthetic Mouse | Lissajous curve modulated by audio | `VJUniverse.pde` |
| Rating Filter | Only show BEST/GOOD shaders (rating 1-2) | `ShaderManager.pde:401-464` |
| Auto-reload | Watch directory for changes | `ShaderManager.pde:56-78` |

### 2.2 Audio Reactivity

| Feature | Description | VJUniverse Source |
|---------|-------------|-------------------|
| Band Levels | bass, lowMid, mid, highs (smoothed) | `SynesthesiaAudioOSC.pde:36-40` |
| Energy Envelopes | energyFast (responsive), energySlow (sustained) | `SynesthesiaAudioOSC.pde:47-48` |
| Kick Detection | kickEnv (envelope), kickPulse (trigger) | `SynesthesiaAudioOSC.pde:42-43` |
| Beat Phase | beatPhaseAudio (0-1 decaying) | `SynesthesiaAudioOSC.pde:44` |
| BPM Sync | bpmTwitcher, bpmSin4 (tempo LFOs) | `SynesthesiaAudioOSC.pde:62-63` |
| Speed Ramping | Gradual buildup/decay based on volume | `SynesthesiaAudioOSC.pde:454-504` |
| Audio Bindings | Map audio → shader uniform | `SynesthesiaAudioOSC.pde:129-194` |
| Timeout Decay | Fade to silence when no audio | `SynesthesiaAudioOSC.pde:390-410` |

### 2.3 Text Rendering

| Feature | Description | VJUniverse Source |
|---------|-------------|-------------------|
| Multi-line Lyrics | prev/current/next lines with visual hierarchy | `Tile.pde:732-796` |
| Refrain Display | Larger, centered chorus text | `Tile.pde:799-825` |
| Song Info | Artist/title with fade-in/hold/fade-out | `Tile.pde:827-852` |
| Auto-sizing | Calculate font size to fit container | `TextRenderer.pde` |
| Text Wrapping | Wrap long lines to max width | `TextRenderer.pde` |
| Fade Animations | Opacity transitions per text slot | `Tile.pde:260-280` |
| Broadcast Messages | Overlay messages (T key to type) | `TextRenderer.pde` |

### 2.4 Image Rendering

| Feature | Description | VJUniverse Source |
|---------|-------------|-------------------|
| Async Loading | Non-blocking image load | `ImageTile.pde:200-244` |
| Crossfade | Smooth transition between images | `ImageTile.pde:250-281` |
| Aspect Ratio | Contain (letterbox) or Cover (crop) | `ImageTile.pde:146-181` |
| Folder Mode | Load all images from directory | `ImageTile.pde:296-339` |
| Beat Cycling | Change image on beat (1, 4, 8 beats) | `ImageTile.pde:371-386` |
| Easing | Quadratic ease-in-out for crossfade | `ImageTile.pde:286-290` |

### 2.5 Syphon Output

| Feature | Description | VJUniverse Source |
|---------|-------------|-------------------|
| Multiple Servers | 7 independent Syphon outputs | `Tile.pde:36`, `TileManager.pde` |
| Per-tile Buffers | 1280x720 P3D buffers | `Tile.pde:55-69` |
| Transparent BG | Alpha channel for compositing | `Tile.pde:169-175` |
| Frame Streaming | Send buffer each frame | `Tile.pde:88-93` |

### 2.6 NOT Porting (Excluded Features)

| Feature | Reason |
|---------|--------|
| VJSims Levels | User specified exclusion (42 3D procedural levels) |
| OSC Audio Input | Internal audio analysis instead |
| OSC Message Log | Replaced by internal pub/sub |
| Debug Overlays | Will have Swift debug views |

---

## 3. Rendering Domain Types

### 3.1 Audio State (Immutable Snapshot)

```swift
/// Audio analysis state snapshot - immutable
struct AudioState: Sendable {
    // Band levels (0.0 - 1.0)
    let bass: Float
    let lowMid: Float
    let mid: Float
    let highs: Float
    let level: Float  // Overall

    // Energy envelopes
    let energyFast: Float  // Responsive
    let energySlow: Float  // Sustained

    // Beat/kick
    let kickEnv: Float      // 0-1 envelope
    let kickPulse: Bool     // True on kick hit
    let beatPhase: Float    // 0-1 decaying

    // Tempo sync
    let beat4: Int          // 0-3 beat counter
    let bpmTwitcher: Float  // Sawtooth LFO
    let bpmSin4: Float      // 4-beat sine LFO
    let bpmConfidence: Float

    // Audio-reactive speed
    let speed: Float        // 0.02 - 1.20

    // Computed
    var isActive: Bool { level > 0.01 }
}
```

### 3.2 Lyrics State

```swift
/// Lyrics display state
struct LyricsDisplayState: Sendable {
    let lines: [LyricLine]
    let activeIndex: Int
    let textOpacity: Float  // 0-255

    var prevLine: String? {
        guard activeIndex > 0 else { return nil }
        return lines[activeIndex - 1].text
    }

    var currentLine: String? {
        guard activeIndex >= 0, activeIndex < lines.count else { return nil }
        return lines[activeIndex].text
    }

    var nextLine: String? {
        guard activeIndex + 1 < lines.count else { return nil }
        return lines[activeIndex + 1].text
    }
}
```

### 3.3 Refrain State

```swift
struct RefrainDisplayState: Sendable {
    let text: String
    let opacity: Float  // 0-255
    let active: Bool
}
```

### 3.4 Song Info State

```swift
struct SongInfoDisplayState: Sendable {
    let artist: String
    let title: String
    let album: String
    let opacity: Float      // 0-255
    let displayTime: Float  // Seconds since shown
    let active: Bool

    // Fade envelope timing
    static let fadeInDuration: Float = 0.5
    static let holdDuration: Float = 5.0
    static let fadeOutDuration: Float = 1.0
}
```

### 3.5 Image State

```swift
struct ImageDisplayState: Sendable {
    let currentImage: CGImage?
    let nextImage: CGImage?
    let crossfadeProgress: Float  // 0.0 - 1.0
    let isFading: Bool
    let coverMode: Bool  // true = cover, false = contain

    // Folder mode
    let folderImages: [URL]
    let folderIndex: Int
    let beatsPerChange: Int  // 0 = manual
}
```

### 3.6 Shader State

```swift
struct ShaderDisplayState: Sendable {
    let name: String
    let path: String
    let rating: ShaderRating
    let isLoaded: Bool
    let error: String?
}
```

---

## 4. Tile System Design

### 4.1 Tile Protocol

```swift
protocol Tile: AnyObject {
    var name: String { get }
    var syphonName: String { get }
    var buffer: MTLTexture? { get }

    func update(audioState: AudioState, deltaTime: Float)
    func render(commandBuffer: MTLCommandBuffer)
    func sendToSyphon()
}
```

### 4.2 Tile Inventory

| Tile Class | Syphon Name | Purpose |
|------------|-------------|---------|
| `ShaderTile` | SwiftVJ/Shader | GLSL shaders via Metal |
| `MaskShaderTile` | SwiftVJ/Mask | Black/white mask shaders |
| `LyricsTile` | SwiftVJ/Lyrics | Prev/current/next lyrics |
| `RefrainTile` | SwiftVJ/Refrain | Chorus/refrain text |
| `SongInfoTile` | SwiftVJ/SongInfo | Artist/title display |
| `ImageTile` | SwiftVJ/Image | Image with crossfade |

### 4.3 TileManager

```swift
actor TileManager {
    private var tiles: [Tile] = []
    private var syphonServers: [String: SyphonServer] = [:]

    func setup(device: MTLDevice) async {
        // Create tiles
        tiles.append(ShaderTile(device: device))
        tiles.append(LyricsTile(device: device))
        tiles.append(RefrainTile(device: device))
        tiles.append(SongInfoTile(device: device))
        tiles.append(ImageTile(device: device))

        // Create Syphon servers
        for tile in tiles {
            syphonServers[tile.syphonName] = SyphonServer(name: tile.syphonName)
        }
    }

    func update(audioState: AudioState, deltaTime: Float) async {
        for tile in tiles {
            tile.update(audioState: audioState, deltaTime: deltaTime)
        }
    }

    func render(commandBuffer: MTLCommandBuffer) async {
        for tile in tiles {
            tile.render(commandBuffer: commandBuffer)
        }
    }

    func sendAllToSyphon() async {
        for tile in tiles {
            if let server = syphonServers[tile.syphonName],
               let buffer = tile.buffer {
                server.publishTexture(buffer)
            }
        }
    }
}
```

---

## 5. Audio Reactivity System

### 5.1 Audio Processor (Internal - No OSC)

```swift
/// Processes audio input and produces smoothed analysis state
actor AudioProcessor {
    private var state: AudioState
    private var rampedSpeed: Float = 0.02
    private var beatBoostAccum: Float = 0.0

    // Smoothing constants (from VJUniverse)
    private let audioSmoothing: Float = 0.80
    private let energyFastSmoothing: Float = 0.60
    private let energySlowSmoothing: Float = 0.92
    private let kickEnvSmoothing: Float = 0.55
    private let kickPulseThreshold: Float = 0.65
    private let kickCooldownMs: Int = 140
    private let beatPhaseDecay: Float = 0.87

    // Speed ramp constants
    private let baseSpeedFloor: Float = 0.02
    private let audioSpeedMax: Float = 1.20
    private let speedRampUp: Float = 0.008
    private let speedRampDown: Float = 0.025
    private let bassBoostWeight: Float = 0.35
    private let beatBoostAmount: Float = 0.15
    private let beatBoostDecay: Float = 0.92

    /// Update from raw audio levels (from Synesthesia or local analysis)
    func update(rawLevels: RawAudioLevels) -> AudioState {
        // Apply exponential smoothing
        let bass = lerp(state.bass, rawLevels.bass, 1 - audioSmoothing)
        let mid = lerp(state.mid, rawLevels.mid, 1 - audioSmoothing)
        // ... etc

        // Compute speed with Magic-style ramping
        let speed = computeAudioReactiveSpeed(bass: bass, level: level)

        return AudioState(
            bass: bass,
            // ... all fields
            speed: speed
        )
    }

    private func computeAudioReactiveSpeed(bass: Float, level: Float) -> Float {
        // 1. SMOOTH (already done)
        // 2. SCALE: Map volume → target speed
        let volumeDriver = level * (1 - bassBoostWeight) + bass * bassBoostWeight
        let targetSpeed = baseSpeedFloor + volumeDriver * (audioSpeedMax - baseSpeedFloor)

        // 3. RAMP: Gradual buildup / faster decay
        if targetSpeed > rampedSpeed {
            rampedSpeed = lerp(rampedSpeed, targetSpeed, speedRampUp)
        } else {
            rampedSpeed = lerp(rampedSpeed, targetSpeed, speedRampDown)
        }

        // 4. BEAT BOOST: Transient punch on kicks
        let beatTrigger = max(kickEnv, beatPhase) * beatBoostAmount
        beatBoostAccum = max(beatBoostAccum * beatBoostDecay, beatTrigger)

        return clamp(rampedSpeed + beatBoostAccum, baseSpeedFloor, audioSpeedMax)
    }
}
```

### 5.2 Audio Source Options

```swift
enum AudioSource {
    case synesthesiaOSC(port: UInt16)  // External Synesthesia
    case systemAudio                    // Local audio capture
    case virtualDJ                      // VDJ audio levels via OSC
}
```

---

## 6. GLSL Shader Rendering

### 6.1 Shader Loading Pipeline

```
Load GLSL File (.glsl, .txt, .frag)
        │
        ▼
convertGLSLForMetal()
├── Add precision qualifiers
├── Inject audio uniforms (bass, mid, highs, kickEnv, beat, speed, ...)
├── Convert Shadertoy conventions (iResolution → resolution, etc.)
└── Generate Metal shader library
        │
        ▼
MTLLibrary / MTLRenderPipelineState
        │
        ▼
Render to MTLTexture (1280x720)
        │
        ▼
SyphonServer.publishTexture()
```

### 6.2 Injected Audio Uniforms

```glsl
// These are injected into every GLSL shader
uniform float time;           // Audio-reactive time
uniform vec2 resolution;      // Pixel dimensions
uniform vec2 mouse;           // Synthetic mouse (Lissajous curve)
uniform float speed;          // Audio-reactive speed (0.02 - 1.20)

// Audio bands (0.0 - 1.0)
uniform float bass;
uniform float lowMid;
uniform float mid;
uniform float highs;
uniform float level;          // Overall

// Beat/kick
uniform float kickEnv;        // Envelope 0-1
uniform float kickPulse;      // 1 on kick, 0 otherwise
uniform float beat;           // Beat phase 0-1
uniform float energyFast;     // Fast energy envelope
uniform float energySlow;     // Slow energy envelope
```

### 6.3 Synthetic Mouse (Lissajous)

```swift
/// Calculate synthetic mouse position for shaders
/// Lissajous figure-8 modulated by audio
func calcSyntheticMouse(
    time: Float,
    energySlow: Float,
    bass: Float,
    mid: Float,
    beatPhase: Float
) -> SIMD2<Float> {
    // Base radius (expands with energy)
    let radius = 0.12 + energySlow * 0.18

    // Figure-8 pattern: x = sin(t), y = sin(2t)
    let x = 0.5 + sin(time) * radius * (1 + bass * 0.3)
    let y = 0.5 + sin(time * 2) * radius * (1 + mid * 0.2)

    // Phase offset on beats
    let phaseOffset = beatPhase * 0.1

    return SIMD2<Float>(
        clamp(x + phaseOffset, 0, 1),
        clamp(y, 0, 1)
    )
}
```

### 6.4 ShaderTile Implementation

```swift
class ShaderTile: Tile {
    let name = "Shader"
    let syphonName = "SwiftVJ/Shader"

    private var currentShader: MTLRenderPipelineState?
    private var audioTime: Float = 0
    private var syntheticMouse: SIMD2<Float> = [0.5, 0.5]

    private let uniformBuffer: MTLBuffer  // Audio uniforms

    func update(audioState: AudioState, deltaTime: Float) {
        // Update audio-reactive time
        audioTime += deltaTime * audioState.speed

        // Update synthetic mouse
        syntheticMouse = calcSyntheticMouse(
            time: audioTime,
            energySlow: audioState.energySlow,
            bass: audioState.bass,
            mid: audioState.mid,
            beatPhase: audioState.beatPhase
        )

        // Update uniform buffer
        updateUniformBuffer(audioState: audioState)
    }

    func render(commandBuffer: MTLCommandBuffer) {
        guard let shader = currentShader else { return }

        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc)
        renderEncoder.setRenderPipelineState(shader)
        renderEncoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
    }

    func loadShader(name: String) async throws {
        let path = shaderDirectory.appendingPathComponent("\(name).glsl")
        let glslSource = try String(contentsOf: path)
        let metalSource = convertGLSLForMetal(glslSource)
        currentShader = try await compileShader(source: metalSource)
    }
}
```

---

## 7. Text Rendering System

### 7.1 LyricsTile (3-line hierarchy)

```swift
class LyricsTile: Tile {
    let name = "Lyrics"
    let syphonName = "SwiftVJ/Lyrics"

    private var state: LyricsDisplayState

    func render(commandBuffer: MTLCommandBuffer) {
        // Draw to buffer with transparent background

        // Previous line: 70% size, 35% opacity, y = 0.28
        if let prev = state.prevLine {
            drawText(prev,
                fontSize: baseFontSize * 0.7,
                opacity: state.textOpacity * 0.35,
                y: 0.28)
        }

        // Current line: 100% size, 100% opacity, y = 0.50
        if let current = state.currentLine {
            drawText(current,
                fontSize: baseFontSize,
                opacity: state.textOpacity,
                y: 0.50)
        }

        // Next line: 70% size, 25% opacity, y = 0.72
        if let next = state.nextLine {
            drawText(next,
                fontSize: baseFontSize * 0.7,
                opacity: state.textOpacity * 0.25,
                y: 0.72)
        }
    }

    /// Auto-size font to fit longest line
    func calcAutoFitFontSize(lines: [String], maxWidth: Float) -> Float {
        var minSize = baseFontSize * 2
        for line in lines {
            let size = calcFontSizeToFit(line, maxWidth: maxWidth)
            minSize = min(minSize, size)
        }
        return min(minSize, 96)  // Cap at 96px
    }
}
```

### 7.2 RefrainTile

```swift
class RefrainTile: Tile {
    let syphonName = "SwiftVJ/Refrain"

    func render(commandBuffer: MTLCommandBuffer) {
        guard !state.text.isEmpty, state.opacity > 0.01 else { return }

        // Larger font, centered
        drawText(state.text,
            fontSize: baseFontSize + 16,
            opacity: state.opacity,
            y: 0.50,
            wrap: true)
    }
}
```

### 7.3 SongInfoTile (Fade Envelope)

```swift
class SongInfoTile: Tile {
    let syphonName = "SwiftVJ/SongInfo"

    func update(audioState: AudioState, deltaTime: Float) {
        guard state.active else { return }

        // Update fade envelope
        let elapsed = state.displayTime
        let fadeIn = SongInfoDisplayState.fadeInDuration
        let hold = SongInfoDisplayState.holdDuration
        let fadeOut = SongInfoDisplayState.fadeOutDuration
        let total = fadeIn + hold + fadeOut

        let opacity: Float
        if elapsed < fadeIn {
            opacity = elapsed / fadeIn  // Fade in
        } else if elapsed < fadeIn + hold {
            opacity = 1.0  // Hold
        } else if elapsed < total {
            opacity = 1.0 - (elapsed - fadeIn - hold) / fadeOut  // Fade out
        } else {
            opacity = 0
            // Mark inactive
        }

        state = state.withOpacity(opacity * 255)
    }

    func render(commandBuffer: MTLCommandBuffer) {
        // Artist (smaller, above center)
        drawText(state.artist,
            fontSize: baseFontSize * 0.65,
            opacity: state.opacity,
            y: 0.42)

        // Title (larger, below center)
        drawText(state.title,
            fontSize: baseFontSize,
            opacity: state.opacity,
            y: 0.55)
    }
}
```

---

## 8. Image Rendering System

### 8.1 ImageTile

```swift
class ImageTile: Tile {
    let syphonName = "SwiftVJ/Image"

    private var currentTexture: MTLTexture?
    private var nextTexture: MTLTexture?
    private var crossfadeProgress: Float = 1.0
    private var fadeStartTime: Date?
    private let fadeDuration: TimeInterval = 0.5

    func loadImage(url: URL) async {
        // Async load
        let image = try await loadImageAsync(url)
        startCrossfade(to: image)
    }

    func loadFolder(url: URL) async {
        let images = FileManager.default.contentsOfDirectory(at: url)
            .filter { isImageFile($0) }
            .sorted()

        state = state.withFolderImages(images)
        if let first = images.first {
            await loadImage(url: first)
        }
    }

    func update(audioState: AudioState, deltaTime: Float) {
        updateCrossfade()
        updateBeatCycling(beat4: audioState.beat4)
    }

    private func updateCrossfade() {
        guard let start = fadeStartTime else { return }

        let elapsed = Date().timeIntervalSince(start)
        crossfadeProgress = Float(clamp(elapsed / fadeDuration, 0, 1))

        // Quadratic ease-in-out
        crossfadeProgress = easeInOutQuad(crossfadeProgress)

        if elapsed >= fadeDuration {
            // Complete transition
            currentTexture = nextTexture
            nextTexture = nil
            fadeStartTime = nil
        }
    }

    func render(commandBuffer: MTLCommandBuffer) {
        if let next = nextTexture, let current = currentTexture {
            // Crossfade
            drawImageAspectRatio(current, alpha: 1 - crossfadeProgress)
            drawImageAspectRatio(next, alpha: crossfadeProgress)
        } else if let current = currentTexture {
            drawImageAspectRatio(current, alpha: 1.0)
        }
    }

    /// Aspect ratio calculation (pure function)
    func calcAspectRatioDimensions(
        imgW: Float, imgH: Float,
        bufW: Float, bufH: Float,
        cover: Bool
    ) -> (x: Float, y: Float, w: Float, h: Float) {
        let imgAspect = imgW / imgH
        let bufAspect = bufW / bufH

        let drawW: Float, drawH: Float
        if cover {
            if imgAspect > bufAspect {
                drawH = bufH
                drawW = bufH * imgAspect
            } else {
                drawW = bufW
                drawH = bufW / imgAspect
            }
        } else {
            if imgAspect > bufAspect {
                drawW = bufW
                drawH = bufW / imgAspect
            } else {
                drawH = bufH
                drawW = bufH * imgAspect
            }
        }

        return (
            x: (bufW - drawW) / 2,
            y: (bufH - drawH) / 2,
            w: drawW,
            h: drawH
        )
    }
}
```

---

## 9. Syphon Output

### 9.1 Syphon Integration

```swift
import Syphon

class SyphonOutputManager {
    private var servers: [String: SyphonMetalServer] = [:]
    private let device: MTLDevice

    func createServer(name: String) {
        servers[name] = SyphonMetalServer(
            name: name,
            device: device,
            options: nil
        )
    }

    func publish(name: String, texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        servers[name]?.publishTexture(
            texture,
            onCommandBuffer: commandBuffer,
            imageRegion: MTLRegionMake2D(0, 0, texture.width, texture.height),
            flipped: false
        )
    }

    func stopAll() {
        for server in servers.values {
            server.stop()
        }
        servers.removeAll()
    }
}
```

### 9.2 Syphon Server Names

| Server Name | Tile | Content |
|-------------|------|---------|
| `SwiftVJ/Shader` | ShaderTile | GLSL shader output |
| `SwiftVJ/Mask` | MaskShaderTile | Black/white masks |
| `SwiftVJ/Lyrics` | LyricsTile | Prev/current/next lyrics |
| `SwiftVJ/Refrain` | RefrainTile | Chorus text |
| `SwiftVJ/SongInfo` | SongInfoTile | Artist/title |
| `SwiftVJ/Image` | ImageTile | Image crossfade |

---

## 10. Implementation Phases (Visual)

### Phase 6: Rendering Foundation

**Goal**: Metal rendering pipeline, Syphon output

```
Tasks:
1. Set up Metal device and command queue
2. Create offscreen render targets (1280x720)
3. Implement Tile protocol
4. Implement TileManager
5. Set up Syphon servers
6. Basic fullscreen quad rendering
```

**TDD Checkpoints:**
- [ ] Metal device initializes
- [ ] Render target creates at correct resolution
- [ ] Syphon server publishes texture
- [ ] Tile lifecycle works (update/render/send)

### Phase 7: Shader Rendering

**Goal**: GLSL shaders via Metal

```
Tasks:
1. GLSL to Metal converter
2. Audio uniform injection
3. ShaderTile implementation
4. Shader loading from file
5. Rating-based filtering
6. Synthetic mouse calculation
```

**TDD Checkpoints:**
- [ ] GLSL converts to valid Metal
- [ ] Audio uniforms pass to shader
- [ ] Shader loads and renders
- [ ] Rating filter excludes SKIP shaders

### Phase 8: Audio Reactivity

**Goal**: Audio-driven animation

```
Tasks:
1. AudioProcessor actor
2. Level smoothing
3. Energy envelope calculation
4. Speed ramping (Magic-style)
5. Beat/kick detection
6. Audio state distribution to tiles
```

**TDD Checkpoints:**
- [ ] Smoothing reduces noise
- [ ] Speed ramps up/down correctly
- [ ] Kick detection has cooldown
- [ ] State updates propagate to tiles

### Phase 9: Text Rendering

**Goal**: Lyrics, refrain, song info display

```
Tasks:
1. Text rendering to texture
2. LyricsTile with 3-line hierarchy
3. RefrainTile
4. SongInfoTile with fade envelope
5. Auto-sizing algorithm
6. Text wrapping
```

**TDD Checkpoints:**
- [ ] Text renders legibly
- [ ] Visual hierarchy correct
- [ ] Fade envelope timing correct
- [ ] Long lines wrap properly

### Phase 10: Image Rendering

**Goal**: Image display with transitions

```
Tasks:
1. Async image loading
2. ImageTile implementation
3. Crossfade animation
4. Aspect ratio modes (contain/cover)
5. Folder mode
6. Beat-sync cycling
```

**TDD Checkpoints:**
- [ ] Images load asynchronously
- [ ] Crossfade animates smoothly
- [ ] Aspect ratio preserved
- [ ] Beat cycling triggers correctly

---

## 11. Metal/Swift Considerations

### 11.1 GLSL to Metal Conversion

Key differences to handle:

| GLSL | Metal |
|------|-------|
| `uniform float x;` | `constant float& x` |
| `varying vec2 uv;` | `fragment float4 frag(VertexOut in [[stage_in]])` |
| `gl_FragCoord` | `in.position` |
| `texture2D(tex, uv)` | `tex.sample(sampler, uv)` |
| `precision highp float;` | Not needed |

### 11.2 Shader Uniform Buffer

```swift
struct ShaderUniforms {
    var time: Float
    var resolution: SIMD2<Float>
    var mouse: SIMD2<Float>
    var speed: Float

    var bass: Float
    var lowMid: Float
    var mid: Float
    var highs: Float
    var level: Float

    var kickEnv: Float
    var kickPulse: Float
    var beat: Float
    var energyFast: Float
    var energySlow: Float
}
```

### 11.3 Render Pipeline

```swift
// Per-frame rendering
func renderFrame() {
    guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

    // Update all tiles
    let audioState = audioProcessor.currentState
    for tile in tiles {
        tile.update(audioState: audioState, deltaTime: deltaTime)
    }

    // Render all tiles
    for tile in tiles {
        tile.render(commandBuffer: commandBuffer)
    }

    // Send to Syphon
    for tile in tiles {
        syphonManager.publish(
            name: tile.syphonName,
            texture: tile.buffer!,
            commandBuffer: commandBuffer
        )
    }

    commandBuffer.commit()
}
```

---

## 12. Reference Files

### VJUniverse Files to Reference

| Feature | File | Lines |
|---------|------|-------|
| Shader loading | `ShaderManager.pde` | 99-172 |
| GLSL conversion | `ShaderManager.pde` | 181-223 |
| Audio uniforms | `ShaderManager.pde` | 254-269 |
| Audio smoothing | `SynesthesiaAudioOSC.pde` | 318-413 |
| Speed ramping | `SynesthesiaAudioOSC.pde` | 454-504 |
| Audio bindings | `SynesthesiaAudioOSC.pde` | 129-194 |
| Tile base class | `Tile.pde` | 1-186 |
| ShaderTile | `Tile.pde` | 193-224 |
| TextlerMultiTile | `Tile.pde` | 677-913 |
| Text slots | `Tile.pde` | 244-289 |
| Lyrics rendering | `Tile.pde` | 732-796 |
| Song info fade | `Tile.pde` | 390-408 |
| Image loading | `ImageTile.pde` | 200-244 |
| Crossfade | `ImageTile.pde` | 250-281 |
| Aspect ratio | `ImageTile.pde` | 146-181 |
| Beat cycling | `ImageTile.pde` | 371-386 |
| AudioEnvelope | `AudioEnvelope.pde` | 1-107 |

---

*Addendum Created: 2026-01-01*
*Source Analysis: VJUniverse ~15,000 LOC Processing/Java*
