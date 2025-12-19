"""
OSC Hub - Centralized OSC routing for VJ system

Architecture:
- Single receive port: 9999 (all incoming OSC from VirtualDJ, Synesthesia, etc.)
- Forwards all received messages to:
  - Port 10000: VJUniverse (Processing)
  - Port 11111: Magic Music Visual
- Send-only channels for outgoing messages:
  - vdj: VirtualDJ (port 9009)
  - synesthesia: Synesthesia (port 7777)
  - karaoke: VJUniverse (port 10000)
"""

import atexit
import logging
import threading
from dataclasses import dataclass
from typing import Any, Callable, Dict, List, Optional, Tuple

import pyliblo3 as liblo

logger = logging.getLogger(__name__)

Handler = Callable[[str, List[Any]], None]

# Central receive port for all incoming OSC
RECEIVE_PORT = 9999

# Forward targets - all received messages are sent to these ports
FORWARD_TARGETS: List[Tuple[str, int]] = [
    ("127.0.0.1", 10000),  # VJUniverse (Processing)
    ("127.0.0.1", 11111),  # Magic Music Visual
]


@dataclass(frozen=True)
class ChannelConfig:
    """Configuration for an OSC channel (send only; recv_port is shared hub port)."""
    name: str
    host: str
    send_port: int
    recv_port: Optional[int] = None


# Channel configurations (send only; recv_port mirrors shared hub port)
VDJ = ChannelConfig("vdj", "127.0.0.1", 9009, RECEIVE_PORT)
SYNESTHESIA = ChannelConfig("synesthesia", "127.0.0.1", 7777, RECEIVE_PORT)
KARAOKE = ChannelConfig("karaoke", "127.0.0.1", 10000, None)


class Channel:
    """
    Single OSC channel for sending messages only.

    Note: Receiving is handled centrally by OSCHub on port 9999.
    """

    def __init__(self, config: ChannelConfig):
        self._config = config
        self._target: Optional[liblo.Address] = None

    @property
    def name(self) -> str:
        return self._config.name

    @property
    def send_port(self) -> int:
        return self._config.send_port

    @property
    def recv_port(self) -> Optional[int]:
        return self._config.recv_port

    def start(self) -> bool:
        """Start the channel. Returns True on success."""
        try:
            self._target = liblo.Address(self._config.host, self._config.send_port)
            logger.info(f"[{self.name}] → {self._config.host}:{self._config.send_port}")
            return True
        except liblo.ServerError as exc:
            logger.error(f"[{self.name}] Start failed: {exc}")
            return False

    def stop(self):
        """Stop the channel."""
        self._target = None
        logger.info(f"[{self.name}] Stopped")

    def send(self, address: str, *args) -> bool:
        """Send OSC message. Returns True on success."""
        if not self._target:
            return False
        try:
            liblo.send(self._target, address, *args)
            return True
        except Exception as exc:
            logger.error(f"[{self.name}] Send error: {exc}")
            return False


class OSCHub:
    """
    Central OSC hub managing a single receiver and forwarding.

    - Receives on port 9999
    - Forwards every message to 10000 and 11111
    - Exposes send-only channels for vdj, synesthesia, karaoke
    """

    def __init__(self):
        self._vdj = Channel(VDJ)
        self._synesthesia = Channel(SYNESTHESIA)
        self._karaoke = Channel(KARAOKE)
        self._started = False
        self._atexit_registered = False

        self._server: Optional[liblo.ServerThread] = None
        self._server_lock = threading.Lock()

        self._forward_targets: List[liblo.Address] = [
            liblo.Address(host, port) for host, port in FORWARD_TARGETS
        ]

        self._listeners: Dict[str, List[Handler]] = {}
        self._listeners_lock = threading.Lock()

    @property
    def is_started(self) -> bool:
        return self._started

    @property
    def receive_port(self) -> int:
        return RECEIVE_PORT

    @property
    def vdj(self) -> Channel:
        return self._vdj

    @property
    def synesthesia(self) -> Channel:
        return self._synesthesia

    @property
    def karaoke(self) -> Channel:
        return self._karaoke

    @property
    def processing(self) -> Channel:
        """Alias for karaoke (VJUniverse port 10000)."""
        return self._karaoke

    def get_channel_status(self) -> Dict[str, Dict[str, Any]]:
        """Get status of all channels."""
        return {
            "vdj": {
                "name": "VirtualDJ",
                "send_port": VDJ.send_port,
                "recv_port": RECEIVE_PORT,
                "active": self._vdj._target is not None,
            },
            "synesthesia": {
                "name": "Synesthesia",
                "send_port": SYNESTHESIA.send_port,
                "recv_port": RECEIVE_PORT,
                "active": self._synesthesia._target is not None,
            },
            "karaoke": {
                "name": "Karaoke/Processing",
                "send_port": KARAOKE.send_port,
                "recv_port": None,
                "active": self._karaoke._target is not None,
            },
        }

    def start(self) -> bool:
        """Start OSC hub (receiver + send channels)."""
        if self._started:
            return True

        try:
            with self._server_lock:
                self._server = liblo.ServerThread(RECEIVE_PORT)
                self._server.add_method(None, None, self._on_message)
                self._server.start()
        except liblo.ServerError as exc:
            logger.error(f"OSCHub start failed: {exc}")
            self._server = None
            return False

        self._vdj.start()
        self._synesthesia.start()
        self._karaoke.start()

        self._started = True
        if not self._atexit_registered:
            atexit.register(self.stop)
            self._atexit_registered = True
        logger.info("OSCHub ready")
        return True

    def stop(self):
        """Stop OSC hub."""
        if not self._started:
            return

        logger.info("OSCHub stopping...")
        self._vdj.stop()
        self._synesthesia.stop()
        self._karaoke.stop()

        with self._server_lock:
            if self._server:
                try:
                    self._server.stop()
                except Exception as exc:
                    logger.error(f"OSCHub stop error: {exc}")
                self._server = None

        self._started = False
        logger.info("OSCHub stopped")

    def start_channel(self, channel_name: str) -> bool:
        """Start a specific OSC channel by name."""
        self.start()
        channel_map = {
            "vdj": self._vdj,
            "synesthesia": self._synesthesia,
            "karaoke": self._karaoke,
        }
        channel = channel_map.get(channel_name)
        return channel.start() if channel else False

    def stop_channel(self, channel_name: str):
        """Stop a specific OSC channel by name."""
        channel_map = {
            "vdj": self._vdj,
            "synesthesia": self._synesthesia,
            "karaoke": self._karaoke,
        }
        channel = channel_map.get(channel_name)
        if channel:
            channel.stop()

    def subscribe(self, path: str, handler: Handler) -> None:
        """Subscribe a handler to incoming OSC messages."""
        if not self._started:
            self.start()
        with self._listeners_lock:
            handlers = self._listeners.setdefault(path, [])
            if handler not in handlers:
                handlers.append(handler)

    def unsubscribe(self, path: str, handler: Handler) -> None:
        """Unsubscribe a handler from incoming OSC messages."""
        with self._listeners_lock:
            handlers = self._listeners.get(path, [])
            if handler in handlers:
                handlers.remove(handler)
                if not handlers:
                    del self._listeners[path]

    def _on_message(self, path: str, args: list, _types: Any, _src: Any):
        """Internal OSC callback: forward + dispatch to subscribers."""
        args_list = list(args)
        self._forward(path, args_list)
        self._dispatch(path, args_list)

    def _forward(self, path: str, args: List[Any]) -> None:
        """Forward a message to all configured targets."""
        for target in self._forward_targets:
            try:
                liblo.send(target, path, *args)
            except Exception as exc:
                logger.error(f"Forward error to {target}: {exc}")

    def _dispatch(self, path: str, args: List[Any]) -> None:
        """Dispatch message to subscribed handlers."""
        with self._listeners_lock:
            listeners = list(self._listeners.items())

        for pattern, handlers in listeners:
            if self._matches(pattern, path):
                for handler in list(handlers):
                    try:
                        handler(path, args)
                    except Exception as exc:
                        logger.error(f"OSC handler error for {pattern}: {exc}")

    @staticmethod
    def _matches(pattern: str, path: str) -> bool:
        if pattern in (None, "", "/", "*"):
            return True
        if pattern.endswith("*"):
            return path.startswith(pattern[:-1])
        return path == pattern


# Global singleton instance
osc = OSCHub()
