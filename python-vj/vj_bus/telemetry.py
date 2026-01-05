"""
OSC Telemetry Data Plane

High-performance OSC telemetry sender for worker → TUI data streams.
Fire-and-forget UDP for low-latency, high-throughput telemetry.
"""

from pythonosc import udp_client
from typing import List, Any
import logging

logger = logging.getLogger('vj_bus.telemetry')


class TelemetrySender:
    """
    High-performance OSC telemetry sender.
    
    Features:
    - Non-blocking UDP send (fire-and-forget)
    - No delivery guarantees (use control sockets for reliability)
    - Optimized for high-frequency streams (60+ fps)
    - Automatic args normalization
    """
    
    def __init__(self, host: str = "127.0.0.1", port: int = 9000):
        """
        Initialize telemetry sender.
        
        Args:
            host: OSC destination host
            port: OSC destination port
        """
        self.client = udp_client.SimpleUDPClient(host, port)
        self.host = host
        self.port = port
        logger.info(f"Telemetry sender initialized: {host}:{port}")
    
    def send(self, address: str, args: Any = None):
        """
        Send OSC message (non-blocking, fire-and-forget).
        
        Args:
            address: OSC address pattern (e.g., "/audio/levels")
            args: Message arguments (single value, list, or None)
        """
        # Normalize args to list
        if args is None:
            args = []
        elif not isinstance(args, (list, tuple)):
            args = [args]
        
        try:
            self.client.send_message(address, args)
        except Exception as e:
            logger.error(f"OSC send failed {address}: {e}")
