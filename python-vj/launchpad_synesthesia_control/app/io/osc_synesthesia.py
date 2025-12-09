"""
OSC Synesthesia Communication

Thin wrapper over launchpad_osc_lib.OscClient that adds:
- OscCommand interface (send OscCommand instead of address+args)
- OscEvent callback translation

For direct OSC access, use launchpad_osc_lib.OscClient directly.
"""

import logging
from typing import Optional, Callable

from launchpad_osc_lib import (
    OscClient,
    OscConfig,
    OscEvent,
    OscCommand,
    DEFAULT_OSC_PORTS,
)

logger = logging.getLogger(__name__)


# =============================================================================
# OSC MANAGER (App wrapper over library OscClient)
# =============================================================================

class OscManager:
    """
    Async OSC manager for Synesthesia communication.
    
    Wraps launchpad_osc_lib.OscClient with:
    - send(OscCommand) interface instead of send(address, args)
    - Compatible callback system
    
    Usage:
        manager = OscManager(OscConfig())
        await manager.connect()
        manager.send(OscCommand("/scenes/MyScene"))
    """
    
    def __init__(self, config: Optional[OscConfig] = None):
        # Use library defaults if not specified
        if config is None:
            config = OscConfig(
                host="127.0.0.1",
                send_port=DEFAULT_OSC_PORTS.send_port,
                receive_port=DEFAULT_OSC_PORTS.receive_port,
            )
        self._client = OscClient(config)
        self._user_callback: Optional[Callable[[OscEvent], None]] = None
    
    async def connect(self) -> bool:
        """
        Connect OSC client and server.
        
        Returns:
            True if connected successfully
        """
        return await self._client.connect()
    
    def set_osc_callback(self, callback: Callable[[OscEvent], None]):
        """
        Set callback for incoming OSC messages.
        
        Args:
            callback: Function called with OscEvent on message receive
        """
        self._user_callback = callback
        self._client.set_callback(callback)
    
    def send(self, command: OscCommand):
        """
        Send OSC command to Synesthesia.
        
        Args:
            command: OSC command to send
        """
        self._client.send(command.address, command.args if command.args else None)
    
    async def reconnect_loop(self, interval: float = 5.0):
        """
        Periodically try to reconnect if disconnected.
        
        Args:
            interval: Seconds between reconnection attempts
        """
        await self._client.reconnect_loop(interval)
    
    async def stop(self):
        """Stop OSC server and client."""
        await self._client.stop()
    
    def is_connected(self) -> bool:
        """Check if OSC is connected."""
        return self._client.is_connected()
    
    @property
    def status(self) -> str:
        """Get connection status string."""
        return self._client.status
    
    @property
    def config(self) -> OscConfig:
        """Get the OSC configuration."""
        return self._client.config
