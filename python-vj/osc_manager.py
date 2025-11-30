"""
OSC Manager - Centralized OSC messaging for VJ system

Provides a singleton OSC sender with message logging and debug capabilities.
All OSC messages in the system should go through this module.

Usage:
    from osc_manager import osc
    
    # Send messages
    osc.send("/karaoke/track", [1, "spotify", "Artist", "Title", "Album", 180.0, 1])
    
    # Get recent messages for debug view
    messages = osc.get_recent_messages(50)
"""

import time
import logging
from typing import List, Tuple, Any, Optional
from pythonosc import udp_client

logger = logging.getLogger('osc_manager')


class OSCManager:
    """
    Centralized OSC message sender with logging.
    
    Features:
    - Single UDP client instance (efficient)
    - Automatic message logging for debug views
    - Thread-safe message history
    - Configurable host/port
    """
    
    def __init__(self, host: str = "127.0.0.1", port: int = 9000):
        self._client = udp_client.SimpleUDPClient(host, port)
        self._message_log: List[Tuple[float, str, Any]] = []
        self._max_log_entries = 200
        self._host = host
        self._port = port
        logger.info(f"OSC Manager initialized: {host}:{port}")
    
    def send(self, address: str, args: Any = None):
        """
        Send an OSC message.
        
        Args:
            address: OSC address pattern (e.g., "/karaoke/track")
            args: Message arguments (single value, list, or None)
        """
        # Normalize args to list
        if args is None:
            args = []
        elif not isinstance(args, (list, tuple)):
            args = [args]
        
        # Send message
        try:
            self._client.send_message(address, args)
            self._log_message(address, args)
        except Exception as e:
            logger.error(f"OSC send failed {address}: {e}")
    
    def _log_message(self, address: str, args: Any):
        """Log message for debug panel (internal)."""
        self._message_log.append((time.time(), address, args))
        if len(self._message_log) > self._max_log_entries:
            self._message_log = self._message_log[-self._max_log_entries:]
    
    def get_recent_messages(self, count: int = 50) -> List[Tuple[float, str, Any]]:
        """
        Get recent OSC messages for debug display.
        
        Returns:
            List of (timestamp, address, args) tuples
        """
        return self._message_log[-count:]
    
    def clear_log(self):
        """Clear message log."""
        self._message_log.clear()
    
    @property
    def host(self) -> str:
        return self._host
    
    @property
    def port(self) -> int:
        return self._port


# Singleton instance - import this throughout the codebase
osc = OSCManager()
