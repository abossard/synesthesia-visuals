#!/usr/bin/env python3
"""
Orchestrators - Focused coordinators with dependency injection

Splits the monolithic KaraokeEngine into specialized coordinators:
- PlaybackCoordinator: Monitors music sources, detects track changes
- LyricsOrchestrator: Fetches and processes lyrics
- AIOrchestrator: Manages background AI tasks (LLM, categorization, image gen)
"""

import time
import logging
from dataclasses import dataclass
from queue import Queue, Full, Empty
from threading import Thread, Event
from typing import Optional, List, Dict, Any

from domain import Track, PlaybackState, parse_lrc, analyze_lyrics
from infrastructure import PipelineTracker, Config
from typing import Optional, List, Dict, Any
from adapters import LyricsFetcher, OSCSender
from ai_services import LLMAnalyzer, SongCategorizer

logger = logging.getLogger('karaoke')


# =============================================================================
# PLAYBACK COORDINATOR - Single source monitor with timing
# =============================================================================


@dataclass(frozen=True)
class PlaybackSample:
    """Result of a playback poll."""
    state: PlaybackState
    source: str
    track_changed: bool
    monitor_status: Dict[str, Dict[str, Any]]
    last_lookup_ms: float = 0.0
    error: Optional[str] = None


class PlaybackCoordinator:
    """
    Monitors playback from a single user-selected source.
    
    No fallback logic - user explicitly selects which source to use.
    Tracks lookup duration for performance monitoring.
    
    Interface:
        poll() -> PlaybackSample
        get_current_state() -> PlaybackState
        set_monitor(monitor) - hot-swap the active monitor
    
    Dependency Injection: Accepts single monitor instance.
    """
    
    def __init__(self, monitor=None):
        self._monitor = monitor
        self._state = PlaybackState()
        self._current_source = "none"
        self._last_lookup_ms = 0.0
        self._was_connected = False  # Track connection state for logging
        self._last_track_key = ""    # Track for change detection
    
    def set_monitor(self, monitor):
        """Hot-swap the active monitor for live source switching."""
        self._monitor = monitor
        self._current_source = self._monitor_key(monitor) if monitor else "none"
        self._was_connected = False  # Reset connection state for new monitor
        logger.info(f"Playback source: switching to {self._current_source}")
    
    @property
    def last_lookup_ms(self) -> float:
        """Duration of last poll() call in milliseconds."""
        return self._last_lookup_ms
    
    def poll(self) -> PlaybackSample:
        """Poll the active monitor and return sample with timing."""
        prev_key = self._state.track.key if self._state.track else ""
        error = None
        
        if not self._monitor:
            self._current_source = "none"
            self._last_lookup_ms = 0.0
            return PlaybackSample(
                state=self._state,
                source="none",
                track_changed=False,
                monitor_status={},
                last_lookup_ms=0.0,
                error="No monitor configured"
            )
        
        # Time the lookup
        start = time.time()
        playback = self._monitor.get_playback()
        self._last_lookup_ms = (time.time() - start) * 1000.0
        
        self._current_source = self._monitor_key(self._monitor)
        
        # Update state if we have playback
        if playback:
            track = Track(
                artist=playback['artist'],
                title=playback['title'],
                album=playback.get('album', ''),
                duration=playback.get('duration_ms', 0) / 1000.0
            )
            position = playback.get('progress_ms', 0) / 1000.0
            
            # Log connection success on first successful poll
            if not self._was_connected:
                self._was_connected = True
                logger.info(f"✓ {self._current_source}: connected - {track.artist} - {track.title}")
            
            # Log track changes
            track_key = track.key
            if track_key != self._last_track_key:
                self._last_track_key = track_key
                if self._was_connected:  # Don't double-log initial connection
                    logger.info(f"♪ Now playing: {track.artist} - {track.title}")
            
            # Update state immutably
            self._state = self._state.update(
                track=track,
                position=position,
                is_playing=True,
                last_update=time.time()
            )
        else:
            # No playback detected - log disconnection
            if self._was_connected:
                self._was_connected = False
                logger.info(f"○ {self._current_source}: no playback detected")
            
            if self._state.has_track:
                self._state = self._state.update(is_playing=False)
        
        current_key = self._state.track.key if self._state.track else ""
        track_changed = current_key != prev_key
        return PlaybackSample(
            state=self._state,
            source=self._current_source,
            track_changed=track_changed,
            monitor_status=self._collect_status(),
            last_lookup_ms=self._last_lookup_ms,
            error=error
        )

    def get_current_state(self) -> PlaybackState:
        """Return last known playback state without polling."""
        return self._state
    
    @property
    def current_track(self) -> Optional[Track]:
        return self._state.track
    
    @property
    def current_source(self) -> str:
        """Return the name of the current playback source."""
        return self._current_source

    def _collect_status(self) -> Dict[str, Dict[str, Any]]:
        """Gather monitor ServiceHealth status."""
        if not self._monitor:
            return {}
        name = self._monitor_key(self._monitor)
        status_attr = getattr(self._monitor, 'status', None)
        if callable(status_attr):
            return {name: status_attr()}
        elif status_attr is not None:
            return {name: status_attr}
        return {}

    def _monitor_key(self, monitor) -> str:
        if not monitor:
            return "none"
        return getattr(monitor, 'monitor_key', monitor.__class__.__name__.replace("Monitor", "").lower())


# =============================================================================
# LYRICS ORCHESTRATOR - Fetches and processes lyrics
# =============================================================================

class LyricsOrchestrator:
    """
    Orchestrates lyrics fetching, parsing, analysis, and song metadata.
    
    Interface:
        process_track(track, timing_offset_ms) -> Optional[List[LyricLine]]
        fetch_metadata(track) -> Dict  # LLM-powered: plain lyrics, keywords, song info
    
    Dependency Injection: LyricsFetcher, PipelineTracker
    """
    
    def __init__(self, fetcher: LyricsFetcher, pipeline: PipelineTracker):
        self._fetcher = fetcher
        self._pipeline = pipeline
        self._current_metadata = None
    
    def process_track(self, track: Track, timing_offset_ms: int = 0) -> Optional[List]:
        """
        Fetch and analyze LRC lyrics for karaoke timing.
        Returns list of LyricLine objects or None if no LRC lyrics found.
        """
        self._pipeline.start("fetch_lyrics")
        
        # Fetch synced LRC lyrics
        lrc_text = self._fetcher.fetch(track.artist, track.title, track.album, track.duration)
        
        if not lrc_text:
            reason = "No LRC available"
            self._pipeline.skip("fetch_lyrics", reason)
            self._pipeline.start("parse_lrc")
            self._pipeline.skip("parse_lrc", reason)
            self._pipeline.start("analyze_refrain")
            self._pipeline.skip("analyze_refrain", reason)
            self._pipeline.start("extract_keywords")
            self._pipeline.skip("extract_keywords", reason)
            return None
        
        self._pipeline.complete("fetch_lyrics", f"{len(lrc_text)} bytes")
        
        # Parse LRC
        self._pipeline.start("parse_lrc")
        lines = parse_lrc(lrc_text)
        if not lines:
            self._pipeline.error("parse_lrc", "Failed to parse")
            self._pipeline.skip("analyze_refrain", "Parse failed")
            self._pipeline.skip("extract_keywords", "Parse failed")
            return None
        self._pipeline.complete("parse_lrc", f"{len(lines)} lines")
        
        # Apply timing offset
        if timing_offset_ms != 0:
            offset_sec = timing_offset_ms / 1000.0
            from dataclasses import replace
            lines = [replace(line, time_sec=line.time_sec + offset_sec) for line in lines]
        
        # Analyze (detect refrains, extract keywords)
        self._pipeline.start("analyze_refrain")
        lines = analyze_lyrics(lines)
        self._pipeline.complete("analyze_refrain", f"{sum(1 for line in lines if line.is_refrain)} refrain lines")
        
        # Extract keyword stats for pipeline display
        self._pipeline.start("extract_keywords")
        keyword_tokens = []
        for line in lines:
            if line.keywords:
                keyword_tokens.extend(line.keywords.split())
        if keyword_tokens:
            unique_keywords = len({kw.lower() for kw in keyword_tokens})
            self._pipeline.complete(
                "extract_keywords",
                f"{unique_keywords} unique / {len(keyword_tokens)} total"
            )
        else:
            self._pipeline.skip("extract_keywords", "No keywords found")
        
        return lines
    
    def fetch_metadata(self, track: Track) -> Dict[str, Any]:
        """
        Fetch song metadata via LLM: plain lyrics, keywords, song info.
        Always returns a dict (may be empty if LLM unavailable).
        """
        self._pipeline.start("fetch_song_info")
        
        metadata = self._fetcher.fetch_metadata(track.artist, track.title)
        
        if metadata:
            self._current_metadata = metadata
            details = []
            if metadata.get('keywords'):
                kw_count = len(metadata['keywords']) if isinstance(metadata['keywords'], list) else 0
                details.append(f"{kw_count} keywords")
            if metadata.get('release_date'):
                details.append(str(metadata['release_date']))
            if metadata.get('genre'):
                genre = metadata['genre']
                details.append(genre if isinstance(genre, str) else genre[0] if genre else '')
            self._pipeline.complete("fetch_song_info", ', '.join(details) if details else "metadata found")
        else:
            self._current_metadata = {}
            self._pipeline.skip("fetch_song_info", "LLM unavailable")
        
        return metadata or {}
    
    # Backwards compatibility
    def fetch_song_info(self, track: Track) -> Optional[Dict[str, Any]]:
        """Alias for fetch_metadata."""
        result = self.fetch_metadata(track)
        return result if result else None
    
    @property
    def current_song_info(self) -> Optional[Dict[str, Any]]:
        """Get current song metadata (backwards compat)."""
        return self._current_metadata
    
    @property
    def current_metadata(self) -> Dict[str, Any]:
        """Get current song metadata."""
        return self._current_metadata or {}


# =============================================================================
# AI ORCHESTRATOR - Background AI processing
# =============================================================================

class AIOrchestrator:
    """
    Manages background AI tasks: LLM analysis, categorization, image generation.
    
    Interface:
        queue_analysis(track, lrc_text)
        queue_categorization(track, lrc_text)
        start() / stop()
    
    Dependency Injection: LLMAnalyzer, SongCategorizer, PipelineTracker, OSCSender
    """
    
    def __init__(self, llm: LLMAnalyzer, categorizer: SongCategorizer, 
                 pipeline: PipelineTracker, osc: OSCSender):
        self._llm = llm
        self._categorizer = categorizer
        self._pipeline = pipeline
        self._osc = osc
        
        # Background workers
        self._llm_queue = Queue(maxsize=5)
        self._cat_queue = Queue(maxsize=5)
        self._llm_worker = None
        self._cat_worker = None
        self._stop_event = Event()
        
        # Current state (for vj_console.py)
        self._current_categories = None
        self._last_llm_result = None  # Store keywords/themes for shader matching
    
    @property
    def current_categories(self):
        """Get current song categories."""
        return self._current_categories
    
    @property
    def last_llm_result(self) -> Optional[Dict[str, Any]]:
        """Get last LLM analysis result (keywords, themes)."""
        return self._last_llm_result
    
    def start(self):
        """Start background worker threads."""
        if not self._llm_worker:
            self._llm_worker = Thread(target=self._llm_worker_loop, daemon=True, name="LLM-Worker")
            self._llm_worker.start()
        
        if not self._cat_worker:
            self._cat_worker = Thread(target=self._cat_worker_loop, daemon=True, name="Cat-Worker")
            self._cat_worker.start()
    
    def stop(self):
        """Stop background workers."""
        self._stop_event.set()
        if self._llm_worker:
            self._llm_worker.join(timeout=2)
        if self._cat_worker:
            self._cat_worker.join(timeout=2)
    
    def queue_analysis(self, track: Track, lrc_text: str):
        """Queue LLM analysis task."""
        try:
            self._llm_queue.put_nowait((track, lrc_text))
        except Full:
            logger.debug("LLM queue full, skipping")
    
    def queue_categorization(self, track: Track, lrc_text: str):
        """Queue categorization task."""
        try:
            self._cat_queue.put_nowait((track, lrc_text))
            logger.info(f"Queued categorization: {track.artist} - {track.title}")
        except Full:
            logger.warning("Categorization queue full, skipping")
    
    # Private worker loops
    
    def _llm_worker_loop(self):
        """Background worker for LLM analysis and image generation."""
        while not self._stop_event.is_set():
            try:
                track, lrc_text = self._llm_queue.get(timeout=1)
                
                # LLM analysis
                if self._llm.is_available:
                    self._pipeline.start("llm_analysis")
                    result = self._llm.analyze_lyrics(lrc_text, track.artist, track.title)
                    if result:
                        self._pipeline.complete("llm_analysis", f"{len(result.get('keywords', []))} keywords")
                        
                        # Store LLM results for shader matching
                        self._last_llm_result = result
                    else:
                        self._pipeline.skip("llm_analysis", "LLM unavailable")
                else:
                    self._pipeline.skip("llm_analysis", "LLM unavailable")
                
            except Exception as e:
                logger.debug(f"LLM worker error: {e}")
                time.sleep(0.1)
    
    def _cat_worker_loop(self):
        """Background worker for song categorization."""
        logger.info("Categorization worker started")
        while not self._stop_event.is_set():
            try:
                track, lrc_text = self._cat_queue.get(timeout=1)
                logger.info(f"Processing categorization: {track.artist} - {track.title}")
                
                if self._categorizer.is_available:
                    self._pipeline.start("categorize_song")
                    categories = self._categorizer.categorize(track.artist, track.title, lrc_text, track.album)
                    if categories:
                        self._current_categories = categories  # Store for vj_console.py
                        self._pipeline.complete("categorize_song", f"{len(categories.get_top(5))} categories")
                        logger.info(f"Categories: {categories.primary_mood}, {len(categories.get_top(5))} moods")
                        
                        # Send categories via OSC
                        for cat in categories.get_top(10):
                            self._osc.send_karaoke("categories", cat.name, cat.score)
                    else:
                        logger.warning("Categorization returned None")
                        self._pipeline.skip("categorize_song", "Categorization failed")
                else:
                    logger.warning(f"Categorizer not available (backend: {self._categorizer._llm.backend_info if self._categorizer._llm else 'none'})")
                    self._pipeline.skip("categorize_song", "Categorizer unavailable")
                
            except Empty:
                continue
            except Exception as e:
                logger.error(f"Categorization worker error: {e}", exc_info=True)
                time.sleep(0.1)
    
