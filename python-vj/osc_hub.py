#!/usr/bin/env python3
"""
OSC Hub - Centralized typed OSC communication for VJ system

Typed channel-based architecture with bidirectional support.
Uses pyliblo3 for OSC (C bindings to liblo library).

Usage:
    from osc_hub import osc
    
    # Send to VirtualDJ
    osc.vdj.send("/deck/1/play")
    osc.vdj.send("/deck/1/get_time")
    
    # Send to Synesthesia
    osc.synesthesia.send("/scene/load", "my_scene")
    
    # Subscribe to messages
    osc.vdj.subscribe("/deck/1/get_time", my_handler)
    
    # Pattern matching
    osc.vdj.subscribe("/deck/*/", deck_handler)  # matches /deck/1/, /deck/2/, etc.

Architecture follows Grokking Simplicity:
- Channel is immutable configuration (data)
- OSCHub manages servers lifecycle (action)
- Message routing is pure function (calculation)
"""

import atexit
import logging
import re
import threading
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional, Tuple

import pyliblo3 as liblo

logger = logging.getLogger("osc_hub")


# =============================================================================
# DATA - Immutable configuration
# =============================================================================

@dataclass(frozen=True)
class ChannelConfig:
    """Immutable channel configuration."""
    name: str
    host: str
    send_port: int
    recv_port: Optional[int] = None  # None = send-only channel


# Universe configurations
VDJ_CONFIG = ChannelConfig("vdj", "127.0.0.1", send_port=9009, recv_port=9008)
SYNESTHESIA_CONFIG = ChannelConfig("synesthesia", "127.0.0.1", send_port=7777, recv_port=9999)
KARAOKE_CONFIG = ChannelConfig("karaoke", "127.0.0.1", send_port=9000, recv_port=None)
PROCESSING_CONFIG = ChannelConfig("processing", "127.0.0.1", send_port=9000, recv_port=None)


# =============================================================================
# CALCULATION - Pure pattern matching
# =============================================================================

def pattern_matches(pattern: str, address: str) -> bool:
    """
    Check if OSC pattern matches address.
    
    Supports:
    - * matches any single path segment
    - ** would match multiple segments (not implemented yet)
    - Exact match
    
    Examples:
        pattern_matches("/deck/*/play", "/deck/1/play")  -> True
        pattern_matches("/deck/1/play", "/deck/2/play")  -> False
    """
    # Convert OSC pattern to regex
    # * matches any single segment (no slashes)
    regex_pattern = pattern.replace("*", "[^/]+")
    regex_pattern = f"^{regex_pattern}$"
    return bool(re.match(regex_pattern, address))


# =============================================================================
# ACTION - Channel with server lifecycle
# =============================================================================

Handler = Callable[[str, List[Any]], None]


class Channel:
    """
    Bidirectional OSC channel with subscription support.
    
    Manages server lifecycle and message routing.
    Thread-safe for subscriptions and message handling.
    """
    
    def __init__(self, config: ChannelConfig):
        self._config = config
        self._target: Optional[liblo.Address] = None
        self._server: Optional[liblo.Server] = None
        self._handlers: Dict[str, List[Handler]] = {}
        self._lock = threading.Lock()
        self._running = False
        self._recv_thread: Optional[threading.Thread] = None
        
    @property
    def name(self) -> str:
        return self._config.name
    
    @property
    def send_port(self) -> int:
        return self._config.send_port
    
    @property
    def recv_port(self) -> Optional[int]:
        return self._config.recv_port
    
    @property
    def is_bidirectional(self) -> bool:
        return self._config.recv_port is not None
    
    @property
    def is_running(self) -> bool:
        return self._running
    
    def start(self) -> bool:
        """
        Start the channel - create target and server.
        Returns True if started successfully.
        """
        if self._running:
            return True
        
        try:
            # Create send target
            self._target = liblo.Address(self._config.host, self._config.send_port)
            logger.info(f"[{self.name}] Send target: {self._config.host}:{self._config.send_port}")
            
            # Create receive server if bidirectional
            if self._config.recv_port:
                self._server = liblo.Server(self._config.recv_port)
                self._server.add_method(None, None, self._dispatch)
                logger.info(f"[{self.name}] Receive server on port {self._config.recv_port}")
                
                # Start receive thread
                self._running = True
                self._recv_thread = threading.Thread(
                    target=self._recv_loop,
                    name=f"OSC-{self.name}",
                    daemon=True
                )
                self._recv_thread.start()
            else:
                self._running = True
                logger.info(f"[{self.name}] Send-only channel (no receiver)")
            
            return True
            
        except liblo.ServerError as e:
            logger.error(f"[{self.name}] Failed to start: {e}")
            return False
    
    def stop(self):
        """Stop the channel - cleanup server and thread."""
        if not self._running:
            return
        
        self._running = False
        
        if self._server:
            # Server will stop when recv_loop exits
            self._server = None
        
        if self._recv_thread and self._recv_thread.is_alive():
            self._recv_thread.join(timeout=1.0)
        
        self._target = None
        logger.info(f"[{self.name}] Stopped")
    
    def send(self, address: str, *args) -> bool:
        """
        Send OSC message to this channel's target.
        
        Args:
            address: OSC address pattern (e.g., "/deck/1/play")
            *args: Message arguments
            
        Returns:
            True if sent successfully
        """
        if not self._target:
            logger.warning(f"[{self.name}] Cannot send - channel not started")
            return False
        
        try:
            liblo.send(self._target, address, *args)
            logger.debug(f"[{self.name}] → {address} {args if args else ''}")
            return True
        except Exception as e:
            logger.error(f"[{self.name}] Send error: {e}")
            return False
    
    def subscribe(self, pattern: str, handler: Handler):
        """
        Subscribe to messages matching pattern.
        
        Args:
            pattern: OSC address pattern (supports * wildcard)
            handler: Callback function(address, args)
        """
        with self._lock:
            if pattern not in self._handlers:
                self._handlers[pattern] = []
            self._handlers[pattern].append(handler)
            logger.debug(f"[{self.name}] Subscribed to {pattern}")
    
    def unsubscribe(self, pattern: str, handler: Optional[Handler] = None):
        """
        Unsubscribe from pattern.
        
        Args:
            pattern: OSC address pattern
            handler: Specific handler to remove, or None to remove all
        """
        with self._lock:
            if pattern not in self._handlers:
                return
            
            if handler is None:
                del self._handlers[pattern]
            else:
                self._handlers[pattern] = [h for h in self._handlers[pattern] if h != handler]
                if not self._handlers[pattern]:
                    del self._handlers[pattern]
    
    def _recv_loop(self):
        """Background thread receiving messages."""
        while self._running and self._server:
            try:
                # Non-blocking receive with timeout
                self._server.recv(50)  # 50ms timeout
            except Exception as e:
                if self._running:
                    logger.error(f"[{self.name}] Receive error: {e}")
    
    def _dispatch(self, path: str, args: List[Any], types: str, src: liblo.Address) -> None:
        """Dispatch received message to matching handlers."""
        logger.debug(f"[{self.name}] ← {path} {args}")
        
        with self._lock:
            handlers_snapshot = dict(self._handlers)
        
        for pattern, handlers in handlers_snapshot.items():
            if pattern_matches(pattern, path):
                for handler in handlers:
                    try:
                        handler(path, args)
                    except Exception as e:
                        logger.error(f"[{self.name}] Handler error for {path}: {e}")


# =============================================================================
# ACTION - Hub singleton managing all channels
# =============================================================================

class OSCHub:
    """
    Central OSC hub with typed channel properties.
    
    Starts all servers on creation, stops on exit.
    Singleton pattern - use module-level `osc` instance.
    """
    
    def __init__(self):
        self._channels: Dict[str, Channel] = {}
        self._started = False
        
        # Create channels (not started yet)
        self._vdj = Channel(VDJ_CONFIG)
        self._synesthesia = Channel(SYNESTHESIA_CONFIG)
        self._karaoke = Channel(KARAOKE_CONFIG)
        self._processing = Channel(PROCESSING_CONFIG)
        
        self._channels = {
            "vdj": self._vdj,
            "synesthesia": self._synesthesia,
            "karaoke": self._karaoke,
            "processing": self._processing,
        }
    
    # Typed channel properties
    @property
    def vdj(self) -> Channel:
        """VirtualDJ channel (bidirectional: send=9009, recv=9008)"""
        return self._vdj
    
    @property
    def synesthesia(self) -> Channel:
        """Synesthesia channel (bidirectional: send=7777, recv=9999)"""
        return self._synesthesia
    
    @property
    def karaoke(self) -> Channel:
        """Karaoke/Processing channel (send-only: 9000)"""
        return self._karaoke
    
    @property
    def processing(self) -> Channel:
        """Processing channel (send-only: 9000) - alias for karaoke port"""
        return self._processing
    
    def start(self) -> bool:
        """
        Start all channels.
        Called automatically on first use, but can be called explicitly.
        """
        if self._started:
            return True
        
        logger.info("OSCHub starting...")
        all_ok = True
        
        for name, channel in self._channels.items():
            if not channel.start():
                logger.warning(f"Channel {name} failed to start")
                all_ok = False
        
        self._started = True
        
        # Register cleanup on exit
        atexit.register(self.stop)
        
        logger.info(f"OSCHub started ({'all channels OK' if all_ok else 'some channels failed'})")
        return all_ok
    
    def stop(self):
        """Stop all channels. Called automatically on process exit."""
        if not self._started:
            return
        
        logger.info("OSCHub stopping...")
        
        for name, channel in self._channels.items():
            channel.stop()
        
        self._started = False
        logger.info("OSCHub stopped")
    
    def get_channel(self, name: str) -> Optional[Channel]:
        """Get channel by name (for dynamic access)."""
        return self._channels.get(name)
    
    @property
    def channels(self) -> Dict[str, Channel]:
        """All channels (read-only view)."""
        return dict(self._channels)


# =============================================================================
# MODULE-LEVEL SINGLETON
# =============================================================================

# Create singleton instance
osc = OSCHub()


def start():
    """Explicitly start the OSC hub. Called automatically on first send."""
    return osc.start()


def stop():
    """Explicitly stop the OSC hub. Called automatically on process exit."""
    osc.stop()


# =============================================================================
# CONVENIENCE FUNCTIONS (for simple use cases)
# =============================================================================

def send_vdj(address: str, *args) -> bool:
    """Send to VirtualDJ."""
    if not osc._started:
        osc.start()
    return osc.vdj.send(address, *args)


def send_synesthesia(address: str, *args) -> bool:
    """Send to Synesthesia."""
    if not osc._started:
        osc.start()
    return osc.synesthesia.send(address, *args)


def send_karaoke(address: str, *args) -> bool:
    """Send to karaoke/processing."""
    if not osc._started:
        osc.start()
    return osc.karaoke.send(address, *args)


# =============================================================================
# MAIN - Test/demo
# =============================================================================

if __name__ == "__main__":
    import time
    
    logging.basicConfig(
        level=logging.DEBUG,
        format="%(asctime)s [%(levelname)s] %(message)s",
        datefmt="%H:%M:%S"
    )
    
    print("=== OSC Hub Test ===\n")
    
    # Start hub
    osc.start()
    
    print("\nChannels:")
    for name, ch in osc.channels.items():
        bidir = "bidirectional" if ch.is_bidirectional else "send-only"
        ports = f"send={ch.send_port}"
        if ch.recv_port:
            ports += f", recv={ch.recv_port}"
        print(f"  {name}: {bidir} ({ports})")
    
    # Test VDJ subscription
    print("\n--- VDJ Test ---")
    
    received_messages = []
    
    def on_vdj_message(path: str, args: list):
        received_messages.append((path, args))
        print(f"  VDJ ← {path}: {args}")
    
    # Subscribe to all VDJ messages
    osc.vdj.subscribe("/*", on_vdj_message)
    
    # Send test message (VDJ needs to be running to respond)
    print("Sending /deck/1/get_title...")
    osc.vdj.send("/deck/1/get_title")
    
    # Wait for responses
    print("Waiting 2 seconds for responses...")
    time.sleep(2)
    
    print(f"\nReceived {len(received_messages)} messages")
    
    # Stop
    osc.stop()
    print("\n=== Done ===")
