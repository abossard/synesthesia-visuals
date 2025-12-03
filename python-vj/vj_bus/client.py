"""
VJ Bus client for TUI.

Provides high-level API for:
- Discovering workers via registry
- Sending commands to workers
- Subscribing to telemetry
"""

import logging
from typing import Dict, Any, Callable, Optional, List
import time

from .messages import (
    CommandMessage,
    ResponseMessage,
    TelemetryMessage,
    CommandType,
    ResponseStatus,
)
from .registry import ServiceRegistry
from .transport import ZMQCommandClient, ZMQTelemetrySubscriber

logger = logging.getLogger('vj_bus.client')


class VJBusClient:
    """
    Client for VJ Bus (used by TUI).

    Features:
    - Discover workers from registry
    - Send commands with timeout/retry
    - Subscribe to telemetry topics
    - Manage multiple worker connections
    """

    def __init__(self):
        """Initialize VJ Bus client."""
        self.registry = ServiceRegistry()

        # Worker connections (name -> ZMQCommandClient)
        self.workers: Dict[str, ZMQCommandClient] = {}

        # Telemetry subscribers (port -> ZMQTelemetrySubscriber)
        self.subscribers: Dict[int, ZMQTelemetrySubscriber] = {}

    def discover_workers(self, include_stale: bool = False) -> Dict[str, Dict[str, Any]]:
        """
        Discover workers from registry.

        Args:
            include_stale: If False, only return workers with recent heartbeat

        Returns:
            Dict of worker_name -> worker_info
        """
        services = self.registry.get_services(include_stale=include_stale)
        logger.info(f"Discovered {len(services)} workers")
        return services

    def get_worker(self, name: str) -> Optional[Dict[str, Any]]:
        """
        Get a specific worker's info.

        Args:
            name: Worker name

        Returns:
            Worker info dict or None if not found
        """
        return self.registry.get_service(name)

    def is_worker_healthy(self, name: str) -> bool:
        """
        Check if worker is healthy.

        Args:
            name: Worker name

        Returns:
            True if worker has recent heartbeat
        """
        return self.registry.is_service_healthy(name)

    def send_command(
        self,
        worker_name: str,
        command: str,
        payload: Optional[Dict[str, Any]] = None,
        timeout_ms: int = 2000
    ) -> ResponseMessage:
        """
        Send a command to a worker.

        Args:
            worker_name: Name of target worker
            command: Command type (e.g., "health_check", "set_config")
            payload: Optional command payload
            timeout_ms: Request timeout in milliseconds

        Returns:
            ResponseMessage from worker

        Raises:
            ValueError: If worker not found
            TimeoutError: If request times out
            ConnectionError: If connection fails
        """
        # Get worker info
        worker_info = self.get_worker(worker_name)
        if not worker_info:
            raise ValueError(f"Worker not found: {worker_name}")

        command_port = worker_info["ports"]["command"]

        # Get or create client
        if worker_name not in self.workers:
            self.workers[worker_name] = ZMQCommandClient(
                port=command_port,
                timeout_ms=timeout_ms
            )

        client = self.workers[worker_name]

        # Create command message
        cmd = CommandMessage(
            command=command,
            payload=payload or {}
        )

        # Send command
        try:
            response = client.send_command(cmd)
            return response
        except Exception as e:
            logger.error(f"Failed to send command to {worker_name}: {e}")
            # Remove stale client
            if worker_name in self.workers:
                self.workers[worker_name].disconnect()
                del self.workers[worker_name]
            raise

    def subscribe(
        self,
        topic: str,
        handler: Callable[[TelemetryMessage], None],
        worker_name: Optional[str] = None
    ):
        """
        Subscribe to a telemetry topic.

        Args:
            topic: Topic pattern (e.g., "audio.features", "audio.*", "*")
            handler: Function to call for matching messages
            worker_name: Optional worker name (if None, subscribes to all workers)
        """
        if worker_name:
            # Subscribe to specific worker
            worker_info = self.get_worker(worker_name)
            if not worker_info:
                logger.warning(f"Worker not found: {worker_name}, cannot subscribe")
                return

            telemetry_port = worker_info["ports"]["telemetry"]
            self._subscribe_to_port(telemetry_port, topic, handler)
        else:
            # Subscribe to all workers
            workers = self.discover_workers(include_stale=False)
            for name, info in workers.items():
                telemetry_port = info["ports"]["telemetry"]
                self._subscribe_to_port(telemetry_port, topic, handler)

    def _subscribe_to_port(
        self,
        port: int,
        topic: str,
        handler: Callable[[TelemetryMessage], None]
    ):
        """Subscribe to a specific port."""
        if port not in self.subscribers:
            # Create new subscriber
            subscriber = ZMQTelemetrySubscriber(port=port)
            subscriber.subscribe(topic, handler)
            self.subscribers[port] = subscriber
        else:
            # Add to existing subscriber
            self.subscribers[port].subscribe(topic, handler)

    def start(self):
        """Start all telemetry subscribers."""
        for port, subscriber in self.subscribers.items():
            if not subscriber.running:
                subscriber.start()
                logger.info(f"Started telemetry subscriber on port {port}")

    def stop(self):
        """Stop all connections."""
        # Stop subscribers
        for subscriber in self.subscribers.values():
            subscriber.stop()

        # Disconnect command clients
        for client in self.workers.values():
            client.disconnect()

        logger.info("VJ Bus client stopped")

    def health_check_all(self) -> Dict[str, bool]:
        """
        Health check all discovered workers.

        Returns:
            Dict of worker_name -> is_healthy
        """
        workers = self.discover_workers(include_stale=False)
        results = {}

        for name in workers.keys():
            try:
                response = self.send_command(name, CommandType.HEALTH_CHECK, timeout_ms=1000)
                results[name] = (response.status == ResponseStatus.OK)
            except Exception as e:
                logger.debug(f"Health check failed for {name}: {e}")
                results[name] = False

        return results

    def get_all_states(self) -> Dict[str, Dict[str, Any]]:
        """
        Get state from all workers.

        Returns:
            Dict of worker_name -> state_dict
        """
        workers = self.discover_workers(include_stale=False)
        states = {}

        for name in workers.keys():
            try:
                response = self.send_command(name, CommandType.GET_STATE)
                if response.status == ResponseStatus.OK:
                    states[name] = response.result
            except Exception as e:
                logger.debug(f"Failed to get state from {name}: {e}")
                states[name] = {"error": str(e)}

        return states
