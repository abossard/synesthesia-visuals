"""
OSC Monitor - Aggregated message tracking for UI display

Groups messages by (channel, address), shows only latest value + count.
Monitoring work is active only while the OSC panel is open.
"""

import logging
import threading
import time
from collections import Counter, defaultdict, deque
from dataclasses import dataclass
from typing import Any, Dict, List, Tuple

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
        self._total_count = 0
        self._channel_counts: Counter[str] = Counter()
        self._prefix_counts: Dict[str, Counter[str]] = defaultdict(Counter)
        self._recent_timestamps: deque[float] = deque()
        self._rate_window_sec = 2.0
        self._max_prefix_depth = 3

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
        if not self._started:
            return
        self._record(f"→{channel}", address, args)

    def _record(self, channel: str, address: str, args: list):
        """Record a message, aggregating by channel:address."""
        now = time.time()
        if not self._started:
            return

        key = f"{channel}:{address}"
        prefixes = self._build_prefixes(address, self._max_prefix_depth)

        with self._lock:
            self._msg_count += 1
            self._total_count += 1
            self._channel_counts[channel] += 1

            self._recent_timestamps.append(now)
            cutoff = now - self._rate_window_sec
            while self._recent_timestamps and self._recent_timestamps[0] < cutoff:
                self._recent_timestamps.popleft()

            for prefix in prefixes:
                self._prefix_counts[channel][prefix] += 1

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

    def get_stats(self) -> Dict[str, Any]:
        """Get current statistics snapshot."""
        with self._lock:
            total = self._total_count
            unique_addresses = len(self._data)
            channels = dict(self._channel_counts)
            rate = len(self._recent_timestamps) / self._rate_window_sec

        return {
            "total": total,
            "unique_addresses": unique_addresses,
            "rate": rate,
            "channels": channels,
        }

    def get_grouped_prefixes(
        self,
        filter_text: str = "",
        max_depth: int = 3,
        limit: int = 6,
        child_limit: int = 5,
    ) -> Dict[str, List[Tuple[str, int, int]]]:
        """Get grouped prefix counts by channel."""
        with self._lock:
            snapshot = {ch: dict(counts) for ch, counts in self._prefix_counts.items()}

        grouped: Dict[str, List[Tuple[str, int, int]]] = {}
        for channel, counts in snapshot.items():
            grouped[channel] = self._build_grouped_prefixes(
                counts,
                filter_text=filter_text,
                max_depth=max_depth,
                limit=limit,
                child_limit=child_limit,
            )
        return grouped

    def get_grouped_messages(
        self,
        filter_text: str = "",
        limit_per_channel: int = 8,
    ) -> Dict[str, List[AggregatedMessage]]:
        """Get aggregated messages grouped by channel."""
        with self._lock:
            items = list(self._data.values())

        match = filter_text.strip().lower()
        grouped: Dict[str, List[AggregatedMessage]] = defaultdict(list)
        for msg in items:
            if match and match not in msg.address.lower():
                continue
            grouped[msg.channel].append(msg)

        for channel in grouped:
            grouped[channel].sort(key=lambda m: m.last_time, reverse=True)
            grouped[channel] = grouped[channel][:limit_per_channel]

        return dict(grouped)

    def clear(self):
        """Clear all tracked messages."""
        with self._lock:
            self._data.clear()
            self._msg_count = 0
            self._total_count = 0
            self._channel_counts.clear()
            self._prefix_counts.clear()
            self._recent_timestamps.clear()

    @staticmethod
    def _build_prefixes(address: str, max_depth: int) -> List[str]:
        parts = [part for part in address.split("/") if part]
        prefixes = []
        for idx in range(min(len(parts), max_depth)):
            prefixes.append("/" + "/".join(parts[: idx + 1]))
        return prefixes

    @staticmethod
    def _build_grouped_prefixes(
        counts: Dict[str, int],
        filter_text: str = "",
        max_depth: int = 3,
        limit: int = 6,
        child_limit: int = 5,
    ) -> List[Tuple[str, int, int]]:
        match = filter_text.strip().lower()
        prefixes = [p for p in counts.keys() if p.count("/") <= max_depth]
        children: Dict[str, List[str]] = defaultdict(list)
        for prefix in prefixes:
            if prefix.count("/") <= 1:
                parent = ""
            else:
                parent = prefix.rsplit("/", 1)[0]
            children[parent].append(prefix)

        include = set(prefixes)
        if match:
            include = set()
            for prefix in prefixes:
                if match in prefix.lower():
                    current = prefix
                    while True:
                        include.add(current)
                        if current.count("/") <= 1:
                            break
                        current = current.rsplit("/", 1)[0]

        result: List[Tuple[str, int, int]] = []

        def add_branch(prefix: str, depth: int) -> None:
            if prefix not in include or depth > max_depth:
                return
            result.append((prefix, counts.get(prefix, 0), depth))
            for child in sorted(
                children.get(prefix, []),
                key=lambda p: counts.get(p, 0),
                reverse=True,
            )[:child_limit]:
                if child in include:
                    add_branch(child, depth + 1)

        top_level = sorted(
            [p for p in children.get("", []) if p in include],
            key=lambda p: counts.get(p, 0),
            reverse=True,
        )[:limit]

        for prefix in top_level:
            add_branch(prefix, 1)

        return result


# Global singleton instance
osc_monitor = OSCMonitor()
