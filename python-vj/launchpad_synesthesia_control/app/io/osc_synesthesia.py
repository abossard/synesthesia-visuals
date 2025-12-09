"""
OSC Synesthesia Communication

Handles bidirectional OSC communication with Synesthesia Pro.
Gracefully degrades when Synesthesia is not available.
"""

import asyncio
import logging
from typing import Optional, Callable, Any, List
from dataclasses import dataclass

try:
    from pythonosc import osc_server, dispatcher, udp_client
    from pythonosc.osc_server import AsyncIOOSCUDPServer
    OSC_AVAILABLE = True
except ImportError:
    OSC_AVAILABLE = False
    osc_server = None
    dispatcher = None
    udp_client = None
    AsyncIOOSCUDPServer = None

from ..domain.model import OscCommand, OscEvent

logger = logging.getLogger(__name__)


# =============================================================================
# OSC CONFIGURATION
# =============================================================================

@dataclass
class OscConfig:
    """OSC configuration."""
    host: str = "127.0.0.1"
    send_port: int = 7777  # Synesthesia listens here (default)
    receive_port: int = 9999  # Synesthesia sends here (default)
    

# =============================================================================
# OSC MANAGER
# =============================================================================

class OscManager:
    """
    Async OSC manager for Synesthesia communication.
    
    Gracefully handles connection failures and reconnects automatically.
    """
    
    def __init__(self, config: OscConfig):
        self.config = config
        self._client: Optional[Any] = None
        self._server: Optional[Any] = None
        self._dispatcher: Optional[Any] = None
        self._callback: Optional[Callable[[OscEvent], None]] = None
        self._connected = False
        self._running = False
    
    async def connect(self) -> bool:
        """
        Connect OSC client and server.
        
        Returns:
            True if connected successfully (gracefully fails if OSC unavailable)
        """
        if not OSC_AVAILABLE:
            logger.warning("python-osc not available - OSC disabled")
            logger.warning("Install with: pip install python-osc")
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
            transport, protocol = await self._server.create_serve_endpoint()
            
            self._connected = True
            logger.info(f"OSC connected: send={self.config.send_port}, receive={self.config.receive_port}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to connect OSC: {e}")
            logger.warning("OSC disabled - will retry connection later")
            self._connected = False
            return False
    
    def set_osc_callback(self, callback: Callable[[OscEvent], None]):
        """
        Set callback for incoming OSC messages.
        
        Args:
            callback: Function called with OscEvent on message receive
        """
        self._callback = callback
    
    def _handle_osc_message(self, address: str, *args):
        """Handle incoming OSC message."""
        import time
        
        if self._callback:
            event = OscEvent(
                timestamp=time.time(),
                address=address,
                args=list(args)
            )
            # Call callback in a non-blocking way
            try:
                self._callback(event)
            except Exception as e:
                logger.error(f"Error in OSC callback: {e}")
    
    def send(self, command: OscCommand):
        """
        Send OSC command to Synesthesia (gracefully fails if not connected).
        
        Args:
            command: OSC command to send
        """
        if not self._connected or not self._client:
            logger.debug(f"OSC not connected, cannot send: {command.address}")
            return
        
        try:
            if command.args:
                self._client.send_message(command.address, command.args)
            else:
                self._client.send_message(command.address, [])
            
            logger.debug(f"OSC sent: {command}")
            
        except Exception as e:
            logger.error(f"Failed to send OSC: {e}")
            # Mark as disconnected and will try to reconnect
            self._connected = False
    
    async def reconnect_loop(self, interval: float = 5.0):
        """
        Periodically try to reconnect if disconnected.
        
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
        
        if self._server:
            self._server.server_close()
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
            return "Disconnected - will retry"
