#!/usr/bin/env python3
"""
OSC Hub - Typed OSC channels for VJ system

Usage:
    from osc_hub import osc
    
    osc.start()
    osc.vdj.send("/deck/1/play")
    osc.synesthesia.send("/scene/load", "my_scene")
    osc.karaoke.send("/track", 1, "artist", "title")
    
    osc.vdj.subscribe("/deck/1/get_time", handler)
    result = osc.vdj.query("/deck/1/get_time", timeout=1.0)
"""

import atexit
import logging
import threading
import time
from dataclasses import dataclass
from typing import Any, Callable, Dict, List, Optional

import pyliblo3 as liblo

logger = logging.getLogger("osc_hub")

Handler = Callable[[str, List[Any]], None]


@dataclass(frozen=True)
class ChannelConfig:
    name: str
    host: str
    send_port: int
    recv_port: Optional[int] = None


VDJ = ChannelConfig("vdj", "127.0.0.1", 9009, 9008)
SYNESTHESIA = ChannelConfig("synesthesia", "127.0.0.1", 7777, 9999)
KARAOKE = ChannelConfig("karaoke", "127.0.0.1", 9000, None)


class Channel:
    def __init__(self, config: ChannelConfig):
        self._config = config
        self._target: Optional[liblo.Address] = None
        self._server: Optional[liblo.ServerThread] = None
        self._handlers: Dict[str, List[Handler]] = {}
        self._query_results: Dict[str, List[Any]] = {}
        self._query_events: Dict[str, threading.Event] = {}
        self._stopping = False
    
    @property
    def name(self) -> str:
        return self._config.name
    
    @property
    def send_port(self) -> int:
        return self._config.send_port
    
    @property
    def recv_port(self) -> Optional[int]:
        return self._config.recv_port
    
    def start(self) -> bool:
        try:
            self._target = liblo.Address(self._config.host, self._config.send_port)
            logger.info(f"[{self.name}] → {self._config.host}:{self._config.send_port}")
            
            if self._config.recv_port:
                self._server = liblo.ServerThread(self._config.recv_port)
                self._server.add_method(None, None, self._dispatch)
                self._server.start()
                logger.info(f"[{self.name}] ← port {self._config.recv_port}")
            return True
        except liblo.ServerError as e:
            logger.error(f"[{self.name}] Start failed: {e}")
            return False
    
    def stop(self):
        self._stopping = True  # Signal handlers to exit fast
        if self._server:
            # Remove catch-all handler first to stop message processing
            try:
                self._server.del_method(None, None)
            except Exception:
                pass
            # Give thread time to finish current dispatch
            time.sleep(0.1)
            try:
                self._server.stop()
            except Exception:
                pass  # Ignore stop errors
            self._server = None
        self._target = None
        self._stopping = False
        logger.info(f"[{self.name}] Stopped")
    
    def send(self, address: str, *args) -> bool:
        if not self._target:
            return False
        try:
            liblo.send(self._target, address, *args)
            return True
        except Exception as e:
            logger.error(f"[{self.name}] Send error: {e}")
            return False
    
    def subscribe(self, address: str, handler: Handler):
        """Subscribe to exact address match."""
        self._handlers.setdefault(address, []).append(handler)
    
    def unsubscribe(self, address: str, handler: Optional[Handler] = None):
        if address not in self._handlers:
            return
        if handler is None:
            del self._handlers[address]
        else:
            self._handlers[address] = [h for h in self._handlers[address] if h != handler]
    
    def query(self, address: str, *args, timeout: float = 1.0) -> Optional[List[Any]]:
        """Send and wait for response. Inline, no subscribe dance."""
        if not self._config.recv_port:
            return None
        
        # Setup inline response capture
        event = threading.Event()
        self._query_events[address] = event
        self._query_results[address] = []
        
        try:
            self.send(address, *args)
            if event.wait(timeout):
                return self._query_results.get(address)
            return None
        finally:
            self._query_events.pop(address, None)
            self._query_results.pop(address, None)
    
    def _dispatch(self, path: str, args: List[Any], types: str, src: liblo.Address):
        # Exit immediately if stopping (prevents deadlock)
        if self._stopping:
            return
        
        # Check for pending query first (fast path)
        if path in self._query_events:
            self._query_results[path] = list(args)
            self._query_events[path].set()
            return
        
        # Dispatch to exact match handlers
        handlers = self._handlers.get(path)
        if handlers:
            for handler in handlers:
                try:
                    handler(path, args)
                except Exception as e:
                    logger.error(f"Handler error: {e}")
        
        # Also dispatch to catch-all "/" handlers (for monitoring)
        if path != "/" and "/" in self._handlers:
            for handler in self._handlers["/"]:
                try:
                    handler(path, args)
                except Exception as e:
                    logger.error(f"Catch-all handler error: {e}")


class OSCHub:
    """
    Central OSC hub managing typed channels for VJ system.
    
    Channels:
        - vdj: VirtualDJ OSC (send 9009, recv 9008)
        - synesthesia: Synesthesia OSC (send 7777, recv 9999)
        - karaoke: Karaoke/Processing OSC (send 9000, no recv)
    
    Usage:
        osc.start()  # Start all channels
        osc.vdj.send("/deck/1/play")
        osc.stop()   # Stop all channels
    """
    
    def __init__(self):
        self._vdj = Channel(VDJ)
        self._synesthesia = Channel(SYNESTHESIA)
        self._karaoke = Channel(KARAOKE)
        self._started = False
    
    @property
    def is_started(self) -> bool:
        """Check if OSC hub is currently running."""
        return self._started
    
    @property
    def vdj(self) -> Channel:
        return self._vdj
    
    @property
    def synesthesia(self) -> Channel:
        return self._synesthesia
    
    @property
    def karaoke(self) -> Channel:
        return self._karaoke
    
    @property
    def processing(self) -> Channel:
        """Alias for karaoke (same port 9000)."""
        return self._karaoke
    
    def get_channel_status(self) -> Dict[str, Dict[str, Any]]:
        """Get status of all channels."""
        return {
            "vdj": {
                "name": "VirtualDJ",
                "send_port": VDJ.send_port,
                "recv_port": VDJ.recv_port,
                "active": self._vdj._target is not None,
            },
            "synesthesia": {
                "name": "Synesthesia",
                "send_port": SYNESTHESIA.send_port,
                "recv_port": SYNESTHESIA.recv_port,
                "active": self._synesthesia._target is not None,
            },
            "karaoke": {
                "name": "Karaoke/Processing",
                "send_port": KARAOKE.send_port,
                "recv_port": KARAOKE.recv_port,
                "active": self._karaoke._target is not None,
            },
        }
    
    def start(self) -> bool:
        """Start all OSC channels."""
        if self._started:
            return True
        logger.info("OSCHub starting...")
        self._vdj.start()
        self._synesthesia.start()
        self._karaoke.start()
        self._started = True
        atexit.register(self.stop)
        logger.info("OSCHub ready")
        return True
    
    def stop(self):
        """Stop all OSC channels."""
        if not self._started:
            return
        self._vdj.stop()
        self._synesthesia.stop()
        self._karaoke.stop()
        self._started = False
        logger.info("OSCHub stopped")


osc = OSCHub()


# =============================================================================
# OSC MONITOR - Aggregated message tracking for UI display
# =============================================================================

@dataclass
class AggregatedMessage:
    """Aggregated OSC message for display: groups by address, tracks count."""
    channel: str
    address: str
    last_args: List[Any]
    last_time: float
    count: int = 1


class OSCMonitor:
    """
    Monitor OSC traffic across all channels with aggregation.
    
    Groups messages by (channel, address), shows only latest value + count.
    Optimized for UI display - no per-message overhead.
    
    Usage:
        monitor = OSCMonitor()
        monitor.start()  # Subscribes to osc channels (requires osc.start() first)
        
        # Get aggregated view (sorted by recency)
        for msg in monitor.get_aggregated():
            print(f"{msg.channel} {msg.address} = {msg.last_args} (×{msg.count})")
    """
    
    def __init__(self, max_addresses: int = 100):
        self._max = max_addresses
        self._data: Dict[str, AggregatedMessage] = {}  # key = "channel:address"
        self._lock = threading.Lock()
        self._started = False
        self._msg_count = 0  # Debug counter
    
    @property
    def is_started(self) -> bool:
        """Check if monitor is currently running."""
        return self._started
    
    def start(self):
        """Subscribe to all OSC channels. Starts OSC hub if not already started."""
        if self._started:
            return True
        if not osc.is_started:
            osc.start()
        osc.vdj.subscribe("/", self._on_vdj)
        osc.synesthesia.subscribe("/", self._on_synesthesia)
        # karaoke is send-only, no recv_port
        self._started = True
        logger.info(f"OSCMonitor started, synesthesia server: {osc.synesthesia._server}")
        return True
    
    def stop(self):
        """Unsubscribe from channels."""
        if not self._started:
            return
        osc.vdj.unsubscribe("/", self._on_vdj)
        osc.synesthesia.unsubscribe("/", self._on_synesthesia)
        self._started = False
    
    def _on_vdj(self, path: str, args: list):
        self._record("vdj", path, args)
    
    def _on_synesthesia(self, path: str, args: list):
        self._record("syn", path, args)
    
    def record_outgoing(self, channel: str, address: str, args: list):
        """Record outgoing message (call from OSCSender)."""
        self._record(f"→{channel}", address, args)
    
    def _record(self, channel: str, address: str, args: list):
        """Record a message, aggregating by channel:address. Lock-free for existing keys."""
        self._msg_count += 1
        key = f"{channel}:{address}"
        now = time.time()
        
        # Fast path: update existing (no lock needed for dict update)
        existing = self._data.get(key)
        if existing:
            self._data[key] = AggregatedMessage(
                channel=channel,
                address=address,
                last_args=list(args),
                last_time=now,
                count=existing.count + 1
            )
            return
        
        # Slow path: new key, need lock for eviction
        with self._lock:
            # Double-check after acquiring lock
            if key in self._data:
                msg = self._data[key]
                self._data[key] = AggregatedMessage(
                    channel=channel,
                    address=address,
                    last_args=list(args),
                    last_time=now,
                    count=msg.count + 1
                )
            else:
                # Evict oldest if at capacity (simple pop, not min search)
                if len(self._data) >= self._max:
                    # Just pop first item (good enough for LRU-ish behavior)
                    try:
                        first_key = next(iter(self._data))
                        del self._data[first_key]
                    except StopIteration:
                        pass
                
                self._data[key] = AggregatedMessage(
                    channel=channel,
                    address=address,
                    last_args=list(args),
                    last_time=now,
                    count=1
                )
    
    def get_aggregated(self, limit: int = 50) -> List[AggregatedMessage]:
        """Get aggregated messages sorted by recency (newest first)."""
        with self._lock:
            items = list(self._data.values())
        items.sort(key=lambda m: m.last_time, reverse=True)
        return items[:limit]
    
    def clear(self):
        """Clear all tracked messages."""
        with self._lock:
            self._data.clear()


# Global monitor instance
osc_monitor = OSCMonitor()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    
    osc.start()
    
    print("\nChannels:")
    for ch in [osc.vdj, osc.synesthesia, osc.karaoke]:
        print(f"  {ch.name}: send={ch.send_port}, recv={ch.recv_port}")
    
    print("\nQuerying VDJ...")
    result = osc.vdj.query("/deck/1/get_time", timeout=0.5)
    print(f"  Result: {result}")
    
    osc.stop()
