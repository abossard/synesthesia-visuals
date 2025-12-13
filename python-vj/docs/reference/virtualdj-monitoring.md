# VirtualDJ Monitoring

Research and implementation details for VirtualDJ integration in the karaoke engine.

---

## Can VirtualDJ be monitored via AppleScript?

**Answer: No** — VirtualDJ does not expose an AppleScript dictionary or API.

### Background

Unlike Spotify, iTunes, or Music.app which have native AppleScript support, VirtualDJ does not provide scriptable access to its playback state. This means:

- ❌ Cannot query current track via AppleScript
- ❌ Cannot get playback position via AppleScript  
- ❌ Cannot control playback via AppleScript
- ✅ **Can** read track info from text files written by VirtualDJ

---

## Current Implementation

The `VirtualDJMonitor` adapter uses **file-based polling** — the standard integration method for VirtualDJ.

### How It Works

1. **VirtualDJ writes** track info to a text file during playback
2. **Monitor reads** the file periodically (every poll cycle)
3. **Parser extracts** artist and title from the file content

### File Locations

VirtualDJ can write to several locations (auto-detected in priority order):

```
~/Library/Application Support/VirtualDJ/History/tracklist.txt  (macOS standard)
~/Documents/VirtualDJ/History/tracklist.txt
~/Documents/VirtualDJ/History/now_playing.txt
~/Documents/VirtualDJ/now_playing.txt
~/Music/VirtualDJ/now_playing.txt
/tmp/virtualdj_now_playing.txt
```

### File Formats Supported

**Single-line format:**
```
Artist Name - Track Title
```

**Multi-line tracklist format:**
```
VirtualDJ History 2024/11/30
------------------------------
22:50 : Bolier, Joe Stone - Keep This Fire Burning
22:53 : Calvin Harris - Summer
```

The monitor reads the **last timestamped entry** from tracklist format.

---

## Priority System

The karaoke engine checks monitors in priority order:

```python
# In karaoke_engine.py
monitors = []
if Config.SPOTIFY_APPLESCRIPT_ENABLED:
    monitors.append(AppleScriptSpotifyMonitor())  # 1st priority
if Config.SPOTIFY_WEBAPI_ENABLED:
    monitors.append(SpotifyMonitor())              # 2nd priority
monitors.append(VirtualDJMonitor(vdj_path))        # 3rd priority (fallback)
```

### How Priority Works

The `PlaybackCoordinator` polls monitors in order:

```python
# In orchestrators.py
for monitor in self._monitors:
    playback = monitor.get_playback()
    if playback:
        self._current_source = self._monitor_key(monitor)
        break  # Stop at first successful monitor
```

**Result:** VirtualDJ is **only active when Spotify is not playing**.

---

## Configuration

### Enable/Disable Spotify Monitors

Control which monitors are active via environment variables:

```bash
# .env file
SPOTIFY_APPLESCRIPT_ENABLED=1  # Default: enabled
SPOTIFY_WEBAPI_ENABLED=0       # Default: disabled
```

### VirtualDJ File Path Override

```bash
# Manually specify VirtualDJ file path
python vj_console.py --vdj-path ~/custom/path/tracklist.txt
```

---

## Alternative: VirtualDJ API

VirtualDJ **Pro** version includes a REST API that could be used instead of file polling.

### Pros
- Real-time playback state
- More detailed metadata
- Two-way control (query + control)

### Cons
- Requires VirtualDJ Pro license
- Network overhead
- More complex setup
- Less common in DJ setups

**Recommendation:** Stick with file-based monitoring for simplicity and broad compatibility.

---

## Troubleshooting

### VirtualDJ not detected

1. **Check file exists:** Verify VirtualDJ is writing the tracklist file
   ```bash
   ls -la ~/Library/Application\ Support/VirtualDJ/History/tracklist.txt
   ```

2. **Enable history logging in VirtualDJ:**
   - Settings → Options → History
   - Enable "Write history to file"

3. **Check permissions:** Ensure python-vj can read the file
   ```bash
   cat ~/Library/Application\ Support/VirtualDJ/History/tracklist.txt
   ```

### VirtualDJ taking priority over Spotify

This should not happen if priority system is working. Debug by checking:

```python
# In vj_console.py, Master Control screen shows current source
Current Source: spotify_local  # Good - Spotify is playing
Current Source: virtualdj      # Only when Spotify is idle
```

---

## Code References

- **Monitor implementation:** `adapters.py` → `VirtualDJMonitor` (lines 500-638)
- **Priority system:** `orchestrators.py` → `PlaybackCoordinator.poll()` (lines 61-72)
- **Monitor initialization:** `karaoke_engine.py` (lines 112-118)
- **Configuration:** `infrastructure.py` → `Config.find_vdj_path()` (lines 63-68)

---

## Summary

✅ **VirtualDJ monitoring works** via file polling (not AppleScript)  
✅ **Priority system works** — VirtualDJ is fallback when Spotify idle  
✅ **No code changes needed** — existing implementation is correct  
❌ **AppleScript not possible** — VirtualDJ has no scriptable interface
