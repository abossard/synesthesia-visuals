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
- `d`: Toggle daemon mode
- `r`: Restart selected app
- `q`: Quit

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

The Karaoke Engine sends OSC messages to Processing:

### Track Change
```
/karaoke/track [int is_active, string source, string artist, string title, string album, float duration_sec, int has_synced_lyrics]
```

### Lyrics Reset (new track)
```
/karaoke/lyrics/reset [string song_id]
```

### Lyric Lines (sent once per track)
```
/karaoke/lyrics/line [int index, float time_sec, string text]
```

### Position Update (10 Hz)
```
/karaoke/pos [float position_sec, int is_playing]
```

### Active Line Index
```
/karaoke/line/active [int index]
```

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
