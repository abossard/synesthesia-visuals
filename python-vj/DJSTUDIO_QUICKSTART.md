# DJ.Studio Integration - Quick Start

This file provides a quick reference for using DJ.Studio with Python VJ Tools.

## TL;DR

DJ.Studio monitoring is **enabled by default**. Just run your DJ.Studio mix and start the VJ console:

```bash
cd python-vj
python vj_console.py
```

The system will automatically detect your current track from DJ.Studio.

## How to Verify It's Working

1. Start DJ.Studio and play a mix
2. Launch `python vj_console.py`
3. Press `1` to open Master Control screen
4. Look for "DJ.Studio" in the playback monitors section
5. Check that current track is displayed

## Setup Options

### Option 1: Window Title (Default, No Setup)

Works if DJ.Studio shows track info in its window title. No configuration needed.

### Option 2: File Export (Recommended for Reliability)

If DJ.Studio can export current track to a file:

```bash
# Create export directory
mkdir -p ~/Documents/DJ.Studio

# Add to .env (if needed)
echo "DJSTUDIO_FILE_PATH=$HOME/Documents/DJ.Studio/current_track.txt" >> .env
```

File format (plain text):
```
Artist Name - Track Title
```

Or JSON for full metadata:
```json
{
  "artist": "Artist Name",
  "title": "Track Title",
  "album": "Album Name",
  "duration_ms": 240000,
  "progress_ms": 120000
}
```

## Testing

Test DJ.Studio detection:

```bash
# Single test
python scripts/test_djstudio.py

# Watch mode (continuous)
python scripts/test_djstudio.py --watch

# Test with custom file
python scripts/test_djstudio.py --file /path/to/track.txt
```

## Configuration

Environment variables (`.env` file):

```env
# Enable/disable (default: enabled)
DJSTUDIO_ENABLED=1

# Custom file path
DJSTUDIO_FILE_PATH=/path/to/track/file.txt

# AppleScript timeout
DJSTUDIO_TIMEOUT=1.5
```

## Troubleshooting

**"DJ.Studio not detected"**
1. Is DJ.Studio running?
2. Is a track playing?
3. Check window title shows track name
4. Try file export method

**See full documentation:** `docs/guides/djstudio-integration.md`

## What Works

✅ Track detection (artist, title)
✅ Album name (if available)
✅ Duration/progress (if available)
✅ Automatic lyrics fetching
✅ Song categorization
✅ OSC output to VJ apps

## Monitor Priority

The system tries sources in this order:
1. Spotify (desktop app) - if actively playing
2. Spotify (Web API) - if enabled
3. **DJ.Studio** - if running
4. VirtualDJ - if tracklist.txt exists

## Support

- Issues: https://github.com/abossard/synesthesia-visuals/issues
- Full docs: `python-vj/docs/guides/djstudio-integration.md`
- Test script: `python scripts/test_djstudio.py --help`
