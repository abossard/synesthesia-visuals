# Python-VJ Multi-Process Architecture

## Overview

Python-VJ uses a resilient multi-process architecture where each subsystem runs as an independent OS process. The TUI becomes a thin orchestration layer that can crash and restart without losing worker state.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         User's System                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐         ┌─────────────────────┐             │
│  │   TUI        │◄────────│  Service Registry   │             │
│  │  (vj_console)│         │  (~/.vj/registry.json)│            │
│  │              │         └─────────────────────┘             │
│  └──────┬───────┘                                              │
│         │ ZMQ REQ/SUB                                          │
│         │                                                       │
│    ┌────┴─────────────────────────────────────┐                │
│    │                                           │                │
│    ▼                                           ▼                │
│  ┌──────────────┐  ┌───────────────┐  ┌──────────────┐        │
│  │process_manager│  │audio_analyzer │  │lyrics_fetcher│        │
│  │  (daemon)    │  │  (daemon)     │  │  (daemon)    │        │
│  │              │  │               │  │              │        │
│  │ ZMQ REP/PUB  │  │ ZMQ REP/PUB   │  │ ZMQ REP/PUB  │        │
│  └──────────────┘  └───────────────┘  └──────────────┘        │
│                                                                 │
│  OSC (UDP 9000) ──► External visualizers (Synesthesia, etc.)   │
└─────────────────────────────────────────────────────────────────┘
```

## Key Design Principles

1. **Resilience**: Workers survive TUI crashes and can be reconnected
2. **Independence**: Each worker is a separate OS process with its own lifecycle
3. **Discovery**: File-based service registry for zero-config discovery
4. **Hybrid IPC**: ZeroMQ for control + telemetry, OSC for external tools
5. **Observability**: All telemetry centralized, structured logging

## Components

### VJ Bus Library (`vj_bus/`)

Core IPC infrastructure used by all components:

- **`messages.py`**: Pydantic message schemas (commands, telemetry, events)
- **`registry.py`**: File-based service registry with atomic updates
- **`transport.py`**: ZeroMQ REP/PUB/REQ/SUB wrappers
- **`worker.py`**: Base class for all workers
- **`client.py`**: High-level client API for TUI

### Workers (`workers/`)

Independent processes that perform specific tasks:

- **`example_worker.py`**: Reference implementation
- **`audio_analyzer_worker.py`**: Real-time audio analysis (implemented)
- **`process_manager_daemon.py`**: Supervisor for all workers (TODO)
- **`lyrics_fetcher_worker.py`**: LLM-powered lyrics analysis (TODO)
- **`spotify_monitor_worker.py`**: Spotify playback monitoring (TODO)
- **`virtualdj_monitor_worker.py`**: VirtualDJ file monitoring (TODO)
- **`osc_debugger_worker.py`**: OSC message capture (TODO)

### TUI Client

- **`vj_console.py`**: Textual-based TUI (will be refactored to use VJBusClient)

## Communication Patterns

### Service Discovery

Workers register themselves in `~/.vj/registry.json`:

```json
{
  "version": "1.0",
  "services": {
    "audio_analyzer": {
      "pid": 12345,
      "status": "running",
      "heartbeat_at": 1733234567.89,
      "ports": {
        "command": 5001,
        "telemetry": 5002
      },
      "metadata": {...}
    }
  }
}
```

TUI reads registry on startup to discover available workers.

### Command Flow (TUI → Worker)

1. TUI sends CommandMessage via ZMQ REQ to worker's command port
2. Worker processes command and returns ResponseMessage
3. Pattern: Request-Response with timeout

Example commands:
- `health_check`: Verify worker is alive
- `get_state`: Get current worker state
- `set_config`: Update configuration
- `restart`: Restart worker
- `shutdown`: Graceful shutdown

### Telemetry Flow (Worker → TUI)

1. Worker publishes TelemetryMessage via ZMQ PUB on telemetry port
2. TUI subscribes to topics of interest
3. Pattern: Publish-Subscribe with topic filtering

Example topics:
- `audio.features`: Audio band energies, beat, BPM
- `audio.stats`: Performance statistics
- `logs.*`: Log messages from workers

### External OSC

Workers continue to send OSC messages (UDP) to external tools like Synesthesia for backward compatibility.

## Port Allocation

| Service | Command Port | Telemetry Port |
|---------|-------------|----------------|
| process_manager | 5000 | 5099 (events) |
| audio_analyzer | 5001 | 5002 |
| lyrics_fetcher | 5011 | 5012 |
| spotify_monitor | 5021 | 5022 |
| virtualdj_monitor | 5031 | 5032 |
| osc_debugger | 5041 | 5042 |
| example_worker | 5051 | 5052 |

## Worker Lifecycle

### Startup

1. Worker creates ZMQ sockets (REP for commands, PUB for telemetry)
2. Worker registers in service registry
3. Worker starts heartbeat thread (updates registry every 5s)
4. Worker enters main loop

### Runtime

- Worker publishes telemetry to subscribed clients
- Worker responds to commands from TUI
- Worker updates heartbeat periodically
- Worker handles SIGTERM/SIGINT for graceful shutdown

### Shutdown

1. Worker stops main loop
2. Worker cleans up resources (call `on_stop()`)
3. Worker unregisters from service registry
4. Worker closes ZMQ sockets

## Failure Modes

### TUI Crashes

- **Workers keep running** (independent processes)
- **TUI restarts** and reads registry
- **TUI reconnects** to command ports
- **TUI resubscribes** to telemetry

### Worker Crashes

- **Registry marks worker as stale** (no heartbeat for 15s)
- **process_manager detects crash** (PID gone)
- **process_manager restarts worker** (with exponential backoff)
- **TUI detects new worker** (registry update)
- **TUI reconnects** automatically

### Network Issues

- **Commands timeout** after 2 seconds
- **TUI shows disconnected** status
- **TUI retries** periodically

## Implementation Status

### ✅ Phase 1: Foundation (Completed)

- [x] VJ Bus module structure
- [x] Message schemas with Pydantic validation
- [x] Service registry with file locking
- [x] ZMQ transport layer
- [x] WorkerBase class
- [x] VJBusClient
- [x] Unit tests (22 tests passing)
- [x] Example worker with test client

### ✅ Phase 2: Audio Analyzer (Partially Complete)

- [x] audio_analyzer_worker.py
- [ ] Integration tests for audio worker
- [ ] Manual testing with real audio

### 📝 Phase 3: Process Manager (TODO)

- [ ] process_manager_daemon.py
- [ ] Worker supervision and auto-restart
- [ ] Process lifecycle events
- [ ] Integration tests

### 📝 Phase 4: Remaining Workers (TODO)

- [ ] lyrics_fetcher_worker.py
- [ ] spotify_monitor_worker.py
- [ ] virtualdj_monitor_worker.py
- [ ] osc_debugger_worker.py
- [ ] log_aggregator_worker.py

### 📝 Phase 5: TUI Integration (TODO)

- [ ] Refactor vj_console.py to use VJBusClient
- [ ] Remove direct worker dependencies
- [ ] Update UI panels for worker status
- [ ] Add reconnection logic

### 📝 Phase 6: Production Hardening (TODO)

- [ ] Error handling and recovery
- [ ] Logging infrastructure
- [ ] Deployment scripts (systemd, launchd)
- [ ] Documentation
- [ ] Performance profiling

## Testing

### Unit Tests

```bash
# Run all unit tests
pytest tests/unit/ -v

# Test messages
pytest tests/unit/test_messages.py -v

# Test registry
pytest tests/unit/test_registry.py -v
```

### Integration Tests

```bash
# Run integration tests (TODO)
pytest tests/integration/ -v
```

### Manual Testing

```bash
# Terminal 1: Start example worker
python workers/example_worker.py

# Terminal 2: Run test client
python dev/test_client.py

# Terminal 3: Check registry
cat ~/.vj/registry.json
```

## Development

### Adding a New Worker

1. Create `workers/your_worker.py`
2. Subclass `WorkerBase`
3. Implement required methods:
   - `run()`: Main loop
   - `get_state()`: Current state
   - `get_metadata()`: Registry metadata
4. Publish telemetry with `self.publish_telemetry(topic, payload)`
5. Test with `dev/test_client.py`

Example skeleton:

```python
from vj_bus.worker import WorkerBase
from vj_bus.messages import WorkerStatePayload

class YourWorker(WorkerBase):
    def run(self):
        while self.running:
            # Do work...
            self.publish_telemetry("your.topic", {"data": 123})
            time.sleep(0.1)

    def get_state(self) -> WorkerStatePayload:
        return WorkerStatePayload(
            status="running",
            uptime_sec=time.time() - self.started_at,
            config=self.config
        )

    def get_metadata(self) -> dict:
        return {"version": "1.0"}
```

### Debugging

1. **Check registry**: `cat ~/.vj/registry.json`
2. **Check worker logs**: Each worker logs to stdout
3. **Monitor ports**: `netstat -an | grep 500`
4. **Test commands**: Use `dev/test_client.py` as reference

## Performance

- **Audio analyzer**: 60+ fps telemetry, <15ms latency
- **ZMQ throughput**: 1M+ messages/second (more than sufficient)
- **TUI updates**: 30 Hz (throttled for smooth rendering)
- **Registry updates**: Every 5 seconds (heartbeat)

## Dependencies

- `pyzmq>=25.0.0`: ZeroMQ for IPC
- `pydantic>=2.0.0`: Message validation
- `pytest>=7.0.0`: Testing framework
- (Existing dependencies remain unchanged)

## Future Enhancements

1. **WebSocket bridge**: Allow web-based TUI
2. **Remote workers**: Workers on different machines
3. **Worker clustering**: Multiple instances of same worker
4. **Metrics dashboard**: Grafana/Prometheus integration
5. **Hot code reload**: Reload worker code without restart
