"""
Base class for VJ Bus workers.

Handles ZMQ setup, registry management, command loop.
"""

import os
import time
import logging
import signal
import threading
from abc import ABC, abstractmethod
from typing import Optional, Dict, Any

from .messages import (
    CommandMessage,
    ResponseMessage,
    TelemetryMessage,
    HeartbeatMessage,
    ResponseStatus,
    CommandType,
    WorkerStatePayload,
)
from .registry import ServiceRegistry
from .transport import ZMQCommandServer, ZMQTelemetryPublisher

logger = logging.getLogger('vj_bus.worker')


class WorkerBase(ABC):
    """
    Base class for resilient VJ workers.

    Responsibilities:
    - ZMQ command server (REP socket)
    - ZMQ telemetry publisher (PUB socket)
    - Service registry management
    - Heartbeat thread
    - Graceful shutdown

    Subclasses must implement:
    - run(): Main worker loop
    - get_state(): Return current state
    - get_metadata(): Return metadata for registry
    """

    def __init__(
        self,
        name: str,
        command_port: int,
        telemetry_port: int,
        config: Optional[Dict[str, Any]] = None
    ):
        """
        Initialize worker.

        Args:
            name: Worker name (e.g., "audio_analyzer")
            command_port: Port for ZMQ REP socket (commands)
            telemetry_port: Port for ZMQ PUB socket (telemetry)
            config: Optional configuration dict
        """
        self.name = name
        self.command_port = command_port
        self.telemetry_port = telemetry_port
        self.config = config or {}

        self.pid = os.getpid()
        self.started_at = time.time()
        self.running = False

        # ZMQ transport
        self.command_server = ZMQCommandServer(
            port=command_port,
            handler=self._handle_command
        )
        self.telemetry_pub = ZMQTelemetryPublisher(port=telemetry_port)

        # Registry
        self.registry = ServiceRegistry()
        self.heartbeat_thread: Optional[threading.Thread] = None
        self.heartbeat_interval = 5.0

        # Shutdown handling
        signal.signal(signal.SIGTERM, self._signal_handler)
        signal.signal(signal.SIGINT, self._signal_handler)

    def start(self):
        """Start worker (called by main)."""
        logger.info(f"Starting worker: {self.name} (PID {self.pid})")

        # Start ZMQ sockets
        self.command_server.start()
        self.telemetry_pub.start()

        # Register in service registry
        self.registry.register_service(
            name=self.name,
            pid=self.pid,
            command_port=self.command_port,
            telemetry_port=self.telemetry_port,
            metadata=self.get_metadata()
        )

        # Start heartbeat
        self.running = True
        self.heartbeat_thread = threading.Thread(
            target=self._heartbeat_loop,
            daemon=True
        )
        self.heartbeat_thread.start()

        # Call subclass initialization
        try:
            self.on_start()
        except Exception as e:
            logger.exception(f"on_start() failed: {e}")
            self.stop()
            raise

        # Enter main loop
        try:
            logger.info(f"Worker {self.name} entering main loop")
            self.run()
        except KeyboardInterrupt:
            logger.info("Received interrupt")
        except Exception as e:
            logger.exception(f"Worker error: {e}")
        finally:
            self.stop()

    def stop(self):
        """Stop worker gracefully."""
        if not self.running:
            return

        logger.info(f"Stopping worker: {self.name}")
        self.running = False

        # Call subclass cleanup
        try:
            self.on_stop()
        except Exception as e:
            logger.exception(f"on_stop() failed: {e}")

        # Unregister from registry
        try:
            self.registry.unregister_service(self.name)
        except Exception as e:
            logger.error(f"Failed to unregister: {e}")

        # Stop ZMQ
        self.command_server.stop()
        self.telemetry_pub.stop()

        logger.info(f"Worker stopped: {self.name}")

    def _heartbeat_loop(self):
        """Update registry heartbeat periodically."""
        while self.running:
            try:
                self.registry.update_heartbeat(
                    name=self.name,
                    metadata=self.get_metadata()
                )
            except Exception as e:
                logger.error(f"Heartbeat failed: {e}")

            time.sleep(self.heartbeat_interval)

    def _handle_command(self, cmd: CommandMessage) -> ResponseMessage:
        """
        Handle incoming command (runs in command server thread).

        Built-in commands: health_check, get_state, set_config, restart, shutdown
        Subclasses can override handle_command() for custom commands.
        """
        try:
            # Built-in commands
            if cmd.command == CommandType.HEALTH_CHECK:
                return ResponseMessage(
                    id=cmd.id,
                    source=self.name,
                    status=ResponseStatus.OK,
                    result={"alive": True, "uptime": time.time() - self.started_at}
                )

            elif cmd.command == CommandType.GET_STATE:
                state = self.get_state()
                return ResponseMessage(
                    id=cmd.id,
                    source=self.name,
                    status=ResponseStatus.OK,
                    result=state.model_dump()
                )

            elif cmd.command == CommandType.SET_CONFIG:
                new_config = cmd.payload.get("config", {})
                self.config.update(new_config)
                restart_required = self.on_config_change(new_config)
                return ResponseMessage(
                    id=cmd.id,
                    source=self.name,
                    status=ResponseStatus.OK,
                    result={"restart_required": restart_required}
                )

            elif cmd.command == CommandType.RESTART:
                # Subclass handles restart logic
                self.on_restart()
                return ResponseMessage(
                    id=cmd.id,
                    source=self.name,
                    status=ResponseStatus.OK,
                    result={"restarted": True}
                )

            elif cmd.command == CommandType.SHUTDOWN:
                # Graceful shutdown
                def delayed_stop():
                    time.sleep(0.5)  # Give time to send response
                    self.stop()

                threading.Thread(target=delayed_stop, daemon=True).start()

                return ResponseMessage(
                    id=cmd.id,
                    source=self.name,
                    status=ResponseStatus.OK,
                    result={"shutting_down": True}
                )

            else:
                # Delegate to subclass
                return self.handle_command(cmd)

        except Exception as e:
            logger.exception(f"Command handler error: {e}")
            return ResponseMessage(
                id=cmd.id,
                source=self.name,
                status=ResponseStatus.ERROR,
                error=str(e)
            )

    def publish_telemetry(self, topic: str, payload: Dict[str, Any]):
        """
        Publish telemetry message (call from subclass).

        Args:
            topic: Topic string (e.g., "audio.features")
            payload: Data dict
        """
        msg = TelemetryMessage(
            source=self.name,
            topic=topic,
            payload=payload
        )
        self.telemetry_pub.publish(msg)

    def _signal_handler(self, signum, frame):
        """Handle SIGTERM/SIGINT."""
        logger.info(f"Received signal {signum}")
        self.stop()

    # =========================================================================
    # Abstract methods - subclasses must implement
    # =========================================================================

    @abstractmethod
    def run(self):
        """
        Main worker loop (blocking).

        Should check self.running periodically and exit when False.
        """
        pass

    @abstractmethod
    def get_state(self) -> WorkerStatePayload:
        """Return current worker state (for get_state command)."""
        pass

    @abstractmethod
    def get_metadata(self) -> Dict[str, Any]:
        """Return metadata for registry (e.g., device name, config summary)."""
        pass

    # =========================================================================
    # Optional hooks - subclasses can override
    # =========================================================================

    def on_start(self):
        """Called after ZMQ/registry setup, before run()."""
        pass

    def on_stop(self):
        """Called before ZMQ/registry cleanup."""
        pass

    def on_config_change(self, new_config: Dict[str, Any]) -> bool:
        """
        Called when set_config command received.

        Args:
            new_config: New configuration dict

        Returns:
            True if restart required, False otherwise
        """
        return False

    def on_restart(self):
        """Called when restart command received."""
        pass

    def handle_command(self, cmd: CommandMessage) -> ResponseMessage:
        """
        Handle custom commands (override in subclass).

        Default: return error.

        Args:
            cmd: CommandMessage

        Returns:
            ResponseMessage
        """
        return ResponseMessage(
            id=cmd.id,
            source=self.name,
            status=ResponseStatus.ERROR,
            error=f"Unknown command: {cmd.command}"
        )
