# Magic Music Visuals - CLI Options and Integration

## Overview

Magic Music Visuals is a macOS application for live visual performance. This guide documents command-line integration with the python-vj console.

## Available Files in Project

The `magic/` directory contains production-ready Magic project files:

| File | Size | Purpose |
|------|------|---------|
| `master.magic` | 8.8KB | Main Magic project file with full VJ setup |
| `master-bus.magic` | 8.8KB | Bus/routing variant of master project |
| `lyrics.magic` | 1.8KB | Lyrics-focused display project |

## Launch Methods

### Standard Launch (No File)

```bash
open -a "Magic"
```

Launches Magic Music Visuals without opening a specific project file.

### Launch with Project File

```bash
open -a "Magic" /path/to/project.magic
```

Opens Magic and loads the specified `.magic` project file.

**Example with project files:**
```bash
# Launch with master project
open -a "Magic" "$PWD/magic/master.magic"

# Launch with lyrics overlay
open -a "Magic" "$PWD/magic/lyrics.magic"
```

### Via Python VJ Console

The VJ Console provides integrated launch control:

1. **Manual Launch**: Check "Magic Music Visuals" in Startup Services panel
2. **Auto-launch**: Enable both checkboxes (Magic + Auto-restart)
3. **File Selection**: Set `magic_file_path` in settings to auto-load a specific file

**Settings Location**: `~/.config/vj-console/settings.json`

```json
{
  "start_magic": true,
  "autorestart_magic": true,
  "magic_file_path": "/path/to/synesthesia-visuals/magic/master.magic"
}
```

## Process Detection

Magic runs as a macOS application with process name `Magic`:

```bash
# Check if running
pgrep -x "Magic"

# View details
ps aux | grep -i magic

# Stop process
pkill -x "Magic"
```

## VJ Console Integration

### Features

- ✅ **Auto-start** - Launch on console startup
- ✅ **Auto-restart** - Restart if crashed
- ✅ **Resource Monitoring** - CPU/memory tracking
- ✅ **File Selection** - Open specific .magic file
- ✅ **Start/Stop** - Centralized control with other VJ services

### Architecture

```
VJ Console (python-vj/vj_console.py)
    │
    ├─ Settings (infrastructure.py)
    │   ├─ start_magic: bool
    │   ├─ autorestart_magic: bool
    │   └─ magic_file_path: str
    │
    ├─ Process Manager
    │   ├─ _is_magic_running() → pgrep -x Magic
    │   ├─ _start_magic() → open -a Magic [file]
    │   └─ _check_apps_and_autorestart()
    │
    └─ UI (StartupControlPanel)
        ├─ Magic checkbox
        ├─ Auto-restart checkbox
        └─ Resource stats display
```

## Command-Line Arguments

**Note**: Magic Music Visuals does NOT support traditional command-line arguments. The macOS `open` command is used for launching.

### What Works

✅ **File argument**: `open -a "Magic" file.magic`
✅ **Process detection**: `pgrep`, `ps`, `pkill`
✅ **macOS integration**: Launch via Finder, Dock, or command line

### What Does NOT Work

❌ **CLI flags**: Magic doesn't support flags like `--fullscreen`, `--preset`, etc.
❌ **Headless mode**: No server/CLI-only mode available
❌ **Scripting API**: No built-in CLI scripting interface

**Workaround**: Use OSC (Open Sound Control) for external control via network protocol. See [Magic Music Visuals Guide](./magic-music-visuals-guide.md) for OSC patterns.

## OSC Control Integration

For runtime control, Magic supports OSC:

```python
# Example: Send OSC to Magic
from pythonosc import udp_client

client = udp_client.SimpleUDPClient("127.0.0.1", 8000)
client.send_message("/magic/intensity", 0.8)
client.send_message("/magic/buildLevel", 0.5)
```

Refer to the [Magic Music Visuals Guide](./magic-music-visuals-guide.md) for complete OSC address documentation.

## Troubleshooting

### Magic Won't Launch

**Check installation:**
```bash
ls -la /Applications/ | grep -i magic
# Should show: Magic.app or similar
```

**Verify executable:**
```bash
open -a "Magic"  # Test direct launch
```

**Check logs:**
```bash
# macOS system logs
log show --predicate 'process == "Magic"' --last 5m
```

### Process Not Detected

**Check process name:**
```bash
ps aux | grep -i magic
# Look for exact process name (case-sensitive)
```

**Update detection:**
If the process name differs, update `vj_console.py`:
```python
def _is_magic_running(self) -> bool:
    return self._run_process(['pgrep', '-xi', 'Magic'], 1)
    # -xi = case-insensitive exact match
```

### File Won't Open

**Verify file exists:**
```bash
ls -la magic/master.magic
```

**Test direct open:**
```bash
open magic/master.magic
# Should launch Magic with the file
```

**Absolute path required:**
The VJ console uses absolute paths. Relative paths may fail.

```python
# Good
magic_file_path = "/Users/you/synesthesia-visuals/magic/master.magic"

# Bad
magic_file_path = "magic/master.magic"
```

## Comparison with Other VJ Apps

| Feature | Magic | Synesthesia | Processing |
|---------|-------|-------------|------------|
| Launch method | `open -a` | `open -a` | `processing-java --run` |
| File loading | .magic files | .synScene | .pde sketches |
| CLI args | ❌ No | ❌ No | ✅ Yes |
| Headless mode | ❌ No | ❌ No | ✅ Yes |
| OSC control | ✅ Yes | ✅ Yes | ✅ Yes (custom) |
| Process name | `Magic` | `Synesthesia` | `java` |

## Best Practices

1. **Use absolute paths** for .magic files
2. **Enable auto-restart** for live performance reliability
3. **Monitor resources** via VJ Console stats panel
4. **Combine with OSC** for runtime parameter control
5. **Test file loading** before live performance
6. **Keep backup** of working .magic files

## Advanced: Programmatic Control

### Python Example

```python
import subprocess
from pathlib import Path

def launch_magic(magic_file: str = None):
    """Launch Magic Music Visuals with optional file."""
    cmd = ['open', '-a', 'Magic']
    if magic_file and Path(magic_file).exists():
        cmd.append(str(Path(magic_file).absolute()))
    subprocess.Popen(cmd)

def is_magic_running():
    """Check if Magic is running."""
    result = subprocess.run(['pgrep', '-x', 'Magic'], 
                          capture_output=True)
    return result.returncode == 0

def stop_magic():
    """Stop Magic if running."""
    subprocess.run(['pkill', '-x', 'Magic'], check=False)

# Usage
launch_magic('magic/master.magic')
```

### Shell Script Example

```bash
#!/bin/bash
# launch_magic.sh - Launch Magic with VJ setup

MAGIC_FILE="${1:-magic/master.magic}"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FULL_PATH="$PROJECT_ROOT/$MAGIC_FILE"

if [ ! -f "$FULL_PATH" ]; then
    echo "Error: Magic file not found: $FULL_PATH"
    exit 1
fi

echo "Launching Magic with: $FULL_PATH"
open -a "Magic" "$FULL_PATH"
```

## Related Documentation

- [Magic Music Visuals Guide](./magic-music-visuals-guide.md) - Complete operational guide
- [MMV Master Pipeline Guide](./mmv-master-pipeline-guide.md) - Production setup
- [Live VJ Setup Guide](../setup/live-vj-setup-guide.md) - Full rig integration
- [Python VJ Console](../../python-vj/README.md) - Console documentation

## External Resources

- [Magic Music Visuals Website](https://magicmusicvisuals.com/)
- [Magic User Guide](https://magicmusicvisuals.com/downloads/Magic_UsersGuide.html)
- [Magic Forums](https://magicmusicvisuals.com/forums)
- [OSC Protocol Specification](http://opensoundcontrol.org/)
