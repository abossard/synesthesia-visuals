"""
Generic OSC Client

Bidirectional OSC communication with configurable ports.
No application-specific logic - pure OSC abstraction.
"""

import asyncio
import logging
import time
from dataclasses import dataclass, field
from typing import Optional, Callable, Any, List, TYPE_CHECKING

if TYPE_CHECKING:
    from .model import OscCommand

try:
    from pythonosc import dispatcher, udp_client
    from pythonosc.osc_server import AsyncIOOSCUDPServer
    OSC_AVAILABLE = True
except ImportError:
    OSC_AVAILABLE = False
    dispatcher = None  # type: Any
    udp_client = None  # type: Any
    AsyncIOOSCUDPServer = None  # type: Any

logger = logging.getLogger(__name__)


# =============================================================================
# OSC EVENT
# =============================================================================

@dataclass(frozen=True)
class OscEvent:
    """
    Received OSC event with timestamp.
    
    Attributes:
        timestamp: Unix timestamp when received
        address: OSC address path
        args: List of arguments
    """
    timestamp: float
    address: str
    args: List[Any] = field(default_factory=list)
    
    def to_command(self) -> "OscCommand":
        """
        Convert to OscCommand (without timestamp).
        
        Useful for transforming received events into sendable commands.
        """
        from .model import OscCommand
        return OscCommand(address=self.address, args=list(self.args))


# =============================================================================
# CONFIGURATION
# =============================================================================

@dataclass
class OscConfig:
    """
    OSC configuration.
    
    Attributes:
        host: IP address to bind/send to
        send_port: Port to send OSC messages to
        receive_port: Port to listen for OSC messages on
    """
    host: str = "127.0.0.1"
    send_port: int = 7777
    receive_port: int = 9999


# =============================================================================
# OSC CLIENT
# =============================================================================

class OscClient:
    """
    Async OSC client for bidirectional communication.
    
    Features:
    - UDP client for sending messages
    - Async server for receiving messages
    - Multi-callback message handling
    - Graceful degradation when python-osc unavailable
    - Auto-reconnection support
    """
    
    def __init__(self, config: Optional[OscConfig] = None):
        self.config = config or OscConfig()
        self._client: Any = None
        self._server: Any = None
        self._dispatcher: Any = None
        self._callbacks: List[Callable[[OscEvent], None]] = []
        self._connected = False
        self._running = False
        self._reconnect_task: Optional[asyncio.Task] = None
        self._reconnect_interval: float = 10.0
    
    async def connect(self) -> bool:
        """
        Connect OSC client and server.
        
        Returns:
            True if connected successfully
        """
        if not OSC_AVAILABLE:
            logger.warning("python-osc not available - install with: pip install python-osc")
            return False
        
        try:
            # Create UDP client for sending
            self._client = udp_client.SimpleUDPClient(
                self.config.host,
                self.config.send_port
            )
            
            # Create dispatcher for receiving
            self._dispatcher = dispatcher.Dispatcher()
            self._dispatcher.set_default_handler(self._handle_osc_message)
            
            # Create async server for receiving
            self._server = AsyncIOOSCUDPServer(
                (self.config.host, self.config.receive_port),
                self._dispatcher,
                asyncio.get_event_loop()
            )
            
            # Start server
            await self._server.create_serve_endpoint()
            
            self._connected = True
            logger.info(f"OSC connected: send={self.config.send_port}, receive={self.config.receive_port}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to connect OSC: {e}")
            self._connected = False
            return False
    
    def add_callback(self, callback: Callable[[OscEvent], None]):
        """
        Add callback for incoming OSC messages.
        
        Multiple callbacks can be registered; all will be called.
        
        Args:
            callback: Function called with OscEvent on message receive
        """
        if callback not in self._callbacks:
            self._callbacks.append(callback)
    
    def remove_callback(self, callback: Callable[[OscEvent], None]):
        """
        Remove a previously registered callback.
        
        Args:
            callback: Function to remove
        """
        if callback in self._callbacks:
            self._callbacks.remove(callback)
    
    def set_callback(self, callback: Callable[[OscEvent], None]):
        """
        Set single callback for incoming OSC messages.
        
        DEPRECATED: Use add_callback() for multi-callback support.
        This replaces all existing callbacks with the single one.
        
        Args:
            callback: Function called with OscEvent on message receive
        """
        self._callbacks = [callback]
    
    def _handle_osc_message(self, address: str, *args):
        """Handle incoming OSC message."""
        if self._callbacks:
            event = OscEvent(
                timestamp=time.time(),
                address=address,
                args=list(args)
            )
            for callback in self._callbacks:
                try:
                    callback(event)
                except Exception as e:
                    logger.error(f"Error in OSC callback: {e}")
    
    def send(self, address: str, args: Optional[List[Any]] = None):
        """
        Send OSC message.
        
        Args:
            address: OSC address path
            args: Optional list of arguments
        """
        if not self._connected or not self._client:
            logger.debug(f"OSC not connected, cannot send: {address}")
            return
        
        try:
            self._client.send_message(address, args or [])
            logger.debug(f"OSC sent: {address} {args}")
        except Exception as e:
            logger.error(f"Failed to send OSC: {e}")
            self._connected = False
    
    def start_auto_reconnect(self, interval: float = 10.0):
        """
        Start auto-reconnection task.
        
        Will periodically check connection and reconnect if needed.
        
        Args:
            interval: Seconds between reconnection attempts (default 10s)
        """
        self._reconnect_interval = interval
        if self._reconnect_task is None or self._reconnect_task.done():
            self._running = True
            self._reconnect_task = asyncio.create_task(self._reconnect_loop())
            logger.info(f"Started OSC auto-reconnect (interval={interval}s)")
    
    def stop_auto_reconnect(self):
        """Stop auto-reconnection task."""
        self._running = False
        if self._reconnect_task:
            self._reconnect_task.cancel()
            self._reconnect_task = None
            logger.info("Stopped OSC auto-reconnect")
    
    async def _reconnect_loop(self):
        """Internal reconnection loop."""
        while self._running:
            if not self._connected:
                logger.info("Attempting to reconnect OSC...")
                await self.connect()
            await asyncio.sleep(self._reconnect_interval)
    
    async def reconnect_loop(self, interval: float = 5.0):
        """
        Periodically try to reconnect if disconnected.
        
        DEPRECATED: Use start_auto_reconnect() instead.
        
        Args:
            interval: Seconds between reconnection attempts
        """
        self._running = True
        
        while self._running:
            if not self._connected:
                logger.info("Attempting to reconnect OSC...")
                await self.connect()
            
            await asyncio.sleep(interval)
    
    async def stop(self):
        """Stop OSC server and client."""
        self._running = False
        self.stop_auto_reconnect()
        
        if self._server:
            self._server = None
        
        self._client = None
        self._connected = False
        logger.info("OSC disconnected")
    
    def is_connected(self) -> bool:
        """Check if OSC is connected."""
        return self._connected
    
    @property
    def status(self) -> str:
        """Get connection status string."""
        if not OSC_AVAILABLE:
            return "OSC library not installed"
        elif self._connected:
            return f"Connected (:{self.config.send_port} → :{self.config.receive_port})"
        else:
            return "Disconnected"
