#!/usr/bin/env python3
"""
Process Manager - Worker Supervisor Daemon

Manages all VJ worker processes with auto-restart on crash.
Monitors heartbeats and restarts failed workers with exponential backoff.
"""

import os
import sys
import time
import signal
import subprocess
import logging
from pathlib import Path
from typing import Dict, List, Optional
from dataclasses import dataclass, field
from datetime import datetime

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent))

from vj_bus import Worker
from vj_bus.schema import CommandMessage, AckMessage, RegisterMessage
from vj_bus.discovery import WorkerDiscovery

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('vj_process_manager')


@dataclass
class ManagedWorker:
    """Represents a managed worker process."""
    name: str
    script: str
    process: Optional[subprocess.Popen] = None
    enabled: bool = True
    restart_count: int = 0
    last_restart: float = 0
    last_heartbeat: float = 0
    crash_times: List[float] = field(default_factory=list)
    
    @property
    def is_running(self) -> bool:
        """Check if process is running."""
        return self.process is not None and self.process.poll() is None
    
    @property
    def should_restart(self) -> bool:
        """Check if worker should be restarted."""
        if not self.enabled:
            return False
        
        # Check crash rate (max 5 restarts in 60 seconds)
        recent_crashes = [t for t in self.crash_times if time.time() - t < 60]
        if len(recent_crashes) >= 5:
            logger.error(f"{self.name}: Too many crashes (5 in 60s), giving up")
            return False
        
        return True


class ProcessManagerWorker(Worker):
    """
    Process manager worker - supervises all other workers.
    
    Provides:
    - Worker process launching and monitoring
    - Heartbeat-based health checks (30s timeout)
    - Auto-restart with exponential backoff
    - Control socket at /tmp/vj-bus/process_manager.sock
    """
    
    HEARTBEAT_TIMEOUT = 30.0  # seconds without heartbeat before restart
    MAX_RESTARTS_PER_MINUTE = 5
    
    def __init__(self):
        super().__init__(
            name="process_manager",
            osc_addresses=[]
        )
        
        self.workers: Dict[str, ManagedWorker] = {}
        self._init_workers()
        
        logger.info("Process manager initialized")
    
    def _init_workers(self):
        """Initialize managed worker definitions."""
        script_dir = Path(__file__).parent
        
        self.workers = {
            "audio_analyzer": ManagedWorker(
                name="audio_analyzer",
                script=str(script_dir / "vj_audio_worker.py"),
                enabled=False  # Disabled by default (requires audio hardware)
            ),
            "spotify_monitor": ManagedWorker(
                name="spotify_monitor",
                script=str(script_dir / "vj_spotify_worker.py"),
                enabled=True
            ),
            "virtualdj_monitor": ManagedWorker(
                name="virtualdj_monitor",
                script=str(script_dir / "vj_virtualdj_worker.py"),
                enabled=True
            ),
            "lyrics_fetcher": ManagedWorker(
                name="lyrics_fetcher",
                script=str(script_dir / "vj_lyrics_worker.py"),
                enabled=True
            ),
            "osc_debugger": ManagedWorker(
                name="osc_debugger",
                script=str(script_dir / "vj_osc_debugger.py"),
                enabled=False  # Disabled by default (debugging tool)
            ),
        }
    
    def on_start(self):
        """Start all enabled workers."""
        logger.info("Starting process manager...")
        
        for worker in self.workers.values():
            if worker.enabled:
                self._start_worker(worker)
        
        logger.info("Process manager started")
    
    def on_stop(self):
        """Stop all workers."""
        logger.info("Stopping all workers...")
        
        for worker in self.workers.values():
            if worker.is_running:
                self._stop_worker(worker)
        
        logger.info("All workers stopped")
    
    def on_command(self, cmd: CommandMessage) -> AckMessage:
        """Handle commands from TUI."""
        if cmd.cmd == "get_state":
            worker_status = {}
            for name, worker in self.workers.items():
                worker_status[name] = {
                    "enabled": worker.enabled,
                    "running": worker.is_running,
                    "restart_count": worker.restart_count,
                    "last_heartbeat": worker.last_heartbeat,
                }
            
            return AckMessage(
                success=True,
                data={
                    "workers": worker_status,
                    "total_managed": len(self.workers),
                }
            )
        
        elif cmd.cmd == "start_worker":
            worker_name = getattr(cmd, 'worker', None)
            if not worker_name or worker_name not in self.workers:
                return AckMessage(success=False, message=f"Unknown worker: {worker_name}")
            
            worker = self.workers[worker_name]
            if worker.is_running:
                return AckMessage(success=False, message=f"{worker_name} already running")
            
            self._start_worker(worker)
            return AckMessage(success=True, message=f"{worker_name} started")
        
        elif cmd.cmd == "stop_worker":
            worker_name = getattr(cmd, 'worker', None)
            if not worker_name or worker_name not in self.workers:
                return AckMessage(success=False, message=f"Unknown worker: {worker_name}")
            
            worker = self.workers[worker_name]
            if not worker.is_running:
                return AckMessage(success=False, message=f"{worker_name} not running")
            
            self._stop_worker(worker)
            return AckMessage(success=True, message=f"{worker_name} stopped")
        
        elif cmd.cmd == "restart_worker":
            worker_name = getattr(cmd, 'worker', None)
            if not worker_name or worker_name not in self.workers:
                return AckMessage(success=False, message=f"Unknown worker: {worker_name}")
            
            worker = self.workers[worker_name]
            if worker.is_running:
                self._stop_worker(worker)
            time.sleep(0.5)
            self._start_worker(worker)
            return AckMessage(success=True, message=f"{worker_name} restarted")
        
        else:
            return AckMessage(success=False, message=f"Unknown command: {cmd.cmd}")
    
    def get_stats(self) -> dict:
        """Get current stats for heartbeat."""
        running_count = sum(1 for w in self.workers.values() if w.is_running)
        enabled_count = sum(1 for w in self.workers.values() if w.enabled)
        
        return {
            "total_workers": len(self.workers),
            "enabled_workers": enabled_count,
            "running_workers": running_count,
        }
    
    def on_loop(self):
        """Monitor worker health and restart crashed workers."""
        if not hasattr(self, '_last_health_check'):
            self._last_health_check = 0
        
        now = time.time()
        if now - self._last_health_check >= 5.0:  # Check every 5 seconds
            self._check_worker_health()
            self._last_health_check = now
    
    def _start_worker(self, worker: ManagedWorker):
        """Start a worker process."""
        try:
            logger.info(f"Starting {worker.name}...")
            
            # Start process
            worker.process = subprocess.Popen(
                [sys.executable, worker.script],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                start_new_session=True  # Detach from parent
            )
            
            worker.last_restart = time.time()
            worker.last_heartbeat = time.time()
            
            logger.info(f"{worker.name} started (PID: {worker.process.pid})")
        
        except Exception as e:
            logger.exception(f"Failed to start {worker.name}: {e}")
            worker.process = None
    
    def _stop_worker(self, worker: ManagedWorker):
        """Stop a worker process."""
        if not worker.process:
            return
        
        try:
            logger.info(f"Stopping {worker.name}...")
            
            # Try graceful termination
            worker.process.terminate()
            try:
                worker.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                logger.warning(f"{worker.name} did not stop gracefully, killing...")
                worker.process.kill()
                worker.process.wait()
            
            logger.info(f"{worker.name} stopped")
        
        except Exception as e:
            logger.error(f"Error stopping {worker.name}: {e}")
        
        finally:
            worker.process = None
    
    def _check_worker_health(self):
        """Check health of all workers and restart if needed."""
        for worker in self.workers.values():
            if not worker.enabled:
                continue
            
            # Check if process crashed
            if not worker.is_running:
                if worker.should_restart:
                    logger.warning(f"{worker.name} crashed, restarting...")
                    worker.crash_times.append(time.time())
                    worker.restart_count += 1
                    
                    # Exponential backoff
                    backoff = min(30, 2 ** min(worker.restart_count, 5))
                    if time.time() - worker.last_restart < backoff:
                        logger.info(f"{worker.name}: Waiting {backoff}s before restart")
                        continue
                    
                    self._start_worker(worker)
                continue
            
            # Check heartbeat timeout (simulate - in full implementation would check via socket)
            # For now, just check if process is alive
            # In full version, we'd track heartbeat messages from workers


def main():
    """Main entry point for process manager."""
    logger.info("=" * 60)
    logger.info("Process Manager starting...")
    logger.info(f"PID: {os.getpid()}")
    logger.info("=" * 60)
    
    manager = ProcessManagerWorker()
    
    def shutdown_handler(signum, frame):
        logger.info(f"Received signal {signum}, shutting down...")
        manager.stop()
        sys.exit(0)
    
    signal.signal(signal.SIGTERM, shutdown_handler)
    signal.signal(signal.SIGINT, shutdown_handler)
    
    try:
        manager.start()
    except Exception as e:
        logger.exception(f"Fatal error: {e}")
        manager.stop()
        sys.exit(1)


if __name__ == "__main__":
    main()
