"""Lyrics fetcher worker using vj_bus and ai_services LLM analyzer.

This worker responds to `fetch` commands with lyrics + metadata, performs
analysis using the LLMAnalyzer (with automatic fallback to deterministic basic
analysis), and streams telemetry + events for the TUI to consume.
"""

from __future__ import annotations

import logging
import threading
from typing import Any, Dict

from ai_services import LLMAnalyzer
from vj_bus import Envelope, WorkerNode

logger = logging.getLogger("lyrics_worker")


class LyricsFetcherWorker:
    def __init__(
        self,
        telemetry_port: int,
        command_endpoint: str,
        event_endpoint: str,
        schema: str = "vj.v1",
        heartbeat_interval: float = 1.0,
        enable_llm: bool = False,
        generation: int = 0,
        instance_id: str | None = None,
    ) -> None:
        self.node = WorkerNode(
            name="lyrics_fetcher",
            telemetry_port=telemetry_port,
            command_endpoint=command_endpoint,
            event_endpoint=event_endpoint,
            schema=schema,
            heartbeat_interval=heartbeat_interval,
            generation=generation,
            instance_id=instance_id,
        )
        self._llm = LLMAnalyzer() if enable_llm else None
        self._lock = threading.Lock()
        self._last_config: Dict[str, Any] = {}

        @self.node.command("fetch")
        def _fetch(env: Envelope) -> Envelope:  # noqa: ANN001
            with self._lock:
                self._last_config = {
                    "config_version": env.payload.config_version,
                    "artist": env.payload.data.get("artist", ""),
                    "title": env.payload.data.get("title", ""),
                }
            lyrics = env.payload.data.get("lyrics", "")
            artist = env.payload.data.get("artist", "")
            title = env.payload.data.get("title", "")
            analysis = self._analyze(lyrics=lyrics, artist=artist, title=title)
            self.node.send_telemetry(
                "lyrics_analysis",
                {
                    "artist": artist,
                    "title": title,
                    "analysis": analysis,
                    "config_version": env.payload.config_version,
                },
            )
            self.node.send_event("info", "lyrics_analyzed", {"title": title, "artist": artist})
            return self.node.ack(
                env,
                status="ok",
                message="analysis ready",
                applied_config_version=env.payload.config_version,
            )

        @self.node.command("state")
        def _state(env: Envelope) -> Envelope:  # noqa: ANN001
            return self.node.ack(env, status="ok", message="state", applied_config_version=self._last_config.get("config_version"))

    def _analyze(self, lyrics: str, artist: str, title: str) -> Dict[str, Any]:
        if self._llm:
            try:
                return self._llm.analyze_lyrics(lyrics, artist, title)
            except Exception as exc:  # noqa: BLE001
                logger.debug("LLM analyze failed, falling back: %s", exc)
        return self._basic_analysis(lyrics, artist, title)

    @staticmethod
    def _basic_analysis(lyrics: str, artist: str, title: str) -> Dict[str, Any]:
        tokens = [token for token in lyrics.replace("\n", " ").split(" ") if token]
        unique = sorted(set(token.lower() for token in tokens))
        top_keywords = unique[:5]
        themes = [t for t in ["love", "party", "night"] if t in unique]
        return {
            "artist": artist,
            "title": title,
            "keywords": top_keywords,
            "themes": themes or ["abstract"],
            "refrain_lines": lyrics.split("\n")[:2],
            "cached": False,
        }

    def start(self) -> None:
        self.node.start()

    def stop(self) -> None:
        self.node.stop()


if __name__ == "__main__":
    from vj_bus.utils import find_free_port

    telemetry_port = find_free_port()
    command_endpoint = f"tcp://127.0.0.1:{find_free_port()}"
    event_endpoint = f"tcp://127.0.0.1:{find_free_port()}"
    worker = LyricsFetcherWorker(
        telemetry_port=telemetry_port,
        command_endpoint=command_endpoint,
        event_endpoint=event_endpoint,
    )
    worker.start()
    print("LyricsFetcherWorker running", telemetry_port, command_endpoint)
