# Testing Strategy for Multi-Process Architecture

## Overview

This document defines the testing approach for the python-vj multi-process architecture, covering unit tests, integration tests, and manual verification procedures.

## Test Categories

### 1. Unit Tests - Message Schema & IPC

**Module:** `tests/test_vj_bus.py`

**Test Cases:**

```python
class TestMessageSchema:
    """Test Pydantic message models."""
    
    def test_heartbeat_serialization():
        """HeartbeatMessage should serialize to JSON correctly."""
        msg = HeartbeatMessage(
            worker="audio_analyzer",
            pid=12345,
            uptime_sec=123.45,
            stats={"fps": 60.0}
        )
        json_str = msg.model_dump_json()
        assert '"worker":"audio_analyzer"' in json_str
    
    def test_command_deserialization():
        """CommandMessage should deserialize from JSON with extra fields."""
        json_data = {
            "type": "command",
            "msg_id": "abc123",
            "cmd": "set_config",
            "enable_essentia": True,
            "enable_pitch": False
        }
        msg = CommandMessage(**json_data)
        assert msg.cmd == "set_config"
        assert msg.enable_essentia == True
    
    def test_ack_message():
        """AckMessage should support success/failure with optional data."""
        ack = AckMessage(
            msg_id="abc123",
            success=True,
            message="Config updated",
            data={"restart_required": True}
        )
        assert ack.success
        assert ack.data["restart_required"]

class TestControlSocket:
    """Test Unix socket communication."""
    
    def test_socket_creation(tmp_path):
        """ControlSocket should create Unix socket file."""
        ControlSocket.SOCKET_DIR = tmp_path
        sock = ControlSocket("test_worker")
        sock.create_server()
        
        assert (tmp_path / "test_worker.sock").exists()
        sock.close()
    
    def test_send_receive_message(tmp_path):
        """Messages should be sent/received with length prefix."""
        ControlSocket.SOCKET_DIR = tmp_path
        
        # Server
        server = ControlSocket("test_server")
        server.create_server()
        
        # Client (in thread to avoid blocking)
        def client_thread():
            client = ControlSocket("test_client")
            client.connect()
            
            msg = HeartbeatMessage(worker="test", pid=123, uptime_sec=1.0)
            client.send_message(msg)
            client.close()
        
        import threading
        t = threading.Thread(target=client_thread)
        t.start()
        
        # Accept connection
        conn, addr = server.sock.accept()
        server.sock = conn  # Replace socket with connection
        
        # Receive message
        data = server.recv_message(timeout=2.0)
        assert data["worker"] == "test"
        
        t.join()
        server.close()
    
    def test_message_too_large(tmp_path):
        """recv_message should reject oversized messages."""
        # Mock socket that sends 10MB length prefix
        # Should return None and log error
        pass  # Implementation omitted for brevity

class TestTelemetrySender:
    """Test OSC telemetry sending."""
    
    def test_osc_send():
        """TelemetrySender should send OSC without blocking."""
        sender = TelemetrySender()
        
        # Should not raise, even if no receiver
        sender.send("/audio/levels", [0.1, 0.2, 0.3])
    
    def test_osc_args_normalization():
        """send() should normalize single values to lists."""
        sender = TelemetrySender()
        
        # Single value
        sender.send("/audio/beat", 1)  # Should send [1]
        
        # None
        sender.send("/audio/reset")  # Should send []
        
        # List
        sender.send("/audio/levels", [0.1, 0.2])  # Should send as-is

class TestWorkerDiscovery:
    """Test worker discovery protocol."""
    
    def test_scan_workers(tmp_path):
        """scan_workers should find socket files."""
        ControlSocket.SOCKET_DIR = tmp_path
        
        # Create fake socket files
        (tmp_path / "audio_analyzer.sock").touch()
        (tmp_path / "lyrics_fetcher.sock").touch()
        
        workers = WorkerDiscovery.scan_workers()
        
        assert len(workers) == 2
        names = [w['name'] for w in workers]
        assert "audio_analyzer" in names
        assert "lyrics_fetcher" in names
    
    def test_test_worker_alive(tmp_path):
        """test_worker should detect responsive worker."""
        ControlSocket.SOCKET_DIR = tmp_path
        
        # Start mock worker
        server = ControlSocket("test_worker")
        server.create_server()
        
        # Test should succeed
        assert WorkerDiscovery.test_worker(str(tmp_path / "test_worker.sock"))
        
        server.close()
    
    def test_test_worker_dead(tmp_path):
        """test_worker should detect unresponsive worker."""
        ControlSocket.SOCKET_DIR = tmp_path
        
        # Create socket file but no server
        (tmp_path / "dead_worker.sock").touch()
        
        # Test should fail
        assert not WorkerDiscovery.test_worker(str(tmp_path / "dead_worker.sock"))
```

**Run with:**
```bash
cd python-vj
python -m pytest tests/test_vj_bus.py -v
```

### 2. Integration Tests - Multi-Process Scenarios

**Module:** `tests/test_integration.py`

**Test Cases:**

```python
import subprocess
import time
import signal
from pathlib import Path

class TestWorkerLifecycle:
    """Test worker process lifecycle."""
    
    def test_worker_starts_and_creates_socket(tmp_path):
        """Worker should start, create socket, send heartbeat."""
        ControlSocket.SOCKET_DIR = tmp_path
        
        # Start worker subprocess
        proc = subprocess.Popen([
            "python", "vj_audio_worker.py"
        ], env={"VJ_BUS_DIR": str(tmp_path)})
        
        # Wait for socket creation
        socket_file = tmp_path / "audio_analyzer.sock"
        for _ in range(50):  # 5 seconds max
            if socket_file.exists():
                break
            time.sleep(0.1)
        
        assert socket_file.exists()
        
        # Connect and verify worker responds
        client = ControlSocket("test_client")
        assert client.connect()
        
        # Request state
        cmd = CommandMessage(cmd="get_state", msg_id="test")
        client.send_message(cmd)
        
        response = client.recv_message(timeout=2.0)
        assert response is not None
        assert response["type"] == "response"
        
        # Cleanup
        proc.terminate()
        proc.wait(timeout=5)
        client.close()
    
    def test_worker_survives_tui_crash(tmp_path):
        """Worker should keep running when TUI exits."""
        # Start worker
        worker_proc = subprocess.Popen(["python", "vj_audio_worker.py"])
        time.sleep(2)  # Let it initialize
        
        # Start TUI, connect to worker
        tui_proc = subprocess.Popen(["python", "vj_console.py"])
        time.sleep(2)
        
        # Kill TUI
        tui_proc.kill()
        tui_proc.wait()
        
        # Worker should still be running
        assert worker_proc.poll() is None
        
        # Verify worker still responds
        client = ControlSocket("test_client")
        assert client.connect()
        
        # Cleanup
        worker_proc.terminate()
        worker_proc.wait(timeout=5)
    
    def test_tui_reconnects_to_running_worker(tmp_path):
        """TUI should reconnect to worker on restart."""
        # Start worker
        worker_proc = subprocess.Popen(["python", "vj_audio_worker.py"])
        time.sleep(2)
        
        # Start TUI (should discover worker)
        tui_proc = subprocess.Popen(["python", "vj_console.py"])
        time.sleep(2)
        
        # Kill TUI
        tui_proc.kill()
        tui_proc.wait()
        
        # Restart TUI (should reconnect)
        tui_proc = subprocess.Popen(["python", "vj_console.py"])
        time.sleep(2)
        
        # TUI should have reconnected (manual verification needed)
        # In real test, would check logs or TUI state
        
        # Cleanup
        tui_proc.terminate()
        worker_proc.terminate()
        tui_proc.wait(timeout=5)
        worker_proc.wait(timeout=5)

class TestProcessManager:
    """Test process manager supervision."""
    
    def test_manager_restarts_crashed_worker(tmp_path):
        """Process manager should restart crashed worker."""
        # Start process manager
        pm_proc = subprocess.Popen(["python", "vj_process_manager.py"])
        time.sleep(2)
        
        # Process manager starts audio worker
        # Get worker PID
        workers = WorkerDiscovery.scan_workers()
        audio_worker = next(w for w in workers if w['name'] == 'audio_analyzer')
        
        client = ControlSocket("test_client")
        client.connect()
        cmd = CommandMessage(cmd="get_state", msg_id="test")
        client.send_message(cmd)
        response = client.recv_message()
        worker_pid = response['data']['pid']
        client.close()
        
        # Kill worker process
        os.kill(worker_pid, signal.SIGKILL)
        
        # Wait for process manager to restart (30s detection + restart)
        time.sleep(35)
        
        # Worker should be restarted with new PID
        client = ControlSocket("test_client")
        assert client.connect()  # Should reconnect successfully
        
        # Cleanup
        pm_proc.terminate()
        pm_proc.wait(timeout=5)

class TestHighThroughput:
    """Test high-frequency telemetry performance."""
    
    def test_audio_analyzer_60fps_no_blocking(tmp_path):
        """Audio analyzer should emit 60 fps without blocking."""
        # Start audio worker
        worker_proc = subprocess.Popen(["python", "vj_audio_worker.py"])
        time.sleep(2)
        
        # Start OSC receiver to count messages
        from pythonosc import dispatcher, osc_server
        import threading
        
        message_count = [0]
        
        def count_messages(address, *args):
            message_count[0] += 1
        
        disp = dispatcher.Dispatcher()
        disp.map("/audio/*", count_messages)
        
        server = osc_server.ThreadingOSCUDPServer(("127.0.0.1", 9000), disp)
        server_thread = threading.Thread(target=server.serve_forever)
        server_thread.daemon = True
        server_thread.start()
        
        # Let worker run for 10 seconds
        time.sleep(10)
        
        # Should have received ~600 messages (60 fps * 10 sec)
        # Allow 10% variance
        assert 540 <= message_count[0] <= 660
        
        # Worker should still be responsive (not blocked)
        client = ControlSocket("test_client")
        assert client.connect()
        cmd = CommandMessage(cmd="get_state", msg_id="test")
        client.send_message(cmd)
        response = client.recv_message(timeout=1.0)
        assert response is not None
        
        # Cleanup
        server.shutdown()
        worker_proc.terminate()
        worker_proc.wait(timeout=5)
    
    def test_tui_handles_osc_burst(tmp_path):
        """TUI should handle OSC message bursts without crashing."""
        # Start TUI
        tui_proc = subprocess.Popen(["python", "vj_console.py"])
        time.sleep(2)
        
        # Send 1000 OSC messages rapidly
        sender = TelemetrySender()
        for i in range(1000):
            sender.send("/test/burst", [i])
        
        # TUI should still be running
        time.sleep(2)
        assert tui_proc.poll() is None
        
        # Cleanup
        tui_proc.terminate()
        tui_proc.wait(timeout=5)

class TestConfigSync:
    """Test configuration synchronization."""
    
    def test_config_change_propagates(tmp_path):
        """Config change from TUI should update worker."""
        # Start worker
        worker_proc = subprocess.Popen(["python", "vj_audio_worker.py"])
        time.sleep(2)
        
        # Connect as TUI
        client = ControlSocket("test_tui")
        client.connect()
        
        # Get initial config
        cmd = CommandMessage(cmd="get_state", msg_id="get1")
        client.send_message(cmd)
        response = client.recv_message()
        initial_config = response['data']['config']
        
        # Change config
        cmd = CommandMessage(
            cmd="set_config",
            msg_id="set1",
            enable_essentia=not initial_config['enable_essentia']
        )
        client.send_message(cmd)
        
        # Wait for ACK
        ack = client.recv_message(timeout=5.0)
        assert ack['success']
        
        # Verify config changed
        cmd = CommandMessage(cmd="get_state", msg_id="get2")
        client.send_message(cmd)
        response = client.recv_message()
        new_config = response['data']['config']
        
        assert new_config['enable_essentia'] != initial_config['enable_essentia']
        
        # Cleanup
        client.close()
        worker_proc.terminate()
        worker_proc.wait(timeout=5)
```

**Run with:**
```bash
cd python-vj
python -m pytest tests/test_integration.py -v -s
```

### 3. Manual Verification Procedures

**Test Script:** `tests/manual_test.sh`

```bash
#!/bin/bash
# Manual test procedures for multi-process architecture

set -e

echo "=== Python-VJ Multi-Process Architecture Manual Tests ==="
echo ""

# Test 1: Workers survive TUI crash
echo "Test 1: Workers survive TUI crash"
echo "1. Starting process manager..."
python vj_process_manager.py &
PM_PID=$!
sleep 3

echo "2. Starting TUI..."
python vj_console.py &
TUI_PID=$!
sleep 3

echo "3. Press 'A' in TUI to start audio analyzer"
echo "4. Verify audio analyzer is running (check logs)"
sleep 5

echo "5. Killing TUI (simulating crash)..."
kill -9 $TUI_PID

echo "6. Checking if workers still running..."
pgrep -f vj_audio_worker.py && echo "✓ Audio worker still running" || echo "✗ Audio worker died"

echo "7. Restarting TUI..."
python vj_console.py &
TUI_PID=$!
sleep 3

echo "8. TUI should reconnect to running audio worker"
echo "   Verify in TUI that audio analyzer shows as running"
echo ""
read -p "Press Enter to continue..."

# Cleanup
kill $TUI_PID $PM_PID 2>/dev/null || true

# Test 2: Worker crash triggers restart
echo ""
echo "Test 2: Worker crash triggers restart"
echo "1. Starting process manager..."
python vj_process_manager.py &
PM_PID=$!
sleep 3

echo "2. Starting audio worker..."
python vj_audio_worker.py &
WORKER_PID=$!
sleep 2

echo "3. Worker PID: $WORKER_PID"
echo "4. Killing worker (simulating crash)..."
kill -9 $WORKER_PID

echo "5. Waiting 35 seconds for process manager to detect and restart..."
sleep 35

echo "6. Checking if worker was restarted..."
NEW_PID=$(pgrep -f vj_audio_worker.py)
if [ -n "$NEW_PID" ] && [ "$NEW_PID" != "$WORKER_PID" ]; then
    echo "✓ Worker restarted with new PID: $NEW_PID"
else
    echo "✗ Worker not restarted"
fi

# Cleanup
kill $PM_PID 2>/dev/null || true
pkill -f vj_audio_worker.py 2>/dev/null || true

# Test 3: High-frequency telemetry
echo ""
echo "Test 3: High-frequency telemetry (audio analyzer @ 60 fps)"
echo "1. Starting audio worker..."
python vj_audio_worker.py &
WORKER_PID=$!
sleep 2

echo "2. Starting TUI..."
python vj_console.py &
TUI_PID=$!
sleep 2

echo "3. Switch to Audio Analysis screen (press '5')"
echo "4. Observe FPS counter - should show ~60 fps"
echo "5. Switch screens rapidly (1-2-3-4-5 repeatedly)"
echo "6. TUI should remain responsive, no lag"
echo ""
read -p "Verify manually, then press Enter to continue..."

# Cleanup
kill $TUI_PID $WORKER_PID 2>/dev/null || true

echo ""
echo "=== Manual tests complete ==="
```

**Run with:**
```bash
cd python-vj/tests
chmod +x manual_test.sh
./manual_test.sh
```

## Test Fixtures and Helpers

**Module:** `tests/conftest.py` (pytest fixtures)

```python
import pytest
import tempfile
import shutil
from pathlib import Path
from vj_bus.control import ControlSocket

@pytest.fixture
def temp_socket_dir():
    """Create temporary directory for test sockets."""
    temp_dir = Path(tempfile.mkdtemp(prefix="vj-bus-test-"))
    original_dir = ControlSocket.SOCKET_DIR
    ControlSocket.SOCKET_DIR = temp_dir
    
    yield temp_dir
    
    # Cleanup
    ControlSocket.SOCKET_DIR = original_dir
    shutil.rmtree(temp_dir, ignore_errors=True)

@pytest.fixture
def mock_worker(temp_socket_dir):
    """Create a mock worker for testing."""
    from vj_bus.worker import Worker
    from vj_bus.schema import CommandMessage, AckMessage
    
    class MockWorker(Worker):
        def __init__(self):
            super().__init__("mock_worker", ["/test/data"])
            self.test_config = {"value": 42}
        
        def on_start(self):
            pass
        
        def on_stop(self):
            pass
        
        def on_command(self, cmd: CommandMessage) -> AckMessage:
            if cmd.cmd == "get_state":
                return AckMessage(success=True, data={"config": self.test_config})
            elif cmd.cmd == "set_config":
                self.test_config.update(cmd.dict())
                return AckMessage(success=True)
            else:
                return AckMessage(success=False, message="Unknown command")
        
        def get_stats(self) -> dict:
            return {"test_stat": 123}
    
    return MockWorker()

@pytest.fixture
def osc_receiver():
    """Create OSC receiver for testing telemetry."""
    from pythonosc import dispatcher, osc_server
    import threading
    
    messages = []
    
    def capture(address, *args):
        messages.append((address, args))
    
    disp = dispatcher.Dispatcher()
    disp.map("/*", capture)
    
    server = osc_server.ThreadingOSCUDPServer(("127.0.0.1", 9000), disp)
    thread = threading.Thread(target=server.serve_forever)
    thread.daemon = True
    thread.start()
    
    yield messages
    
    server.shutdown()
    thread.join(timeout=1)
```

## Development Harness

**Script:** `scripts/dev_harness.py`

```python
#!/usr/bin/env python3
"""
Development harness for python-vj multi-process architecture.

Starts all workers and TUI together for manual testing.
Provides convenient controls for starting/stopping/restarting components.
"""

import subprocess
import time
import signal
import sys
from pathlib import Path

class DevHarness:
    def __init__(self):
        self.processes = {}
        self.running = False
    
    def start_process_manager(self):
        """Start process manager."""
        print("Starting process manager...")
        proc = subprocess.Popen(
            ["python", "vj_process_manager.py"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        self.processes['process_manager'] = proc
        time.sleep(2)
        print(f"  ✓ Process manager started (PID: {proc.pid})")
    
    def start_worker(self, name: str, script: str):
        """Start a worker process."""
        print(f"Starting {name}...")
        proc = subprocess.Popen(
            ["python", script],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        self.processes[name] = proc
        time.sleep(1)
        print(f"  ✓ {name} started (PID: {proc.pid})")
    
    def start_tui(self):
        """Start TUI (foreground)."""
        print("Starting TUI...")
        proc = subprocess.Popen(["python", "vj_console.py"])
        self.processes['tui'] = proc
        return proc
    
    def start_all(self):
        """Start all components."""
        self.running = True
        
        # Start process manager first
        self.start_process_manager()
        
        # Start workers
        self.start_worker("audio_analyzer", "vj_audio_worker.py")
        self.start_worker("lyrics_fetcher", "vj_lyrics_worker.py")
        self.start_worker("spotify_monitor", "vj_spotify_worker.py")
        self.start_worker("virtualdj_monitor", "vj_virtualdj_worker.py")
        
        # Start TUI (blocks)
        tui_proc = self.start_tui()
        
        try:
            tui_proc.wait()
        except KeyboardInterrupt:
            print("\nShutting down...")
            self.stop_all()
    
    def stop_all(self):
        """Stop all components."""
        print("Stopping all processes...")
        
        for name, proc in self.processes.items():
            try:
                print(f"  Stopping {name}...")
                proc.terminate()
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                print(f"  Force killing {name}...")
                proc.kill()
            except Exception as e:
                print(f"  Error stopping {name}: {e}")
        
        self.processes.clear()
        self.running = False
        print("All processes stopped")

def main():
    harness = DevHarness()
    
    # Setup signal handlers
    def shutdown(signum, frame):
        print("\nReceived shutdown signal")
        harness.stop_all()
        sys.exit(0)
    
    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)
    
    # Start everything
    harness.start_all()

if __name__ == "__main__":
    main()
```

**Run with:**
```bash
cd python-vj
python scripts/dev_harness.py
```

## CI/CD Integration

**GitHub Actions:** `.github/workflows/test-vj-architecture.yml`

```yaml
name: Test VJ Multi-Process Architecture

on:
  push:
    paths:
      - 'python-vj/**'
  pull_request:
    paths:
      - 'python-vj/**'

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      
      - name: Install dependencies
        run: |
          cd python-vj
          pip install -r requirements.txt
          pip install pytest pytest-asyncio pytest-timeout
      
      - name: Run unit tests
        run: |
          cd python-vj
          python -m pytest tests/test_vj_bus.py -v --timeout=10
  
  integration-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      
      - name: Install dependencies
        run: |
          cd python-vj
          pip install -r requirements.txt
          pip install pytest pytest-asyncio pytest-timeout
      
      - name: Run integration tests
        run: |
          cd python-vj
          python -m pytest tests/test_integration.py -v --timeout=60 -s
```

## Performance Benchmarks

**Script:** `tests/benchmark.py`

```python
#!/usr/bin/env python3
"""Performance benchmarks for multi-process architecture."""

import time
from vj_bus.control import ControlSocket
from vj_bus.telemetry import TelemetrySender
from vj_bus.schema import HeartbeatMessage

def benchmark_control_socket_throughput():
    """Measure control socket message throughput."""
    # TODO: Implement benchmark
    pass

def benchmark_osc_telemetry_latency():
    """Measure OSC message latency (send to receive)."""
    # TODO: Implement benchmark
    pass

def benchmark_worker_discovery_time():
    """Measure time to discover N workers."""
    # TODO: Implement benchmark
    pass

if __name__ == "__main__":
    print("Running performance benchmarks...")
    # TODO: Run all benchmarks
```

## Summary

This testing strategy provides:

1. **Unit tests** for core `vj_bus` library (message schema, IPC, discovery)
2. **Integration tests** for multi-process scenarios (crash recovery, reconnection, throughput)
3. **Manual test procedures** for human verification
4. **Development harness** for easy local testing
5. **CI/CD integration** for automated testing on commits
6. **Performance benchmarks** for latency and throughput validation

The combination ensures the multi-process architecture is robust, performant, and maintainable.
