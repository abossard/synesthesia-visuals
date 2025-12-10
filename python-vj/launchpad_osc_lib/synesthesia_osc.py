"""
Synesthesia OSC Manager

High-level OSC manager specifically for Synesthesia communication.
Wraps OscClient with Synesthesia defaults, auto-reconnection, and
controllable-message filtering.

This is the recommended way to interact with Synesthesia via OSC.
"""

import logging
from typing import Optional, Callable, List, Any

from .osc_client import OscClient, OscConfig, OscEvent
from .model import OscCommand
from .synesthesia_config import (
    DEFAULT_OSC_PORTS,
    is_controllable,
    is_noisy_audio,
    BEAT_ADDRESS,
)

logger = logging.getLogger(__name__)


class SynesthesiaOscManager:
    """
    High-level OSC manager for Synesthesia communication.
    
    Features:
    - Uses Synesthesia default ports (7777/9999)
    - Auto-reconnection with configurable interval (default 10s)
    - send(OscCommand) interface
    - Separate callbacks for controllable vs all messages
    - Beat pulse tracking for LED sync
    
    Usage:
        manager = SynesthesiaOscManager()
        await manager.connect()
        
        # Register for controllable messages only (learn mode)
        manager.add_controllable_listener(on_controllable_event)
        
        # Send commands
        manager.send(OscCommand("/scenes/MyScene", []))
        
        # Cleanup
        await manager.stop()
    """
    
    def __init__(
        self,
        host: str = DEFAULT_OSC_PORTS.host,
        send_port: int = DEFAULT_OSC_PORTS.send_port,
        receive_port: int = DEFAULT_OSC_PORTS.receive_port,
        auto_reconnect_interval: float = 10.0,
    ):
        """
        Initialize SynesthesiaOscManager.
        
        Args:
            host: OSC host address (default: 127.0.0.1)
            send_port: Port to send OSC to (default: 7777)
            receive_port: Port to receive OSC from (default: 9999)
            auto_reconnect_interval: Seconds between reconnect attempts (default: 10)
        """
        config = OscConfig(host=host, send_port=send_port, receive_port=receive_port)
        self._client = OscClient(config)
        self._auto_reconnect_interval = auto_reconnect_interval
        
        # Callback lists
        self._controllable_listeners: List[Callable[[OscEvent], None]] = []
        self._monitor_listeners: List[Callable[[OscEvent], None]] = []
        self._all_listeners: List[Callable[[OscEvent], None]] = []
        
        # Beat pulse state (for LED blinking)
        self._beat_pulse: bool = False
        
        # Register internal handler
        self._client.add_callback(self._on_osc_event)
    
    # =========================================================================
    # CONNECTION MANAGEMENT
    # =========================================================================
    
    async def connect(self) -> bool:
        """
        Connect to Synesthesia OSC.
        
        Returns:
            True if connected successfully
        """
        result = await self._client.connect()
        if result:
            self._client.start_auto_reconnect(self._auto_reconnect_interval)
        return result
    
    async def stop(self):
        """Stop OSC manager and disconnect."""
        self._client.stop_auto_reconnect()
        await self._client.stop()
    
    def is_connected(self) -> bool:
        """Check if OSC is connected."""
        return self._client.is_connected()
    
    @property
    def status(self) -> str:
        """Get connection status string."""
        return self._client.status
    
    # =========================================================================
    # CALLBACK REGISTRATION
    # =========================================================================
    
    def add_controllable_listener(self, callback: Callable[[OscEvent], None]):
        """
        Add listener for controllable OSC messages only.
        
        Controllable messages are those that can be mapped to Launchpad pads:
        - /scenes/*
        - /presets/*
        - /favslots/*
        - /playlist/*
        - /controls/meta/*
        - /controls/global/*
        
        Args:
            callback: Function called with OscEvent for controllable messages
        """
        if callback not in self._controllable_listeners:
            self._controllable_listeners.append(callback)
    
    def remove_controllable_listener(self, callback: Callable[[OscEvent], None]):
        """Remove a controllable listener."""
        if callback in self._controllable_listeners:
            self._controllable_listeners.remove(callback)
    
    def add_monitor_listener(self, callback: Callable[[OscEvent], None]):
        """
        Add listener for OSC messages suitable for UI monitoring.
        
        Filters out noisy high-frequency messages:
        - /audio/level* (sent every frame)
        - /audio/fft/* (FFT data every frame)
        - /audio/timecode (continuous)
        
        Use this for:
        - OSC monitor/debug display
        - UI event logging
        
        Args:
            callback: Function called with filtered OscEvents
        """
        if callback not in self._monitor_listeners:
            self._monitor_listeners.append(callback)
    
    def remove_monitor_listener(self, callback: Callable[[OscEvent], None]):
        """Remove a monitor listener."""
        if callback in self._monitor_listeners:
            self._monitor_listeners.remove(callback)
    
    def add_all_listener(self, callback: Callable[[OscEvent], None]):
        """
        Add listener for ALL OSC messages (unfiltered).
        
        WARNING: This includes high-frequency audio messages (levels, FFT).
        For UI monitoring, use add_monitor_listener() instead.
        
        Use this for:
        - Beat sync (/audio/beat/*)
        - BPM tracking (/audio/bpm)
        - Raw audio analysis
        
        Args:
            callback: Function called with every OscEvent
        """
        if callback not in self._all_listeners:
            self._all_listeners.append(callback)
    
    def remove_all_listener(self, callback: Callable[[OscEvent], None]):
        """Remove an all-messages listener."""
        if callback in self._all_listeners:
            self._all_listeners.remove(callback)
    
    # =========================================================================
    # SENDING
    # =========================================================================
    
    def send(self, command: OscCommand):
        """
        Send OSC command to Synesthesia.
        
        Args:
            command: OscCommand with address and args
        """
        self._client.send(command.address, command.args)
    
    def send_raw(self, address: str, args: Optional[List[Any]] = None):
        """
        Send raw OSC message.
        
        Args:
            address: OSC address path
            args: Optional list of arguments
        """
        self._client.send(address, args)
    
    # =========================================================================
    # INTERNAL EVENT HANDLING
    # =========================================================================
    
    def _on_osc_event(self, event: OscEvent):
        """Handle incoming OSC event - dispatch to appropriate listeners."""
        address = event.address
        
        # Track beat pulse
        if address == BEAT_ADDRESS:
            self._beat_pulse = bool(event.args[0]) if event.args else False
        
        # Dispatch to all-message listeners (unfiltered)
        for callback in self._all_listeners:
            try:
                callback(event)
            except Exception as e:
                logger.error(f"Error in OSC all-listener: {e}")
        
        # Dispatch to monitor listeners (filtered - no noisy audio)
        if not is_noisy_audio(address):
            for callback in self._monitor_listeners:
                try:
                    callback(event)
                except Exception as e:
                    logger.error(f"Error in OSC monitor-listener: {e}")
        
        # Dispatch to controllable listeners (filtered)
        if is_controllable(address):
            for callback in self._controllable_listeners:
                try:
                    callback(event)
                except Exception as e:
                    logger.error(f"Error in OSC controllable-listener: {e}")
    
    # =========================================================================
    # STATE ACCESS
    # =========================================================================
    
    @property
    def beat_pulse(self) -> bool:
        """
        Current beat pulse state.
        
        True on beat, False otherwise. Use for LED blinking sync.
        """
        return self._beat_pulse
    
    @property
    def config(self) -> OscConfig:
        """Get underlying OSC configuration."""
        return self._client.config
