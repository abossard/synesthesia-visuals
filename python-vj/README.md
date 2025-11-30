# Python VJ Tools

Console application and karaoke engine for VJ performance control.

## Components

### VJ Console (`vj_console.py`)

A terminal UI application for managing VJ sessions:

- **Processing App Launcher**: Lists and launches Processing sketches from the project
- **Daemon Mode**: Auto-restarts crashed apps for reliable live performance
- **Karaoke Engine Integration**: Monitors Spotify/VirtualDJ and sends lyrics via OSC

### Karaoke Engine (`karaoke_engine.py`)

Monitors music playback and sends synced lyrics via OSC:

- **Spotify Integration**: Uses Spotify Web API for "Now Playing" tracking
- **VirtualDJ Support**: Monitors `now_playing.txt` file
- **LRCLIB Lyrics**: Fetches synced lyrics (LRC format) from LRCLIB API
- **OSC Output**: Sends track metadata, lyrics, and position to Processing

## Installation

```bash
cd python-vj
pip install -r requirements.txt
```

### Spotify Setup (Optional)

1. Create an app at https://developer.spotify.com/dashboard
2. Set callback URL to `http://localhost:8888/callback`
3. Export environment variables:

```bash
export SPOTIPY_CLIENT_ID="your_client_id"
export SPOTIPY_CLIENT_SECRET="your_client_secret"
export SPOTIPY_REDIRECT_URI="http://localhost:8888/callback"
```

Or create a `.env` file:

```env
SPOTIPY_CLIENT_ID=your_client_id
SPOTIPY_CLIENT_SECRET=your_client_secret
SPOTIPY_REDIRECT_URI=http://localhost:8888/callback
```

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
- `q`: Quit

**Data Storage:**

Settings, lyrics cache, and state files are stored in `python-vj/.cache/`:
- `settings.json` - Timing offset and user preferences
- `lyrics/` - Cached lyrics (avoids re-downloading)
- `llm_cache/` - AI analysis results (refrain detection, keywords)
- `state.json` - Current karaoke state for debugging

### AI-Powered Lyrics Analysis

The engine uses AI to detect refrain/chorus sections and extract important keywords. It supports:

1. **OpenAI** (if `OPENAI_API_KEY` is set in .env)
2. **Local Ollama** (auto-detects installed models)
3. **Basic analysis** (fallback, no LLM needed)

**Recommended Ollama models** (in priority order):
- `llama3.2` - Best overall for lyrics analysis
- `mistral` - Lightweight, good for limited resources
- `deepseek-r1` - Good for poetic/metaphorical language

To use local Ollama:
```bash
# Install Ollama from https://ollama.com
ollama pull llama3.2
# Engine will auto-detect and use it
```

### Karaoke Engine (Standalone)

```bash
python karaoke_engine.py [options]
```

**Options:**
- `--osc-host HOST`: OSC destination (default: 127.0.0.1)
- `--osc-port PORT`: OSC port (default: 9000)
- `--vdj-path PATH`: VirtualDJ now_playing.txt path
- `--state-file FILE`: JSON state file path (default: karaoke_state.json)
- `--poll-interval SECS`: Update interval (default: 0.1)
- `-v, --verbose`: Verbose logging

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
| `KaraokeRefrain` | Chorus lines only (magenta) | Highlight choruses |
| `KaraokeKeywords` | Key words only (cyan) | Bold word highlights |

Select any of these in Magic Music Visuals as separate video sources!

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
│ Processing    │   │ Karaoke Engine │   │ Other VJ      │
│ Apps          │   │                │   │ Components    │
│ (Daemon Mode) │   │ Spotify API    │   │               │
└───────────────┘   │ VirtualDJ      │   └───────────────┘
                    │ LRCLIB API     │
                    └───────┬────────┘
                            │ OSC
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
