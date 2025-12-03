"""
Integration tests for process manager daemon.

Tests:
- Start/stop workers via commands
- Worker crash detection and auto-restart
- Event publishing
- Worker supervision
"""

import pytest
import time
import subprocess
import sys
import signal
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from vj_bus.client import VJBusClient


@pytest.fixture(scope="function")
def process_manager():
    """Start process manager in subprocess."""
    proc = subprocess.Popen(
        [sys.executable, "workers/process_manager_daemon.py"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd=Path(__file__).parent.parent.parent
    )

    # Wait for startup
    time.sleep(3)

    yield proc

    # Cleanup
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()


class TestProcessManager:
    """Test process manager daemon."""

    def test_process_manager_starts(self, process_manager):
        """Process manager starts and registers."""
        client = VJBusClient()
        workers = client.discover_workers()

        assert "process_manager" in workers
        assert workers["process_manager"]["status"] == "running"

    def test_health_check(self, process_manager):
        """Process manager responds to health check."""
        client = VJBusClient()

        time.sleep(1)  # Let it fully initialize

        response = client.send_command("process_manager", "health_check")
        assert response.status == "ok"
        assert response.result["alive"] is True

    def test_list_workers(self, process_manager):
        """Can list managed workers."""
        client = VJBusClient()

        time.sleep(1)

        response = client.send_command("process_manager", "list_workers")
        assert response.status == "ok"
        assert "workers" in response.result

        workers = response.result["workers"]
        worker_names = [w["name"] for w in workers]

        assert "example_worker" in worker_names
        assert "audio_analyzer" in worker_names

    def test_start_worker(self, process_manager):
        """Can start a worker via command."""
        client = VJBusClient()

        time.sleep(1)

        # Start example worker
        response = client.send_command(
            "process_manager",
            "start_worker",
            payload={"worker": "example_worker"}
        )

        assert response.status == "ok"
        assert response.result["started"] is True

        # Wait for worker to register
        time.sleep(3)

        # Check worker is running
        workers = client.discover_workers()
        assert "example_worker" in workers

    def test_stop_worker(self, process_manager):
        """Can stop a worker via command."""
        client = VJBusClient()

        time.sleep(1)

        # Start worker
        client.send_command(
            "process_manager",
            "start_worker",
            payload={"worker": "example_worker"}
        )

        time.sleep(3)

        # Stop worker
        response = client.send_command(
            "process_manager",
            "stop_worker",
            payload={"worker": "example_worker"}
        )

        assert response.status == "ok"
        assert response.result["stopped"] is True

        # Wait for cleanup
        time.sleep(2)

        # Check worker is not in registry
        workers = client.discover_workers(include_stale=False)
        assert "example_worker" not in workers

    def test_restart_worker(self, process_manager):
        """Can restart a worker via command."""
        client = VJBusClient()

        time.sleep(1)

        # Start worker
        client.send_command(
            "process_manager",
            "start_worker",
            payload={"worker": "example_worker"}
        )

        time.sleep(3)

        # Get initial PID
        initial_workers = client.discover_workers()
        initial_pid = initial_workers["example_worker"]["pid"]

        # Restart
        response = client.send_command(
            "process_manager",
            "restart_worker",
            payload={"worker": "example_worker"}
        )

        assert response.status == "ok"
        assert response.result["restarted"] is True

        time.sleep(3)

        # Check new PID (should be different)
        new_workers = client.discover_workers()
        new_pid = new_workers["example_worker"]["pid"]

        assert new_pid != initial_pid

    def test_worker_crash_detection(self, process_manager):
        """Process manager detects crashed workers."""
        client = VJBusClient()

        time.sleep(1)

        # Subscribe to events
        events = []

        def event_handler(msg):
            events.append(msg.payload)

        client.subscribe("events.lifecycle", event_handler)
        client.start()

        # Start worker
        client.send_command(
            "process_manager",
            "start_worker",
            payload={"worker": "example_worker"}
        )

        time.sleep(3)

        # Get worker PID
        workers = client.discover_workers()
        worker_pid = workers["example_worker"]["pid"]

        # Kill worker manually
        import os
        os.kill(worker_pid, signal.SIGKILL)

        # Wait for process manager to detect crash and restart
        time.sleep(10)

        # Check events
        crash_events = [e for e in events if e.get("event") == "worker_crashed"]
        restart_events = [e for e in events if e.get("event") == "worker_restarted"]

        assert len(crash_events) >= 1
        assert crash_events[0]["worker"] == "example_worker"

        # Worker should be restarted
        workers = client.discover_workers()
        assert "example_worker" in workers

        # Cleanup
        client.stop()

    def test_get_state(self, process_manager):
        """Can get process manager state."""
        client = VJBusClient()

        time.sleep(1)

        response = client.send_command("process_manager", "get_state")
        assert response.status == "ok"

        state = response.result
        assert state["status"] == "running"
        assert "metrics" in state
        assert "workers" in state["metrics"]
