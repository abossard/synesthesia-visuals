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
        if self._server:
            self._server.stop()
            self._server = None
        self._target = None
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
        # Check for pending query first (fast path)
        if path in self._query_events:
            self._query_results[path] = list(args)
            self._query_events[path].set()
            return
        
        # Dispatch to exact match handlers (no copy, direct access)
        handlers = self._handlers.get(path)
        if handlers:
            for handler in handlers:
                try:
                    handler(path, args)
                except Exception as e:
                    logger.error(f"Handler error: {e}")


class OSCHub:
    def __init__(self):
        self._vdj = Channel(VDJ)
        self._synesthesia = Channel(SYNESTHESIA)
        self._karaoke = Channel(KARAOKE)
        self._started = False
    
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
    
    def start(self) -> bool:
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
        monitor.start()  # Subscribes to osc channels
        
        # Get aggregated view (sorted by recency)
        for msg in monitor.get_aggregated():
            print(f"{msg.channel} {msg.address} = {msg.last_args} (×{msg.count})")
    """
    
    def __init__(self, max_addresses: int = 100):
        self._max = max_addresses
        self._data: Dict[str, AggregatedMessage] = {}  # key = "channel:address"
        self._lock = threading.Lock()
        self._started = False
    
    def start(self):
        """Subscribe to all OSC channels."""
        if self._started:
            return
        osc.start()
        osc.vdj.subscribe("/", self._on_vdj)
        osc.synesthesia.subscribe("/", self._on_synesthesia)
        # karaoke is send-only, no recv_port
        self._started = True
    
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
        """Record a message, aggregating by channel:address."""
        import time
        key = f"{channel}:{address}"
        now = time.time()
        
        with self._lock:
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
                # Evict oldest if at capacity
                if len(self._data) >= self._max:
                    oldest_key = min(self._data, key=lambda k: self._data[k].last_time)
                    del self._data[oldest_key]
                
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
