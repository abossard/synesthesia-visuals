# Implementation Plan: Multi-Process Architecture

## Overview

This document provides a step-by-step implementation plan for transforming python-vj from a monolithic threaded application to a resilient multi-process architecture.

Each phase is designed to:
- Keep the system runnable at every step
- Include automated tests for new functionality
- Provide manual verification procedures
- Build incrementally on previous phases

## Phase 1: Shared IPC Library (`vj_bus`)

**Goal:** Create the foundation for inter-process communication

**Duration:** 2-3 days

### Step 1.1: Create Package Structure

**Files to create:**
- `python-vj/vj_bus/__init__.py`
- `python-vj/vj_bus/schema.py`
- `python-vj/vj_bus/control.py`
- `python-vj/vj_bus/telemetry.py`
- `python-vj/vj_bus/worker.py`
- `python-vj/vj_bus/discovery.py`

**Actions:**
1. Create `vj_bus/` directory
2. Implement Pydantic message models in `schema.py`
3. Implement Unix socket control plane in `control.py`
4. Implement OSC telemetry helpers in `telemetry.py`
5. Create base `Worker` class in `worker.py`
6. Implement discovery protocol in `discovery.py`

**Tests:**
- Create `tests/test_vj_bus.py`
- Unit tests for message serialization/deserialization
- Unit tests for Unix socket send/receive
- Unit tests for worker discovery

**Verification:**
```bash
# Run unit tests
python -m pytest tests/test_vj_bus.py -v

# Manual test: Start mock worker, connect client
python -c "from vj_bus.control import ControlSocket; import time; s = ControlSocket('test'); s.create_server(); time.sleep(10)"
# In another terminal:
python -c "from vj_bus.control import ControlSocket; s = ControlSocket('test_client'); s.connect(); print('Connected!')"
```

**Acceptance Criteria:**
- ✓ All unit tests pass
- ✓ Messages serialize/deserialize correctly
- ✓ Unix sockets can send/receive messages
- ✓ Discovery scans socket directory correctly

### Step 1.2: Add Dependencies

**Files to modify:**
- `python-vj/requirements.txt`

**Actions:**
1. Add `pydantic>=2.0.0` for message schema validation

**Verification:**
```bash
pip install -r requirements.txt
python -c "import pydantic; print(pydantic.__version__)"
```

---

## Phase 2: Extract Audio Analyzer as Worker

**Goal:** Convert audio_analyzer from thread to standalone process

**Duration:** 3-4 days

### Step 2.1: Create Audio Worker Script

**Files to create:**
- `python-vj/vj_audio_worker.py`

**Actions:**
1. Copy audio analyzer logic from `vj_console.py`
2. Inherit from `vj_bus.Worker` base class
3. Implement `on_start()` - initialize audio analyzer
4. Implement `on_stop()` - cleanup audio resources
5. Implement `on_command()` - handle config changes, restart
6. Implement `get_stats()` - return current stats for heartbeat
7. Use `self.telemetry.send()` for OSC output

**Tests:**
- Create `tests/test_audio_worker.py`
- Test worker startup/shutdown
- Test config change via command
- Test OSC emission (60 fps)

**Verification:**
```bash
# Start audio worker standalone
python vj_audio_worker.py &

# Check socket created
ls /tmp/vj-bus/audio_analyzer.sock

# Connect and send command
python -c "
from vj_bus.control import ControlSocket
from vj_bus.schema import CommandMessage
s = ControlSocket('test')
s.connect()
cmd = CommandMessage(cmd='get_state', msg_id='test')
s.send_message(cmd)
print(s.recv_message())
"

# Check OSC output (requires OSC receiver)
# Should see /audio/levels messages at ~60 fps
```

**Acceptance Criteria:**
- ✓ Audio worker runs as standalone process
- ✓ Creates control socket at `/tmp/vj-bus/audio_analyzer.sock`
- ✓ Responds to `get_state` command
- ✓ Emits OSC telemetry at 60 fps
- ✓ Handles config changes and restarts gracefully

### Step 2.2: Integrate Audio Worker into TUI

**Files to modify:**
- `python-vj/vj_console.py`

**Actions:**
1. Remove audio analyzer thread code
2. Add worker discovery on TUI startup
3. Connect to audio worker control socket
4. Request worker state on connection
5. Send config commands when user toggles features
6. Keep OSC subscription (TUI-side, no worker changes needed)

**Tests:**
- Integration test: Start worker, start TUI, verify connection
- Integration test: Toggle feature in TUI, verify worker config changes

**Verification:**
```bash
# Start audio worker
python vj_audio_worker.py &

# Start TUI
python vj_console.py

# In TUI:
# 1. Press '5' to view Audio Analysis screen
# 2. Verify live audio features displayed
# 3. Press 'E' to toggle Essentia
# 4. Verify worker restarts with new config
# 5. Press Ctrl+C to exit TUI
# 6. Audio worker should still be running (check with ps)
```

**Acceptance Criteria:**
- ✓ TUI discovers and connects to audio worker
- ✓ Audio analysis screen shows live data
- ✓ Feature toggles send commands to worker
- ✓ Worker restarts when config changes
- ✓ TUI exit does NOT stop audio worker

---

## Phase 3: Extract Lyrics Fetcher as Worker

**Goal:** Convert lyrics fetcher + LLM to standalone process

**Duration:** 2-3 days

### Step 3.1: Create Lyrics Worker Script

**Files to create:**
- `python-vj/vj_lyrics_worker.py`

**Actions:**
1. Extract lyrics fetching and LLM logic from `karaoke_engine.py`
2. Inherit from `vj_bus.Worker`
3. Subscribe to track changes via OSC (worker-to-worker communication)
4. Fetch lyrics, perform LLM analysis
5. Emit results via OSC
6. Handle config commands (LLM provider, Ollama model, ComfyUI enable)

**Tests:**
- Test lyrics worker startup
- Test lyrics fetching for known track
- Test LLM analysis (with mock or real Ollama)
- Test OSC output for lyrics/categories

**Verification:**
```bash
# Start lyrics worker
python vj_lyrics_worker.py &

# Send fake track change
python -c "
from vj_bus.telemetry import TelemetrySender
t = TelemetrySender()
t.send('/karaoke/track', [1, 'test', 'Daft Punk', 'One More Time', 'Discovery', 180.0, 0])
"

# Check logs for lyrics fetch attempt
tail -f /tmp/vj-bus/lyrics_fetcher.log
```

**Acceptance Criteria:**
- ✓ Lyrics worker runs standalone
- ✓ Fetches lyrics for track changes
- ✓ Performs LLM analysis (refrain, keywords, image prompts)
- ✓ Emits OSC messages for lyrics/categories
- ✓ Handles config changes (LLM provider, etc.)

### Step 3.2: Integrate Lyrics Worker into TUI

**Files to modify:**
- `python-vj/vj_console.py`

**Actions:**
1. Remove lyrics/LLM thread code from TUI
2. Add lyrics worker to discovery
3. Connect to lyrics worker control socket
4. Subscribe to lyrics OSC output (already implemented)

**Verification:**
```bash
# Start lyrics worker
python vj_lyrics_worker.py &

# Start Spotify/VDJ monitor (next phase) or TUI
python vj_console.py

# Play a song in Spotify
# Verify lyrics appear in TUI
```

**Acceptance Criteria:**
- ✓ TUI connects to lyrics worker
- ✓ Lyrics display in TUI when song plays
- ✓ Categories panel shows mood/theme scores
- ✓ Image prompts generated (if ComfyUI enabled)

---

## Phase 4: Extract Playback Monitors as Workers

**Goal:** Convert Spotify and VirtualDJ monitors to standalone processes

**Duration:** 2-3 days

### Step 4.1: Create Spotify Monitor Worker

**Files to create:**
- `python-vj/vj_spotify_worker.py`

**Actions:**
1. Extract Spotify monitoring logic
2. Poll Spotify API every 2 seconds
3. Emit track changes via OSC
4. Handle config commands (poll interval)

**Acceptance Criteria:**
- ✓ Spotify worker runs standalone
- ✓ Detects track changes
- ✓ Emits OSC track/position messages

### Step 4.2: Create VirtualDJ Monitor Worker

**Files to create:**
- `python-vj/vj_virtualdj_worker.py`

**Actions:**
1. Extract VirtualDJ file watching logic
2. Watch `now_playing.txt` for changes
3. Emit track changes via OSC
4. Handle config commands (file path)

**Acceptance Criteria:**
- ✓ VDJ worker runs standalone
- ✓ Detects file changes
- ✓ Emits OSC track messages

---

## Phase 5: Process Manager Overhaul

**Goal:** Transform process manager into supervision daemon

**Duration:** 3-4 days

### Step 5.1: Redesign Process Manager

**Files to modify:**
- `python-vj/process_manager.py` → `python-vj/vj_process_manager.py`

**Actions:**
1. Create process manager as daemon (not part of TUI)
2. Start all enabled workers as subprocesses
3. Monitor heartbeats from workers (via control sockets)
4. Auto-restart crashed workers with exponential backoff
5. Provide process manager control socket
6. Handle TUI commands (start/stop/restart workers)

**Tests:**
- Integration test: Worker crash triggers restart
- Integration test: Max restart limit prevents restart loop
- Integration test: Heartbeat timeout detection

**Verification:**
```bash
# Start process manager (starts all workers)
python vj_process_manager.py &

# Check workers started
ls /tmp/vj-bus/*.sock

# Kill a worker
pkill -9 -f vj_audio_worker.py

# Wait 35 seconds, verify restart
ps aux | grep vj_audio_worker.py
```

**Acceptance Criteria:**
- ✓ Process manager starts all workers
- ✓ Detects crashed workers (heartbeat timeout)
- ✓ Restarts crashed workers automatically
- ✓ Respects max restart limit
- ✓ Responds to TUI control commands

### Step 5.2: Integrate Process Manager with TUI

**Files to modify:**
- `python-vj/vj_console.py`

**Actions:**
1. Connect to process manager control socket
2. Query worker status from process manager
3. Send start/stop/restart commands to process manager
4. Display worker health in TUI

**Verification:**
```bash
# Start process manager
python vj_process_manager.py &

# Start TUI
python vj_console.py

# In TUI:
# 1. View master control panel
# 2. Verify all workers shown as running
# 3. Toggle audio analyzer (A key)
# 4. Verify process manager stops/starts worker
```

**Acceptance Criteria:**
- ✓ TUI queries process manager for worker status
- ✓ TUI can start/stop workers via process manager
- ✓ TUI displays worker health (heartbeat status)

---

## Phase 6: OSC Debugger + Log Aggregation

**Goal:** Create debug worker for OSC capture and log aggregation

**Duration:** 2 days

### Step 6.1: Create Debug Worker

**Files to create:**
- `python-vj/vj_debug_worker.py`

**Actions:**
1. Listen on OSC port (as receiver, not sender)
2. Capture all OSC messages
3. Aggregate logs from worker heartbeats
4. Provide commands to retrieve messages/logs
5. Implement message filtering (by address pattern)

**Acceptance Criteria:**
- ✓ Debug worker captures OSC messages
- ✓ TUI can query recent messages
- ✓ TUI can query aggregated logs
- ✓ Message filtering works

### Step 6.2: Integrate Debug Worker with TUI

**Files to modify:**
- `python-vj/vj_console.py`

**Actions:**
1. Connect to debug worker
2. Request OSC messages for debug view (screen 2)
3. Request logs for logs view (screen 4)

**Verification:**
```bash
# Start all workers + TUI
python vj_process_manager.py &
python vj_console.py

# In TUI:
# 1. Press '2' for OSC view
# 2. Verify live OSC messages displayed
# 3. Press '4' for logs view
# 4. Verify aggregated logs from all workers
```

---

## Phase 7: TUI Refactoring

**Goal:** Simplify TUI to be stateless coordinator

**Duration:** 2-3 days

### Step 7.1: Remove Embedded Logic from TUI

**Files to modify:**
- `python-vj/vj_console.py`

**Actions:**
1. Remove all embedded worker logic (audio, lyrics, monitors)
2. Keep only discovery, connection, and UI rendering
3. TUI state is derived from worker state (no local cache)
4. Implement reconnection logic (on worker restart)

**Tests:**
- Integration test: TUI restart reconnects to workers
- Integration test: TUI handles worker disconnect/reconnect

**Verification:**
```bash
# Start workers
python vj_process_manager.py &

# Start TUI
python vj_console.py

# Kill TUI (Ctrl+C)

# Restart TUI
python vj_console.py

# Verify all worker data restored
```

**Acceptance Criteria:**
- ✓ TUI has no embedded worker logic
- ✓ TUI restart reconnects to workers
- ✓ No state loss on TUI restart
- ✓ TUI handles worker reconnections gracefully

---

## Phase 8: Integration Testing & Hardening

**Goal:** Comprehensive integration tests for all scenarios

**Duration:** 2-3 days

### Step 8.1: Integration Test Suite

**Files to create:**
- `tests/test_integration.py`

**Actions:**
1. Implement all integration tests from TESTING_STRATEGY.md
2. Test worker crash recovery
3. Test TUI crash recovery
4. Test high-frequency telemetry (60 fps audio)
5. Test config synchronization
6. Test process manager supervision

**Verification:**
```bash
python -m pytest tests/test_integration.py -v -s
```

**Acceptance Criteria:**
- ✓ All integration tests pass
- ✓ Workers survive TUI crash
- ✓ TUI reconnects to workers
- ✓ Process manager restarts crashed workers
- ✓ High-frequency telemetry works without blocking

### Step 8.2: Manual Testing

**Files to create:**
- `tests/manual_test.sh`

**Actions:**
1. Create manual test script
2. Test all failure scenarios manually
3. Verify performance (latency, throughput)
4. Test with real audio devices and Spotify

**Verification:**
```bash
cd tests
./manual_test.sh
```

---

## Phase 9: Developer Experience

**Goal:** Make it easy to develop and debug

**Duration:** 1-2 days

### Step 9.1: Dev Harness Script

**Files to create:**
- `scripts/dev_harness.py`

**Actions:**
1. Script to start all workers + TUI together
2. Convenient stop/restart commands
3. Log aggregation and viewing

**Verification:**
```bash
python scripts/dev_harness.py
```

**Acceptance Criteria:**
- ✓ Single command starts entire system
- ✓ Easy to restart individual workers
- ✓ Logs aggregated and easily viewable

### Step 9.2: Documentation

**Files to create:**
- `docs/MIGRATION_GUIDE.md`
- `docs/TROUBLESHOOTING.md`

**Actions:**
1. Document migration from old architecture
2. Create troubleshooting guide
3. Document worker protocol and message schemas

---

## Phase 10: Deployment & Cleanup

**Goal:** Final polish and deployment

**Duration:** 1-2 days

### Step 10.1: Cleanup Old Code

**Files to delete:**
- Old threaded code in `vj_console.py`
- Unused imports and functions

**Actions:**
1. Remove all old threaded implementations
2. Update README with new architecture
3. Update screenshots (if UI changed)

### Step 10.2: CI/CD

**Files to create:**
- `.github/workflows/test-vj-architecture.yml`

**Actions:**
1. Add GitHub Actions workflow for testing
2. Run unit + integration tests on PR
3. Ensure tests pass before merge

---

## Summary Timeline

| Phase | Duration | Cumulative |
|-------|----------|------------|
| 1. Shared IPC Library | 2-3 days | 3 days |
| 2. Audio Analyzer Worker | 3-4 days | 7 days |
| 3. Lyrics Fetcher Worker | 2-3 days | 10 days |
| 4. Playback Monitors | 2-3 days | 13 days |
| 5. Process Manager | 3-4 days | 17 days |
| 6. OSC Debugger | 2 days | 19 days |
| 7. TUI Refactoring | 2-3 days | 22 days |
| 8. Integration Testing | 2-3 days | 25 days |
| 9. Developer Experience | 1-2 days | 27 days |
| 10. Deployment | 1-2 days | 29 days |

**Total: ~4-5 weeks of development**

## Risk Mitigation

### Risk: Breaking existing functionality

**Mitigation:**
- Keep old code alongside new code during transition
- Implement feature flags to toggle between old/new
- Extensive testing at each phase

### Risk: Performance degradation

**Mitigation:**
- Benchmark at each phase
- Use profiling to identify bottlenecks
- Optimize IPC if needed (binary protocol, shared memory)

### Risk: Increased complexity

**Mitigation:**
- Clear documentation at each step
- Simple, consistent patterns across workers
- Dev harness for easy local development

### Risk: Platform-specific issues

**Mitigation:**
- Test on macOS and Linux
- Use cross-platform libraries (Pydantic, pythonosc)
- Provide fallbacks for missing features

## Success Metrics

1. **Resilience:** TUI crash does not stop workers
2. **Reconnection:** TUI reconnects to workers within 5 seconds
3. **Auto-Restart:** Crashed worker restarts within 35 seconds
4. **Performance:** Audio telemetry maintains 60 fps
5. **Latency:** OSC end-to-end latency < 30ms
6. **Reliability:** System runs 24+ hours without crashes
7. **Testability:** >80% code coverage with unit + integration tests

## Post-Implementation

### Monitoring

- Add metrics collection (worker uptime, message counts, error rates)
- Create dashboard for system health
- Log aggregation to single file

### Optimization

- Consider binary protocol for control sockets (protobuf, msgpack)
- Implement shared memory for high-frequency data
- Add worker affinity (pin to CPU cores)

### Future Enhancements

- Web-based TUI (replace Textual with FastAPI + React)
- Remote monitoring and control
- Distributed architecture (workers on different machines)
- Kubernetes deployment for cloud VJ
