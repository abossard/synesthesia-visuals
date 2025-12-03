"""
ZeroMQ transport layer for VJ Bus.

Provides wrappers for:
- Command server (REP socket)
- Telemetry publisher (PUB socket)
- Command client (REQ socket)
- Telemetry subscriber (SUB socket)

All messages are JSON-encoded Pydantic models.
"""

import zmq
import json
import logging
import threading
from typing import Callable, Optional, Dict, Any, List
from .messages import CommandMessage, ResponseMessage, TelemetryMessage

logger = logging.getLogger('vj_bus.transport')


class ZMQCommandServer:
    """
    ZMQ REP socket server for handling commands.

    Runs in a background thread, calls handler for each request.
    """

    def __init__(self, port: int, handler: Callable[[CommandMessage], ResponseMessage]):
        """
        Initialize command server.

        Args:
            port: Port to bind to
            handler: Function to handle commands (receives CommandMessage, returns ResponseMessage)
        """
        self.port = port
        self.handler = handler

        self.context = zmq.Context()
        self.socket: Optional[zmq.Socket] = None
        self.thread: Optional[threading.Thread] = None
        self.running = False

    def start(self):
        """Start the command server thread."""
        if self.running:
            logger.warning("Command server already running")
            return

        self.socket = self.context.socket(zmq.REP)
        self.socket.bind(f"tcp://127.0.0.1:{self.port}")
        self.running = True

        self.thread = threading.Thread(target=self._run_loop, daemon=True)
        self.thread.start()

        logger.info(f"Command server started on port {self.port}")

    def stop(self):
        """Stop the command server."""
        if not self.running:
            return

        self.running = False

        if self.socket:
            self.socket.close()

        if self.thread:
            self.thread.join(timeout=2.0)

        logger.info("Command server stopped")

    def _run_loop(self):
        """Main server loop (runs in thread)."""
        while self.running:
            try:
                # Wait for request (with timeout to check running flag)
                if not self.socket.poll(timeout=500):  # 500ms
                    continue

                # Receive request
                raw_msg = self.socket.recv_string()

                # Parse command
                try:
                    msg_dict = json.loads(raw_msg)
                    cmd = CommandMessage(**msg_dict)
                except Exception as e:
                    logger.error(f"Failed to parse command: {e}")
                    # Send error response
                    error_response = ResponseMessage(
                        status="error",
                        error=f"Invalid command format: {e}"
                    )
                    self.socket.send_string(error_response.model_dump_json())
                    continue

                # Handle command
                try:
                    response = self.handler(cmd)
                except Exception as e:
                    logger.exception(f"Command handler error: {e}")
                    response = ResponseMessage(
                        id=cmd.id,
                        status="error",
                        error=str(e)
                    )

                # Send response
                self.socket.send_string(response.model_dump_json())

            except zmq.ZMQError as e:
                if not self.running:
                    break
                logger.error(f"ZMQ error in command server: {e}")
            except Exception as e:
                logger.exception(f"Unexpected error in command server: {e}")


class ZMQTelemetryPublisher:
    """
    ZMQ PUB socket for publishing telemetry.

    Thread-safe, non-blocking publishing.
    """

    def __init__(self, port: int):
        """
        Initialize telemetry publisher.

        Args:
            port: Port to bind to
        """
        self.port = port

        self.context = zmq.Context()
        self.socket: Optional[zmq.Socket] = None

    def start(self):
        """Start the publisher."""
        if self.socket:
            logger.warning("Telemetry publisher already started")
            return

        self.socket = self.context.socket(zmq.PUB)
        self.socket.bind(f"tcp://127.0.0.1:{self.port}")

        logger.info(f"Telemetry publisher started on port {self.port}")

    def stop(self):
        """Stop the publisher."""
        if self.socket:
            self.socket.close()
            self.socket = None

        logger.info("Telemetry publisher stopped")

    def publish(self, msg: TelemetryMessage):
        """
        Publish a telemetry message.

        Args:
            msg: TelemetryMessage to publish
        """
        if not self.socket:
            logger.warning("Cannot publish: socket not started")
            return

        try:
            # Send with topic prefix for filtering
            topic = msg.topic
            payload = msg.model_dump_json()

            # ZMQ topic filtering: send "topic payload"
            self.socket.send_string(f"{topic} {payload}")

        except zmq.ZMQError as e:
            logger.error(f"Failed to publish telemetry: {e}")


class ZMQCommandClient:
    """
    ZMQ REQ socket client for sending commands.

    Used by TUI to send commands to workers.
    """

    def __init__(self, host: str = "127.0.0.1", port: int = 5001, timeout_ms: int = 2000):
        """
        Initialize command client.

        Args:
            host: Host to connect to
            port: Port to connect to
            timeout_ms: Request timeout in milliseconds
        """
        self.host = host
        self.port = port
        self.timeout_ms = timeout_ms

        self.context = zmq.Context()
        self.socket: Optional[zmq.Socket] = None

    def connect(self):
        """Connect to the command server."""
        if self.socket:
            self.socket.close()

        self.socket = self.context.socket(zmq.REQ)
        self.socket.setsockopt(zmq.RCVTIMEO, self.timeout_ms)
        self.socket.setsockopt(zmq.SNDTIMEO, self.timeout_ms)
        self.socket.setsockopt(zmq.LINGER, 0)  # Don't wait on close

        self.socket.connect(f"tcp://{self.host}:{self.port}")

        logger.debug(f"Connected to command server at {self.host}:{self.port}")

    def disconnect(self):
        """Disconnect from the server."""
        if self.socket:
            self.socket.close()
            self.socket = None

    def send_command(self, cmd: CommandMessage) -> ResponseMessage:
        """
        Send a command and wait for response.

        Args:
            cmd: CommandMessage to send

        Returns:
            ResponseMessage from server

        Raises:
            TimeoutError: If request times out
            ConnectionError: If connection fails
        """
        if not self.socket:
            self.connect()

        try:
            # Send command
            self.socket.send_string(cmd.model_dump_json())

            # Wait for response
            raw_response = self.socket.recv_string()

            # Parse response
            response_dict = json.loads(raw_response)
            response = ResponseMessage(**response_dict)

            return response

        except zmq.Again:
            # Timeout
            logger.error(f"Command timeout after {self.timeout_ms}ms")
            # Need new socket after timeout
            self.disconnect()
            raise TimeoutError(f"Command timeout after {self.timeout_ms}ms")

        except zmq.ZMQError as e:
            logger.error(f"ZMQ error sending command: {e}")
            self.disconnect()
            raise ConnectionError(f"ZMQ error: {e}")

        except Exception as e:
            logger.error(f"Failed to send command: {e}")
            self.disconnect()
            raise

    def __enter__(self):
        """Context manager entry."""
        self.connect()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit."""
        self.disconnect()


class ZMQTelemetrySubscriber:
    """
    ZMQ SUB socket for receiving telemetry.

    Runs in a background thread, calls handlers for matching topics.
    """

    def __init__(self, host: str = "127.0.0.1", port: int = 5002):
        """
        Initialize telemetry subscriber.

        Args:
            host: Host to connect to
            port: Port to connect to
        """
        self.host = host
        self.port = port

        self.context = zmq.Context()
        self.socket: Optional[zmq.Socket] = None
        self.thread: Optional[threading.Thread] = None
        self.running = False

        # Topic -> handler mapping
        self.handlers: Dict[str, List[Callable[[TelemetryMessage], None]]] = {}

    def subscribe(self, topic: str, handler: Callable[[TelemetryMessage], None]):
        """
        Subscribe to a topic.

        Args:
            topic: Topic pattern (e.g., "audio.features", "audio.*", "*")
            handler: Function to call for matching messages
        """
        if topic not in self.handlers:
            self.handlers[topic] = []

        self.handlers[topic].append(handler)

        # Update ZMQ subscription filter if socket is active
        if self.socket:
            self.socket.setsockopt_string(zmq.SUBSCRIBE, topic.split('.')[0])

        logger.debug(f"Subscribed to topic: {topic}")

    def connect(self):
        """Connect to the telemetry publisher."""
        if self.socket:
            logger.warning("Already connected")
            return

        self.socket = self.context.socket(zmq.SUB)
        self.socket.connect(f"tcp://{self.host}:{self.port}")

        # Subscribe to all registered topics
        for topic in self.handlers.keys():
            self.socket.setsockopt_string(zmq.SUBSCRIBE, topic.split('.')[0])

        logger.info(f"Connected to telemetry publisher at {self.host}:{self.port}")

    def start(self):
        """Start the subscriber thread."""
        if self.running:
            logger.warning("Subscriber already running")
            return

        self.connect()
        self.running = True

        self.thread = threading.Thread(target=self._run_loop, daemon=True)
        self.thread.start()

        logger.info("Telemetry subscriber started")

    def stop(self):
        """Stop the subscriber."""
        if not self.running:
            return

        self.running = False

        if self.socket:
            self.socket.close()
            self.socket = None

        if self.thread:
            self.thread.join(timeout=2.0)

        logger.info("Telemetry subscriber stopped")

    def _run_loop(self):
        """Main subscriber loop (runs in thread)."""
        while self.running:
            try:
                # Wait for message (with timeout to check running flag)
                if not self.socket.poll(timeout=500):  # 500ms
                    continue

                # Receive message
                raw_msg = self.socket.recv_string()

                # Parse: "topic payload"
                parts = raw_msg.split(' ', 1)
                if len(parts) != 2:
                    logger.warning(f"Invalid telemetry format: {raw_msg[:100]}")
                    continue

                topic, payload_str = parts

                # Parse message
                try:
                    msg_dict = json.loads(payload_str)
                    msg = TelemetryMessage(**msg_dict)
                except Exception as e:
                    logger.error(f"Failed to parse telemetry: {e}")
                    continue

                # Call matching handlers
                for pattern, handlers in self.handlers.items():
                    if self._topic_matches(topic, pattern):
                        for handler in handlers:
                            try:
                                handler(msg)
                            except Exception as e:
                                logger.exception(f"Handler error for {topic}: {e}")

            except zmq.ZMQError as e:
                if not self.running:
                    break
                logger.error(f"ZMQ error in subscriber: {e}")
            except Exception as e:
                logger.exception(f"Unexpected error in subscriber: {e}")

    def _topic_matches(self, topic: str, pattern: str) -> bool:
        """
        Check if topic matches pattern.

        Patterns:
        - "audio.features" matches exactly "audio.features"
        - "audio.*" matches "audio.features", "audio.stats", etc.
        - "*" matches everything
        """
        if pattern == "*":
            return True

        if pattern.endswith(".*"):
            prefix = pattern[:-2]
            return topic.startswith(prefix + ".")

        return topic == pattern
