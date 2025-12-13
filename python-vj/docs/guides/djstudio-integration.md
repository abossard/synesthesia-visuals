# DJ.Studio Integration Guide

This guide explains how to integrate DJ.Studio with the Python VJ Tools to display current track information and synchronized lyrics during your DJ mixes.

## Overview

The DJ.Studio monitor tracks the currently playing song from DJ.Studio and sends it to the karaoke engine for lyrics display and song analysis. The monitor uses multiple strategies to detect the current track:

1. **Window Title Monitoring** (default) - Extracts track info from DJ.Studio's window title
2. **File Export** - Reads track info from a file if DJ.Studio exports it
3. **AppleScript** - Direct integration if DJ.Studio supports AppleScript automation

## Quick Start

DJ.Studio monitoring is **enabled by default**. No configuration is required for basic usage.

```bash
cd python-vj
python vj_console.py
```

The monitor will automatically try all available strategies and use the first one that succeeds.

## How It Works

### Monitor Priority Order

The Python VJ Tools monitor playback sources in this priority:

1. Spotify (AppleScript) - if Spotify desktop app is playing
2. Spotify (Web API) - if enabled and authenticated
3. **DJ.Studio** - if running and has track info
4. VirtualDJ - if tracklist.txt file exists

When DJ.Studio is playing, it will be used as the source unless Spotify is actively playing.

### Strategy Details

#### 1. Window Title Monitoring (Default)

The monitor checks DJ.Studio's window title for track information. This works if DJ.Studio displays the current track in its window title.

**Supported formats:**
- `"Artist - Title - DJ.Studio"`
- `"Now Playing: Artist - Title"`
- `"DJ.Studio - Artist - Title"`

**Pros:**
- Works out of the box
- No configuration needed
- No file system access required

**Cons:**
- Only works if window title contains track info
- Polling-based (checks every second)

#### 2. File Export

If DJ.Studio exports the current track to a file, the monitor can read it.

**Supported file formats:**

**Plain text** (`Artist - Title`):
```
Daft Punk - Get Lucky
```

**JSON** (more detailed):
```json
{
  "artist": "Daft Punk",
  "title": "Get Lucky",
  "album": "Random Access Memories",
  "duration_ms": 248000,
  "progress_ms": 120000
}
```

**Auto-detected paths:**
- `~/Documents/DJ.Studio/current_track.txt`
- `~/Documents/DJ.Studio/now_playing.txt`
- `~/Library/Application Support/DJ.Studio/current_track.txt`
- `~/Library/Application Support/DJ.Studio/now_playing.txt`
- `/tmp/djstudio_now_playing.txt`

**Pros:**
- Most reliable if available
- Can include duration and progress
- Low overhead

**Cons:**
- Requires DJ.Studio to export track info
- Need to configure export path

#### 3. AppleScript (Advanced)

If DJ.Studio supports AppleScript, the monitor can query it directly.

**Pros:**
- Direct integration
- Most accurate timing

**Cons:**
- DJ.Studio must be AppleScript-enabled
- macOS only
- Currently, DJ.Studio's AppleScript support is limited

## Configuration

### Environment Variables

Control DJ.Studio monitoring via environment variables in your `.env` file:

```env
# Enable/disable DJ.Studio monitoring (default: 1)
DJSTUDIO_ENABLED=1

# Custom file path for track export
DJSTUDIO_FILE_PATH=/path/to/your/track/file.txt

# AppleScript timeout in seconds (default: 1.5)
DJSTUDIO_TIMEOUT=1.5

# Custom AppleScript path
DJSTUDIO_APPLESCRIPT_PATH=/path/to/custom/script.applescript
```

### Disabling DJ.Studio Monitor

To disable DJ.Studio monitoring:

```env
DJSTUDIO_ENABLED=0
```

Or set the environment variable before running:

```bash
DJSTUDIO_ENABLED=0 python vj_console.py
```

## Setting Up File Export

If DJ.Studio can export the current track to a file, this is the most reliable method.

### Option 1: Use a Standard Path

Create a file at one of the auto-detected paths:

```bash
mkdir -p ~/Documents/DJ.Studio
touch ~/Documents/DJ.Studio/current_track.txt
```

Then configure DJ.Studio (if possible) to export to this file.

### Option 2: Custom Path

If DJ.Studio exports to a different location:

```env
# .env file
DJSTUDIO_FILE_PATH=/Users/yourname/CustomPath/track.txt
```

### File Format

**Recommended:** Use plain text format for simplicity:
```
Artist Name - Track Title
```

**Advanced:** Use JSON for full metadata:
```json
{
  "artist": "Artist Name",
  "title": "Track Title",
  "album": "Album Name",
  "duration_ms": 240000,
  "progress_ms": 120000
}
```

## Troubleshooting

### Monitor Status

Check the monitor status in the VJ Console:

1. Launch `python vj_console.py`
2. Press `1` for Master Control screen
3. Look for "DJ.Studio" in the playback monitors section

Status indicators:
- **Available** - Monitor is working and has detected DJ.Studio
- **Unavailable** - DJ.Studio not detected or not playing

### Common Issues

#### "DJ.Studio not detected"

**Possible causes:**
- DJ.Studio is not running
- Window title doesn't contain track info
- No export file configured

**Solutions:**
1. Verify DJ.Studio is running
2. Check if window title shows track name
3. Configure file export (see above)

#### "File not found"

**Possible causes:**
- Export file doesn't exist
- Wrong file path configured
- Permissions issue

**Solutions:**
1. Verify file exists: `ls -la ~/Documents/DJ.Studio/current_track.txt`
2. Check file path in `.env`
3. Ensure file is readable: `chmod 644 ~/Documents/DJ.Studio/current_track.txt`

#### Track info not updating

**Possible causes:**
- File not being updated by DJ.Studio
- Window title not changing

**Solutions:**
1. Check if file timestamp updates: `ls -la ~/Documents/DJ.Studio/current_track.txt`
2. Verify window title shows current track
3. Check logs: Press `4` in VJ Console

### Debug Logging

Enable debug logging to see what the monitor is doing:

```bash
# Run with debug logging
LOG_LEVEL=DEBUG python vj_console.py
```

Look for lines like:
```
DJ.Studio: Monitoring window title
DJ.Studio: Monitoring file /path/to/file.txt
DJ.Studio: Detected via AppleScript
```

## Integration Examples

### Example 1: Window Title Only

No configuration needed. Just run DJ.Studio and Python VJ Tools:

```bash
# Terminal 1: Start DJ.Studio
open -a "DJ.Studio"

# Terminal 2: Start Python VJ Tools
cd python-vj
python vj_console.py
```

### Example 2: File Export

Setup a file export:

```bash
# Create export directory
mkdir -p ~/Documents/DJ.Studio

# Configure .env
echo "DJSTUDIO_FILE_PATH=$HOME/Documents/DJ.Studio/current_track.txt" >> .env

# Start Python VJ Tools
python vj_console.py
```

Then configure DJ.Studio to write current track to that file.

### Example 3: Disable DJ.Studio, Use VirtualDJ

If you use both DJ.Studio and VirtualDJ:

```bash
# Disable DJ.Studio monitoring
echo "DJSTUDIO_ENABLED=0" >> .env

# VirtualDJ will be used instead
python vj_console.py
```

## Testing

Test the monitor independently:

```python
from adapters import DJStudioMonitor

# Create monitor
monitor = DJStudioMonitor()

# Try to get playback
playback = monitor.get_playback()

if playback:
    print(f"Now playing: {playback['artist']} - {playback['title']}")
    print(f"Album: {playback['album']}")
    print(f"Progress: {playback['progress_ms']}ms / {playback['duration_ms']}ms")
else:
    print("DJ.Studio not detected")
```

## Future Enhancements

Potential improvements for DJ.Studio integration:

1. **Native Plugin** - DJ.Studio plugin that sends OSC directly
2. **API Integration** - If DJ.Studio adds a REST API
3. **MIDI Time Code** - Sync via MTC if supported
4. **Ableton Link** - Sync timing via Link protocol

## Support

If you have issues with DJ.Studio integration:

1. Check the [GitHub Issues](https://github.com/abossard/synesthesia-visuals/issues)
2. Enable debug logging and capture logs
3. Test with a simple file export first
4. Verify DJ.Studio version and capabilities

## Related Documentation

- [Python VJ README](../../README.md) - Main documentation
- [Architecture Guide](../development/architecture.md) - System design
- [OSC Protocol](../../README.md#osc-protocol) - OSC message format
