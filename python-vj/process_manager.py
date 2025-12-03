#!/usr/bin/env python3
"""
Process Manager - Manages Processing app processes with auto-restart.

This module contains the core process management classes used by the VJ Console:
- ProcessingApp: Represents a Processing sketch that can be launched
- AppState: Current state of the VJ Console
- ProcessManager: Manages Processing app processes with auto-restart
"""

import json
import multiprocessing
import os
import sys
import time
import subprocess
import logging
import shutil
from pathlib import Path
from threading import Thread, Event
from dataclasses import dataclass, field
from typing import Callable, List, Optional, Dict

from vj_bus import EnvelopeBuilder
from vj_bus.utils import find_free_port, generate_instance_id, now_ts
from vj_bus.worker import WorkerNode
from vj_bus.zmq_helpers import publish, start_pub

# Load .env file if present
try:
    from dotenv import load_dotenv
    env_locations = [
        Path.cwd() / '.env',
        Path(__file__).parent / '.env',
        Path.home() / '.env',
    ]
    for env_path in env_locations:
        if env_path.exists():
            load_dotenv(env_path)
            break
except ImportError:
    pass

logger = logging.getLogger('process_manager')


@dataclass
class ProcessingApp:
    """Represents a Processing sketch that can be launched."""
    name: str
    path: Path
    description: str = ""
    process: Optional[subprocess.Popen] = None
    restart_count: int = 0
    last_restart: float = 0
    enabled: bool = False


@dataclass
class AppState:
    """Current state of the VJ Console."""
    selected_index: int = 0
    daemon_mode: bool = False
    karaoke_enabled: bool = True
    running: bool = True
    message: str = ""
    message_time: float = 0
    needs_redraw: bool = True
    last_draw_time: float = 0


@dataclass
class WorkerSpec:
    """Specification for a managed worker process."""

    name: str
    telemetry_port: int
    command_endpoint: str
    event_endpoint: str
    entrypoint: Callable[["WorkerSpec", int, str], None]
    schema: str = "vj.v1"
    generation: int = 0


@dataclass
class ManagedWorker:
    spec: WorkerSpec
    process: Optional[multiprocessing.Process]
    instance_id: str
    generation: int


def _spawn_worker_process(spec: WorkerSpec, generation: int, instance_id: str) -> None:
    spec.entrypoint(spec, generation, instance_id)


class ProcessManager:
    """Manages Processing app processes with auto-restart."""
    
    def __init__(self, processing_path: Optional[str] = None):
        self.apps: List[ProcessingApp] = []
        self.monitor_thread: Optional[Thread] = None
        self.stop_event = Event()
        
        # Find Processing executable
        self.processing_cmd = self._find_processing(processing_path)
        if self.processing_cmd:
            logger.info(f"Processing found: {self.processing_cmd}")
        else:
            logger.warning("Processing not found in PATH. Apps must be run manually.")
    
    def _find_processing(self, custom_path: Optional[str] = None) -> Optional[str]:
        """Find the Processing executable."""
        if custom_path and Path(custom_path).exists():
            return custom_path
        
        # Common locations
        candidates = [
            "processing-java",  # Linux/CLI
            "/Applications/Processing.app/Contents/MacOS/Processing",  # macOS
            Path.home() / "Applications" / "Processing.app" / "Contents" / "MacOS" / "Processing",
        ]
        
        # Check PATH first
        processing_java = shutil.which("processing-java")
        if processing_java:
            return processing_java
        
        for candidate in candidates:
            if isinstance(candidate, str):
                if shutil.which(candidate):
                    return candidate
            elif candidate.exists():
                return str(candidate)
        
        return None
    
    def discover_apps(self, project_root: Path) -> List[ProcessingApp]:
        """Discover Processing sketches in the project."""
        self.apps = []

        # Look for .pde files in processing-vj/src
        examples_dir = project_root / "processing-vj" / "src"
        if not examples_dir.exists():
            logger.warning(f"Source directory not found: {examples_dir}")
            return self.apps
        
        for sketch_dir in examples_dir.iterdir():
            if sketch_dir.is_dir():
                pde_files = list(sketch_dir.glob("*.pde"))
                if pde_files:
                    # Use main .pde file that matches directory name
                    main_file = sketch_dir / f"{sketch_dir.name}.pde"
                    if not main_file.exists() and pde_files:
                        main_file = pde_files[0]
                    
                    description = self._extract_description(main_file)
                    
                    self.apps.append(ProcessingApp(
                        name=sketch_dir.name,
                        path=sketch_dir,
                        description=description
                    ))
        
        self.apps.sort(key=lambda a: a.name)
        logger.info(f"Discovered {len(self.apps)} Processing apps")
        return self.apps
    
    def _extract_description(self, pde_file: Path) -> str:
        """Extract description from Processing sketch comments."""
        try:
            content = pde_file.read_text()
            # Look for first line comment or docstring
            lines = content.split('\n')
            for line in lines[:20]:  # Check first 20 lines
                line = line.strip()
                if line.startswith('/**') or line.startswith('/*'):
                    continue
                if line.startswith('*') and len(line) > 2:
                    desc = line.lstrip('* ').strip()
                    if desc and not desc.startswith('@'):
                        return desc[:60]  # Truncate
                if line.startswith('//'):
                    desc = line.lstrip('/ ').strip()
                    if desc:
                        return desc[:60]
        except Exception:
            pass
        return ""
    
    def launch_app(self, app: ProcessingApp) -> bool:
        """Launch a Processing app."""
        if app.process and app.process.poll() is None:
            logger.warning(f"{app.name} is already running")
            return False
        
        if not self.processing_cmd:
            logger.error("Processing not found. Cannot launch apps.")
            return False
        
        try:
            # Use processing-java to run the sketch
            cmd = [
                self.processing_cmd,
                "--sketch=" + str(app.path),
                "--run"
            ]
            
            # Start in new process group for proper cleanup
            app.process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                start_new_session=True
            )
            app.enabled = True
            app.last_restart = time.time()
            logger.info(f"Launched {app.name} (PID: {app.process.pid})")
            return True
            
        except Exception as e:
            logger.error(f"Failed to launch {app.name}: {e}")
            return False
    
    def stop_app(self, app: ProcessingApp):
        """Stop a running Processing app."""
        if app.process:
            try:
                # Try graceful termination first
                app.process.terminate()
                try:
                    app.process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    app.process.kill()
                logger.info(f"Stopped {app.name}")
            except Exception as e:
                logger.error(f"Error stopping {app.name}: {e}")
            finally:
                app.process = None
        app.enabled = False
    
    def is_running(self, app: ProcessingApp) -> bool:
        """Check if an app is currently running."""
        if app.process is None:
            return False
        return app.process.poll() is None
    
    def start_monitoring(self, daemon_mode: bool = True):
        """Start background thread to monitor and restart crashed apps."""
        self.stop_event.clear()
        self.monitor_thread = Thread(target=self._monitor_loop, args=(daemon_mode,), daemon=True)
        self.monitor_thread.start()
    
    def stop_monitoring(self):
        """Stop the monitoring thread."""
        self.stop_event.set()
        if self.monitor_thread:
            self.monitor_thread.join(timeout=2)
    
    def _monitor_loop(self, daemon_mode: bool):
        """Monitor running apps and restart if crashed (daemon mode)."""
        while not self.stop_event.is_set():
            for app in self.apps:
                if app.enabled and not self.is_running(app):
                    if daemon_mode:
                        # App crashed - restart it
                        cooldown = min(30, 5 * (app.restart_count + 1))
                        if time.time() - app.last_restart > cooldown:
                            logger.warning(f"{app.name} crashed. Restarting...")
                            app.restart_count += 1
                            self.launch_app(app)
                    else:
                        logger.info(f"{app.name} exited")
                        app.enabled = False
            
            time.sleep(2)
    
    def cleanup(self):
        """Stop all running apps and monitoring."""
        self.stop_monitoring()
        for app in self.apps:
            if self.is_running(app):
                self.stop_app(app)


class VJProcessManager:
    """Supervisor for vj_bus workers with registry + restart."""

    def __init__(
        self,
        registry_path: Path | None = None,
        pub_endpoint: str | None = None,
        schema: str = "vj.v1",
    ) -> None:
        self.registry_path = registry_path or Path("/tmp/python-vj/process_registry.json")
        self.pub_endpoint = pub_endpoint or f"tcp://127.0.0.1:{find_free_port()}"
        self.schema = schema
        self._builder = EnvelopeBuilder(schema=schema, worker="process_manager")
        self._pub_socket = start_pub(self.pub_endpoint)
        self._workers: Dict[str, ManagedWorker] = {}
        self._stop = Event()
        self._monitor = Thread(target=self._monitor_loop, daemon=True)

    # Worker spec helpers
    def make_worker_spec(
        self,
        name: str,
        telemetry_port: Optional[int] = None,
        command_port: Optional[int] = None,
        event_port: Optional[int] = None,
        entrypoint: Optional[Callable[[WorkerSpec, int, str], None]] = None,
    ) -> WorkerSpec:
        telemetry = telemetry_port or find_free_port()
        command = command_port or find_free_port()
        event = event_port or find_free_port()
        return WorkerSpec(
            name=name,
            telemetry_port=telemetry,
            command_endpoint=f"tcp://127.0.0.1:{command}",
            event_endpoint=f"tcp://127.0.0.1:{event}",
            entrypoint=entrypoint or VJProcessManager._default_entrypoint,
        )

    @staticmethod
    def _default_entrypoint(spec: WorkerSpec, generation: int, instance_id: str) -> None:
        node = WorkerNode(
            name=spec.name,
            telemetry_port=spec.telemetry_port,
            command_endpoint=spec.command_endpoint,
            event_endpoint=spec.event_endpoint,
            schema=spec.schema,
            heartbeat_interval=1.0,
            generation=generation,
            instance_id=instance_id,
        )
        node.start()
        node.run_forever()

    def add_worker(self, spec: WorkerSpec) -> None:
        instance_id = generate_instance_id()
        self._workers[spec.name] = ManagedWorker(
            spec=spec, process=None, instance_id=instance_id, generation=spec.generation
        )

    def start(self) -> None:
        for managed in list(self._workers.values()):
            self._launch(managed)
        if not self._monitor.is_alive():
            self._monitor.start()

    def _launch(self, managed: ManagedWorker) -> None:
        if managed.process and managed.process.is_alive():
            return
        managed.process = multiprocessing.Process(
            target=_spawn_worker_process,
            args=(managed.spec, managed.generation, managed.instance_id),
            daemon=True,
        )
        managed.process.start()
        self._write_registry()
        env = self._builder.event(
            level="info",
            message="register",
            details={"worker": managed.spec.name, "instance_id": managed.instance_id, "generation": managed.generation},
        )
        publish(self._pub_socket, env)

    def _monitor_loop(self) -> None:
        while not self._stop.wait(0.5):
            for name, managed in list(self._workers.items()):
                if managed.process and managed.process.is_alive():
                    continue
                managed.generation += 1
                managed.instance_id = generate_instance_id()
                self._launch(managed)

    def stop(self) -> None:
        self._stop.set()
        if self._monitor.is_alive():
            self._monitor.join(timeout=2)
        for managed in self._workers.values():
            if managed.process and managed.process.is_alive():
                managed.process.terminate()
                managed.process.join(timeout=2)
        self._write_registry()
        self._pub_socket.close(0)

    def registry_snapshot(self) -> Dict[str, Dict[str, str | int]]:
        return {
            name: {
                "instance_id": managed.instance_id,
                "generation": managed.generation,
                "telemetry": managed.spec.telemetry_port,
                "command": managed.spec.command_endpoint,
                "events": managed.spec.event_endpoint,
                "started_at": now_ts(),
            }
            for name, managed in self._workers.items()
        }

    def _write_registry(self) -> None:
        data = {"schema": self.schema, "workers": self.registry_snapshot()}
        self.registry_path.parent.mkdir(parents=True, exist_ok=True)
        self.registry_path.write_text(json.dumps(data, indent=2))
