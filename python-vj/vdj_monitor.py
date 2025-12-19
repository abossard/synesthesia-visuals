#!/usr/bin/env python3
"""
VirtualDJ OSC Monitor - Minimal implementation

Subscribes to VDJ OSC for track info and is_audible state.
Implements get_playback() compatible with AppleScriptSpotifyMonitor.

Requirements: VirtualDJ PRO license, oscPort=9009, oscPortBack=9999
"""

import logging
import threading
import time
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

from osc import osc

logger = logging.getLogger(__name__)


@dataclass
class VDJDeckState:
    """Minimal state for a VirtualDJ deck."""
    deck: int = 1
    artist: str = ""
    title: str = ""
    album: str = ""
    key: str = ""
    duration_sec: float = 0.0
    is_playing: bool = False
    is_audible: bool = False  # VDJ: playing AND volume up
    position: float = 0.0  # 0.0-1.0
    bpm: float = 0.0
    beat_intensity: float = 0.0
    volume: float = 1.0
    loaded: bool = False


@dataclass
class VDJState:
    """Global VDJ state with two decks."""
    deck1: VDJDeckState = field(default_factory=lambda: VDJDeckState(deck=1))
    deck2: VDJDeckState = field(default_factory=lambda: VDJDeckState(deck=2))
    last_message_time: float = 0.0


class VDJMonitor:
    """Minimal VirtualDJ OSC Monitor."""
    
    monitor_key = "vdj_osc"
    monitor_label = "VirtualDJ (OSC)"
    
    # Only subscribe to what we actually use
    DECK_SUBS = [
        "get_title", "get_artist", "get_album", "get_key",
        "get_songlength", "get_bpm", "get_beat",
        "play", "is_audible", "song_pos", "volume", "loaded",
    ]
    
    TIMEOUT_SEC = 5.0
    
    def __init__(self):
        self._state = VDJState()
        self._lock = threading.RLock()
        self._running = False
    
    def start(self) -> bool:
        """Start monitor, subscribe to VDJ OSC."""
        if self._running:
            return True
        try:
            if not osc.is_started:
                osc.start()
            osc.subscribe("/vdj/*", self._on_message)
            self._subscribe()
            self._running = True
            logger.info(f"[VDJMonitor] Started on port {osc.receive_port}")
            return True
        except Exception as e:
            logger.error(f"[VDJMonitor] Start failed: {e}")
            return False
    
    def stop(self):
        """Stop monitor."""
        if not self._running:
            return
        try:
            self._unsubscribe()
            osc.unsubscribe("/vdj/*", self._on_message)
        except Exception:
            pass
        self._running = False
    
    def get_playback(self) -> Optional[Dict[str, Any]]:
        """Get playback info for audible deck (TextlerEngine interface)."""
        with self._lock:
            if not self._is_connected():
                return None
            deck = self._get_audible_deck()
            if not deck or not deck.loaded or (not deck.artist and not deck.title):
                return None
            return {
                'artist': deck.artist,
                'title': deck.title,
                'album': deck.album,
                'duration_ms': int(deck.duration_sec * 1000),
                'progress_ms': int(deck.position * deck.duration_sec * 1000),
                'is_playing': deck.is_playing,
                'source': 'vdj',
                'deck': deck.deck,
                'bpm': deck.bpm,
                'key': deck.key,
            }
    
    @property
    def status(self) -> Dict[str, Any]:
        """Monitor status for UI."""
        with self._lock:
            connected = self._is_connected()
            deck = self._get_audible_deck()
            return {
                'available': connected,
                'status': 'connected' if connected else 'offline',
                'audible_deck': deck.deck if deck else None,
                'bpm': deck.bpm if deck else 0,
            }
    
    def _on_message(self, address: str, args: List[Any]):
        """Handle VDJ OSC message."""
        if not address.startswith("/vdj/"):
            return
        with self._lock:
            self._state.last_message_time = time.time()
        parts = address.split("/")
        if len(parts) >= 5 and parts[2] == "deck":
            try:
                deck_num = int(parts[3])
                verb = parts[4]
                self._handle_deck(deck_num, verb, args[0] if args else None)
            except (ValueError, IndexError):
                pass
    
    def _handle_deck(self, deck: int, verb: str, value: Any):
        """Update deck state from OSC."""
        if deck not in (1, 2):
            return
        with self._lock:
            d = self._state.deck1 if deck == 1 else self._state.deck2
            if verb == "get_title":
                d.title = str(value) if value else ""
            elif verb == "get_artist":
                d.artist = str(value) if value else ""
            elif verb == "get_album":
                d.album = str(value) if value else ""
            elif verb == "get_key":
                d.key = str(value) if value else ""
            elif verb == "get_songlength":
                d.duration_sec = float(value) if value else 0.0
            elif verb == "get_bpm":
                d.bpm = float(value) if value else 0.0
            elif verb == "get_beat":
                d.beat_intensity = float(value) if value else 0.0
            elif verb == "play":
                d.is_playing = bool(value)
            elif verb == "is_audible":
                d.is_audible = bool(value)
            elif verb == "song_pos":
                d.position = float(value) if value else 0.0
            elif verb == "volume":
                d.volume = float(value) if value else 1.0
            elif verb == "loaded":
                d.loaded = bool(value)
    
    def _subscribe(self):
        """Subscribe to VDJ OSC updates."""
        for deck in (1, 2):
            for verb in self.DECK_SUBS:
                osc.vdj.send(f"/vdj/subscribe/deck/{deck}/{verb}")
        # Query initial state
        for deck in (1, 2):
            for verb in self.DECK_SUBS:
                osc.vdj.send(f"/vdj/query/deck/{deck}/{verb}")
    
    def _unsubscribe(self):
        """Unsubscribe from VDJ OSC."""
        for deck in (1, 2):
            for verb in self.DECK_SUBS:
                osc.vdj.send(f"/vdj/unsubscribe/deck/{deck}/{verb}")
    
    def _get_audible_deck(self) -> Optional[VDJDeckState]:
        """Return audible deck (VDJ is_audible = playing + volume up)."""
        d1, d2 = self._state.deck1, self._state.deck2
        if d1.is_audible and not d2.is_audible:
            return d1
        if d2.is_audible and not d1.is_audible:
            return d2
        if d1.is_audible and d2.is_audible:
            return d1  # Both audible, pick deck 1
        # Fallback: any loaded
        return d1 if d1.loaded else (d2 if d2.loaded else None)
    
    def _is_connected(self) -> bool:
        """Check if VDJ responded recently."""
        t = self._state.last_message_time
        return t > 0 and (time.time() - t) < self.TIMEOUT_SEC
