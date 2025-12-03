"""
Service registry for VJ Bus workers.

File-based registry with file locking for concurrent access.
Each worker registers itself on startup and updates heartbeat periodically.
TUI discovers workers by reading the registry.
"""

import os
import json
import time
import fcntl
import logging
from pathlib import Path
from typing import Dict, Any, Optional
from contextlib import contextmanager

logger = logging.getLogger('vj_bus.registry')


class ServiceRegistry:
    """
    File-based service registry with atomic updates.

    Registry format:
    {
        "version": "1.0",
        "updated_at": 1733234567.89,
        "services": {
            "audio_analyzer": {
                "pid": 12345,
                "status": "running",
                "started_at": 1733234500.0,
                "heartbeat_at": 1733234567.89,
                "ports": {
                    "command": 5001,
                    "telemetry": 5002
                },
                "metadata": {...}
            }
        }
    }
    """

    REGISTRY_VERSION = "1.0"
    DEFAULT_DIR = Path.home() / ".vj"
    DEFAULT_FILE = "registry.json"
    HEARTBEAT_TIMEOUT_SEC = 15.0  # Mark as stale after 15s without heartbeat

    def __init__(self, registry_dir: Optional[Path] = None):
        """
        Initialize registry.

        Args:
            registry_dir: Directory for registry file (default: ~/.vj/)
        """
        self.registry_dir = registry_dir or self.DEFAULT_DIR
        self.registry_file = self.registry_dir / self.DEFAULT_FILE

        # Create directory if needed
        self.registry_dir.mkdir(parents=True, exist_ok=True)

        # Initialize empty registry if doesn't exist
        if not self.registry_file.exists():
            self._write_registry({
                "version": self.REGISTRY_VERSION,
                "updated_at": time.time(),
                "services": {}
            })

    @contextmanager
    def _lock_registry(self):
        """
        Context manager for exclusive file lock.

        Uses fcntl.flock for POSIX systems.
        """
        lock_file = self.registry_dir / f"{self.DEFAULT_FILE}.lock"

        # Open lock file
        fd = os.open(str(lock_file), os.O_CREAT | os.O_RDWR)

        try:
            # Acquire exclusive lock (blocks until available)
            fcntl.flock(fd, fcntl.LOCK_EX)
            yield
        finally:
            # Release lock
            fcntl.flock(fd, fcntl.LOCK_UN)
            os.close(fd)

    def _read_registry(self) -> Dict[str, Any]:
        """Read registry from file (assumes lock is held)."""
        try:
            with open(self.registry_file, 'r') as f:
                return json.load(f)
        except (FileNotFoundError, json.JSONDecodeError) as e:
            logger.warning(f"Failed to read registry: {e}, returning empty")
            return {
                "version": self.REGISTRY_VERSION,
                "updated_at": time.time(),
                "services": {}
            }

    def _write_registry(self, data: Dict[str, Any]):
        """Write registry to file (assumes lock is held)."""
        data["updated_at"] = time.time()

        # Write atomically via temp file + rename
        temp_file = self.registry_file.with_suffix('.tmp')
        try:
            with open(temp_file, 'w') as f:
                json.dump(data, f, indent=2)

            # Atomic rename
            temp_file.replace(self.registry_file)
        except Exception as e:
            logger.error(f"Failed to write registry: {e}")
            if temp_file.exists():
                temp_file.unlink()
            raise

    def register_service(
        self,
        name: str,
        pid: int,
        command_port: int,
        telemetry_port: int,
        metadata: Optional[Dict[str, Any]] = None
    ):
        """
        Register a service in the registry.

        Args:
            name: Service name (e.g., "audio_analyzer")
            pid: Process ID
            command_port: ZMQ REP port for commands
            telemetry_port: ZMQ PUB port for telemetry
            metadata: Optional metadata dict
        """
        with self._lock_registry():
            registry = self._read_registry()

            registry["services"][name] = {
                "pid": pid,
                "status": "running",
                "started_at": time.time(),
                "heartbeat_at": time.time(),
                "ports": {
                    "command": command_port,
                    "telemetry": telemetry_port
                },
                "metadata": metadata or {}
            }

            self._write_registry(registry)
            logger.info(f"Registered service: {name} (PID {pid})")

    def unregister_service(self, name: str):
        """Remove a service from the registry."""
        with self._lock_registry():
            registry = self._read_registry()

            if name in registry["services"]:
                del registry["services"][name]
                self._write_registry(registry)
                logger.info(f"Unregistered service: {name}")

    def update_heartbeat(self, name: str, metadata: Optional[Dict[str, Any]] = None):
        """
        Update service heartbeat timestamp.

        Args:
            name: Service name
            metadata: Optional updated metadata
        """
        with self._lock_registry():
            registry = self._read_registry()

            if name in registry["services"]:
                registry["services"][name]["heartbeat_at"] = time.time()

                if metadata is not None:
                    registry["services"][name]["metadata"] = metadata

                self._write_registry(registry)
            else:
                logger.warning(f"Cannot update heartbeat: service {name} not registered")

    def get_services(self, include_stale: bool = True) -> Dict[str, Dict[str, Any]]:
        """
        Get all services from registry.

        Args:
            include_stale: If False, only return services with recent heartbeat

        Returns:
            Dict of service_name -> service_info
        """
        with self._lock_registry():
            registry = self._read_registry()
            services = registry.get("services", {})

            if not include_stale:
                # Filter out stale services
                now = time.time()
                services = {
                    name: info
                    for name, info in services.items()
                    if (now - info.get("heartbeat_at", 0)) < self.HEARTBEAT_TIMEOUT_SEC
                }

            return services

    def get_service(self, name: str) -> Optional[Dict[str, Any]]:
        """
        Get a specific service.

        Returns:
            Service info dict or None if not found
        """
        services = self.get_services()
        return services.get(name)

    def is_service_healthy(self, name: str) -> bool:
        """
        Check if service is healthy (recent heartbeat).

        Args:
            name: Service name

        Returns:
            True if service exists and has recent heartbeat
        """
        service = self.get_service(name)
        if not service:
            return False

        now = time.time()
        heartbeat_age = now - service.get("heartbeat_at", 0)

        return heartbeat_age < self.HEARTBEAT_TIMEOUT_SEC

    def cleanup_stale_services(self):
        """Mark stale services as crashed."""
        with self._lock_registry():
            registry = self._read_registry()
            now = time.time()

            for name, info in registry["services"].items():
                heartbeat_age = now - info.get("heartbeat_at", 0)

                if heartbeat_age >= self.HEARTBEAT_TIMEOUT_SEC:
                    if info.get("status") == "running":
                        info["status"] = "crashed"
                        logger.warning(f"Service {name} marked as crashed (no heartbeat for {heartbeat_age:.1f}s)")

            self._write_registry(registry)
