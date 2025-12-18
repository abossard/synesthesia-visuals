"""
OSC Hub - Typed OSC channels for VJ system

Provides typed access to OSC channels:
- vdj: VirtualDJ (send 9009, recv 9008)
- synesthesia: Synesthesia (send 7777, recv 9999)
- karaoke: Processing/Karaoke overlay (send 9000, no recv)
"""

import atexit
import logging
import threading
import time
from dataclasses import dataclass
from typing import Any, Callable, Dict, List, Optional

import pyliblo3 as liblo

logger = logging.getLogger(__name__)

Handler = Callable[[str, List[Any]], None]


@dataclass(frozen=True)
class ChannelConfig:
    """Configuration for an OSC channel."""
    name: str
    host: str
    send_port: int
    recv_port: Optional[int] = None


# Default channel configurations
VDJ = ChannelConfig("vdj", "127.0.0.1", 9009, 9008)
SYNESTHESIA = ChannelConfig("synesthesia", "127.0.0.1", 7777, 9999)
KARAOKE = ChannelConfig("karaoke", "127.0.0.1", 9000, None)


class Channel:
    """
    Single OSC channel with send/receive capabilities.

    Supports:
    - Sending messages to a target
    - Subscribing to incoming messages
    - Query-response pattern with timeout
    """

    def __init__(self, config: ChannelConfig):
        self._config = config
        self._target: Optional[liblo.Address] = None
        self._server: Optional[liblo.ServerThread] = None
        self._handlers: Dict[str, List[Handler]] = {}
        self._query_results: Dict[str, List[Any]] = {}
        self._query_events: Dict[str, threading.Event] = {}
        self._stopping = False

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

            if self._config.recv_port:
                self._server = liblo.ServerThread(self._config.recv_port)
                self._server.add_method(None, None, self._dispatch)
                self._server.start()
                logger.info(f"[{self.name}] ← port {self._config.recv_port}")
            return True
        except liblo.ServerError as e:
            logger.error(f"[{self.name}] Start failed: {e}")
            return False

    def stop(self):
        """Stop the channel."""
        self._stopping = True
        if self._server:
            try:
                self._server.del_method(None, None)
            except Exception:
                pass
            time.sleep(0.1)
            try:
                self._server.stop()
            except Exception:
                pass
            self._server = None
        self._target = None
        self._stopping = False
        logger.info(f"[{self.name}] Stopped")

    def send(self, address: str, *args) -> bool:
        """Send OSC message. Returns True on success."""
        if not self._target:
            return False
        try:
            liblo.send(self._target, address, *args)
            return True
        except Exception as e:
            logger.error(f"[{self.name}] Send error: {e}")
            return False

    def subscribe(self, address: str, handler: Handler):
        """Subscribe to messages matching address. Use "/" for catch-all."""
        self._handlers.setdefault(address, []).append(handler)

    def unsubscribe(self, address: str, handler: Optional[Handler] = None):
        """Unsubscribe from address. If handler is None, removes all."""
        if address not in self._handlers:
            return
        if handler is None:
            del self._handlers[address]
        else:
            self._handlers[address] = [h for h in self._handlers[address] if h != handler]

    def query(self, address: str, *args, timeout: float = 1.0) -> Optional[List[Any]]:
        """Send message and wait for response. Returns None on timeout."""
        if not self._config.recv_port:
            return None

        event = threading.Event()
        self._query_events[address] = event
        self._query_results[address] = []

        try:
            self.send(address, *args)
            if event.wait(timeout):
                return self._query_results.get(address)
            return None
        finally:
            self._query_events.pop(address, None)
            self._query_results.pop(address, None)

    def _dispatch(self, path: str, args: List[Any], types: str, src: liblo.Address):
        """Internal: dispatch incoming messages to handlers."""
        if self._stopping:
            return

        # Check for pending query first
        if path in self._query_events:
            self._query_results[path] = list(args)
            self._query_events[path].set()
            return

        # Dispatch to exact match handlers
        handlers = self._handlers.get(path)
        if handlers:
            for handler in handlers:
                try:
                    handler(path, args)
                except Exception as e:
                    logger.error(f"Handler error: {e}")

        # Also dispatch to catch-all "/" handlers
        if path != "/" and "/" in self._handlers:
            for handler in self._handlers["/"]:
                try:
                    handler(path, args)
                except Exception as e:
                    logger.error(f"Catch-all handler error: {e}")


class OSCHub:
    """
    Central OSC hub managing typed channels for VJ system.

    Channels:
        - vdj: VirtualDJ OSC (send 9009, recv 9008)
        - synesthesia: Synesthesia OSC (send 7777, recv 9999)
        - karaoke: Karaoke/Processing OSC (send 9000, no recv)
    """

    def __init__(self):
        self._vdj = Channel(VDJ)
        self._synesthesia = Channel(SYNESTHESIA)
        self._karaoke = Channel(KARAOKE)
        self._started = False

    @property
    def is_started(self) -> bool:
        return self._started

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
        """Alias for karaoke (same port 9000)."""
        return self._karaoke

    def get_channel_status(self) -> Dict[str, Dict[str, Any]]:
        """Get status of all channels."""
        return {
            "vdj": {
                "name": "VirtualDJ",
                "send_port": VDJ.send_port,
                "recv_port": VDJ.recv_port,
                "active": self._vdj._target is not None,
            },
            "synesthesia": {
                "name": "Synesthesia",
                "send_port": SYNESTHESIA.send_port,
                "recv_port": SYNESTHESIA.recv_port,
                "active": self._synesthesia._target is not None,
            },
            "karaoke": {
                "name": "Karaoke/Processing",
                "send_port": KARAOKE.send_port,
                "recv_port": KARAOKE.recv_port,
                "active": self._karaoke._target is not None,
            },
        }

    def start(self) -> bool:
        """Start all OSC channels."""
        logger.info("OSCHub starting all channels...")
        self._vdj.start()
        self._synesthesia.start()
        self._karaoke.start()
        self._started = True
        atexit.register(self.stop)
        logger.info("OSCHub ready")
        return True

    def stop(self):
        """Stop all OSC channels."""
        logger.info("OSCHub stopping all channels...")
        self._vdj.stop()
        self._synesthesia.stop()
        self._karaoke.stop()
        self._started = False
        logger.info("OSCHub stopped")

    def start_channel(self, channel_name: str) -> bool:
        """Start a specific OSC channel by name."""
        channel_map = {
            "vdj": self._vdj,
            "synesthesia": self._synesthesia,
            "karaoke": self._karaoke,
        }
        channel = channel_map.get(channel_name)
        if channel:
            success = channel.start()
            if any(ch._target is not None for ch in channel_map.values()):
                self._started = True
                atexit.register(self.stop)
            return success
        return False

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
            if all(ch._target is None for ch in channel_map.values()):
                self._started = False


# Global singleton instance
osc = OSCHub()
