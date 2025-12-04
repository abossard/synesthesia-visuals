# VJ Console - Quick Start Guide

## 🚀 Easy Startup (Recommended)

The VJ Console now features **auto-start** and **auto-healing** capabilities for a seamless experience.

### One-Command Startup

```bash
cd python-vj
./start_vj.sh
```

That's it! The console will:
- ✅ Auto-start all essential workers (Spotify, VirtualDJ, Lyrics, OSC, Logs)
- ✅ Monitor worker health continuously
- ✅ Auto-restart crashed workers with exponential backoff
- ✅ Provide real-time status across multiple screens

## 📊 Console Screens

Press the number keys to switch between screens:

- **0** - Overview: Quick view of all workers and metrics
- **1** - Playback: Detailed VirtualDJ/Spotify monitoring
- **2** - Lyrics & AI: Song analysis and categorization
- **3** - Audio: Real-time audio analysis (if available)
- **4** - OSC: OSC message debugging
- **5** - Logs: Application logs

## 🛡️ Auto-Healing Features

The console includes robust auto-healing:

1. **Worker Health Monitoring**: Checks worker status every 10 seconds
2. **Automatic Restart**: Crashed workers restart automatically with backoff
3. **Exponential Backoff**: 1s → 2s → 4s → 8s → 16s → 30s (max)
4. **Retry Limit**: Up to 5 restart attempts per worker
5. **Graceful Shutdown**: Workers stop cleanly when console exits

## ⚙️ Features

- **Multi-Screen TUI**: Beautiful terminal interface with tabbed views
- **Worker Architecture**: Distributed VJ Bus communication
- **Real-Time Updates**: Live playback, lyrics, and audio analysis
- **OSC Integration**: Synesthesia, Processing, and more
- **Service Status**: Monitor Spotify, VirtualDJ, Ollama, ComfyUI
- **Audio Analysis**: Real-time frequency analysis and beat detection

## 🎹 Keyboard Controls

### Navigation
- `0-5` - Switch screens
- `q` - Quit application

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

## 🔧 Manual Worker Management

If you need to start workers manually:

```bash
# Start specific workers
python workers/spotify_monitor_worker.py
python workers/virtualdj_monitor_worker.py
python workers/lyrics_fetcher_worker.py
python workers/osc_debugger_worker.py
python workers/log_aggregator_worker.py
```

Or use the development harness:

```bash
# Start all workers
python dev/start_all_workers.py

# List available workers
python dev/start_all_workers.py --list

# Monitor running workers
python dev/start_all_workers.py --monitor
```

## 📝 Logs

All logs are captured and displayed in the Logs screen (press `5`). Logs are also written to:
- Console output
- Individual worker logs (if configured)

## 🆘 Troubleshooting

### Workers not starting
- Check that all worker scripts exist in `workers/` directory
- Check Python dependencies: `pip install -r requirements.txt`
- Check logs for error messages

### Workers keep crashing
- Check the Logs screen (press `5`) for error details
- Verify external services (Spotify API, VirtualDJ, etc.) are configured
- Check network connectivity for remote services

### No playback detected
- Ensure Spotify or VirtualDJ is running
- Check Spotify API credentials in `.env` file
- Verify VirtualDJ info file exists

## 💡 Tips

1. **Start with Overview screen** - Get a quick view of system health
2. **Check Services panel** - Verify all external services are connected
3. **Use Logs screen** - Debug issues with detailed logs
4. **Watch worker counts** - Green checkmark = all workers connected
5. **Auto-healing active** - Crashed workers restart automatically

## 🎯 Architecture

The system uses a pure VJ Bus architecture:
- **Console** - TUI interface (this application)
- **Workers** - Independent processes communicating via VJ Bus
- **VJ Bus** - Message bus for command/telemetry communication
- **Registry** - Service discovery and health monitoring

All workers are loosely coupled and can be started/stopped independently.

---

**Enjoy your VJ session! 🎵🎨**
