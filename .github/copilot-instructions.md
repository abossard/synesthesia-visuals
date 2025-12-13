# Copilot Instructions for synesthesia-visuals

## Project Overview
A VJ performance toolkit combining:
- **Python VJ Console** (`python-vj/`) - Master control, karaoke engine, MIDI router, AI services
- **Synesthesia shaders** (`synesthesia-shaders/`) - `.synScene` directories with GLSL + JSON + JS
- **Processing games** (`processing-vj/`) - Java sketches with Launchpad MIDI control + Syphon output

## Architecture Principles
This codebase follows **Grokking Simplicity** and **A Philosophy of Software Design** patterns:
- **Domain models** are immutable frozen dataclasses ([domain.py](../python-vj/domain.py))
- **Adapters** are deep modules hiding protocol complexity ([adapters.py](../python-vj/adapters.py))
- **Orchestrators** coordinate via dependency injection ([orchestrators.py](../python-vj/orchestrators.py))
- **Pure functions** for calculations with no side effects

## Repository Structure
\`\`\`
python-vj/               # Master control center (Textual TUI)
  ├── vj_console.py      # Main entry - terminal UI with 6 screens
  ├── domain.py          # Immutable data models (frozen dataclasses)
  ├── adapters.py        # External services (Spotify, VirtualDJ, LRCLIB, OSC)
  ├── orchestrators.py   # Coordinators (PlaybackCoordinator, LyricsOrchestrator)
  └── ai_services.py     # LLM integration (LM Studio with MCP web-search)
synesthesia-shaders/     # SSF scenes (main.glsl, scene.json, script.js)
processing-vj/
  ├── examples/          # VJ games (WhackAMole, CrowdBattle, BuildupRelease)
  ├── src/               # Main apps (VJSims, VJUniverse, KaraokeOverlay)
  └── lib/               # LaunchpadUtils.pde - shared MIDI utilities
\`\`\`

## Python VJ Patterns

### Domain Models (frozen dataclasses)
\`\`\`python
@dataclass(frozen=True)
class LyricLine:
    time_sec: float
    text: str
    is_refrain: bool = False
    
    def with_refrain(self, is_refrain: bool) -> 'LyricLine':
        return replace(self, is_refrain=is_refrain)  # immutable update
\`\`\`

### Adapter Pattern (deep modules)
Each adapter hides one external service behind a simple interface:
- \`SpotifyMonitor.get_playback() -> Optional[Dict]\` - hides OAuth, token refresh
- \`VirtualDJMonitor.get_playback() -> Optional[Dict]\` - hides file polling, tracklist parsing
- \`LyricsFetcher.fetch(artist, title) -> Optional[str]\` - hides LRCLIB + LM Studio fallback

### OSC Communication
All OSC uses **flat arrays** (no nested structures) via centralized \`osc_manager.osc\`:
\`\`\`python
osc.send("/karaoke/track", [1, "spotify", artist, title, album, duration, has_lyrics])
osc.send("/audio/levels", [sub_bass, bass, low_mid, mid, high_mid, presence, air, rms])
\`\`\`

## Synesthesia Shader (SSF) Conventions

### Key Uniforms (auto-injected, DO NOT declare)
\`\`\`glsl
TIME, RENDERSIZE, PASSINDEX, FRAMECOUNT
_xy (pixel coords), _uv (normalized 0-1), _uvc (aspect-correct)
syn_BassLevel, syn_MidLevel, syn_HighLevel, syn_Level
syn_BassHits, syn_HighHits, syn_BeatTime, syn_BPM
syn_Spectrum (sampler1D), syn_LevelTrail (sampler1D)
\`\`\`

### Control Mapping (scene.json → uniform)
\`\`\`json
{"NAME": "warp_amount", "TYPE": "slider", "MIN": 0.0, "MAX": 1.0, "DEFAULT": 0.3}
\`\`\`

### Audio Reactivity Pattern
\`\`\`glsl
float baseTime = TIME * 0.3;                    // always-moving base
float audioTime = syn_Time * 0.5;               // audio-driven boost
float bassActive = smoothstep(0.3, 0.4, syn_BassHits);  // threshold trigger
\`\`\`

## Processing Game Conventions

### Critical Requirements
- **Resolution**: Always \`1920x1080\` (Full HD) for VJ output
- **Renderer**: \`P3D\` required for Syphon on macOS
- **Syphon**: Always include \`SyphonServer\` with \`sendScreen()\` in draw loop
- **MIDI**: Auto-detect Launchpad, always provide keyboard/mouse fallback

### VJ Output Design (NO UI on screen)
- Use \`background(0)\` - black becomes transparent in Add/Screen blend
- **No** "Launchpad Connected" status, scores, debug overlays
- Launchpad LEDs = performer feedback (private), Screen = audience visuals (public)

### MIDI Robustness Pattern
\`\`\`java
MidiBus launchpad;
boolean hasLaunchpad = false;

void initMidi() {
  for (String dev : MidiBus.availableInputs()) {
    if (dev != null && dev.toLowerCase().contains("launchpad")) {
      try { launchpad = new MidiBus(this, dev, dev); hasLaunchpad = true; }
      catch (Exception e) { hasLaunchpad = false; }
      break;
    }
  }
}

void lightPad(int col, int row, int color) {
  if (!hasLaunchpad || launchpad == null) return;  // guard ALL MIDI calls
  launchpad.sendNoteOn(0, gridToNote(col, row), color);
}
\`\`\`

### Launchpad Grid (Programmer Mode)
Notes 11-88: \`note = (row+1)*10 + (col+1)\`. Use [LaunchpadUtils.pde](../processing-vj/lib/LaunchpadUtils.pde) for \`noteToGrid()\`, \`gridToNote()\`, color constants.

## Development Workflows

### Quick Start
\`\`\`bash
cd python-vj && pip install -r requirements.txt
python vj_console.py          # Launch terminal UI (press 1-6 for screens)
python midi_router_cli.py run # Launch MIDI router separately
\`\`\`

### Makefile Commands
\`\`\`bash
make stats         # Show shader analysis statistics
make clean-errors  # Delete .error.json files (allows re-analysis)
make find-black    # Find black/broken shaders from screenshots
\`\`\`

### Testing Shaders
1. Copy \`.synScene/\` to Synesthesia custom library folder
2. Reload library in Synesthesia
3. Use Stats overlay to verify performance

### Processing Games
1. Put Launchpad in Programmer mode: hold Session → press orange button → release
2. Run sketch from Processing IDE (Intel build on Apple Silicon for Syphon)
3. Keyboard fallbacks work without Launchpad

### Live Rig Audio Routing (macOS)
- Install BlackHole for audio loopback
- Create Multi-Output Device (speakers + BlackHole)
- Set Synesthesia audio input to BlackHole

## Key Files Reference
- [docs/reference/isf-to-synesthesia-migration.md](../docs/reference/isf-to-synesthesia-migration.md) - shader conversion guide
- [docs/setup/live-vj-setup-guide.md](../docs/setup/live-vj-setup-guide.md) - full Syphon/Magic pipeline
- [python-vj/MIDI_ROUTER.md](../python-vj/MIDI_ROUTER.md) - MIDI middleware documentation
- [processing-vj/lib/LaunchpadUtils.pde](../processing-vj/lib/LaunchpadUtils.pde) - grid conversion, LED colors
