"""
OSC Client

Self-contained bidirectional OSC communication.
"""

import asyncio
import logging
import time
from dataclasses import dataclass
from typing import Optional, Callable, List, Any

from .model import OscCommand, OscEvent
from .osc_categories import enrich_event

try:
    from pythonosc import dispatcher, udp_client
    from pythonosc.osc_server import AsyncIOOSCUDPServer
    OSC_AVAILABLE = True
except ImportError:
    OSC_AVAILABLE = False
    dispatcher = None
    udp_client = None
    AsyncIOOSCUDPServer = None

logger = logging.getLogger(__name__)


@dataclass
class OscConfig:
    """OSC configuration."""
    host: str = "127.0.0.1"
    send_port: int = 7777
    receive_port: int = 9999


class OscClient:
    """Async OSC client for bidirectional communication."""
    
    def __init__(self, config: Optional[OscConfig] = None):
        self.config = config or OscConfig()
        self._client: Any = None
        self._server: Any = None
        self._dispatcher: Any = None
        self._callbacks: List[Callable[[OscEvent], None]] = []
        self._connected = False
    
    async def connect(self) -> bool:
        """Connect OSC client and server."""
        if not OSC_AVAILABLE:
            logger.warning("python-osc not available")
            return False
        
        try:
            # UDP client for sending
            self._client = udp_client.SimpleUDPClient(
                self.config.host,
                self.config.send_port
            )
            
            # Dispatcher for receiving
            self._dispatcher = dispatcher.Dispatcher()
            self._dispatcher.set_default_handler(self._handle_message)
            
            # Async server
            self._server = AsyncIOOSCUDPServer(
                (self.config.host, self.config.receive_port),
                self._dispatcher,
                asyncio.get_event_loop()
            )
            
            await self._server.create_serve_endpoint()
            
            self._connected = True
            logger.info(f"OSC: send={self.config.send_port}, recv={self.config.receive_port}")
            return True
            
        except Exception as e:
            logger.error(f"OSC connect failed: {e}")
            return False
    
    def add_callback(self, callback: Callable[[OscEvent], None]):
        """Add OSC message callback."""
        if callback not in self._callbacks:
            self._callbacks.append(callback)
    
    def _handle_message(self, address: str, *args):
        """Handle incoming OSC message."""
        event = enrich_event(address, list(args), time.time())
        
        # Format args for logging
        args_str = " ".join(str(a) for a in args) if args else "(no args)"
        logger.info(f"OSC RX: {address} {args_str} [priority={event.priority}]")
        
        for callback in self._callbacks:
            try:
                callback(event)
            except Exception as e:
                logger.error(f"Callback error: {e}")
    
    def send(self, command: OscCommand):
        """Send OSC message."""
        if not self._connected or not self._client:
            return
        
        try:
            args_str = " ".join(str(a) for a in command.args) if command.args else "(no args)"
            logger.info(f"OSC TX: {command.address} {args_str}")
            self._client.send_message(command.address, command.args)
        except Exception as e:
            logger.error(f"OSC send failed: {e}")
    
    async def stop(self):
        """Stop OSC."""
        self._server = None
        self._client = None
        self._connected = False
        logger.info("OSC disconnected")
    
    def is_connected(self) -> bool:
        """Check connection status."""
        return self._connected
