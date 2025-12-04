"""
OSC Manager - Centralized OSC messaging for VJ system

Optimized for high-throughput audio analysis (60+ fps).
Provides a singleton OSC sender with optional message logging.
All OSC messages in the system should go through this module.

Usage:
    from osc_manager import osc
    
    # Send messages (always fast, logging is async)
    osc.send("/karaoke/track", [1, "spotify", "Artist", "Title", "Album", 180.0, 1])
    
    # Get recent messages for debug view (only when UI needs it)
    messages = osc.get_recent_messages(50)
"""

import time
import logging
import threading
from collections import deque
from typing import List, Tuple, Any, Optional
from pythonosc import udp_client

logger = logging.getLogger('osc_manager')


class OSCManager:
    """
    Centralized OSC message sender with optional logging.
    
    Features:
    - Single UDP client instance (efficient)
    - Non-blocking message send (UDP fire-and-forget)
    - Optional message logging for debug views (disabled by default)
    - Thread-safe message history using deque
    - Configurable host/port
    - Handles 1000+ messages/second without blocking
    """
    
    def __init__(self, host: str = "127.0.0.1", port: int = 9000):
        self._client = udp_client.SimpleUDPClient(host, port)
        self._message_log: deque = deque(maxlen=200)  # Fixed-size, efficient
        self._log_lock = threading.Lock()
        self._logging_enabled = False  # Disabled by default for performance
        self._host = host
        self._port = port
        self._message_count = 0
        logger.info(f"OSC Manager initialized: {host}:{port}")
    
    def send(self, address: str, args: Any = None):
        """
        Send an OSC message (non-blocking, always fast).
        
        Args:
            address: OSC address pattern (e.g., "/karaoke/track")
            args: Message arguments (single value, list, or None)
        """
        # Normalize args to list
        if args is None:
            args = []
        elif not isinstance(args, (list, tuple)):
            args = [args]
        
        # Send message (UDP - fire and forget, no blocking)
        try:
            self._client.send_message(address, args)
            self._message_count += 1
            
            # Log only if enabled (for debug view)
            if self._logging_enabled:
                self._log_message(address, args)
                
        except Exception as e:
            logger.error(f"OSC send failed {address}: {e}")
    
    def _log_message(self, address: str, args: Any):
        """Log message for debug panel (internal, thread-safe)."""
        with self._log_lock:
            # deque with maxlen automatically drops old entries
            self._message_log.append((time.time(), address, args))
    
    def enable_logging(self):
        """Enable message logging (call when OSC debug view is visible)."""
        self._logging_enabled = True
        logger.debug("OSC message logging enabled")
    
    def disable_logging(self):
        """Disable message logging (call when OSC debug view is hidden)."""
        self._logging_enabled = False
        logger.debug("OSC message logging disabled")
    
    def get_recent_messages(self, count: int = 50) -> List[Tuple[float, str, Any]]:
        """
        Get recent OSC messages for debug display.
        
        Returns:
            List of (timestamp, address, args) tuples
        """
        with self._log_lock:
            # Get last N messages efficiently
            return list(self._message_log)[-count:] if self._message_log else []
    
    def clear_log(self):
        """Clear message log."""
        with self._log_lock:
            self._message_log.clear()
    
    def get_stats(self) -> dict:
        """Get OSC manager statistics."""
        return {
            'total_messages': self._message_count,
            'logged_messages': len(self._message_log),
            'logging_enabled': self._logging_enabled,
        }
    
    @property
    def host(self) -> str:
        return self._host
    
    @property
    def port(self) -> int:
        return self._port


# Singleton instance - import this throughout the codebase
osc = OSCManager()
