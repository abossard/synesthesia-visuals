#!/usr/bin/env python3
"""
VirtualDJ Remote API Client

Async HTTP client for VirtualDJ's Network Control plugin.

VirtualDJ Setup:
    - Install & enable the "Network Control" plugin (Effects -> Other)
    - Configure its port (e.g. 8080) and optional password
    - This client talks to:
        POST {base_url}/query   with VDJScript in the body (text/plain)
        POST {base_url}/execute likewise

This module provides:
    - VirtualDJClient: low-level async HTTP client
    - DeckStatus: track info for a deck
    - VirtualDJWatcher: polls masterdeck and calls callbacks

Events:
    - on_main_changed(status: DeckStatus, prev_deck: int | None)
        called when masterdeck OR track info on that deck changes
    - on_position(status: DeckStatus)
        called every `position_interval` seconds for the current masterdeck

Usage example:

    import asyncio
    from vdj_api import VirtualDJClient, VirtualDJWatcher, DeckStatus

    async def on_main_changed(status: DeckStatus, prev_deck: int | None):
        print(f"[MAIN] deck={status.deck} {status.artist} - {status.title}")

    async def on_position(status: DeckStatus):
        print(f"[POS] deck={status.deck} pos={status.position:.3f}")

    async def main():
        async with VirtualDJClient(base_url="http://127.0.0.1:8080") as client:
            watcher = VirtualDJWatcher(
                client,
                decks=(1, 2),
                poll_interval=0.5,
                position_interval=2.0,
                on_main_changed=on_main_changed,
                on_position=on_position,
            )
            await watcher.run()

    if __name__ == "__main__":
        asyncio.run(main())
"""

from __future__ import annotations

import asyncio
import time
import logging
from dataclasses import dataclass
from typing import Awaitable, Callable, Dict, Iterable, Optional, Tuple, Union

try:
    import aiohttp
    AIOHTTP_AVAILABLE = True
except ImportError:
    AIOHTTP_AVAILABLE = False
    aiohttp = None

logger = logging.getLogger('karaoke')


# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------

@dataclass
class DeckStatus:
    """Status information for a VirtualDJ deck."""
    deck: int
    title: str
    artist: str
    bpm: float              # track BPM
    position: float         # 0.0–1.0 position in track
    elapsed_ms: int         # elapsed time in ms
    length_sec: float       # full length in seconds


# ---------------------------------------------------------------------------
# Low-level HTTP client
# ---------------------------------------------------------------------------

class VirtualDJClient:
    """
    Async client for VirtualDJ's Network Control HTTP plugin.

    Use:

        async with VirtualDJClient(base_url="http://127.0.0.1:8080", password=None) as vdj:
            status = await vdj.get_deck_status(deck=1)
    """

    def __init__(
        self,
        base_url: str = "http://127.0.0.1:8080",
        password: Optional[str] = None,
        session: Optional["aiohttp.ClientSession"] = None,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.password = password
        self._external_session = session
        self._session: Optional["aiohttp.ClientSession"] = None

    async def __aenter__(self) -> "VirtualDJClient":
        if not AIOHTTP_AVAILABLE:
            raise RuntimeError("aiohttp is required for VirtualDJ API. Install with: pip install aiohttp")
        if self._external_session is None:
            self._session = aiohttp.ClientSession()
        return self

    async def __aexit__(self, exc_type, exc, tb) -> None:
        if self._session is not None:
            await self._session.close()
            self._session = None

    @property
    def session(self) -> "aiohttp.ClientSession":
        if self._external_session is not None:
            return self._external_session
        if self._session is None:
            raise RuntimeError(
                "ClientSession not initialised. Use 'async with VirtualDJClient(...)' "
                "or pass an existing aiohttp.ClientSession via session=."
            )
        return self._session

    def _auth_params(self) -> Dict[str, str]:
        """Get authentication parameters for requests."""
        if not self.password:
            return {}
        return {"bearer": self.password}

    async def query(self, script: str) -> str:
        """
        Run a VDJScript expression via /query and return the raw text result.
        """
        url = f"{self.base_url}/query"
        params = self._auth_params()
        headers = {"Content-Type": "text/plain; charset=utf-8"}

        async with self.session.post(
            url,
            params=params,
            data=script.encode("utf-8"),
            headers=headers,
        ) as resp:
            resp.raise_for_status()
            text = await resp.text()
            return text.strip()

    async def execute(self, script: str) -> bool:
        """
        Run a VDJScript command via /execute and return True/False based on response.
        """
        url = f"{self.base_url}/execute"
        params = self._auth_params()
        headers = {"Content-Type": "text/plain; charset=utf-8"}

        async with self.session.post(
            url,
            params=params,
            data=script.encode("utf-8"),
            headers=headers,
        ) as resp:
            resp.raise_for_status()
            text = (await resp.text()).strip().lower()
            return text in {"1", "true", "ok", "success"}

    async def get_deck_status(self, deck: int = 1) -> DeckStatus:
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

        coros = [self.query(s) for s in scripts.values()]
        results = await asyncio.gather(*coros, return_exceptions=True)

        data: Dict[str, str] = {}
        for key, res in zip(scripts.keys(), results):
            if isinstance(res, Exception):
                # On error, treat as empty string (we'll default below).
                data[key] = ""
            else:
                data[key] = res

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
            title=data["title"],
            artist=data["artist"],
            bpm=_to_float(data["bpm"]),
            position=_to_float(data["pos"]),
            elapsed_ms=_to_int(data["elapsed"]),
            length_sec=_to_float(data["length"]),
        )

    async def get_masterdeck(self, decks: Iterable[int]) -> Optional[int]:
        """
        Return the current masterdeck number among `decks`,
        using `deck N masterdeck ? 1 : 0`.

        If none of the given decks is master, returns None.
        """
        deck_list = list(decks)
        scripts = {
            d: f"deck {d} masterdeck ? 1 : 0"
            for d in deck_list
        }

        coros = [self.query(s) for s in scripts.values()]
        results = await asyncio.gather(*coros, return_exceptions=True)

        for deck, res in zip(deck_list, results):
            if isinstance(res, Exception):
                continue
            if res.strip() in {"1", "true", "yes"}:
                return deck
        return None

    async def check_connection(self) -> bool:
        """Check if VirtualDJ is reachable."""
        try:
            # Simple query to check if VDJ responds
            await self.query("get_vdj_folder")
            return True
        except Exception:
            return False


# ---------------------------------------------------------------------------
# Watcher
# ---------------------------------------------------------------------------

MainChangedCallback = Callable[[DeckStatus, Optional[int]], Union[Awaitable[None], None]]
PositionCallback = Callable[[DeckStatus], Union[Awaitable[None], None]]


class VirtualDJWatcher:
    """
    Watches the masterdeck and emits events:

        - on_main_changed(status, prev_deck)
            Called when:
              * the masterdeck changes, OR
              * the track info (artist/title/BPM/length) on the masterdeck changes.

        - on_position(status)
            Called every `position_interval` seconds
            for the current masterdeck, if any.

    Polling:
        - poll_interval: base loop interval (seconds)
        - position_interval: minimum seconds between position events

    NOTE:
        This class does not create its own task; call `await run()` in a task:

            watcher = VirtualDJWatcher(client, on_main_changed=..., on_position=...)
            task = asyncio.create_task(watcher.run())

        To stop, call `watcher.stop()` or cancel the task.
    """

    def __init__(
        self,
        client: VirtualDJClient,
        *,
        decks: Iterable[int] = (1, 2),
        poll_interval: float = 0.5,
        position_interval: float = 2.0,
        on_main_changed: Optional[MainChangedCallback] = None,
        on_position: Optional[PositionCallback] = None,
    ) -> None:
        self.client = client
        self.decks = tuple(decks)
        self.poll_interval = poll_interval
        self.position_interval = position_interval
        self.on_main_changed = on_main_changed
        self.on_position = on_position

        self._running = False
        self._last_main_deck: Optional[int] = None
        self._last_meta_key: Optional[Tuple] = None
        self._last_pos_emit: float = 0.0

    def stop(self) -> None:
        """Stop the watcher loop."""
        self._running = False

    @property
    def is_running(self) -> bool:
        """Check if watcher is currently running."""
        return self._running

    @property
    def last_deck(self) -> Optional[int]:
        """Get the last known masterdeck."""
        return self._last_main_deck

    async def _call_main_changed(
        self,
        status: DeckStatus,
        prev_deck: Optional[int],
    ) -> None:
        if not self.on_main_changed:
            return
        cb = self.on_main_changed
        if asyncio.iscoroutinefunction(cb):
            await cb(status, prev_deck)
        else:
            loop = asyncio.get_running_loop()
            await loop.run_in_executor(None, cb, status, prev_deck)

    async def _call_position(self, status: DeckStatus) -> None:
        if not self.on_position:
            return
        cb = self.on_position
        if asyncio.iscoroutinefunction(cb):
            await cb(status)
        else:
            loop = asyncio.get_running_loop()
            await loop.run_in_executor(None, cb, status)

    async def run(self) -> None:
        """
        Main loop: follow masterdeck, emit events.

        - Follows VirtualDJ's masterdeck (via `deck N masterdeck ?`).
        - When masterdeck or its track metadata changes, emits on_main_changed.
        - Every `position_interval` seconds, emits on_position for current masterdeck.
        """
        self._running = True
        self._last_pos_emit = time.monotonic()

        while self._running:
            try:
                master = await self.client.get_masterdeck(self.decks)
            except Exception:
                # If query fails (VDJ not running etc.), just wait and retry.
                master = None

            if master is not None:
                try:
                    status = await self.client.get_deck_status(master)
                except Exception:
                    status = None

                if status is not None:
                    # Build "meta" key ignoring position/elapsed.
                    meta_key = (
                        status.deck,
                        status.title,
                        status.artist,
                        round(status.bpm, 2),
                        round(status.length_sec, 2),
                    )

                    # MAIN CHANGED?
                    if (
                        master != self._last_main_deck
                        or meta_key != self._last_meta_key
                    ):
                        prev = self._last_main_deck
                        self._last_main_deck = master
                        self._last_meta_key = meta_key
                        await self._call_main_changed(status, prev)

                    # POSITION EVENT?
                    now = time.monotonic()
                    if now - self._last_pos_emit >= self.position_interval:
                        self._last_pos_emit = now
                        await self._call_position(status)

            await asyncio.sleep(self.poll_interval)

    async def poll_once(self) -> Optional[DeckStatus]:
        """
        Poll once and return the current deck status without triggering callbacks.
        Useful for synchronous integration.
        """
        try:
            master = await self.client.get_masterdeck(self.decks)
            if master is not None:
                return await self.client.get_deck_status(master)
        except Exception:
            pass
        return None
