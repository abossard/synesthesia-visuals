"""
Synchronous OSC Client

Simple sync OSC client for applications that don't need async.
For async applications, use osc_client.OscClient instead.
"""

import logging
import threading
import time
from typing import Optional, Callable, List, Any

from .model import OscCommand, OscEvent
from .synesthesia_config import enrich_event

try:
    from pythonosc import dispatcher, udp_client, osc_server
    OSC_AVAILABLE = True
except ImportError:
    OSC_AVAILABLE = False
    dispatcher = None  # type: ignore
    udp_client = None  # type: ignore
    osc_server = None  # type: ignore

logger = logging.getLogger(__name__)


class SyncOscClient:
    """
    Synchronous OSC client for bidirectional communication.
    
    Uses threading for the receive server instead of asyncio.
    Simpler to use in non-async applications.
    
    Example:
        osc = SyncOscClient(send_port=7777, receive_port=9999)
        osc.add_callback(my_handler)
        osc.start()
        osc.send(OscCommand("/test", [1.0]))
        osc.stop()
    """
    
    def __init__(
        self,
        host: str = "127.0.0.1",
        send_port: int = 7777,
        receive_port: int = 9999,
    ):
        self.host = host
        self.send_port = send_port
        self.receive_port = receive_port
        
        self._client: Any = None
        self._server: Any = None
        self._server_thread: Optional[threading.Thread] = None
        self._callbacks: List[Callable[[OscEvent], None]] = []
        self._running = False
    
    def start(self) -> bool:
        """
        Start OSC client and server.
        
        Returns:
            True if started successfully
        """
        if not OSC_AVAILABLE:
            logger.warning("python-osc not available - install with: pip install python-osc")
            return False
        
        try:
            # Create UDP client for sending
            self._client = udp_client.SimpleUDPClient(self.host, self.send_port)
            
            # Create dispatcher for receiving
            disp = dispatcher.Dispatcher()
            disp.set_default_handler(self._handle_message)
            
            # Create threaded server
            self._server = osc_server.ThreadingOSCUDPServer(
                (self.host, self.receive_port),
                disp
            )
            
            # Start server in background thread
            self._running = True
            self._server_thread = threading.Thread(
                target=self._server.serve_forever,
                daemon=True
            )
            self._server_thread.start()
            
            logger.info(f"OSC started: send={self.send_port}, receive={self.receive_port}")
            return True
            
        except Exception as e:
            logger.error(f"OSC start failed: {e}")
            return False
    
    def add_callback(self, callback: Callable[[OscEvent], None]):
        """Add OSC message callback."""
        if callback not in self._callbacks:
            self._callbacks.append(callback)
    
    def _handle_message(self, address: str, *args):
        """Handle incoming OSC message."""
        event = enrich_event(address, list(args), time.time())
        
        for callback in self._callbacks:
            try:
                callback(event)
            except Exception as e:
                logger.error(f"Callback error: {e}")
    
    def send(self, command: OscCommand):
        """Send OSC message."""
        if not self._client:
            logger.debug("OSC not connected, cannot send")
            return
        
        try:
            self._client.send_message(command.address, command.args)
            logger.debug(f"OSC sent: {command}")
        except Exception as e:
            logger.error(f"OSC send failed: {e}")
    
    def stop(self):
        """Stop OSC server and client."""
        self._running = False
        
        if self._server:
            self._server.shutdown()
            self._server = None
        
        self._client = None
        logger.info("OSC stopped")
    
    def is_running(self) -> bool:
        """Check if OSC is running."""
        return self._running and self._client is not None
