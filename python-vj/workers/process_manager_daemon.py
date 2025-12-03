#!/usr/bin/env python3
"""
Process Manager Daemon - Supervises all VJ workers.

Responsibilities:
- Start/stop/restart workers
- Monitor worker health (heartbeat + PID checks)
- Auto-restart crashed workers with exponential backoff
- Publish lifecycle events (started, stopped, crashed, restarted)

Usage:
    python workers/process_manager_daemon.py
"""

import os
import sys
import time
import signal
import logging
import subprocess
from pathlib import Path
from typing import Dict, Any, Optional, List
from dataclasses import dataclass, field

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from vj_bus.worker import WorkerBase
from vj_bus.messages import WorkerStatePayload, EventMessage, EventType
from vj_bus.registry import ServiceRegistry

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

logger = logging.getLogger('process_manager')


@dataclass
class ManagedWorker:
    """Configuration for a managed worker."""
    name: str
    script_path: Path
    enabled: bool = False
    process: Optional[subprocess.Popen] = None
    restart_count: int = 0
    last_start_time: float = 0.0
    last_crash_time: float = 0.0
    backoff_until: float = 0.0


class ProcessManagerDaemon(WorkerBase):
    """
    Process manager daemon.

    Supervises all VJ workers:
    - Starts enabled workers on startup
    - Monitors worker health (heartbeat + PID)
    - Restarts crashed workers with exponential backoff
    - Publishes lifecycle events
    - Accepts commands to start/stop/restart workers
    """

    # Worker configurations
    WORKER_CONFIGS = [
        ("audio_analyzer", "workers/audio_analyzer_worker.py"),
        ("example_worker", "workers/example_worker.py"),
        ("virtualdj_monitor", "workers/virtualdj_monitor_worker.py"),
        ("lyrics_fetcher", "workers/lyrics_fetcher_worker.py"),
        # Will add more as we implement them
    ]

    def __init__(self):
        super().__init__(
            name="process_manager",
            command_port=5000,
            telemetry_port=5099,  # Used for events
            config={
                "check_interval": 5.0,  # Check every 5 seconds
                "max_restarts": 10,  # Max restarts before giving up
                "base_backoff": 5.0,  # Base backoff in seconds
                "max_backoff": 300.0,  # Max backoff (5 minutes)
            }
        )

        self.workers: Dict[str, ManagedWorker] = {}
        self.project_root = Path(__file__).parent.parent

        # Initialize worker configs
        for name, script_path in self.WORKER_CONFIGS:
            full_path = self.project_root / script_path
            self.workers[name] = ManagedWorker(
                name=name,
                script_path=full_path,
                enabled=False  # Don't auto-start by default
            )

    def on_start(self):
        """Initialize process manager."""
        logger.info("Process manager starting...")
        logger.info(f"Managing {len(self.workers)} workers")

        # Auto-start enabled workers (none by default)
        for worker in self.workers.values():
            if worker.enabled:
                self._start_worker(worker)

    def on_stop(self):
        """Stop all managed workers."""
        logger.info("Stopping all managed workers...")

        for worker in self.workers.values():
            if worker.process:
                self._stop_worker(worker)

    def run(self):
        """Main supervision loop."""
        logger.info("Process manager supervision loop started")

        check_interval = self.config.get("check_interval", 5.0)

        while self.running:
            # Check all workers
            for worker in self.workers.values():
                if worker.enabled:
                    self._check_worker(worker)

            # Sleep
            time.sleep(check_interval)

        logger.info("Process manager supervision loop exited")

    def _check_worker(self, worker: ManagedWorker):
        """
        Check worker health and restart if needed.

        Health checks:
        1. Is process running? (PID check)
        2. Is registry heartbeat fresh? (< 15s old)
        """
        # Check if we're in backoff period
        if worker.backoff_until > time.time():
            return  # Still in backoff

        # Check if process is running
        if worker.process:
            poll_result = worker.process.poll()

            if poll_result is not None:
                # Process exited
                exit_code = poll_result
                logger.warning(f"Worker {worker.name} exited with code {exit_code}")

                worker.last_crash_time = time.time()
                worker.process = None

                # Publish crash event
                self._publish_event(EventType.WORKER_CRASHED, worker.name, {
                    "exit_code": exit_code,
                    "restart_count": worker.restart_count
                })

                # Restart with backoff
                self._restart_worker(worker)
                return

        # Check registry heartbeat
        if not self.registry.is_service_healthy(worker.name):
            # Worker registered but heartbeat is stale
            service = self.registry.get_service(worker.name)

            if service and worker.process:
                # Worker process exists but not responding
                logger.warning(f"Worker {worker.name} has stale heartbeat")

                # Try to kill it
                try:
                    worker.process.terminate()
                    time.sleep(2)
                    if worker.process.poll() is None:
                        worker.process.kill()
                except Exception as e:
                    logger.error(f"Failed to kill {worker.name}: {e}")

                worker.process = None
                worker.last_crash_time = time.time()

                # Publish crash event
                self._publish_event(EventType.WORKER_CRASHED, worker.name, {
                    "reason": "stale_heartbeat"
                })

                # Restart
                self._restart_worker(worker)

    def _start_worker(self, worker: ManagedWorker) -> bool:
        """Start a worker process."""
        if worker.process and worker.process.poll() is None:
            logger.warning(f"Worker {worker.name} already running")
            return False

        if not worker.script_path.exists():
            logger.error(f"Worker script not found: {worker.script_path}")
            return False

        try:
            # Start worker as independent process
            logger.info(f"Starting worker: {worker.name}")

            worker.process = subprocess.Popen(
                [sys.executable, str(worker.script_path)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                start_new_session=True  # Detach from parent
            )

            worker.last_start_time = time.time()
            worker.enabled = True

            logger.info(f"Worker {worker.name} started (PID {worker.process.pid})")

            # Publish started event
            self._publish_event(EventType.WORKER_STARTED, worker.name, {
                "pid": worker.process.pid
            })

            return True

        except Exception as e:
            logger.error(f"Failed to start worker {worker.name}: {e}")
            return False

    def _stop_worker(self, worker: ManagedWorker) -> bool:
        """Stop a worker process gracefully."""
        if not worker.process:
            logger.warning(f"Worker {worker.name} not running")
            return False

        try:
            logger.info(f"Stopping worker: {worker.name}")

            # Try graceful termination first
            worker.process.terminate()

            try:
                worker.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                # Force kill
                logger.warning(f"Worker {worker.name} didn't stop gracefully, killing")
                worker.process.kill()
                worker.process.wait(timeout=2)

            logger.info(f"Worker {worker.name} stopped")

            worker.process = None
            worker.enabled = False

            # Publish stopped event
            self._publish_event(EventType.WORKER_STOPPED, worker.name, {})

            return True

        except Exception as e:
            logger.error(f"Failed to stop worker {worker.name}: {e}")
            return False

    def _restart_worker(self, worker: ManagedWorker):
        """Restart a crashed worker with exponential backoff."""
        worker.restart_count += 1

        max_restarts = self.config.get("max_restarts", 10)

        if worker.restart_count > max_restarts:
            logger.error(f"Worker {worker.name} exceeded max restarts ({max_restarts}), giving up")
            worker.enabled = False
            return

        # Calculate backoff
        base_backoff = self.config.get("base_backoff", 5.0)
        max_backoff = self.config.get("max_backoff", 300.0)

        backoff = min(base_backoff * (2 ** (worker.restart_count - 1)), max_backoff)
        worker.backoff_until = time.time() + backoff

        logger.info(f"Will restart {worker.name} in {backoff:.1f}s (attempt {worker.restart_count})")

        # Schedule restart (will happen in next check iteration)
        def delayed_restart():
            time.sleep(backoff)
            if worker.enabled and not worker.process:
                success = self._start_worker(worker)

                if success:
                    # Publish restarted event
                    self._publish_event(EventType.WORKER_RESTARTED, worker.name, {
                        "restart_count": worker.restart_count,
                        "backoff_sec": backoff
                    })

        # Don't block supervision loop
        import threading
        threading.Thread(target=delayed_restart, daemon=True).start()

    def _publish_event(self, event_type: EventType, worker_name: str, payload: Dict[str, Any]):
        """Publish a lifecycle event."""
        self.publish_telemetry("events.lifecycle", {
            "event": event_type,
            "worker": worker_name,
            "payload": payload
        })

    def get_state(self) -> WorkerStatePayload:
        """Return current state."""
        worker_states = {}

        for name, worker in self.workers.items():
            worker_states[name] = {
                "enabled": worker.enabled,
                "running": worker.process is not None and worker.process.poll() is None,
                "pid": worker.process.pid if worker.process else None,
                "restart_count": worker.restart_count,
                "last_start": worker.last_start_time,
            }

        return WorkerStatePayload(
            status="running" if self.running else "stopped",
            uptime_sec=time.time() - self.started_at,
            config=self.config,
            metrics={
                "workers": worker_states,
                "total_workers": len(self.workers),
                "enabled_workers": sum(1 for w in self.workers.values() if w.enabled),
                "running_workers": sum(1 for w in self.workers.values() if w.process and w.process.poll() is None),
            }
        )

    def get_metadata(self) -> Dict[str, Any]:
        """Return metadata for registry."""
        return {
            "version": "1.0",
            "managed_workers": list(self.workers.keys()),
            "running_workers": sum(1 for w in self.workers.values() if w.process and w.process.poll() is None),
        }

    def handle_command(self, cmd):
        """Handle custom commands."""
        from vj_bus.messages import ResponseMessage

        if cmd.command == "start_worker":
            worker_name = cmd.payload.get("worker")

            if not worker_name or worker_name not in self.workers:
                return ResponseMessage(
                    id=cmd.id,
                    source=self.name,
                    status="error",
                    error=f"Unknown worker: {worker_name}"
                )

            worker = self.workers[worker_name]
            success = self._start_worker(worker)

            return ResponseMessage(
                id=cmd.id,
                source=self.name,
                status="ok" if success else "error",
                result={"started": success}
            )

        elif cmd.command == "stop_worker":
            worker_name = cmd.payload.get("worker")

            if not worker_name or worker_name not in self.workers:
                return ResponseMessage(
                    id=cmd.id,
                    source=self.name,
                    status="error",
                    error=f"Unknown worker: {worker_name}"
                )

            worker = self.workers[worker_name]
            success = self._stop_worker(worker)

            return ResponseMessage(
                id=cmd.id,
                source=self.name,
                status="ok" if success else "error",
                result={"stopped": success}
            )

        elif cmd.command == "restart_worker":
            worker_name = cmd.payload.get("worker")

            if not worker_name or worker_name not in self.workers:
                return ResponseMessage(
                    id=cmd.id,
                    source=self.name,
                    status="error",
                    error=f"Unknown worker: {worker_name}"
                )

            worker = self.workers[worker_name]

            # Stop then start
            if worker.process:
                self._stop_worker(worker)

            time.sleep(0.5)
            success = self._start_worker(worker)

            return ResponseMessage(
                id=cmd.id,
                source=self.name,
                status="ok" if success else "error",
                result={"restarted": success}
            )

        elif cmd.command == "list_workers":
            workers_info = []

            for name, worker in self.workers.items():
                workers_info.append({
                    "name": name,
                    "enabled": worker.enabled,
                    "running": worker.process is not None and worker.process.poll() is None,
                    "pid": worker.process.pid if worker.process else None,
                    "restart_count": worker.restart_count,
                })

            return ResponseMessage(
                id=cmd.id,
                source=self.name,
                status="ok",
                result={"workers": workers_info}
            )

        else:
            return super().handle_command(cmd)


def main():
    """Entry point."""
    daemon = ProcessManagerDaemon()

    logger.info("=" * 60)
    logger.info("Process Manager Daemon Starting")
    logger.info("=" * 60)
    logger.info(f"PID: {daemon.pid}")
    logger.info(f"Command port: {daemon.command_port}")
    logger.info(f"Events port: {daemon.telemetry_port}")
    logger.info(f"Managing {len(daemon.workers)} workers")
    logger.info("=" * 60)

    try:
        daemon.start()
    except Exception as e:
        logger.exception(f"Process manager failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
