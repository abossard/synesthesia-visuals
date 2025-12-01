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
from queue import Queue, Full, Empty
from threading import Thread, Event
from typing import Optional, List

from domain import Track, PlaybackState, parse_lrc, analyze_lyrics
from infrastructure import PipelineTracker
from adapters import LyricsFetcher, OSCSender
from ai_services import LLMAnalyzer, SongCategorizer, ComfyUIGenerator

logger = logging.getLogger('karaoke')


# =============================================================================
# PLAYBACK COORDINATOR - Monitors sources, detects track changes
# =============================================================================

class PlaybackCoordinator:
    """
    Monitors playback from multiple sources and detects track changes.
    
    Priority order:
    1. Spotify (if actively playing)
    2. VirtualDJ (fallback)
    
    Interface:
        get_current_state() -> PlaybackState
        has_track_changed() -> bool
    
    Dependency Injection: Accepts list of monitors (Spotify, VirtualDJ, etc.)
    """
    
    def __init__(self, monitors: List):
        self._monitors = monitors
        self._state = PlaybackState()
        self._last_track_key = ""
        self._current_source = "unknown"
    
    def get_current_state(self) -> PlaybackState:
        """
        Poll all monitors and return current playback state.
        
        Priority: Spotify first (if playing), then fallback monitors.
        This prevents VirtualDJ from overriding active Spotify playback.
        """
        # First, check if Spotify is actively playing
        spotify_playback = None
        other_monitors = []
        
        for monitor in self._monitors:
            # Identify Spotify by class name
            if monitor.__class__.__name__ == 'SpotifyMonitor':
                spotify_playback = monitor.get_playback()
            else:
                other_monitors.append(monitor)
        
        # Use Spotify if it has active playback
        if spotify_playback:
            playback = spotify_playback
            self._current_source = "spotify"
        else:
            # Fall back to other monitors (VirtualDJ, etc.)
            playback = None
            for monitor in other_monitors:
                playback = monitor.get_playback()
                if playback:
                    self._current_source = monitor.__class__.__name__.replace("Monitor", "").lower()
                    break
        
        # Update state if we have playback
        if playback:
            track = Track(
                artist=playback['artist'],
                title=playback['title'],
                album=playback.get('album', ''),
                duration=playback.get('duration_ms', 0) / 1000.0
            )
            position = playback.get('progress_ms', 0) / 1000.0
            
            # Update state immutably
            self._state = self._state.update(
                track=track,
                position=position,
                is_playing=True,
                last_update=time.time()
            )
            return self._state
        
        # No playback detected
        if self._state.has_track:
            self._state = self._state.update(is_playing=False)
        
        return self._state
    
    def has_track_changed(self) -> bool:
        """Check if track changed since last call."""
        current_key = self._state.track.key if self._state.track else ""
        if current_key != self._last_track_key:
            self._last_track_key = current_key
            return current_key != ""
        return False
    
    @property
    def current_track(self) -> Optional[Track]:
        return self._state.track
    
    @property
    def current_source(self) -> str:
        """Return the name of the current playback source (spotify, virtualdj, etc.)."""
        return self._current_source


# =============================================================================
# LYRICS ORCHESTRATOR - Fetches and processes lyrics
# =============================================================================

class LyricsOrchestrator:
    """
    Orchestrates lyrics fetching, parsing, and analysis.
    
    Interface:
        process_track(track, timing_offset_ms) -> Optional[List[LyricLine]]
    
    Dependency Injection: LyricsFetcher, PipelineTracker
    """
    
    def __init__(self, fetcher: LyricsFetcher, pipeline: PipelineTracker):
        self._fetcher = fetcher
        self._pipeline = pipeline
    
    def process_track(self, track: Track, timing_offset_ms: int = 0) -> Optional[List]:
        """
        Fetch and analyze lyrics for track.
        Returns list of LyricLine objects or None if no lyrics found.
        """
        self._pipeline.start("fetch_lyrics")
        
        # Fetch LRC
        lrc_text = self._fetcher.fetch(track.artist, track.title, track.album, track.duration)
        
        if not lrc_text:
            self._pipeline.error("fetch_lyrics", "No lyrics found")
            return None
        
        self._pipeline.complete("fetch_lyrics", f"{len(lrc_text)} bytes")
        
        # Parse LRC
        self._pipeline.start("parse_lrc")
        lines = parse_lrc(lrc_text)
        if not lines:
            self._pipeline.error("parse_lrc", "Failed to parse")
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
        
        return lines


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
    
    Dependency Injection: LLMAnalyzer, SongCategorizer, ComfyUIGenerator, PipelineTracker, OSCSender
    """
    
    def __init__(self, llm: LLMAnalyzer, categorizer: SongCategorizer, 
                 image_gen: ComfyUIGenerator, pipeline: PipelineTracker, osc: OSCSender):
        self._llm = llm
        self._categorizer = categorizer
        self._image_gen = image_gen
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
    
    @property
    def current_categories(self):
        """Get current song categories."""
        return self._current_categories
    
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
                        
                        # Image prompt generation
                        self._pipeline.start("generate_image_prompt")
                        prompt = result.get('image_prompt') or self._llm.generate_image_prompt(
                            track.artist, track.title,
                            result.get('keywords', []),
                            result.get('themes', [])
                        )
                        self._pipeline.set_image_prompt(prompt)
                        self._pipeline.complete("generate_image_prompt")
                        
                        # Queue image generation
                        if self._image_gen.is_available and prompt:
                            self._generate_image(track, prompt)
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
    
    def _generate_image(self, track: Track, prompt: str):
        """Generate image in background thread."""
        def _gen():
            try:
                self._pipeline.start("comfyui_generate")
                img_path = self._image_gen.generate_image(prompt, track.artist, track.title)
                if img_path:
                    self._pipeline.complete("comfyui_generate", str(img_path.name))
                    self._osc.send_karaoke("image", "path", str(img_path))
                else:
                    self._pipeline.skip("comfyui_generate", "Generation failed")
            except Exception as e:
                self._pipeline.error("comfyui_generate", str(e))
        
        Thread(target=_gen, daemon=True, name="ImageGen").start()
