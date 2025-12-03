#!/usr/bin/env python3
"""
Lyrics Fetcher Worker - Fetches and analyzes lyrics with LLM.

Fetches synced lyrics from LRCLIB API and analyzes them using AI (OpenAI/Ollama).

Usage:
    python workers/lyrics_fetcher_worker.py
"""

import time
import logging
import sys
from pathlib import Path
from typing import Dict, Any, Optional, List
from dataclasses import asdict

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from vj_bus.worker import WorkerBase
from vj_bus.messages import WorkerStatePayload

# Import existing adapters and services
try:
    from adapters import LyricsFetcher
    from ai_services import LLMAnalyzer, SongCategorizer
    from domain import parse_lrc, LyricLine
    LYRICS_AVAILABLE = True
except ImportError as e:
    LYRICS_AVAILABLE = False
    LyricsFetcher = None
    LLMAnalyzer = None
    SongCategorizer = None
    parse_lrc = None
    logging.warning(f"Lyrics/AI modules not available: {e}")

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

logger = logging.getLogger('lyrics_fetcher_worker')


class LyricsFetcherWorker(WorkerBase):
    """
    Lyrics fetcher and analyzer worker.

    Fetches synced lyrics and performs AI analysis for keyword extraction,
    theme detection, and mood categorization.
    """

    def __init__(self):
        super().__init__(
            name="lyrics_fetcher",
            command_port=5033,
            telemetry_port=5034,
            config={
                "enable_llm": True,
                "enable_categorization": True,
            }
        )

        if not LYRICS_AVAILABLE:
            logger.warning("Lyrics/AI modules not available")

        self.lyrics_fetcher: Optional[Any] = None
        self.llm_analyzer: Optional[Any] = None
        self.categorizer: Optional[Any] = None
        self.current_track_key = ""
        self.lyrics_cache_hits = 0
        self.lyrics_cache_misses = 0
        self.llm_analyses = 0

    def on_start(self):
        """Initialize lyrics fetcher and LLM analyzer."""
        logger.info("Starting lyrics fetcher worker...")

        try:
            if LYRICS_AVAILABLE:
                self.lyrics_fetcher = LyricsFetcher()

                if self.config.get("enable_llm", True):
                    self.llm_analyzer = LLMAnalyzer()
                    logger.info(f"LLM backend: {self.llm_analyzer.backend_info}")

                    if self.config.get("enable_categorization", True):
                        self.categorizer = SongCategorizer(llm=self.llm_analyzer)
                        logger.info("Categorizer enabled")

            logger.info("Lyrics fetcher worker initialized")
        except Exception as e:
            logger.error(f"Failed to initialize lyrics fetcher: {e}")
            raise

    def run(self):
        """Main loop - wait for commands."""
        logger.info("Lyrics fetcher worker running")

        # This worker is command-driven, not polling
        # It processes fetch requests via handle_command()
        while self.running:
            time.sleep(1)

        logger.info("Lyrics fetcher worker loop exited")

    def handle_command(self, command: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        """Handle commands for lyrics fetching."""

        if command == "fetch_lyrics":
            return self._handle_fetch_lyrics(payload)

        elif command == "analyze_lyrics":
            return self._handle_analyze_lyrics(payload)

        elif command == "categorize_song":
            return self._handle_categorize_song(payload)

        elif command == "fetch_and_analyze":
            # Combined command: fetch + analyze + categorize
            return self._handle_fetch_and_analyze(payload)

        else:
            return super().handle_command(command, payload)

    def _handle_fetch_lyrics(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        """Fetch lyrics for a track."""
        artist = payload.get("artist", "")
        title = payload.get("title", "")
        album = payload.get("album", "")
        duration = payload.get("duration", 0)

        if not artist or not title:
            return {"success": False, "error": "Missing artist or title"}

        try:
            if not self.lyrics_fetcher:
                return {"success": False, "error": "Lyrics fetcher not available"}

            lrc_text = self.lyrics_fetcher.fetch(artist, title, album, duration)

            if lrc_text:
                self.lyrics_cache_misses += 1

                # Parse LRC text into structured lines
                lines = parse_lrc(lrc_text) if parse_lrc else []

                # Publish telemetry
                self.publish_telemetry("lyrics.fetched", {
                    "artist": artist,
                    "title": title,
                    "has_lyrics": True,
                    "line_count": len(lines),
                    "lrc_text": lrc_text,
                    "timestamp": time.time(),
                })

                return {
                    "success": True,
                    "has_lyrics": True,
                    "lrc_text": lrc_text,
                    "line_count": len(lines),
                }
            else:
                return {
                    "success": True,
                    "has_lyrics": False,
                    "message": "No lyrics found"
                }

        except Exception as e:
            logger.error(f"Error fetching lyrics: {e}")
            return {"success": False, "error": str(e)}

    def _handle_analyze_lyrics(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        """Analyze lyrics with LLM."""
        lyrics = payload.get("lyrics", "")
        artist = payload.get("artist", "")
        title = payload.get("title", "")

        if not lyrics:
            return {"success": False, "error": "Missing lyrics"}

        try:
            if not self.llm_analyzer:
                return {"success": False, "error": "LLM analyzer not available"}

            result = self.llm_analyzer.analyze_lyrics(lyrics, artist, title)
            self.llm_analyses += 1

            # Publish telemetry
            self.publish_telemetry("lyrics.analyzed", {
                "artist": artist,
                "title": title,
                "refrain_lines": result.get("refrain_lines", []),
                "keywords": result.get("keywords", []),
                "themes": result.get("themes", []),
                "cached": result.get("cached", False),
                "timestamp": time.time(),
            })

            return {
                "success": True,
                "analysis": result
            }

        except Exception as e:
            logger.error(f"Error analyzing lyrics: {e}")
            return {"success": False, "error": str(e)}

    def _handle_categorize_song(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        """Categorize song by mood/theme."""
        artist = payload.get("artist", "")
        title = payload.get("title", "")
        lyrics = payload.get("lyrics", "")
        album = payload.get("album", "")

        if not artist or not title:
            return {"success": False, "error": "Missing artist or title"}

        try:
            if not self.categorizer:
                return {"success": False, "error": "Categorizer not available"}

            categories = self.categorizer.categorize(artist, title, lyrics, album)

            # Publish telemetry
            self.publish_telemetry("song.categorized", {
                "artist": artist,
                "title": title,
                "categories": categories.get_dict(),
                "primary_mood": categories.primary_mood,
                "timestamp": time.time(),
            })

            return {
                "success": True,
                "categories": categories.get_dict(),
                "primary_mood": categories.primary_mood,
            }

        except Exception as e:
            logger.error(f"Error categorizing song: {e}")
            return {"success": False, "error": str(e)}

    def _handle_fetch_and_analyze(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        """Combined command: fetch lyrics, analyze, and categorize."""
        artist = payload.get("artist", "")
        title = payload.get("title", "")
        album = payload.get("album", "")
        duration = payload.get("duration", 0)
        track_key = payload.get("track_key", f"{artist}_{title}")

        if not artist or not title:
            return {"success": False, "error": "Missing artist or title"}

        # Update current track
        self.current_track_key = track_key

        result = {
            "success": True,
            "artist": artist,
            "title": title,
            "has_lyrics": False,
        }

        # Step 1: Fetch lyrics
        fetch_result = self._handle_fetch_lyrics(payload)
        if fetch_result.get("success") and fetch_result.get("has_lyrics"):
            result["has_lyrics"] = True
            result["lrc_text"] = fetch_result.get("lrc_text", "")
            result["line_count"] = fetch_result.get("line_count", 0)

            lrc_text = fetch_result.get("lrc_text", "")

            # Step 2: Analyze lyrics
            if self.config.get("enable_llm", True) and self.llm_analyzer:
                analyze_payload = {
                    "lyrics": lrc_text,
                    "artist": artist,
                    "title": title,
                }
                analyze_result = self._handle_analyze_lyrics(analyze_payload)
                if analyze_result.get("success"):
                    result["analysis"] = analyze_result.get("analysis", {})

            # Step 3: Categorize song
            if self.config.get("enable_categorization", True) and self.categorizer:
                categorize_payload = {
                    "artist": artist,
                    "title": title,
                    "lyrics": lrc_text,
                    "album": album,
                }
                categorize_result = self._handle_categorize_song(categorize_payload)
                if categorize_result.get("success"):
                    result["categories"] = categorize_result.get("categories", {})
                    result["primary_mood"] = categorize_result.get("primary_mood", "")

        return result

    def get_state(self) -> WorkerStatePayload:
        """Return current state."""
        return WorkerStatePayload(
            status="running" if self.running else "stopped",
            uptime_sec=time.time() - self.started_at,
            config=self.config,
            metrics={
                "lyrics_cached": self.lyrics_fetcher.get_cached_count() if self.lyrics_fetcher else 0,
                "cache_hits": self.lyrics_cache_hits,
                "cache_misses": self.lyrics_cache_misses,
                "llm_analyses": self.llm_analyses,
                "llm_backend": self.llm_analyzer.backend_info if self.llm_analyzer else "none",
                "current_track": self.current_track_key,
            }
        )

    def get_metadata(self) -> Dict[str, Any]:
        """Return metadata for registry."""
        return {
            "version": "1.0",
            "platform": "cross-platform",
            "features": ["lyrics_fetch", "llm_analysis", "categorization"],
            "backends": {
                "lyrics": "LRCLIB",
                "llm": self.llm_analyzer.backend_info if self.llm_analyzer else "none",
            }
        }


def main():
    """Entry point."""
    worker = LyricsFetcherWorker()

    logger.info("=" * 60)
    logger.info("Lyrics Fetcher Worker Starting")
    logger.info("=" * 60)
    logger.info(f"PID: {worker.pid}")
    logger.info("=" * 60)

    try:
        worker.start()
    except Exception as e:
        logger.exception(f"Worker failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
