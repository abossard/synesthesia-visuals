#!/usr/bin/env python3
"""
Lyrics Fetcher Worker - Standalone Process

Fetches lyrics and performs LLM analysis for karaoke/VJ features.
Runs as independent process with lyrics API and LLM integration.
"""

import os
import sys
import logging
import time
from pathlib import Path
from typing import Optional, Dict, Any

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent))

from vj_bus import Worker
from vj_bus.schema import CommandMessage, AckMessage

# Try to import lyrics and LLM services
try:
    from adapters import LyricsFetcher
    LYRICS_AVAILABLE = True
except ImportError:
    LYRICS_AVAILABLE = False
    LyricsFetcher = None

try:
    from ai_services import LLMAnalyzer, SongCategorizer
    LLM_AVAILABLE = True
except ImportError:
    LLM_AVAILABLE = False
    LLMAnalyzer = None
    SongCategorizer = None

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('vj_lyrics_worker')


class LyricsWorker(Worker):
    """
    Lyrics fetcher worker process.
    
    Provides:
    - Lyrics fetching from LRCLIB API
    - LLM analysis (refrain detection, keywords, categories, image prompts)
    - Control socket at /tmp/vj-bus/lyrics_fetcher.sock
    - OSC output for lyrics and analysis results
    - Subscribe to track changes via polling or explicit commands
    """
    
    OSC_ADDRESSES = [
        "/karaoke/lyrics",
        "/karaoke/analysis",
        "/karaoke/categories",
        "/karaoke/refrain",
    ]
    
    def __init__(self):
        super().__init__(
            name="lyrics_fetcher",
            osc_addresses=self.OSC_ADDRESSES
        )
        
        self.lyrics_fetcher: Optional[Any] = None
        self.llm_analyzer: Optional[Any] = None
        self.categorizer: Optional[Any] = None
        
        self.current_track = {"artist": "", "title": ""}
        self.current_lyrics = None
        self.current_analysis = None
        
        self.llm_enabled = True
        self.categorization_enabled = True
        self.auto_fetch = True
        
        logger.info("Lyrics worker initialized")
    
    def on_start(self):
        """Initialize lyrics fetcher and LLM services."""
        logger.info("Starting lyrics fetcher...")
        
        # Initialize lyrics fetcher
        if LYRICS_AVAILABLE:
            try:
                self.lyrics_fetcher = LyricsFetcher()
                logger.info("Lyrics fetcher initialized")
            except Exception as e:
                logger.exception(f"Failed to initialize lyrics fetcher: {e}")
                self.lyrics_fetcher = None
        else:
            logger.warning("LyricsFetcher not available - lyrics disabled")
        
        # Initialize LLM services
        if LLM_AVAILABLE and self.llm_enabled:
            try:
                self.llm_analyzer = LLMAnalyzer()
                self.categorizer = SongCategorizer(llm=self.llm_analyzer)
                logger.info(f"LLM initialized: {self.llm_analyzer.backend_info}")
            except Exception as e:
                logger.exception(f"Failed to initialize LLM: {e}")
                self.llm_analyzer = None
                self.categorizer = None
        else:
            logger.info("LLM analysis disabled")
        
        logger.info("Lyrics worker started")
    
    def on_stop(self):
        """Stop lyrics fetcher."""
        logger.info("Stopping lyrics worker...")
        self.lyrics_fetcher = None
        self.llm_analyzer = None
        self.categorizer = None
        logger.info("Lyrics worker stopped")
    
    def on_command(self, cmd: CommandMessage) -> AckMessage:
        """Handle commands from TUI/process manager."""
        if cmd.cmd == "get_state":
            return AckMessage(
                success=True,
                data={
                    "status": "running" if self.lyrics_fetcher else "stopped",
                    "llm_enabled": self.llm_enabled,
                    "llm_available": self.llm_analyzer is not None,
                    "llm_backend": self.llm_analyzer.backend_info if self.llm_analyzer else "none",
                    "cached_count": self.lyrics_fetcher.get_cached_count() if self.lyrics_fetcher else 0,
                    "current_track": self.current_track,
                    "has_lyrics": self.current_lyrics is not None,
                }
            )
        
        elif cmd.cmd == "fetch_lyrics":
            # Explicit request to fetch lyrics for a track
            artist = getattr(cmd, 'artist', '')
            title = getattr(cmd, 'title', '')
            
            if not artist or not title:
                return AckMessage(success=False, message="artist and title required")
            
            try:
                self._fetch_and_analyze(artist, title)
                return AckMessage(success=True, message="Lyrics fetched and analyzed")
            except Exception as e:
                logger.exception(f"Error fetching lyrics: {e}")
                return AckMessage(success=False, message=f"Fetch failed: {e}")
        
        elif cmd.cmd == "set_config":
            try:
                if hasattr(cmd, 'llm_enabled'):
                    self.llm_enabled = bool(cmd.llm_enabled)
                    if self.llm_enabled and not self.llm_analyzer and LLM_AVAILABLE:
                        # Re-initialize LLM
                        self.llm_analyzer = LLMAnalyzer()
                        self.categorizer = SongCategorizer(llm=self.llm_analyzer)
                
                if hasattr(cmd, 'categorization_enabled'):
                    self.categorization_enabled = bool(cmd.categorization_enabled)
                
                if hasattr(cmd, 'auto_fetch'):
                    self.auto_fetch = bool(cmd.auto_fetch)
                
                return AckMessage(success=True, message="Config updated")
            except Exception as e:
                logger.exception(f"Error updating config: {e}")
                return AckMessage(success=False, message=f"Config update failed: {e}")
        
        elif cmd.cmd == "restart":
            try:
                self.on_stop()
                self.on_start()
                return AckMessage(success=True, message="Restarted")
            except Exception as e:
                logger.exception(f"Restart failed: {e}")
                return AckMessage(success=False, message=f"Restart failed: {e}")
        
        else:
            return AckMessage(success=False, message=f"Unknown command: {cmd.cmd}")
    
    def get_stats(self) -> dict:
        """Get current stats for heartbeat."""
        return {
            "running": self.lyrics_fetcher is not None,
            "llm_enabled": self.llm_enabled,
            "llm_available": self.llm_analyzer is not None,
            "cached_count": self.lyrics_fetcher.get_cached_count() if self.lyrics_fetcher else 0,
        }
    
    def _fetch_and_analyze(self, artist: str, title: str):
        """Fetch lyrics and perform LLM analysis."""
        if not self.lyrics_fetcher:
            logger.warning("Lyrics fetcher not available")
            return
        
        # Update current track
        self.current_track = {"artist": artist, "title": title}
        
        # Fetch lyrics
        logger.info(f"Fetching lyrics for: {artist} - {title}")
        
        try:
            lyrics = self.lyrics_fetcher.fetch_lyrics(artist, title)
            
            if lyrics:
                self.current_lyrics = lyrics
                
                # Emit lyrics via OSC
                # Format: [artist, title, lyrics_text, has_timestamps]
                has_timestamps = bool(lyrics.get('syncedLyrics'))
                lyrics_text = lyrics.get('syncedLyrics') or lyrics.get('plainLyrics', '')
                
                self.telemetry.send("/karaoke/lyrics", [
                    artist,
                    title,
                    lyrics_text[:500],  # Truncate for OSC
                    1 if has_timestamps else 0
                ])
                
                # Perform LLM analysis if enabled
                if self.llm_enabled and self.llm_analyzer:
                    self._analyze_lyrics(artist, title, lyrics_text)
                
                logger.info(f"Lyrics fetched successfully for {artist} - {title}")
            else:
                logger.info(f"No lyrics found for {artist} - {title}")
                self.current_lyrics = None
        
        except Exception as e:
            logger.exception(f"Error fetching lyrics: {e}")
            self.current_lyrics = None
    
    def _analyze_lyrics(self, artist: str, title: str, lyrics_text: str):
        """Perform LLM analysis on lyrics."""
        if not self.llm_analyzer:
            return
        
        try:
            logger.info(f"Analyzing lyrics with LLM...")
            
            # Get song categories
            if self.categorization_enabled and self.categorizer:
                categories = self.categorizer.categorize_song(artist, title, lyrics_text)
                
                if categories:
                    self.current_analysis = {
                        "categories": categories,
                        "timestamp": time.time()
                    }
                    
                    # Emit categories via OSC
                    # Format: [artist, title, vibe, tempo, genre, mood, category_name, keywords...]
                    self.telemetry.send("/karaoke/categories", [
                        artist,
                        title,
                        categories.vibe,
                        categories.tempo,
                        categories.genre,
                        categories.mood,
                        categories.category_name,
                    ] + list(categories.keywords[:5]))  # Send up to 5 keywords
                    
                    logger.info(f"Analysis complete: {categories.category_name}")
        
        except Exception as e:
            logger.exception(f"Error analyzing lyrics: {e}")


def main():
    """Main entry point for lyrics worker."""
    logger.info("=" * 60)
    logger.info("Lyrics Fetcher Worker starting...")
    logger.info(f"PID: {os.getpid()}")
    logger.info(f"Lyrics API available: {LYRICS_AVAILABLE}")
    logger.info(f"LLM available: {LLM_AVAILABLE}")
    logger.info("=" * 60)
    
    if not LYRICS_AVAILABLE:
        logger.warning("LyricsFetcher not available - lyrics fetching disabled")
        logger.info("This worker will still run but won't fetch lyrics")
    
    worker = LyricsWorker()
    try:
        worker.start()
    except KeyboardInterrupt:
        logger.info("Keyboard interrupt received")
    except Exception as e:
        logger.exception(f"Fatal error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
