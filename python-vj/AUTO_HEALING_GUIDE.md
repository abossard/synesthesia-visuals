# VJ Console - Auto-Healing System Guide

## 🎯 Overview

The VJ Console now features **automatic worker startup** and **self-healing capabilities**, making it robust and easy to use. The system uses an orchestrator pattern where the console communicates with a process manager daemon that handles all worker lifecycle management.

## 🏗️ Architecture

```
┌──────────────────────────────────────────────────────────┐
│                    VJ Console (TUI)                      │
│  • Multi-screen interface                               │
│  • Real-time visualization                              │
│  • Worker status monitoring                             │
└───────────────────┬──────────────────────────────────────┘
                    │ VJ Bus Commands
                    ↓
┌──────────────────────────────────────────────────────────┐
│           Process Manager Daemon (Orchestrator)          │
│  • Auto-start workers on demand                         │
│  • Health monitoring (PID + heartbeat)                  │
│  • Auto-restart crashed workers                         │
│  • Exponential backoff (5s → 10s → 20s → 40s...)       │
│  • Maximum 10 restart attempts per worker               │
└───────────────────┬──────────────────────────────────────┘
                    │ Manages
                    ↓
┌──────────────────────────────────────────────────────────┐
│                        Workers                           │
│  • spotify_monitor     - Spotify playback tracking      │
│  • virtualdj_monitor   - VirtualDJ state monitoring     │
│  • lyrics_fetcher      - Lyrics fetching & analysis     │
│  • osc_debugger        - OSC message logging            │
│  • log_aggregator      - Centralized log collection     │
│  • audio_analyzer      - Real-time audio analysis       │
└──────────────────────────────────────────────────────────┘
```

## 🚀 Quick Start

### Method 1: One-Command Startup (Recommended)

```bash
cd python-vj
./start_vj.sh
```

That's it! The script will:
1. ✅ Activate virtual environment
2. ✅ Check dependencies
3. ✅ Start the console
4. ✅ Console auto-starts process manager
5. ✅ Process manager starts all workers
6. ✅ Auto-healing monitors everything

### Method 2: Manual Start

```bash
cd python-vj
source ../.venv/bin/activate  # or source .venv/bin/activate
python vj_console.py
```

## 🔄 Auto-Start Behavior

When the console starts:

1. **Process Manager Check**: Console checks if process manager is running
   - If not found: Starts process manager daemon
   - If found: Connects to existing instance

2. **Worker Startup Requests**: Console sends commands to process manager:
   ```
   📡 Requesting process manager to start all workers...
     ✓ spotify_monitor started
     ✓ virtualdj_monitor started
     ✓ lyrics_fetcher started
     ✓ osc_debugger started
     ✓ log_aggregator started
   ```

3. **Fallback Mode**: If process manager unavailable:
   - Console starts workers directly
   - Limited auto-healing (only process manager monitoring)

## 🛡️ Auto-Healing Features

### Two-Level Healing

#### 1. Worker-Level Healing (Process Manager)
The process manager continuously monitors all workers:

- **Health Checks** (every 5 seconds):
  - PID check: Is process still running?
  - Heartbeat check: Is registry heartbeat fresh? (<15s)

- **Crash Detection**:
  ```
  ⚠️  Worker spotify_monitor crashed (exit code: 1)
  🔄 Auto-restarting spotify_monitor in 5s (attempt 1/10)
  ✓ Worker spotify_monitor restarted (PID: 12345)
  ```

- **Exponential Backoff**:
  - Attempt 1: 5s delay
  - Attempt 2: 10s delay
  - Attempt 3: 20s delay
  - ...
  - Max: 300s (5 minutes)

- **Restart Limit**: 10 attempts per worker

#### 2. Orchestrator-Level Healing (Console)
The console monitors the process manager itself:

- **Health Checks** (every 10 seconds):
  - Is process manager running?

- **Recovery**:
  ```
  ❌ Process manager crashed (exit code: 1)
  🔄 Restarting process manager in 2s...
  ✓ Process manager restarted (PID: 12346)
  📡 Re-requesting worker starts...
  ```

- **Restart Limit**: 3 attempts for process manager

## 📊 Console Screens

Press number keys to navigate:

### Screen 0: Overview
```
┌─══ VJ Bus Workers ══─────────────────────┐
│ ✓ 5 workers connected                    │
│   ● spotify_monitor                       │
│     Ports: 5001/5101                      │
│   ● virtualdj_monitor                     │
│     Ports: 5002/5102                      │
│   ...                                     │
└──────────────────────────────────────────┘

┌─══ Quick Metrics ══──────────────────────┐
│ Playback: ▶ Spotify                      │
│ Lyrics: ✓ 42 lines                       │
│ Mood: energetic                          │
│ Audio: ● 128 BPM                         │
└──────────────────────────────────────────┘
```

### Screen 1: Playback
```
┌─══ Playback State ══─────────────────────┐
│ Source: Spotify                          │
│ Status: ▶ Playing                        │
│                                          │
│ Track:                                   │
│   Artist: Example Artist                 │
│   Title:  Example Song                   │
│   Album:  Example Album                  │
│   Duration: 3:45                         │
│                                          │
│   ████████████████░░░░░░░░░░░░░░        │
│   2:15 / 3:45                           │
└──────────────────────────────────────────┘
```

### Screen 2: Lyrics & AI
```
┌─══ Lyrics Status ══──────────────────────┐
│ Current Track:                           │
│   Example Artist - Example Song          │
│                                          │
│ ✓ Lyrics Available                       │
│   Lines: 42                              │
│                                          │
│ Keywords:                                │
│   love, dance, night, party, freedom    │
│                                          │
│ Themes:                                  │
│   celebration, romance                   │
└──────────────────────────────────────────┘

┌─══ Song Categories ══────────────────────┐
│ Primary Mood: ENERGETIC                  │
│                                          │
│   energetic       ████████████░  0.85   │
│   danceable       ██████████░░  0.72   │
│   happy           ████████░░░░  0.68   │
│   romantic        ██████░░░░░░  0.45   │
└──────────────────────────────────────────┘
```

### Screen 3: Audio
```
┌─══ Audio Analysis ══─────────────────────┐
│ Guide Pulse Stack                        │
│   ⚡ Bass     ████████████  0.78         │
│   · Mids     ██████░░░░░░  0.45         │
│   · Highs    ████░░░░░░░░  0.32         │
│                                          │
│ Overall Energy  ██████████████░░  0.82  │
│                                          │
│ Core Triggers                            │
│   ● synced  BPM 128.0 (conf 0.95)      │
│   Pitch 440.2 Hz (conf 0.88)            │
│                                          │
│ Structure Signals                        │
│   ↗ BUILD-UP  energy +0.15              │
│   ↓ drop      brightness 0.62           │
└──────────────────────────────────────────┘
```

### Screen 4: OSC
```
┌─══ OSC Debug ══──────────────────────────┐
│ 21:15:32 /karaoke/categories [0.85...]  │
│ 21:15:32 /vj/mood energetic              │
│ 21:15:32 /audio/beat [1, 128.0]         │
│ 21:15:32 /audio/levels [0.78, 0.45...] │
│ 21:15:31 /karaoke/lyric/current ...     │
│ ...                                      │
└──────────────────────────────────────────┘
```

### Screen 5: Logs
```
┌─══ Application Logs ══───────────────────┐
│ 2025-12-04 21:15:30 - INFO - ✓ Worker   │
│   spotify_monitor started                │
│ 2025-12-04 21:15:31 - INFO - ✓ Worker   │
│   lyrics_fetcher started                 │
│ 2025-12-04 21:15:35 - INFO - Discovered │
│   5 workers                              │
│ ...                                      │
└──────────────────────────────────────────┘
```

## ⌨️ Keyboard Controls

### Navigation
- `0-5` - Switch between screens
- `q` - Quit (gracefully stops all workers)

### App Control
- `s` - Toggle Synesthesia
- `m` - Toggle MilkSyphon
- `a` - Toggle Audio Analyzer
- `b` - Run audio benchmark

### Audio Features
- `e` - Toggle Essentia DSP
- `p` - Toggle Pitch Detection
- `o` - Toggle Beat/BPM
- `t` - Toggle Structure Detection
- `y` - Toggle Spectrum OSC
- `l` - Toggle Analyzer Logging

## 🔧 Configuration

### Auto-Start Control

Edit `vj_console.py` `__init__` method:
```python
self._auto_start_workers = True   # Enable/disable auto-start
self._auto_heal_workers = True    # Enable/disable auto-healing
```

### Worker Selection

Edit `process_manager_daemon.py` `WORKER_CONFIGS`:
```python
WORKER_CONFIGS = [
    ("spotify_monitor", "workers/spotify_monitor_worker.py"),
    ("virtualdj_monitor", "workers/virtualdj_monitor_worker.py"),
    # Add or remove workers as needed
]
```

## 🐛 Troubleshooting

### Workers not starting

**Check logs** (Press `5`):
```
2025-12-04 21:15:30 - ERROR - ✗ Failed to start spotify_monitor: ...
```

**Verify worker scripts exist**:
```bash
ls -la workers/
```

**Check process manager**:
```bash
ps aux | grep process_manager
```

### Workers keep crashing

**Check worker-specific logs**:
- Each worker logs to console output
- Look for Python exceptions or configuration errors

**Common issues**:
- Missing API credentials (Spotify, OpenAI, etc.)
- Network connectivity
- Port conflicts
- Missing dependencies

**Manual worker test**:
```bash
python workers/spotify_monitor_worker.py
```

### Process manager not responding

**Check if running**:
```bash
ps aux | grep process_manager_daemon
```

**Restart manually**:
```bash
pkill -f process_manager_daemon
python workers/process_manager_daemon.py &
```

**Console will auto-restart**: If process manager crashes, console detects and restarts it automatically.

## 📈 Monitoring

### Real-Time Status

**Overview Screen (0)** shows:
- Number of connected workers
- Worker names and ports
- Quick metrics from all workers

**Services Panel** shows:
- VJ Bus mode status
- Connected worker count
- Individual worker names

### Health Indicators

- **Green ✓**: Worker healthy and connected
- **Yellow ⚠**: Worker starting or reconnecting
- **Red ❌**: Worker failed after max restarts

### Log Messages

Key log patterns to watch:
```
✓ - Success
⚠️ - Warning (temporary)
❌ - Error (serious)
🔄 - Auto-restart in progress
📡 - VJ Bus communication
🚀 - Startup
🛑 - Shutdown
```

## 🎯 Best Practices

1. **Always use ./start_vj.sh** - Ensures proper environment setup

2. **Monitor Overview screen** - Quick health check of entire system

3. **Check logs regularly** - Early warning of issues

4. **Graceful shutdown** - Press `q` to stop console cleanly
   - Console stops all workers automatically
   - Prevents orphaned processes

5. **Worker restart limits** - If worker hits restart limit:
   - Fix underlying issue
   - Restart console to reset counters

6. **Process manager first** - If manually starting workers:
   - Start process manager first
   - Let it manage worker lifecycle

## 🔬 Advanced Usage

### Manual Worker Control

**Via VJ Bus Client**:
```python
from vj_bus.client import VJBusClient

client = VJBusClient()

# Start worker
response = client.send_command(
    "process_manager",
    "start_worker",
    {"worker": "spotify_monitor"}
)

# Stop worker
response = client.send_command(
    "process_manager",
    "stop_worker",
    {"worker": "spotify_monitor"}
)

# List workers
response = client.send_command(
    "process_manager",
    "list_workers",
    {}
)
```

### Custom Health Checks

Extend `ProcessManagerDaemon._check_worker()` to add custom checks:
```python
def _check_worker(self, worker: ManagedWorker):
    # Custom check example
    if worker.name == "spotify_monitor":
        # Check Spotify API connectivity
        if not self._check_spotify_api():
            self._restart_worker(worker)
```

## 📝 Summary

The auto-healing system provides:

✅ **Zero-configuration startup** - Just run the console
✅ **Automatic recovery** - Workers restart on failure
✅ **Intelligent backoff** - Prevents restart loops
✅ **Multi-level monitoring** - Workers and orchestrator
✅ **Graceful degradation** - Fallback modes if needed
✅ **Comprehensive logging** - Track all lifecycle events
✅ **User-friendly UI** - Real-time status visualization

The system is designed to **just work** - start it and let it manage itself!

---

**Need help?** Check the logs screen (press `5`) or review `VJBUS_INTEGRATION_SUMMARY.md` for architecture details.
