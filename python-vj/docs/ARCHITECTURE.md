# Python-VJ Multi-Process Architecture

## Executive Summary

This document defines the target architecture for python-vj, transforming it from a monolithic threaded application into a resilient multi-process system where:

1. **Each sub-function runs as an independent process** - audio analyzer, lyrics fetcher, Spotify integration, VirtualDJ integration, OSC debugger, log aggregator, and process manager
2. **Workers survive TUI crashes** - If the TUI dies, all worker processes keep running
3. **TUI reconnects to workers** - When TUI restarts, it discovers and reconnects to running workers
4. **Automatic crash recovery** - Process manager supervises workers and restarts crashed processes
5. **High-throughput, low-latency IPC** - Hybrid OSC (telemetry) + Unix sockets (control) architecture

## Critical Evaluation: OSC vs Hybrid IPC

### Pure OSC Analysis

**Strengths:**
- Already integrated throughout codebase
- Low-latency UDP transport
- Simple fire-and-forget semantics
- Excellent for high-frequency telemetry (audio analysis @ 60 fps)
- Standard in VJ/music software ecosystem

**Weaknesses for Local Multi-Process:**
- UDP is unreliable - no delivery guarantees
- No request/response pattern - hard to implement synchronous config updates
- No connection state - can't detect if worker died vs silently stopped sending
- No authentication/security for local IPC
- Difficult to implement discovery protocol
- Poor for config synchronization (idempotent state sync is complex)

### Recommendation: Hybrid Architecture

**Use OSC for:** High-frequency telemetry streams (read-only data flow from workers to TUI)
- Audio features @ 60 fps
- Lyrics position updates @ 2 fps  
- Log messages (low priority)
- Debug events

**Use Unix Domain Sockets for:** Control plane (bidirectional command/config/discovery)
- Worker registration and heartbeats
- Configuration updates (synchronous, with ACK)
- Command dispatch (start/stop/restart with response)
- Health checks and status queries
- TUI-to-worker control messages

**Why Unix Sockets for Control:**
- Reliable (TCP-like) with guaranteed delivery
- Bidirectional - enables request/response pattern
- Connection-aware - detects worker death immediately
- File-based discovery - workers create socket files in `/tmp/vj-bus/`
- Built-in backpressure - won't overwhelm receivers
- Supports structured message framing (length-prefixed JSON)

## Process Topology

```
┌─────────────────────────────────────────────────────────────────┐
│                      VJ Console (TUI)                           │
│  - Textual UI (stateless coordinator)                          │
│  - Discovers workers via /tmp/vj-bus/*.sock                    │
│  - Subscribes to OSC telemetry streams                         │
│  - Sends control commands via Unix sockets                     │
└────────────┬────────────────────────────────────────────────────┘
             │
    ┌────────┴──────────┬──────────┬──────────┬──────────┬────────┐
    │                   │          │          │          │        │
    ▼                   ▼          ▼          ▼          ▼        ▼
┌─────────┐      ┌───────────┐ ┌──────────┐ ┌──────────┐ ┌─────────┐
│ Process │      │  Audio    │ │ Lyrics   │ │ Spotify  │ │  VDJ    │
│ Manager │      │ Analyzer  │ │ Fetcher  │ │ Monitor  │ │ Monitor │
│         │      │           │ │ + LLM    │ │          │ │         │
└────┬────┘      └─────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬────┘
     │                 │            │            │            │
     │   supervises    │            │            │            │
     └────────────────►│◄───────────┴────────────┴────────────┘
                       │
                  ┌────┴────┐
                  │   OSC   │
                  │  Debug  │
                  │  +Log   │
                  └─────────┘

Legend:
━━━ Unix Socket (control/config/discovery)
─── Supervision relationship
```

### Process Responsibilities

#### 1. VJ Console (TUI) - `vj_console.py`
**Role:** Stateless coordinator and UI
- Discovers workers by scanning `/tmp/vj-bus/*.sock`
- Connects to each worker's control socket
- Subscribes to workers' OSC telemetry streams
- Sends control commands (enable/disable features, adjust config)
- Displays aggregated state from all workers
- **Does NOT maintain state** - workers are source of truth

**Startup Behavior:**
1. Check `/tmp/vj-bus/` for existing worker sockets
2. Connect to found workers, request current state
3. Start missing workers (via process manager)
4. Subscribe to OSC streams for each worker

**Crash Recovery:**
- Workers keep running independently
- On restart, TUI reconnects to existing workers
- No state loss (workers never stopped)

#### 2. Process Manager - `vj_process_manager.py`
**Role:** Supervisor daemon for all workers
- Starts/stops/restarts worker processes
- Monitors worker health via heartbeats
- Auto-restarts crashed workers with exponential backoff
- Tracks restart counts and crash history
- Provides process manager control socket at `/tmp/vj-bus/process_manager.sock`

**Supervision Strategy:**
- Each worker sends heartbeat every 5 seconds via control socket
- If heartbeat missed for 15 seconds, mark as unhealthy
- If heartbeat missed for 30 seconds, restart worker
- Max 5 restarts in 60 seconds before giving up
- Exponential backoff: 1s, 2s, 4s, 8s, 16s, 30s (cap)

**Startup Behavior:**
1. Create `/tmp/vj-bus/` directory
2. Start all enabled workers as subprocesses
3. Monitor their control sockets for heartbeats
4. Listen for supervisor commands from TUI

#### 3. Audio Analyzer - `vj_audio_worker.py`
**Role:** Real-time audio analysis and feature extraction
- Captures audio from configured device (BlackHole)
- Performs FFT, band extraction, beat detection, BPM, pitch
- Emits features via OSC at 60 fps to `127.0.0.1:9000`
- Control socket: `/tmp/vj-bus/audio_analyzer.sock`

**OSC Output:**
- `/audio/levels [8 floats]` @ 60 fps
- `/audio/beat [int, float]` @ 60 fps
- `/audio/bpm [float, float]` @ 1 fps
- `/audio/pitch [float, float]` @ 60 fps
- `/audio/structure [int, int, float, float]` @ 10 fps
- `/audio/spectrum [32 floats]` @ 60 fps (if enabled)

**Control Commands:**
- `{"cmd": "set_config", "enable_essentia": true/false}`
- `{"cmd": "set_config", "enable_pitch": true/false}`
- `{"cmd": "set_config", "enable_bpm": true/false}`
- `{"cmd": "set_config", "enable_structure": true/false}`
- `{"cmd": "set_config", "enable_spectrum": true/false}`
- `{"cmd": "restart"}` - graceful restart with config reload

**Heartbeat:** Every 5 seconds, sends `{"type": "heartbeat", "stats": {...}}`

#### 4. Lyrics Fetcher + LLM - `vj_lyrics_worker.py`
**Role:** Fetch lyrics and perform AI analysis
- Monitors track changes from Spotify/VDJ workers via OSC
- Fetches synced lyrics from LRCLIB API
- Performs LLM analysis (refrain, keywords, image prompts, categories)
- Emits results via OSC
- Control socket: `/tmp/vj-bus/lyrics_fetcher.sock`

**OSC Output:**
- `/karaoke/lyrics/reset []`
- `/karaoke/lyrics/line [index, time, text]`
- `/karaoke/refrain/reset []`
- `/karaoke/refrain/line [index, time, text]`
- `/karaoke/keywords/line [index, time, keywords]`
- `/karaoke/categories/mood [string]`
- `/karaoke/categories/{name} [float]`
- `/karaoke/image [path]`

**Control Commands:**
- `{"cmd": "set_config", "llm_provider": "ollama"/"openai"}`
- `{"cmd": "set_config", "ollama_model": "llama3.2"}`
- `{"cmd": "set_config", "comfyui_enabled": true/false}`
- `{"cmd": "restart"}`

**Heartbeat:** Every 5 seconds with LLM cache stats

#### 5. Spotify Monitor - `vj_spotify_worker.py`
**Role:** Monitor Spotify playback
- Polls Spotify API for current track (every 2 seconds)
- Emits track changes and position via OSC
- Control socket: `/tmp/vj-bus/spotify_monitor.sock`

**OSC Output:**
- `/karaoke/track [active, source, artist, title, album, duration, has_lyrics]`
- `/karaoke/pos [position_sec, is_playing]`

**Control Commands:**
- `{"cmd": "set_config", "poll_interval": 2.0}`
- `{"cmd": "restart"}`

**Heartbeat:** Every 5 seconds with Spotify API status

#### 6. VirtualDJ Monitor - `vj_virtualdj_worker.py`
**Role:** Monitor VirtualDJ now playing file
- Watches `~/Documents/VirtualDJ/now_playing.txt` for changes
- Emits track changes via OSC
- Control socket: `/tmp/vj-bus/virtualdj_monitor.sock`

**OSC Output:**
- `/karaoke/track [active, source, artist, title, album, duration, has_lyrics]`
- `/karaoke/pos [position_sec, is_playing]`

**Control Commands:**
- `{"cmd": "set_config", "file_path": "/custom/path.txt"}`
- `{"cmd": "restart"}`

**Heartbeat:** Every 5 seconds with file watch status

#### 7. OSC Debugger + Log Aggregator - `vj_debug_worker.py`
**Role:** Capture and relay OSC messages and logs
- Listens on OSC port (as a receiver, not sender)
- Captures all OSC traffic for debugging
- Aggregates logs from all workers via their heartbeat messages
- Control socket: `/tmp/vj-bus/osc_debugger.sock`

**Control Commands:**
- `{"cmd": "set_config", "logging_enabled": true/false}`
- `{"cmd": "get_messages", "count": 50}` → returns recent OSC messages
- `{"cmd": "get_logs", "count": 100}` → returns recent log lines
- `{"cmd": "clear"}`

**Heartbeat:** Every 5 seconds with message counts

## Communication Architecture

### Control Plane: Unix Domain Sockets

**Socket File Layout:**
```
/tmp/vj-bus/
├── process_manager.sock      # Process manager control
├── audio_analyzer.sock        # Audio worker control
├── lyrics_fetcher.sock        # Lyrics + LLM worker control
├── spotify_monitor.sock       # Spotify worker control
├── virtualdj_monitor.sock     # VDJ worker control
└── osc_debugger.sock          # Debug worker control
```

**Message Protocol:**
- Length-prefixed JSON over Unix stream socket
- Format: `[4-byte length (big-endian)][JSON payload]`
- Supports request/response pattern via `msg_id` field

**Message Schema:**

```python
# Heartbeat (worker → TUI/process_manager)
{
    "type": "heartbeat",
    "worker": "audio_analyzer",
    "pid": 12345,
    "uptime_sec": 123.45,
    "stats": {
        "frames_processed": 7200,
        "fps": 60.0,
        "audio_alive": true
    }
}

# Config update (TUI → worker)
{
    "type": "command",
    "msg_id": "abc123",  # For ACK correlation
    "cmd": "set_config",
    "enable_essentia": true,
    "enable_pitch": false
}

# ACK (worker → TUI)
{
    "type": "ack",
    "msg_id": "abc123",
    "success": true,
    "message": "Config updated, restarting analyzer..."
}

# Worker registration (worker → process_manager)
{
    "type": "register",
    "worker": "audio_analyzer",
    "pid": 12345,
    "socket_path": "/tmp/vj-bus/audio_analyzer.sock",
    "osc_addresses": ["/audio/levels", "/audio/beat", ...]
}

# State request (TUI → worker)
{
    "type": "command",
    "msg_id": "xyz789",
    "cmd": "get_state"
}

# State response (worker → TUI)
{
    "type": "response",
    "msg_id": "xyz789",
    "state": {
        "config": {"enable_essentia": true, ...},
        "status": "running",
        "last_error": null
    }
}
```

### Data Plane: OSC (Telemetry)

**OSC Output:** Workers emit telemetry to `127.0.0.1:9000` (fire-and-forget)
- No ACKs or reliability - use for high-frequency data only
- TUI does NOT send OSC - uses control sockets instead
- OSC messages are logged by `osc_debugger` worker for debug view

**Rate Limiting:**
- Audio features: 60 fps (every ~16ms)
- Track position: 2 fps (every 500ms)
- Categories/lyrics: Event-driven (on change only)
- Logs: Max 10/sec (burst), aggregated in debug worker

## Worker Discovery and Reconnection

### Discovery Protocol

**On TUI Startup:**
1. Scan `/tmp/vj-bus/*.sock` for existing workers
2. For each socket file:
   - Attempt connection (non-blocking)
   - Send `{"type": "command", "cmd": "get_state", "msg_id": "..."}` 
   - Wait 1 second for response
   - If response received: worker alive, store connection
   - If timeout: remove stale socket file, mark worker as dead
3. Query process manager for list of supervised workers
4. Start missing workers via process manager

**On Worker Crash:**
1. Process manager detects missing heartbeat (30 sec timeout)
2. Process manager restarts worker subprocess
3. Restarted worker creates new socket at same path
4. TUI detects new socket (via periodic scan every 5 sec)
5. TUI reconnects automatically

**On Worker Restart (Graceful):**
1. Worker closes existing socket, deletes file
2. Worker reinitializes with new config
3. Worker creates new socket at same path
4. Worker sends registration to process manager
5. TUI reconnects on next scan (5 sec max delay)

### Idempotent State Sync

**Problem:** When TUI reconnects to worker, they may have diverged state

**Solution:** Workers are source of truth, TUI always resyncs
1. TUI sends `get_state` command on reconnect
2. Worker responds with full current config + status
3. TUI updates UI to reflect worker's actual state
4. User config changes are sent as commands (with ACK)
5. TUI waits for ACK before updating UI (optimistic updates allowed)

**Conflict Resolution:**
- Worker config file on disk is authoritative
- If TUI sends invalid config, worker responds with error ACK
- TUI must handle ACK errors and revert UI state

## Failure Handling

### Scenario 1: TUI Crashes

**What happens:**
- All workers keep running (independent processes)
- OSC telemetry continues (e.g., Synesthesia still gets audio features)
- Process manager keeps supervising workers

**Recovery:**
1. User restarts TUI manually: `python vj_console.py`
2. TUI discovers workers via socket scan (see Discovery Protocol)
3. TUI requests state from each worker via `get_state`
4. TUI subscribes to OSC streams (TUI-side, no worker action needed)
5. UI rebuilds from worker state (no data loss)

**Time to recovery:** ~5 seconds (scan + reconnect)

### Scenario 2: Worker Crashes

**What happens:**
- Process manager detects missing heartbeat (30 sec)
- Process manager kills zombie process (if any)
- Process manager starts new worker instance
- Worker creates new socket, sends registration
- TUI detects new socket on next scan (5 sec)

**Recovery:**
1. Process manager restarts worker subprocess
2. Worker reads config from disk (`~/.vj_audio_config.json`, etc.)
3. Worker reinitializes with last known config
4. Worker creates control socket, sends registration
5. Worker resumes OSC telemetry
6. TUI reconnects automatically, requests state

**Time to recovery:** ~35 seconds (30s detection + 5s reconnect)

**State loss:**
- Transient state lost (e.g., current audio frame)
- Persistent state preserved (config files)
- TUI shows "reconnecting..." during gap

### Scenario 3: Process Manager Crashes

**What happens:**
- All workers keep running (not children of process manager)
- No supervision temporarily
- Workers continue emitting OSC, responding to control commands

**Recovery:**
1. User manually restarts process manager OR TUI detects missing process manager socket
2. Process manager scans for running worker PIDs (via socket connections)
3. Process manager adopts existing workers (no restart)
4. Supervision resumes

**Time to recovery:** Immediate (workers never stopped)

**Alternative Design (if workers are children):**
- Use `nohup` or `setsid` to detach workers from process manager
- Workers write PID files to `/tmp/vj-bus/*.pid`
- Restarted process manager reads PID files and reattaches

### Scenario 4: Config Change During Worker Offline

**What happens:**
- User changes config in TUI while worker is restarting
- TUI sends config command to worker socket (fails, connection closed)

**Recovery:**
1. TUI detects send failure, queues config command
2. When worker reconnects, TUI replays queued commands
3. Worker ACKs config update
4. TUI marks command as delivered

**Alternative:** TUI writes config to worker's disk config file directly (race-prone, not recommended)

### Scenario 5: High-Frequency Telemetry Overwhelms TUI

**What happens:**
- Audio analyzer sends 60 OSC messages/sec
- TUI update loop slows down (Textual UI rendering)
- OSC messages pile up in TUI's receive buffer

**Solution (Already Implemented):**
- OSC messages are fire-and-forget UDP (no backpressure to worker)
- TUI samples OSC messages (read latest, discard old)
- TUI disables OSC logging when OSC debug view is hidden (performance optimization)
- Worker never blocks on OSC send (uses `send_message`, not `send_message_reliable`)

**Additional Optimization:**
- TUI could subscribe to OSC on dedicated thread
- Thread writes to lock-free ringbuffer (latest value only)
- UI thread reads from ringbuffer at its own pace (e.g., 10 fps)

## Shared IPC Library: `vj_bus`

### Package Structure

```
python-vj/
├── vj_bus/
│   ├── __init__.py
│   ├── schema.py          # Pydantic models for all messages
│   ├── control.py         # Unix socket control plane
│   ├── telemetry.py       # OSC telemetry helpers
│   ├── worker.py          # Base worker class
│   └── discovery.py       # Discovery protocol
├── vj_audio_worker.py
├── vj_lyrics_worker.py
├── vj_spotify_worker.py
├── vj_virtualdj_worker.py
├── vj_debug_worker.py
├── vj_process_manager.py
├── vj_console.py
└── tests/
    ├── test_vj_bus.py
    └── test_integration.py
```

### Core Classes

#### `vj_bus.schema` - Message Schema (Pydantic)

```python
from pydantic import BaseModel, Field
from typing import Literal, Optional, Dict, Any, List
from enum import Enum

class MessageType(str, Enum):
    HEARTBEAT = "heartbeat"
    COMMAND = "command"
    ACK = "ack"
    RESPONSE = "response"
    REGISTER = "register"
    ERROR = "error"

class BaseMessage(BaseModel):
    type: MessageType
    msg_id: Optional[str] = None  # For request/response correlation

class HeartbeatMessage(BaseMessage):
    type: Literal[MessageType.HEARTBEAT] = MessageType.HEARTBEAT
    worker: str
    pid: int
    uptime_sec: float
    stats: Dict[str, Any] = Field(default_factory=dict)

class CommandMessage(BaseMessage):
    type: Literal[MessageType.COMMAND] = MessageType.COMMAND
    cmd: str  # "get_state", "set_config", "restart", etc.
    # Additional fields based on cmd
    class Config:
        extra = "allow"  # Allow additional fields

class AckMessage(BaseMessage):
    type: Literal[MessageType.ACK] = MessageType.ACK
    success: bool
    message: Optional[str] = None
    data: Optional[Dict[str, Any]] = None

class ResponseMessage(BaseMessage):
    type: Literal[MessageType.RESPONSE] = MessageType.RESPONSE
    data: Dict[str, Any]

class RegisterMessage(BaseMessage):
    type: Literal[MessageType.REGISTER] = MessageType.REGISTER
    worker: str
    pid: int
    socket_path: str
    osc_addresses: List[str] = Field(default_factory=list)

class ErrorMessage(BaseMessage):
    type: Literal[MessageType.ERROR] = MessageType.ERROR
    error: str
    traceback: Optional[str] = None
```

#### `vj_bus.control` - Unix Socket Communication

```python
import socket
import json
import struct
import logging
from pathlib import Path
from typing import Optional, Dict, Any, Callable
from .schema import BaseMessage, AckMessage, CommandMessage

logger = logging.getLogger('vj_bus.control')

class ControlSocket:
    """Unix domain socket for control plane communication."""
    
    SOCKET_DIR = Path("/tmp/vj-bus")
    MAX_MESSAGE_SIZE = 1024 * 1024  # 1 MB
    
    def __init__(self, name: str):
        self.name = name
        self.socket_path = self.SOCKET_DIR / f"{name}.sock"
        self.sock: Optional[socket.socket] = None
        self._ensure_socket_dir()
    
    def _ensure_socket_dir(self):
        self.SOCKET_DIR.mkdir(parents=True, exist_ok=True)
    
    def create_server(self) -> None:
        """Create server socket (for workers)."""
        # Remove stale socket
        if self.socket_path.exists():
            self.socket_path.unlink()
        
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.bind(str(self.socket_path))
        self.sock.listen(5)
        logger.info(f"Control socket listening: {self.socket_path}")
    
    def connect(self, timeout: float = 1.0) -> bool:
        """Connect to server socket (for TUI/clients)."""
        try:
            self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            self.sock.settimeout(timeout)
            self.sock.connect(str(self.socket_path))
            logger.info(f"Connected to {self.socket_path}")
            return True
        except Exception as e:
            logger.error(f"Failed to connect to {self.socket_path}: {e}")
            return False
    
    def send_message(self, msg: BaseMessage) -> bool:
        """Send message (length-prefixed JSON)."""
        if not self.sock:
            return False
        
        try:
            data = msg.model_dump_json().encode('utf-8')
            length = struct.pack('>I', len(data))  # Big-endian 4-byte length
            self.sock.sendall(length + data)
            return True
        except Exception as e:
            logger.error(f"Failed to send message: {e}")
            return False
    
    def recv_message(self, timeout: float = 1.0) -> Optional[Dict[str, Any]]:
        """Receive message (length-prefixed JSON)."""
        if not self.sock:
            return None
        
        try:
            self.sock.settimeout(timeout)
            
            # Read 4-byte length prefix
            length_data = self._recv_exact(4)
            if not length_data:
                return None
            
            length = struct.unpack('>I', length_data)[0]
            if length > self.MAX_MESSAGE_SIZE:
                logger.error(f"Message too large: {length} bytes")
                return None
            
            # Read message body
            data = self._recv_exact(length)
            if not data:
                return None
            
            return json.loads(data.decode('utf-8'))
        
        except socket.timeout:
            return None
        except Exception as e:
            logger.error(f"Failed to receive message: {e}")
            return None
    
    def _recv_exact(self, n: int) -> Optional[bytes]:
        """Receive exactly n bytes."""
        data = b''
        while len(data) < n:
            chunk = self.sock.recv(n - len(data))
            if not chunk:
                return None  # Connection closed
            data += chunk
        return data
    
    def close(self):
        """Close socket and cleanup."""
        if self.sock:
            self.sock.close()
            self.sock = None
        if self.socket_path.exists():
            try:
                self.socket_path.unlink()
            except:
                pass
```

#### `vj_bus.telemetry` - OSC Helpers

```python
from pythonosc import udp_client
from typing import List, Any
import logging

logger = logging.getLogger('vj_bus.telemetry')

class TelemetrySender:
    """High-performance OSC telemetry sender."""
    
    def __init__(self, host: str = "127.0.0.1", port: int = 9000):
        self.client = udp_client.SimpleUDPClient(host, port)
        self.host = host
        self.port = port
        logger.info(f"Telemetry sender initialized: {host}:{port}")
    
    def send(self, address: str, args: Any = None):
        """Send OSC message (fire-and-forget, non-blocking)."""
        if args is None:
            args = []
        elif not isinstance(args, (list, tuple)):
            args = [args]
        
        try:
            self.client.send_message(address, args)
        except Exception as e:
            logger.error(f"OSC send failed {address}: {e}")
```

#### `vj_bus.worker` - Base Worker Class

```python
import os
import time
import signal
import logging
from abc import ABC, abstractmethod
from typing import Optional, Dict, Any
from .control import ControlSocket
from .telemetry import TelemetrySender
from .schema import HeartbeatMessage, CommandMessage, AckMessage

logger = logging.getLogger('vj_bus.worker')

class Worker(ABC):
    """Base class for all VJ workers."""
    
    def __init__(self, name: str, osc_addresses: list = None):
        self.name = name
        self.osc_addresses = osc_addresses or []
        self.control = ControlSocket(name)
        self.telemetry = TelemetrySender()
        self.running = False
        self.start_time = time.time()
        
        # Setup signal handlers
        signal.signal(signal.SIGTERM, self._handle_shutdown)
        signal.signal(signal.SIGINT, self._handle_shutdown)
    
    def _handle_shutdown(self, signum, frame):
        """Graceful shutdown on SIGTERM/SIGINT."""
        logger.info(f"{self.name} received shutdown signal")
        self.stop()
    
    def start(self):
        """Start worker (creates control socket, starts heartbeat)."""
        logger.info(f"Starting worker: {self.name}")
        self.control.create_server()
        self.running = True
        
        # Register with process manager
        self._register()
        
        # Start worker-specific initialization
        self.on_start()
        
        # Main loop
        self._run_loop()
    
    def stop(self):
        """Stop worker gracefully."""
        logger.info(f"Stopping worker: {self.name}")
        self.running = False
        self.on_stop()
        self.control.close()
    
    @abstractmethod
    def on_start(self):
        """Worker-specific startup (override in subclass)."""
        pass
    
    @abstractmethod
    def on_stop(self):
        """Worker-specific shutdown (override in subclass)."""
        pass
    
    @abstractmethod
    def on_command(self, cmd: CommandMessage) -> AckMessage:
        """Handle command from TUI/process manager (override in subclass)."""
        pass
    
    @abstractmethod
    def get_stats(self) -> Dict[str, Any]:
        """Get current stats for heartbeat (override in subclass)."""
        pass
    
    def _run_loop(self):
        """Main worker loop (heartbeat + command handling)."""
        last_heartbeat = 0
        
        while self.running:
            now = time.time()
            
            # Send heartbeat every 5 seconds
            if now - last_heartbeat > 5.0:
                self._send_heartbeat()
                last_heartbeat = now
            
            # Handle incoming commands (non-blocking)
            msg = self.control.recv_message(timeout=0.1)
            if msg and msg.get('type') == 'command':
                try:
                    cmd = CommandMessage(**msg)
                    ack = self.on_command(cmd)
                    ack.msg_id = cmd.msg_id
                    self.control.send_message(ack)
                except Exception as e:
                    logger.exception(f"Error handling command: {e}")
                    error_ack = AckMessage(
                        msg_id=msg.get('msg_id'),
                        success=False,
                        message=f"Error: {e}"
                    )
                    self.control.send_message(error_ack)
    
    def _send_heartbeat(self):
        """Send heartbeat to process manager."""
        heartbeat = HeartbeatMessage(
            worker=self.name,
            pid=os.getpid(),
            uptime_sec=time.time() - self.start_time,
            stats=self.get_stats()
        )
        # Send to process manager socket (future enhancement)
        logger.debug(f"Heartbeat: {heartbeat.model_dump()}")
    
    def _register(self):
        """Register with process manager."""
        # Future enhancement: send registration message
        pass
```

#### `vj_bus.discovery` - Worker Discovery

```python
from pathlib import Path
from typing import List, Dict
from .control import ControlSocket
import logging

logger = logging.getLogger('vj_bus.discovery')

class WorkerDiscovery:
    """Discovers running workers by scanning socket files."""
    
    @staticmethod
    def scan_workers() -> List[Dict[str, str]]:
        """Scan /tmp/vj-bus/ for worker sockets."""
        workers = []
        socket_dir = ControlSocket.SOCKET_DIR
        
        if not socket_dir.exists():
            return workers
        
        for sock_file in socket_dir.glob("*.sock"):
            name = sock_file.stem  # Remove .sock extension
            workers.append({
                'name': name,
                'socket_path': str(sock_file)
            })
        
        logger.info(f"Discovered {len(workers)} workers: {[w['name'] for w in workers]}")
        return workers
    
    @staticmethod
    def test_worker(socket_path: str, timeout: float = 1.0) -> bool:
        """Test if worker is responsive."""
        try:
            sock = ControlSocket("test_client")
            if sock.connect(timeout):
                sock.close()
                return True
        except:
            pass
        return False
```

### Usage Examples

#### Example 1: Audio Worker Using vj_bus

```python
# vj_audio_worker.py
import time
from vj_bus.worker import Worker
from vj_bus.schema import CommandMessage, AckMessage
from audio_analyzer import AudioAnalyzer, AudioConfig

class AudioWorker(Worker):
    def __init__(self):
        super().__init__(
            name="audio_analyzer",
            osc_addresses=["/audio/levels", "/audio/beat", "/audio/bpm"]
        )
        self.analyzer = None
        self.config = AudioConfig()
    
    def on_start(self):
        """Initialize audio analyzer."""
        self.analyzer = AudioAnalyzer(
            config=self.config,
            osc_callback=self.telemetry.send  # Send OSC via vj_bus
        )
        self.analyzer.start()
    
    def on_stop(self):
        """Stop audio analyzer."""
        if self.analyzer:
            self.analyzer.stop()
    
    def on_command(self, cmd: CommandMessage) -> AckMessage:
        """Handle commands from TUI."""
        if cmd.cmd == "get_state":
            return AckMessage(
                success=True,
                data={
                    "config": self.config.__dict__,
                    "status": "running" if self.analyzer else "stopped"
                }
            )
        
        elif cmd.cmd == "set_config":
            # Update config from command
            for key, value in cmd.dict().items():
                if hasattr(self.config, key):
                    setattr(self.config, key, value)
            
            # Restart analyzer with new config
            self.on_stop()
            self.on_start()
            
            return AckMessage(success=True, message="Config updated")
        
        elif cmd.cmd == "restart":
            self.on_stop()
            self.on_start()
            return AckMessage(success=True, message="Restarted")
        
        else:
            return AckMessage(success=False, message=f"Unknown command: {cmd.cmd}")
    
    def get_stats(self) -> dict:
        """Get stats for heartbeat."""
        if not self.analyzer:
            return {}
        
        return self.analyzer.get_stats()

if __name__ == "__main__":
    worker = AudioWorker()
    worker.start()  # Blocks until shutdown signal
```

#### Example 2: TUI Discovering and Controlling Workers

```python
# vj_console.py (simplified example)
from vj_bus.discovery import WorkerDiscovery
from vj_bus.control import ControlSocket
from vj_bus.schema import CommandMessage

class VJConsole:
    def __init__(self):
        self.workers = {}
    
    def discover_workers(self):
        """Discover and connect to workers."""
        found = WorkerDiscovery.scan_workers()
        
        for worker_info in found:
            name = worker_info['name']
            socket_path = worker_info['socket_path']
            
            # Test if worker is alive
            if WorkerDiscovery.test_worker(socket_path):
                # Connect to worker
                control = ControlSocket(f"{name}_client")
                if control.connect():
                    self.workers[name] = control
                    
                    # Request current state
                    cmd = CommandMessage(cmd="get_state", msg_id="init")
                    control.send_message(cmd)
                    
                    response = control.recv_message(timeout=2.0)
                    if response:
                        print(f"Connected to {name}: {response}")
    
    def toggle_audio_feature(self, feature: str, enabled: bool):
        """Send config update to audio worker."""
        audio_control = self.workers.get("audio_analyzer")
        if not audio_control:
            print("Audio worker not found")
            return
        
        cmd = CommandMessage(
            cmd="set_config",
            msg_id="toggle_feature",
            **{feature: enabled}
        )
        
        audio_control.send_message(cmd)
        ack = audio_control.recv_message(timeout=2.0)
        
        if ack and ack.get('success'):
            print(f"Feature {feature} = {enabled}")
        else:
            print(f"Failed to toggle {feature}: {ack.get('message')}")
```

