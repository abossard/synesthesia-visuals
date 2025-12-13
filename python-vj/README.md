# Python VJ Tools

Master control center for VJ performance: karaoke engine, audio analysis, MIDI routing, and app management.

## Quick Start

```bash
cd python-vj
pip install -r requirements.txt
python vj_console.py          # Launch terminal UI
```

**Keyboard shortcuts:** `1-6` switch screens, `S` Synesthesia, `M` MilkSyphon, `K` Karaoke, `A` Audio, `Q` Quit

---

## Documentation

### Features

| Doc | Description |
|-----|-------------|
| [Audio Analysis](docs/features/audio-analysis.md) | Real-time audio processing, OSC output, VJ software mapping |

### Guides

| Doc | Description |
|-----|-------------|
| [OSC Visual Mapping](docs/guides/osc-visual-mapping.md) | Complete VJ software mapping guide (Magic, Resolume, TouchDesigner) |
| [Launchpad Setup](docs/guides/launchpad-setup.md) | Launchpad Mini MK3 programmer mode reference |

### Reference

| Doc | Description |
|-----|-------------|
| [MIDI Router Visual Guide](docs/reference/midi-router-visual-guide.md) | ASCII art visual reference for MIDI Router screen |
| [VirtualDJ Monitoring](docs/reference/virtualdj-monitoring.md) | VirtualDJ integration details and AppleScript research |

### Development

| Doc | Description |
|-----|-------------|
| [Architecture](docs/development/architecture.md) | Design patterns, refactoring notes, code organization |

### Archive

Historical documents preserved for reference:
- [Feature Comparison](docs/archive/feature-comparison-python-vs-mmv.md) - Python Essentia vs Magic Music Visuals
- [Stability Fixes](docs/archive/stability-fixes.md) - Bug fix documentation
- [lpminimk3 Migration](docs/archive/lpminimk3-migration.md) - Library migration guide

---

## Features

- **🎛️ Master Control** — Start/stop Synesthesia, MilkSyphon, Processing apps
- **🎤 Karaoke Engine** — Spotify/VirtualDJ monitoring, synced lyrics via OSC
- **🎧 Audio Analysis** — Beat detection, BPM, spectral features at 60 fps
- **🎹 MIDI Router** — Toggle state management with LED feedback
- **🏷️ Song Categorization** — AI-powered mood/theme analysis
- **🤖 AI Integration** — LM Studio or OpenAI for lyrics analysis
- **⚡ Daemon Mode** — Auto-restarts crashed apps

---

## Screens

| Key | Screen | Purpose |
|-----|--------|---------|
| `1` | Master Control | Dashboard, apps, services |
| `2` | OSC View | Message debug |
| `3` | Song AI Debug | Categorization pipeline |
| `4` | All Logs | Application logs |
| `5` | Audio Analysis | Real-time frequency, beat, BPM |
| `6` | MIDI Router | Toggle management |

---

## Setup

### Spotify (Optional)

```env
# .env file
SPOTIPY_CLIENT_ID=your_client_id
SPOTIPY_CLIENT_SECRET=your_client_secret
SPOTIPY_REDIRECT_URI=http://127.0.0.1:8888/callback
```

### Audio Analysis (macOS)

```bash
brew install blackhole-2ch
```
Create Multi-Output Device in Audio MIDI Setup (speakers + BlackHole).

### LM Studio (Recommended)

Download from https://lmstudio.ai/, load a model, start the local server (port 1234).

---

## OSC Protocol

All messages use flat arrays (no nested structures) on port 9000.

### Karaoke

```
/karaoke/track    [active, source, artist, title, album, duration, has_lyrics]
/karaoke/pos      [position_sec, is_playing]
/karaoke/lyrics/* [reset, line, active]
/karaoke/refrain/* [reset, line, active]
```

### Audio

```
/audio/levels     [sub, bass, low_mid, mid, high_mid, presence, air, rms]
/audio/spectrum   [32 bins]
/audio/beat       [is_onset, flux]
/audio/bpm        [tempo, confidence]
/audio/structure  [buildup, drop, energy_trend, brightness]
```

See [Audio Analysis](docs/features/audio-analysis.md) for complete reference.

---

## Architecture

```
┌────────────────────────────────────────────┐
│ vj_console.py (Textual TUI)                │
├────────────────────────────────────────────┤
│ karaoke_engine.py | audio_analyzer.py      │
├────────────────────────────────────────────┤
│ orchestrators.py (Coordinators)            │
├────────────────────────────────────────────┤
│ adapters.py | ai_services.py               │
├────────────────────────────────────────────┤
│ domain.py (Pure) | infrastructure.py       │
└────────────────────────────────────────────┘
```

---

## Dependencies

```
textual          # TUI framework
spotipy          # Spotify API
python-osc       # OSC protocol
sounddevice      # Audio I/O
numpy            # FFT
essentia         # Beat/tempo/pitch detection
chromadb         # Shader semantic search
```

---

## Related Projects

- [`processing-vj/`](../processing-vj/) — Processing sketches with Launchpad control
- [`synesthesia-shaders/`](../synesthesia-shaders/) — Synesthesia .synScene shaders
