# Profiling Guide for SwiftVJApp

Profile live performance bottlenecks using native Apple tools. No source code changes required. All traces are saved to `profiling/` (gitignored).

## Quick Start

```bash
cd swift-vj

# See all profiling targets
make help

# Fastest way to see GPU stats - live Metal HUD overlay
make profile-hud
```

## Profiling Targets

### `make profile-hud` - Live Metal HUD

Launches the app with Apple's built-in Metal performance overlay. Shows real-time:
- GPU utilization %
- Frame time (GPU + CPU)
- Encoder count per frame
- Buffer/texture memory

No file saved - visual overlay only. Best for quick sanity checks.

### `make profile-metal` - Metal System Trace

**Saves:** `profiling/metal-trace-*.trace`

Captures detailed GPU execution timeline. Open the `.trace` file in Instruments to see:
- **GPU utilization** - is the GPU saturated or idle?
- **Per-encoder execution time** - which render pass (Shader, Mask, Lyrics, etc.) is slowest?
- **GPU idle gaps** - indicates CPU-bound frames (GPU waiting for CPU to submit work)
- **Texture bandwidth** - read/write pressure on VRAM

**What to look for:**
- GPU utilization consistently > 90% = GPU-bound
- Long idle gaps between encoders = CPU-bound (render prep or MainActor contention)
- One render pass dominating GPU time = that tile is the bottleneck

### `make profile-cpu` - Time Profiler

**Saves:** `profiling/cpu-trace-*.trace`

Captures CPU activity per thread. Open in Instruments and inspect:
- **`RenderEngine.HeadlessTimer` thread** - how much CPU time does render prep take?
- **Main thread / MainActor** - is SwiftUI text rendering expensive?
- **Cooperative thread pool** - audio processing, OSC handling
- **Heaviest stack traces** - where is CPU time actually spent?

**What to look for:**
- Render thread spending > 5ms on CPU prep = uniform calculation or state reads are costly
- MainActor spending significant time in `ImageRenderer` or `SwiftUITextTileRenderer` = text rendering bottleneck
- Unexpected hotspots in audio smoothing or OSC parsing

### `make profile-alloc` - Allocations

**Saves:** `profiling/alloc-trace-*.trace`

Tracks all heap allocations including Metal textures, buffers, and command buffers.

**What to look for:**
- Total Metal texture bytes (persistent + transient)
- Metal buffer allocations per frame (should be near-zero in steady state)
- Memory growth over time (leak indicator)
- Peak allocation during shader switches
- Sort by "Persistent Bytes" to find largest allocations

**Tip:** Run for 10+ minutes to catch slow memory growth.

### `make profile-leaks` - Leaks

**Saves:** `profiling/leaks-trace-*.trace`

Detects memory leaks over time. Switch shaders several times during the session.

**What to look for:**
- Metal textures or pipeline states not being freed after shader switches
- Growing object counts for any class
- Leaked command buffers or render pass descriptors

### `make profile-vmmap` - Memory Snapshot

**Saves:** `profiling/vmmap-*.txt`

Captures process memory layout while the app is running. Start the app first, then run this target in another terminal.

**What to look for in the text file:**
- `IOKit` region - GPU/VRAM allocations
- `MALLOC` regions - heap allocations
- `__DATA` - static data
- Total `RESIDENT` size - actual physical memory used
- Compare against 8GB system budget

### `make profile-gpu-power` - GPU Power Metrics

**Saves:** `profiling/gpu-power-*.txt`

Captures GPU power draw and utilization for 60 seconds. Requires `sudo`.

**What to look for:**
- GPU utilization % under load
- Thermal throttling indicators
- Power consumption trends

## Test Procedure

During all profiling sessions, simulate a live performance:
1. All 6 tiles active (shader, mask, lyrics, refrain, songInfo, image)
2. Audio playing through Synesthesia with OSC output to SwiftVJ
3. Pre-analyzed songs loaded (song analysis is done ahead of time)

### Recommended session flow

1. **Quick check:** `make profile-hud` - get a visual feel for GPU load
2. **GPU deep dive:** `make profile-metal` - run for 2-3 minutes
3. **CPU deep dive:** `make profile-cpu` - run for 2-3 minutes
4. **Memory check:** `make profile-alloc` - run for 10+ minutes, switch shaders periodically
5. **Leak check:** `make profile-leaks` - switch shaders 10+ times
6. **Memory snapshot:** Start app normally, then `make profile-vmmap` from another terminal
7. **GPU power:** Start app normally, then `make profile-gpu-power` from another terminal

## Interpreting Results

Open `.trace` files in Instruments.app (double-click or `open profiling/*.trace`).

### Key questions to answer

| Question | Tool | How to tell |
|----------|------|-------------|
| GPU-bound or CPU-bound? | Metal System Trace | GPU idle gaps = CPU-bound; GPU at 100% = GPU-bound |
| Which tile costs the most? | Metal System Trace | Compare encoder durations in GPU timeline |
| How much VRAM is used? | Allocations, vmmap | Filter by IOKit in vmmap; Metal allocations in Instruments |
| Any memory leaks? | Leaks, Allocations | Growing allocation count over time |
| Is text rendering expensive? | Time Profiler | Check MainActor time in SwiftUI rendering |
| Is OSC processing a factor? | Time Profiler | Check cooperative thread pool time |

### After analysis

Document findings and use them to plan targeted fixes. Do not optimize speculatively.
