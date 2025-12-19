"""
OSC Hub - Centralized OSC routing for VJ system

Architecture:
- Single receive port: 9999 (all incoming OSC from VirtualDJ, Synesthesia, etc.)
- Forwards all received messages to:
  - Port 10000: VJUniverse (Processing)
  - Port 11111: Magic Music Visual
- Send-only channels for outgoing messages:
  - vdj: VirtualDJ (port 9009)
  - synesthesia: Synesthesia (port 7777)
  - textler: VJUniverse (port 10000)
"""

import logging
import queue
import threading
import time
from dataclasses import dataclass
from typing import Any, Callable, Dict, List, Optional, Tuple

import pyliblo3 as liblo

logger = logging.getLogger(__name__)

Handler = Callable[[str, List[Any]], None]

_MATCH_ANY = "any"
_MATCH_EXACT = "exact"
_MATCH_PREFIX = "prefix"

QUEUE_MAXSIZE = 4096
QUEUE_POLL_TIMEOUT = 0.1


@dataclass(frozen=True)
class _PatternEntry:
    order: int
    pattern: Optional[str]
    handlers: Tuple[Handler, ...]


class _PrefixTrieNode:
    __slots__ = ("children", "entries")

    def __init__(self) -> None:
        self.children: Dict[str, "_PrefixTrieNode"] = {}
        self.entries: List[_PatternEntry] = []


class _PrefixTrie:
    __slots__ = ("_root",)

    def __init__(self) -> None:
        self._root = _PrefixTrieNode()

    def add(self, prefix: str, entry: _PatternEntry) -> None:
        node = self._root
        for char in prefix:
            node = node.children.setdefault(char, _PrefixTrieNode())
        node.entries.append(entry)

    def match(self, path: str) -> List[_PatternEntry]:
        node = self._root
        matches: List[_PatternEntry] = []
        if node.entries:
            matches.extend(node.entries)
        for char in path:
            node = node.children.get(char)
            if node is None:
                break
            if node.entries:
                matches.extend(node.entries)
        return matches


@dataclass(frozen=True)
class _ListenerSnapshot:
    any_entries: Tuple[_PatternEntry, ...]
    exact_entries: Dict[str, _PatternEntry]
    prefix_trie: _PrefixTrie


def _classify_pattern(pattern: Optional[str]) -> Tuple[str, Optional[str]]:
    if pattern in (None, "", "/", "*"):
        return _MATCH_ANY, None
    if pattern.endswith("*"):
        return _MATCH_PREFIX, pattern[:-1]
    return _MATCH_EXACT, pattern


@dataclass
class _HubStats:
    drops: int = 0
    processed: int = 0
    queue_peak: int = 0
    latency_sum: float = 0.0
    latency_max: float = 0.0
    latency_count: int = 0

# Central receive port for all incoming OSC
RECEIVE_PORT = 9999

# Forward targets - all received messages are sent to these ports
FORWARD_TARGETS: List[Tuple[str, int]] = [
    ("127.0.0.1", 10000),  # VJUniverse (Processing)
    ("127.0.0.1", 11111),  # Magic Music Visual
]


@dataclass(frozen=True)
class ChannelConfig:
    """Configuration for an OSC channel (send only; recv_port is shared hub port)."""
    name: str
    host: str
    send_port: int
    recv_port: Optional[int] = None


# Channel configurations (send only; recv_port mirrors shared hub port)
VDJ = ChannelConfig("vdj", "127.0.0.1", 9009, RECEIVE_PORT)
SYNESTHESIA = ChannelConfig("synesthesia", "127.0.0.1", 7777, RECEIVE_PORT)
TEXTLER = ChannelConfig("textler", "127.0.0.1", 10000, None)


class Channel:
    """
    Single OSC channel for sending messages only.

    Note: Receiving is handled centrally by OSCHub on port 9999.
    """

    def __init__(self, config: ChannelConfig):
        self._config = config
        self._target: Optional[liblo.Address] = None

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
        """Start the channel. Returns True on success."""
        try:
            self._target = liblo.Address(self._config.host, self._config.send_port)
            logger.info(f"[{self.name}] → {self._config.host}:{self._config.send_port}")
            return True
        except liblo.ServerError as exc:
            logger.error(f"[{self.name}] Start failed: {exc}")
            return False

    def stop(self):
        """Stop the channel."""
        self._target = None
        logger.info(f"[{self.name}] Stopped")

    def send(self, address: str, *args) -> bool:
        """Send OSC message. Returns True on success."""
        if not self._target:
            return False
        try:
            liblo.send(self._target, address, *args)
            return True
        except Exception as exc:
            logger.error(f"[{self.name}] Send error: {exc}")
            return False


class OSCHub:
    """
    Central OSC hub managing a single receiver and forwarding.

    - Receives on port 9999
    - Forwards every message to 10000 and 11111
    - Exposes send-only channels for vdj, synesthesia, textler
    """

    def __init__(self):
        self._vdj = Channel(VDJ)
        self._synesthesia = Channel(SYNESTHESIA)
        self._textler = Channel(TEXTLER)
        self._started = False

        self._server: Optional[liblo.ServerThread] = None
        self._server_lock = threading.Lock()

        self._queue: queue.Queue = queue.Queue(maxsize=QUEUE_MAXSIZE)
        self._worker_stop = threading.Event()
        self._worker_thread: Optional[threading.Thread] = None

        self._stats_enabled = False
        self._stats_lock = threading.Lock()
        self._stats = _HubStats()

        self._forward_targets: List[liblo.Address] = [
            liblo.Address(host, port) for host, port in FORWARD_TARGETS
        ]

        self._listeners: Dict[str, List[Handler]] = {}
        self._listeners_lock = threading.Lock()
        self._listeners_snapshot = _ListenerSnapshot((), {}, _PrefixTrie())
        self._listener_count = 0

    @property
    def is_started(self) -> bool:
        return self._started

    @property
    def receive_port(self) -> int:
        return RECEIVE_PORT

    @property
    def vdj(self) -> Channel:
        return self._vdj

    @property
    def synesthesia(self) -> Channel:
        return self._synesthesia

    @property
    def textler(self) -> Channel:
        return self._textler

    @property
    def processing(self) -> Channel:
        """Alias for textler (VJUniverse port 10000)."""
        return self._textler

    def set_stats_enabled(self, enabled: bool) -> None:
        with self._stats_lock:
            self._stats_enabled = enabled
            if enabled:
                self._stats = _HubStats()

    def get_hub_stats(self) -> Dict[str, Any]:
        if not self._stats_enabled:
            return {}
        with self._stats_lock:
            stats = _HubStats(
                drops=self._stats.drops,
                processed=self._stats.processed,
                queue_peak=self._stats.queue_peak,
                latency_sum=self._stats.latency_sum,
                latency_max=self._stats.latency_max,
                latency_count=self._stats.latency_count,
            )
        avg_latency = (
            stats.latency_sum / stats.latency_count
            if stats.latency_count > 0
            else 0.0
        )
        return {
            "queue_depth": self._queue.qsize(),
            "queue_capacity": self._queue.maxsize,
            "queue_peak": stats.queue_peak,
            "dropped": stats.drops,
            "processed": stats.processed,
            "queue_latency_avg_ms": avg_latency * 1000.0,
            "queue_latency_max_ms": stats.latency_max * 1000.0,
            "queue_latency_samples": stats.latency_count,
        }

    def get_channel_status(self) -> Dict[str, Dict[str, Any]]:
        """Get status of all channels."""
        return {
            "vdj": {
                "name": "VirtualDJ",
                "send_port": VDJ.send_port,
                "recv_port": RECEIVE_PORT,
                "active": self._vdj._target is not None,
            },
            "synesthesia": {
                "name": "Synesthesia",
                "send_port": SYNESTHESIA.send_port,
                "recv_port": RECEIVE_PORT,
                "active": self._synesthesia._target is not None,
            },
            "textler": {
                "name": "Textler/Processing",
                "send_port": TEXTLER.send_port,
                "recv_port": None,
                "active": self._textler._target is not None,
            },
        }

    def start(self) -> bool:
        """Start OSC hub (receiver + send channels)."""
        if self._started:
            return True

        self._start_worker()
        try:
            with self._server_lock:
                self._server = liblo.ServerThread(RECEIVE_PORT)
                self._server.add_method(None, None, self._on_message)
                self._server.start()
        except liblo.ServerError as exc:
            logger.error(f"OSCHub start failed: {exc}")
            self._server = None
            self._stop_worker()
            return False

        self._vdj.start()
        self._synesthesia.start()
        self._textler.start()

        self._started = True
        # Do not register atexit; shutdown can block on some platforms.
        logger.info("OSCHub ready")
        return True

    def stop(self):
        """Stop OSC hub."""
        if not self._started:
            return

        logger.info("OSCHub stopping...")
        self._vdj.stop()
        self._synesthesia.stop()
        self._textler.stop()

        with self._server_lock:
            server = self._server
            self._server = None

        if server:
            stop_thread = threading.Thread(
                target=self._stop_server,
                args=(server,),
                name="OSCHubStop",
                daemon=True,
            )
            stop_thread.start()
            stop_thread.join(timeout=0.5)
            if stop_thread.is_alive():
                logger.warning("OSCHub stop timed out; continuing shutdown")

        self._stop_worker()
        self._started = False
        logger.info("OSCHub stopped")

    def start_channel(self, channel_name: str) -> bool:
        """Start a specific OSC channel by name."""
        self.start()
        channel_map = {
            "vdj": self._vdj,
            "synesthesia": self._synesthesia,
            "textler": self._textler,
        }
        channel = channel_map.get(channel_name)
        return channel.start() if channel else False

    def stop_channel(self, channel_name: str):
        """Stop a specific OSC channel by name."""
        channel_map = {
            "vdj": self._vdj,
            "synesthesia": self._synesthesia,
            "textler": self._textler,
        }
        channel = channel_map.get(channel_name)
        if channel:
            channel.stop()

    def subscribe(self, path: str, handler: Handler) -> None:
        """Subscribe a handler to incoming OSC messages."""
        if not self._started:
            self.start()
        with self._listeners_lock:
            handlers = self._listeners.setdefault(path, [])
            if handler not in handlers:
                handlers.append(handler)
            self._refresh_listeners_snapshot()

    def unsubscribe(self, path: str, handler: Handler) -> None:
        """Unsubscribe a handler from incoming OSC messages."""
        with self._listeners_lock:
            handlers = self._listeners.get(path, [])
            if handler in handlers:
                handlers.remove(handler)
                if not handlers:
                    del self._listeners[path]
                self._refresh_listeners_snapshot()

    def _on_message(self, path: str, args: list, _types: Any, _src: Any):
        """Internal OSC callback: forward + dispatch to subscribers."""
        self._enqueue_message(path, args)

    def _enqueue_message(self, path: str, args: list) -> None:
        timestamp = time.monotonic() if self._stats_enabled else None
        try:
            self._queue.put_nowait((path, args, timestamp))
        except queue.Full:
            if self._stats_enabled:
                with self._stats_lock:
                    self._stats.drops += 1
            return
        if self._stats_enabled:
            queue_size = self._queue.qsize()
            with self._stats_lock:
                if queue_size > self._stats.queue_peak:
                    self._stats.queue_peak = queue_size

    def _forward(self, path: str, args: List[Any]) -> None:
        """Forward a message to all configured targets."""
        message = liblo.Message(path, *args)
        bundle = liblo.Bundle()
        bundle.add(message)
        for target in self._forward_targets:
            try:
                liblo.send(target, bundle)
            except Exception as exc:
                logger.error(f"Forward error to {target}: {exc}")

    def _dispatch(self, path: str, args: List[Any]) -> None:
        """Dispatch message to subscribed handlers."""
        snapshot = self._listeners_snapshot
        matches: List[_PatternEntry] = []
        if snapshot.any_entries:
            matches.extend(snapshot.any_entries)
        exact_entry = snapshot.exact_entries.get(path)
        if exact_entry:
            matches.append(exact_entry)
        matches.extend(snapshot.prefix_trie.match(path))
        if not matches:
            return
        if len(matches) > 1:
            matches.sort(key=lambda entry: entry.order)
        # Reuse list args across handlers; treat as read-only.
        args_list = args if isinstance(args, list) else list(args)
        for entry in matches:
            for handler in entry.handlers:
                try:
                    handler(path, args_list)
                except Exception as exc:
                    logger.error(f"OSC handler error for {entry.pattern}: {exc}")

    def _refresh_listeners_snapshot(self) -> None:
        any_entries: List[_PatternEntry] = []
        exact_entries: Dict[str, _PatternEntry] = {}
        prefix_trie = _PrefixTrie()
        total = 0
        order = 0
        for pattern, handlers in self._listeners.items():
            if not handlers:
                continue
            entry = _PatternEntry(order=order, pattern=pattern, handlers=tuple(handlers))
            match_type, match_value = _classify_pattern(pattern)
            if match_type == _MATCH_ANY:
                any_entries.append(entry)
            elif match_type == _MATCH_EXACT:
                exact_entries[match_value] = entry
            else:
                if match_value is not None:
                    prefix_trie.add(match_value, entry)
            total += len(handlers)
            order += 1
        self._listeners_snapshot = _ListenerSnapshot(
            tuple(any_entries),
            exact_entries,
            prefix_trie,
        )
        self._listener_count = total

    def _start_worker(self) -> None:
        if self._worker_thread and self._worker_thread.is_alive():
            return
        self._worker_stop.clear()
        self._worker_thread = threading.Thread(
            target=self._worker_loop,
            name="OSCHubWorker",
            daemon=True,
        )
        self._worker_thread.start()

    def _stop_worker(self) -> None:
        if not self._worker_thread:
            return
        self._worker_stop.set()
        self._worker_thread.join(timeout=0.5)
        if self._worker_thread.is_alive():
            logger.warning("OSCHub worker stop timed out; continuing shutdown")
            return
        self._worker_thread = None
        self._drain_queue()

    def _drain_queue(self) -> None:
        try:
            while True:
                self._queue.get_nowait()
        except queue.Empty:
            return

    def _worker_loop(self) -> None:
        while not self._worker_stop.is_set():
            try:
                path, args, timestamp = self._queue.get(timeout=QUEUE_POLL_TIMEOUT)
            except queue.Empty:
                continue
            self._forward(path, args)
            if self._listener_count:
                self._dispatch(path, args)
            if self._stats_enabled and timestamp is not None:
                delay = time.monotonic() - timestamp
                with self._stats_lock:
                    self._stats.processed += 1
                    self._stats.latency_sum += delay
                    self._stats.latency_count += 1
                    if delay > self._stats.latency_max:
                        self._stats.latency_max = delay

    @staticmethod
    def _stop_server(server: liblo.ServerThread) -> None:
        try:
            server.stop()
        except Exception as exc:
            logger.error(f"OSCHub stop error: {exc}")


# Global singleton instance
osc = OSCHub()
