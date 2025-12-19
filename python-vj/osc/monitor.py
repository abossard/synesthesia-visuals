"""
OSC Monitor - Aggregated message tracking for UI display

Groups messages by (channel, address), shows only latest value + count.
Optimized for UI display - no per-message overhead.
"""

import logging
import threading
import time
from dataclasses import dataclass
from typing import Any, Dict, List

from .hub import osc

logger = logging.getLogger(__name__)


@dataclass
class AggregatedMessage:
    """Aggregated OSC message for display."""
    channel: str
    address: str
    last_args: List[Any]
    last_time: float
    count: int = 1


class OSCMonitor:
    """
    Monitor OSC traffic across the hub with aggregation.

    Usage:
        monitor = OSCMonitor()
        monitor.start()

        for msg in monitor.get_aggregated():
            print(f"{msg.channel} {msg.address} = {msg.last_args} (×{msg.count})")
    """

    def __init__(self, max_addresses: int = 100):
        self._max = max_addresses
        self._data: Dict[str, AggregatedMessage] = {}
        self._lock = threading.Lock()
        self._started = False
        self._msg_count = 0

    @property
    def is_started(self) -> bool:
        return self._started

    def start(self):
        """Subscribe to all incoming OSC messages."""
        if self._started:
            return True
        if not osc.is_started:
            osc.start()
        osc.subscribe("/", self._on_incoming)
        self._started = True
        logger.info(f"OSCMonitor started")
        return True

    def stop(self):
        """Unsubscribe from incoming OSC messages."""
        if not self._started:
            return
        osc.unsubscribe("/", self._on_incoming)
        self._started = False

    def _on_incoming(self, path: str, args: list):
        self._record("hub", path, args)

    def record_outgoing(self, channel: str, address: str, args: list):
        """Record outgoing message (call from OSCSender)."""
        self._record(f"→{channel}", address, args)

    def _record(self, channel: str, address: str, args: list):
        """Record a message, aggregating by channel:address."""
        self._msg_count += 1
        key = f"{channel}:{address}"
        now = time.time()

        # Fast path: update existing
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
                if len(self._data) >= self._max:
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
        """Get aggregated messages sorted by recency."""
        with self._lock:
            items = list(self._data.values())
        items.sort(key=lambda m: m.last_time, reverse=True)
        return items[:limit]

    def clear(self):
        """Clear all tracked messages."""
        with self._lock:
            self._data.clear()


# Global singleton instance
osc_monitor = OSCMonitor()
