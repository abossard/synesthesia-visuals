"""
VJController - Thin coordinator for VJ system

This is the ONLY coordinator. It's tiny (~100 lines of actual logic).
Uses the three deep modules:
- PlaybackService: track detection
- LyricsService: lyrics + metadata  
- OutputService: OSC output

The controller just runs a tick() loop that:
1. Polls playback
2. On track change: load lyrics, send to output
3. On position change: update active line

Provides compatibility API for vj_console.py:
- get_snapshot() → PlaybackSnapshot
- set_playback_source(key)
- playback_source, current_shader, current_categories, last_lookup_ms
"""

import logging
import threading
import time
from typing import Any, Callable, Dict, List, Optional

from services.playback import PlaybackService, Playback
from services.lyrics import LyricsService
from services.output import OutputService

logger = logging.getLogger(__name__)


class VJController:
    """
    Thin coordinator for VJ system.
    
    Simple interface:
        controller.start()
        controller.tick()  # call every 100-200ms
        controller.stop()
    
    Properties for UI:
        controller.playback → current playback state
        controller.lyrics → LyricsService (for lines, metadata)
        controller.sources → available playback sources
    """
    
    def __init__(self):
        # Deep modules do the work
        self._playback = PlaybackService()
        self._lyrics = LyricsService()
        self._output = OutputService()
        
        # State
        self._running = False
        self._last_track_key = ""
        self._last_active_index = -1
        
        # Register for track changes
        self._playback.on_track_change(self._handle_track_change)
    
    # =========================================================================
    # LIFECYCLE
    # =========================================================================
    
    def start(self) -> None:
        """Start the controller."""
        self._running = True
        logger.info("VJController started")
    
    def stop(self) -> None:
        """Stop the controller."""
        self._running = False
        logger.info("VJController stopped")
    
    def tick(self) -> None:
        """
        Main tick - call every 100-200ms.
        
        Polls playback, updates active line.
        Track changes handled via callback.
        """
        if not self._running:
            return
        
        # Poll playback (track changes trigger callback)
        playback = self._playback.poll()
        
        if not playback.has_track:
            return
        
        # Update active line based on position
        if self._lyrics.has_lyrics:
            index = self._lyrics.get_active_index(playback.position_sec)
            if index != self._last_active_index:
                self._last_active_index = index
                self._output.send_active_line(index)
                
                # Check if active line is a refrain
                line = self._lyrics.get_line(index)
                if line and line.is_refrain:
                    self._output.send_refrain_active(index, line.text)
    
    # =========================================================================
    # TRACK CHANGE HANDLER
    # =========================================================================
    
    def _handle_track_change(self, track) -> None:
        """Handle track change from PlaybackService."""
        if not track:
            self._lyrics.clear()
            self._output.send_no_track()
            self._output.send_no_lyrics()
            self._last_track_key = ""
            self._last_active_index = -1
            return
        
        track_key = f"{track.artist}|{track.title}".lower()
        if track_key == self._last_track_key:
            return  # Same track
        
        self._last_track_key = track_key
        self._last_active_index = -1
        
        logger.info(f"♪ {track.artist} - {track.title}")
        
        # Load lyrics
        has_lyrics = self._lyrics.load(track)
        
        # Send to output
        self._output.send_track(track, has_lyrics=has_lyrics)
        
        if has_lyrics:
            self._output.send_lyrics(self._lyrics.lines)
            self._output.send_refrains(self._lyrics.refrain_lines)
        else:
            self._output.send_no_lyrics()
    
    # =========================================================================
    # UI ACCESSORS
    # =========================================================================
    
    @property
    def playback(self):
        """Current playback state."""
        return self._playback.playback
    
    @property
    def lyrics(self) -> LyricsService:
        """Lyrics service for accessing lines, metadata."""
        return self._lyrics
    
    @property
    def sources(self):
        """Available playback sources."""
        return self._playback.sources
    
    @property
    def current_source(self) -> str:
        """Current playback source name."""
        return self._playback.current_source
    
    def set_source(self, name: str) -> bool:
        """Set playback source."""
        return self._playback.set_source(name)
    
    @property
    def is_running(self) -> bool:
        """Check if controller is running."""
        return self._running
    
    # =========================================================================
    # COMPATIBILITY API (for vj_console.py drop-in replacement)
    # =========================================================================
    
    def get_snapshot(self):
        """
        Get current playback snapshot for UI.
        
        Returns PlaybackSnapshot-like object with:
        - state: PlaybackState with track, position, is_playing
        - source: current source name
        - monitor_status: dict of monitor statuses
        - error: error message if any
        """
        from domain_types import PlaybackSnapshot, PlaybackState, Track as DomainTrack
        
        pb = self._playback.playback
        
        # Build Track if we have one
        track = None
        if pb.has_track and pb.track:
            track = DomainTrack(
                artist=pb.track.artist,
                title=pb.track.title,
                album=pb.track.album,
                duration=pb.track.duration_sec,
            )
        
        # Build PlaybackState
        state = PlaybackState(
            track=track,
            position=pb.position_sec,
            is_playing=pb.is_playing,
            last_update=pb.updated_at,
        )
        
        # Build snapshot
        return PlaybackSnapshot(
            state=state,
            source=self._playback.current_source,
            monitor_status=self._playback.monitor_status,
            error="",
        )
    
    def set_playback_source(self, key: str) -> bool:
        """Set playback source by key (alias for set_source)."""
        return self.set_source(key)
    
    @property
    def playback_source(self) -> str:
        """Current playback source key."""
        return self._playback.current_source
    
    @property
    def current_shader(self) -> str:
        """Current shader name (placeholder - shader matching not yet integrated)."""
        return ""
    
    @property
    def current_categories(self):
        """Current song categories (placeholder - AI not yet integrated)."""
        return None
    
    @property
    def last_lookup_ms(self) -> float:
        """Last playback lookup duration in ms."""
        return self._playback.last_lookup_ms
    
    def adjust_timing(self, ms: int) -> None:
        """Adjust lyrics timing offset (placeholder)."""
        # TODO: implement timing offset in LyricsService
        logger.debug(f"Timing adjustment requested: {ms}ms (not yet implemented)")
