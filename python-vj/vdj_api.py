#!/usr/bin/env python3
"""
VirtualDJ Remote API Client

Synchronous HTTP client for VirtualDJ's Network Control plugin.

VirtualDJ Setup:
    - Install & enable the "Network Control" plugin (Effects -> Other)
    - Configure its port (e.g. 8080) and optional password
    - This client talks to:
        POST {base_url}/query   with VDJScript in the body (text/plain)
        POST {base_url}/execute likewise

This module provides:
    - VirtualDJClient: synchronous HTTP client using requests
    - DeckStatus: track info for a deck

Usage example:

    from vdj_api import VirtualDJClient, DeckStatus

    client = VirtualDJClient(base_url="http://127.0.0.1:8080")
    
    if client.is_connected():
        master = client.get_masterdeck()
        if master:
            status = client.get_deck_status(master)
            print(f"{status.artist} - {status.title} @ {status.bpm} BPM")
"""

from __future__ import annotations

import time
import logging
import requests
from dataclasses import dataclass
from typing import Dict, Iterable, Optional, Tuple

logger = logging.getLogger('karaoke')


# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------

@dataclass
class DeckStatus:
    """
    Status information for a VirtualDJ deck.
    
    Attributes:
        deck: Deck number (1, 2, 3, or 4)
        title: Track title (empty string if no track loaded)
        artist: Track artist (empty string if no track loaded)
        bpm: Track BPM (0.0 if unknown or no track)
        position: Position in track from 0.0 to 1.0 (may exceed 1.0 briefly at end)
        elapsed_ms: Elapsed playback time in milliseconds (0 if not playing)
        length_sec: Total track length in seconds (0.0 if unknown)
    """
    deck: int
    title: str
    artist: str
    bpm: float              # 0.0 if unknown
    position: float         # 0.0–1.0 (may briefly exceed 1.0 at track end)
    elapsed_ms: int         # milliseconds elapsed
    length_sec: float       # total seconds


# ---------------------------------------------------------------------------
# Synchronous HTTP client
# ---------------------------------------------------------------------------

class VirtualDJClient:
    """
    Synchronous client for VirtualDJ's Network Control HTTP plugin.

    Usage:
        client = VirtualDJClient(base_url="http://127.0.0.1:8080")
        if client.is_connected():
            status = client.get_deck_status(deck=1)
    """
    
    DEFAULT_TIMEOUT = 2.0  # seconds

    def __init__(
        self,
        base_url: str = "http://127.0.0.1:8080",
        password: Optional[str] = None,
        timeout: float = DEFAULT_TIMEOUT,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.password = password
        self.timeout = timeout
        self._session = requests.Session()
        self._connected = False
        
        # Check connection on init
        self._check_connection()

    def _check_connection(self) -> None:
        """Check if VirtualDJ is reachable."""
        try:
            self.query("get_vdj_folder")
            self._connected = True
        except Exception:
            self._connected = False

    def is_connected(self) -> bool:
        """Check if connected to VirtualDJ."""
        return self._connected

    def _auth_params(self) -> Dict[str, str]:
        """Get authentication parameters for requests."""
        if not self.password:
            return {}
        return {"bearer": self.password}

    def query(self, script: str) -> str:
        """
        Run a VDJScript expression via /query and return the raw text result.
        """
        url = f"{self.base_url}/query"
        params = self._auth_params()
        headers = {"Content-Type": "text/plain; charset=utf-8"}

        resp = self._session.post(
            url,
            params=params,
            data=script.encode("utf-8"),
            headers=headers,
            timeout=self.timeout,
        )
        resp.raise_for_status()
        return resp.text.strip()

    def execute(self, script: str) -> bool:
        """
        Run a VDJScript command via /execute and return True/False based on response.
        """
        url = f"{self.base_url}/execute"
        params = self._auth_params()
        headers = {"Content-Type": "text/plain; charset=utf-8"}

        resp = self._session.post(
            url,
            params=params,
            data=script.encode("utf-8"),
            headers=headers,
            timeout=self.timeout,
        )
        resp.raise_for_status()
        text = resp.text.strip().lower()
        return text in {"1", "true", "ok", "success"}

    def get_deck_status(self, deck: int = 1) -> Optional[DeckStatus]:
        """
        Fetch artist, title, bpm, position, elapsed_ms and length_sec for a deck.

        Uses VDJScript verbs:
            deck X get_title
            deck X get_artist
            deck X get_bpm
            deck X get_position
            deck X get_time "elapsed"
            deck X get_songlength
        """
        prefix = f"deck {deck} "

        scripts = {
            "title":   prefix + "get_title",
            "artist":  prefix + "get_artist",
            "bpm":     prefix + "get_bpm",
            "pos":     prefix + "get_position",
            "elapsed": prefix + 'get_time "elapsed"',
            "length":  prefix + "get_songlength",
        }

        data: Dict[str, str] = {}
        try:
            for key, script in scripts.items():
                try:
                    data[key] = self.query(script)
                except Exception:
                    data[key] = ""
        except Exception:
            self._connected = False
            return None

        def _to_float(s: str, default: float = 0.0) -> float:
            try:
                return float(s.replace(",", "."))
            except Exception:
                return default

        def _to_int(s: str, default: int = 0) -> int:
            try:
                return int(float(s.replace(",", ".")))
            except Exception:
                return default

        return DeckStatus(
            deck=deck,
            title=data.get("title", ""),
            artist=data.get("artist", ""),
            bpm=_to_float(data.get("bpm", "")),
            position=_to_float(data.get("pos", "")),
            elapsed_ms=_to_int(data.get("elapsed", "")),
            length_sec=_to_float(data.get("length", "")),
        )

    def get_masterdeck(self, decks: Iterable[int] = (1, 2)) -> Optional[int]:
        """
        Return the current masterdeck number among `decks`,
        using `deck N masterdeck ? 1 : 0`.

        If none of the given decks is master, returns None.
        """
        deck_list = list(decks)

        for deck in deck_list:
            try:
                result = self.query(f"deck {deck} masterdeck ? 1 : 0")
                if result.strip() in {"1", "true", "yes"}:
                    return deck
            except Exception:
                continue

        return None

    def close(self) -> None:
        """Close the HTTP session."""
        self._session.close()
