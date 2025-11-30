# Python VJ Tools

Console application and karaoke engine for VJ performance control.

## Quick Start

```bash
cd python-vj
pip install -r requirements.txt
python vj_console.py          # Launch the terminal UI
```

## Features

- **🎤 Karaoke Engine**: Monitors Spotify/VirtualDJ, fetches synced lyrics, sends via OSC
- **📡 3 OSC Channels**: Full lyrics, refrain-only, and keywords for VJ mixing
- **🤖 AI Analysis**: OpenAI or local Ollama for refrain detection and image prompts
- **🎨 ComfyUI Integration**: Generates song-matched visuals with black backgrounds
- **⚡ Daemon Mode**: Auto-restarts crashed Processing apps
- **📊 Pipeline View**: Colorful terminal UI showing processing steps and logs

## Components

### VJ Console (`vj_console.py`)

A colorful terminal UI application for managing VJ sessions:

- **Processing App Launcher**: Lists and launches Processing sketches from the project
- **Daemon Mode**: Auto-restarts crashed apps for reliable live performance  
- **Karaoke Engine Integration**: Monitors Spotify/VirtualDJ and sends lyrics via OSC
- **Pipeline Display**: Shows real-time processing steps for each song
- **Timing Adjustment**: Fine-tune lyrics sync with +/- keys (±200ms per press)

### Karaoke Engine (`karaoke_engine.py`)

Monitors music playback and sends synced lyrics via OSC:

- **Spotify Integration**: Uses Spotify Web API for "Now Playing" tracking
- **VirtualDJ Support**: Monitors `now_playing.txt` file (auto-detected on macOS)
- **LRCLIB Lyrics**: Fetches synced lyrics (LRC format) from LRCLIB API  
- **AI Analysis**: Detects refrain/chorus, extracts keywords, generates image prompts
- **OSC Output**: Sends track metadata, lyrics, and position to Processing

## Installation

```bash
cd python-vj
pip install -r requirements.txt
```

### Optional Services Detection

On startup, the console checks for available services and shows their status:

```
╔════════════════════════════════════════════════════════════╗
║  🔍 Service Detection                                       ║
╠════════════════════════════════════════════════════════════╣
║  ✓ Spotify API      Credentials configured                 ║
║  ✓ VirtualDJ        ~/Documents/VirtualDJ/now_playing.txt  ║
║  ✓ Ollama LLM       llama3.2 (from 5 models)               ║
║  ✓ ComfyUI          http://127.0.0.1:8188                  ║
║  ○ OpenAI           OPENAI_API_KEY not set                 ║
╚════════════════════════════════════════════════════════════╝
```

### Spotify Setup (Optional)

1. Create an app at https://developer.spotify.com/dashboard
2. Set callback URL to `http://localhost:8888/callback`
3. Create a `.env` file in `python-vj/`:

```env
SPOTIPY_CLIENT_ID=your_client_id
SPOTIPY_CLIENT_SECRET=your_client_secret
SPOTIPY_REDIRECT_URI=http://localhost:8888/callback
```

### Ollama LLM Setup (Recommended)

For AI-powered lyrics analysis (refrain detection, keyword extraction, image prompts):

```bash
# Install Ollama from https://ollama.com/download
# macOS:
brew install ollama

# Pull a recommended model:
ollama pull llama3.2          # Best overall
# or
ollama pull mistral           # Lighter weight
# or  
ollama pull deepseek-r1       # Good for poetic language

# Start Ollama service:
ollama serve
```

**Detection Process:**
1. Checks `http://localhost:11434/api/tags` for running Ollama
2. Lists installed models and selects best match from priority list
3. Falls back to basic heuristic analysis if unavailable

**Priority order:** `llama3.2` → `llama3.1` → `mistral` → `deepseek-r1` → `llama2` → `phi3` → `gemma2`

### ComfyUI Image Generation (Optional, Disabled by Default)

ComfyUI integration is **disabled by default** as it's experimental. To enable:

```bash
# In your .env file or environment:
COMFYUI_ENABLED=1
```

For generating song-matched visuals with black backgrounds (perfect for VJ overlays):

```bash
# Install ComfyUI from https://github.com/comfyanonymous/ComfyUI
git clone https://github.com/comfyanonymous/ComfyUI
cd ComfyUI
pip install -r requirements.txt

# Download SDXL model (required):
# Place sd_xl_base_1.0.safetensors in ComfyUI/models/checkpoints/

# Start ComfyUI:
python main.py --listen 127.0.0.1 --port 8188
```

**Detection Process:**
1. Checks `http://127.0.0.1:8188/system_stats` for running ComfyUI
2. Queries `/object_info/CheckpointLoaderSimple` to list available models
3. Loads custom workflows from `python-vj/workflows/` directory
4. Queues image generation via `/prompt` API endpoint

**Custom Workflows:**

You can use your own ComfyUI workflows:

1. In ComfyUI, enable "Dev Mode Options" in Settings
2. Click "Save (API Format)" to export workflow as JSON
3. Place the `.json` file in `python-vj/workflows/`

The engine will:
- Auto-detect workflows on startup
- Inject your prompt into CLIPTextEncode nodes
- Retrieve generated images from SaveImage node output

Example workflow setup:
```
python-vj/
└── workflows/
    ├── README.md              # Instructions
    ├── default_sdxl.json      # Default SDXL workflow
    ├── flux_artistic.json     # Flux model for artistic styles
    └── fast_lcm.json          # Fast LCM-based generation
```

**Image Generation Features:**
- Prompts automatically enhanced with "pure black background, isolated subject"
- Negative prompt excludes busy backgrounds, ensures clean overlays
- Images cached in `.cache/generated_images/` by song
- 1024x1024 PNG output, suitable for Syphon input
- **Sends image path via OSC** to Processing `ImageOverlay` app
- Image displayed as separate Syphon output `KaraokeImage`

### OpenAI Setup (Optional)

As an alternative to local Ollama:

```env
OPENAI_API_KEY=sk-your-api-key
```

Uses GPT-3.5-turbo for lyrics analysis. OpenAI is preferred over Ollama if both are available.

## Usage

### VJ Console

```bash
python vj_console.py
```

**Controls:**
- `↑/↓` or `j/k`: Navigate menu
- `Enter`: Select/toggle option
- `+/-`: Adjust lyrics timing offset (±200ms per press)
- `d`: Toggle daemon mode
- `r`: Restart selected app
- `K`: Toggle karaoke engine
- `q`: Quit

### Pipeline View

When a song starts playing, the console shows a colorful pipeline:

```
═══ Processing Pipeline ═══
  ✓ 🎵 Detect Playback - spotify: Daft Punk
  ✓ 📜 Fetch Lyrics - Found synced lyrics
  ✓ ⏱ Parse LRC Timecodes - 47 lines
  ✓ 🔁 Detect Refrain - 12 refrain lines
  ✓ 🔑 Extract Keywords - Done
  ◐ 🤖 AI Analysis - Using Ollama (llama3.2)...
  ○ 🎨 Generate Image Prompt
  ○ 📡 Send OSC

═══ Logs ═══
  14:32:05 New track: Daft Punk - One More Time
  14:32:05 [fetch_lyrics] ✓ Found synced lyrics
  14:32:06 [llm_analysis] Themes: dance, celebration, unity
```

**Data Storage:**

Settings, lyrics cache, and state files are stored in `python-vj/.cache/`:
- `settings.json` - Timing offset and user preferences
- `lyrics/` - Cached lyrics (avoids re-downloading)
- `llm_cache/` - AI analysis results (refrain detection, keywords, image prompts)
- `generated_images/` - ComfyUI generated images by song
- `state.json` - Current karaoke state for debugging

## OSC Protocol

The Karaoke Engine sends OSC messages on **3 separate channels** for flexible VJ mixing:

### Channel 1: Full Lyrics (`/karaoke/...`)
Complete lyrics with all lines for karaoke-style display.

```
/karaoke/track          [is_active, source, artist, title, album, duration, has_synced]
/karaoke/lyrics/reset   [song_id]
/karaoke/lyrics/line    [index, time_sec, text]
/karaoke/pos            [position_sec, is_playing]
/karaoke/line/active    [index]
```

### Channel 2: Refrain (`/karaoke/refrain/...`)
Only chorus/refrain lines - detected by repetition in lyrics.

```
/karaoke/refrain/reset  [song_id]
/karaoke/refrain/line   [index, time_sec, text]
/karaoke/refrain/active [index, current_text]
```

### Channel 3: Keywords (`/karaoke/keywords/...`)
Key words extracted from each line (stop words removed).

```
/karaoke/keywords/reset  [song_id]
/karaoke/keywords/line   [index, time_sec, keywords]
/karaoke/keywords/active [index, current_keywords]
```

## Processing Syphon Outputs

The Processing KaraokeOverlay app creates **3 separate Syphon servers**:

| Syphon Server | Content | Usage |
|---------------|---------|-------|
| `KaraokeFullLyrics` | Full lyrics with prev/current/next | Main karaoke display |
| `KaraokeRefrain` | Chorus lines only | Highlight choruses |
| `KaraokeKeywords` | Key words only | Bold word highlights |
| `KaraokeImage` | AI-generated song image | Visual backdrop |

Select any of these in Magic Music Visuals as separate video sources!

### ImageOverlay App

The `ImageOverlay` Processing app (`processing-vj/examples/ImageOverlay/`) receives image paths via OSC and displays them:

**OSC Messages:**
```
/karaoke/image [path]        - Load and display image at absolute path
/karaoke/image/clear         - Clear current image (show black)
/karaoke/image/opacity [f]   - Set image opacity (0.0-1.0)
/karaoke/image/fade [ms]     - Set fade duration in milliseconds
```

**Features:**
- Async image loading (no frame drops)
- Automatic aspect ratio preservation
- Fade-in transitions
- On-screen logging with error messages
- Keyboard controls: `c` clear, `r` reload, `+/-` opacity, `L` toggle logs

## Debug Output

The engine writes `karaoke_state.json` with the current state:

```json
{
  "active": true,
  "source": "spotify",
  "artist": "Artist Name",
  "title": "Song Title",
  "album": "Album Name",
  "duration_sec": 233.5,
  "position_sec": 42.3,
  "has_synced_lyrics": true,
  "lines": [
    {"time_sec": 0.5, "text": "First line"},
    {"time_sec": 5.4, "text": "Second line"}
  ]
}
```

## Processing Integration

See [`processing-vj/examples/KaraokeOverlay/`](../processing-vj/examples/KaraokeOverlay/) for the Processing client that receives OSC messages and renders lyrics.

See [`processing-vj/examples/ImageOverlay/`](../processing-vj/examples/ImageOverlay/) for the Processing client that displays AI-generated images.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         VJ Console                          │
│   (Terminal UI with arrow key navigation and app control)   │
└────────────────────────────┬────────────────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        ▼                    ▼                    ▼
┌───────────────┐   ┌────────────────┐   ┌───────────────┐
│ Processing    │   │ Karaoke Engine │   │ ComfyUI       │
│ Apps          │   │                │   │ Image Gen     │
│ (Daemon Mode) │   │ Spotify API    │   │               │
└───────────────┘   │ VirtualDJ      │   └───────┬───────┘
                    │ LRCLIB API     │           │
                    │ Ollama LLM     │           │
                    └───────┬────────┘           │
                            │ OSC                │
        ┌───────────────────┴───────────────────┐│
        ▼                                       ▼▼
                            ▼
                    ┌───────────────┐
                    │ Processing    │
                    │ Karaoke       │
                    │ Overlay       │
                    └───────────────┘
                            │ Syphon
                            ▼
                    ┌───────────────┐
                    │ VJ Mixer      │
                    │ (Magic, etc)  │
                    └───────────────┘
```

## VirtualDJ Setup

VirtualDJ can output the current track to a text file:

1. Open VirtualDJ Settings → Interface → Broadcast
2. Enable "Now Playing" output
3. Set the file path (default: `~/Documents/VirtualDJ/now_playing.txt`)

Or use a VirtualDJ script/plugin to write "Artist - Title" to a file.

## Dependencies

- **spotipy**: Spotify Web API client
- **python-osc**: OSC protocol implementation
- **requests**: HTTP client for LRCLIB API
- **blessed**: Terminal UI library
- **psutil**: Process management
