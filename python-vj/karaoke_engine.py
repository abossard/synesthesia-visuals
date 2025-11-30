#!/usr/bin/env python3
"""
Karaoke Engine - Refactored with stratified design

ARCHITECTURE:
- domain.py: Pure calculations, immutable data structures
- infrastructure.py: Config, settings, service health, pipeline tracking
- adapters.py: External service interfaces (Spotify, VirtualDJ, LRCLIB, OSC)
- ai_services.py: AI integrations (LLM, categorization, image generation)
- orchestrators.py: Focused coordinators with dependency injection
- karaoke_engine.py: Main engine composition (this file)

LIVE EVENT SOFTWARE - Designed for resilience and graceful degradation.
All services are optional and will auto-reconnect if they become available.
"""

import time
import logging
import argparse
from pathlib import Path
from typing import Optional

# Domain and infrastructure
from domain import (
    get_active_line_index, get_refrain_lines,
    SongCategories,  # Export for vj_console.py
)
from infrastructure import Config, Settings, PipelineTracker

# Re-export for compatibility with vj_console.py
__all__ = ['KaraokeEngine', 'Config', 'SongCategories', 'get_active_line_index']

# External adapters
from adapters import SpotifyMonitor, VirtualDJMonitor, LyricsFetcher, OSCSender

# AI services
from ai_services import LLMAnalyzer, SongCategorizer, ComfyUIGenerator

# Orchestrators
from orchestrators import PlaybackCoordinator, LyricsOrchestrator, AIOrchestrator

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('karaoke')


# =============================================================================
# KARAOKE ENGINE - Main composition with dependency injection
# =============================================================================

class KaraokeEngine:
    """
    Main karaoke engine - composes all components.
    
    Refactored to use:
    - Dependency Injection for testability
    - Focused orchestrators instead of God Object
    - Immutable data updates for thread safety
    - Consolidated OSC sending
    
    Simple interface: start(), stop(), adjust_timing()
    """
    
    def __init__(
        self,
        osc_host: Optional[str] = None,
        osc_port: Optional[int] = None,
        vdj_path: Optional[str] = None,
        state_file: Optional[str] = None
    ):
        # Settings
        self._settings = Settings()
        
        # Pipeline tracking
        self._pipeline = PipelineTracker()
        
        # External adapters
        self._osc = OSCSender(osc_host or Config.DEFAULT_OSC_HOST, osc_port or Config.DEFAULT_OSC_PORT)
        self._lyrics_fetcher = LyricsFetcher()
        
        # Playback monitors
        spotify = SpotifyMonitor()
        vdj = VirtualDJMonitor(vdj_path)
        self._playback = PlaybackCoordinator(monitors=[spotify, vdj])
        
        # AI services (all optional)
        self._llm = LLMAnalyzer()
        self._categorizer = SongCategorizer(llm=self._llm)
        self._image_gen = ComfyUIGenerator()
        
        # Orchestrators
        self._lyrics_orchestrator = LyricsOrchestrator(self._lyrics_fetcher, self._pipeline)
        self._ai_orchestrator = AIOrchestrator(
            self._llm, self._categorizer, self._image_gen, self._pipeline, self._osc
        )
        
        # Current state
        self._current_lines = []
        self._last_active_index = -1
        self._last_position_send = 0.0  # Throttle position updates
        self._running = False
    
    @property
    def timing_offset_ms(self) -> int:
        """Get current timing offset."""
        return self._settings.timing_offset_ms
    
    def adjust_timing(self, delta_ms: int) -> int:
        """Adjust timing offset and return new value."""
        self._settings.adjust_timing(delta_ms)
        logger.info(f"Timing offset: {self._settings.timing_offset_ms}ms")
        return self._settings.timing_offset_ms
    
    @property
    def pipeline(self) -> PipelineTracker:
        """Access pipeline for UI display."""
        return self._pipeline
    
    @property
    def lyrics_cached_count(self) -> int:
        """Number of cached lyrics."""
        return self._lyrics_fetcher.get_cached_count()
    
    @property
    def llm_backend(self) -> str:
        """LLM backend info."""
        return self._llm.backend_info
    
    @property
    def current_categories(self) -> Optional['SongCategories']:
        """Current song categories (for vj_console.py)."""
        return self._ai_orchestrator.current_categories
    
    @property
    def osc_sender(self) -> OSCSender:
        """OSC sender (for vj_console.py)."""
        return self._osc
    
    @property
    def current_state(self):
        """Current playback state (for vj_console.py compatibility)."""
        return self._playback.get_current_state()
    
    # Backwards compatibility aliases
    @property
    def _state(self):
        """Alias for current_state (backwards compatibility)."""
        return self.current_state
    
    @property
    def _spotify(self):
        """Access to Spotify monitor (for vj_console.py connection check)."""
        for monitor in self._playback._monitors:
            if isinstance(monitor, SpotifyMonitor):
                return monitor
        return None
    
    @property
    def current_lines(self):
        """Current lyrics lines (for vj_console.py)."""
        return self._current_lines
    
    def start(self, poll_interval: float = 0.1):
        """Start in background thread."""
        if self._running:
            return
        
        import threading
        self._running = True
        self._ai_orchestrator.start()
        thread = threading.Thread(target=self._run_loop, args=(poll_interval,), daemon=True, name="Karaoke-Main")
        thread.start()
        logger.info("Karaoke engine started")
    
    def stop(self):
        """Stop engine and workers."""
        self._running = False
        self._ai_orchestrator.stop()
        logger.info("Karaoke engine stopped")
    
    def run(self, poll_interval: float = 0.1):
        """Run in foreground (blocking)."""
        self._running = True
        self._ai_orchestrator.start()
        try:
            self._run_loop(poll_interval)
        finally:
            self._ai_orchestrator.stop()
    
    # Private implementation
    
    def _run_loop(self, poll_interval: float):
        """Main loop."""
        while self._running:
            try:
                self._tick()
                time.sleep(poll_interval)
            except KeyboardInterrupt:
                break
            except Exception as e:
                logger.error(f"Loop error: {e}")
                time.sleep(1)
    
    def _tick(self):
        """Single update cycle."""
        # Get current playback state
        state = self._playback.get_current_state()
        
        # Check for track change
        if self._playback.has_track_changed():
            if state.track:
                self._on_track_change(state.track)
            else:
                self._on_no_track()
        
        # Send position updates (throttled to every 2 seconds)
        if state.track:
            current_time = time.time()
            if current_time - self._last_position_send >= 2.0:
                self._osc.send_karaoke("position", "update", {
                    "time": state.position,
                    "playing": state.is_playing
                })
                self._last_position_send = current_time
            
            # Update active line
            if self._current_lines:
                active_index = get_active_line_index(self._current_lines, state.position)
                if active_index != self._last_active_index:
                    self._last_active_index = active_index
                    if active_index >= 0:
                        self._send_active_line(active_index)
    
    def _on_track_change(self, track):
        """Handle new track."""
        logger.info(f"Track: {track.artist} - {track.title}")
        self._pipeline.reset(track.key)
        self._current_lines = []
        self._last_active_index = -1
        
        # Send track info with source
        self._osc.send_karaoke("track", "info", {
            "source": self._playback.current_source,
            "artist": track.artist,
            "title": track.title,
            "album": track.album,
            "duration": track.duration
        })
        
        # Fetch and process lyrics
        self._pipeline.start("detect_playback")
        self._pipeline.complete("detect_playback")
        
        lines = self._lyrics_orchestrator.process_track(track, self._settings.timing_offset_ms)
        
        if lines:
            self._current_lines = lines
            self._send_all_lyrics(track.key, lines)
            
            # Queue AI tasks (background)
            lrc_text = '\n'.join(f"[{int(line.time_sec//60):02d}:{int(line.time_sec%60):02d}]{line.text}" for line in lines)
            self._ai_orchestrator.queue_categorization(track, lrc_text)
            self._ai_orchestrator.queue_analysis(track, lrc_text)
            
            self._pipeline.start("send_osc")
            self._pipeline.complete("send_osc", f"{len(lines)} lines sent")
        else:
            # No lyrics but still send track info
            self._osc.send_karaoke("lyrics", "reset", {"song_id": track.key, "has_lyrics": False})
    
    def _on_no_track(self):
        """Handle no track playing."""
        self._pipeline.reset()
        self._current_lines = []
        self._osc.send_karaoke("track", "none", {})
    
    def _send_all_lyrics(self, song_id: str, lines):
        """Send all lyrics channels via OSC."""
        # Reset all channels
        self._osc.send_karaoke("lyrics", "reset", {"song_id": song_id})
        self._osc.send_karaoke("refrain", "reset", {"song_id": song_id})
        self._osc.send_karaoke("keywords", "reset", {"song_id": song_id})
        
        # Send full lyrics
        for i, line in enumerate(lines):
            self._osc.send_karaoke("lyrics", "line", {
                "index": i,
                "time": line.time_sec,
                "text": line.text
            })
        
        # Send refrain channel
        refrain_lines = get_refrain_lines(lines)
        for i, line in enumerate(refrain_lines):
            self._osc.send_karaoke("refrain", "line", {
                "index": i,
                "time": line.time_sec,
                "text": line.text
            })
        
        # Send keywords channel
        for i, line in enumerate(lines):
            if line.keywords:
                self._osc.send_karaoke("keywords", "line", {
                    "index": i,
                    "time": line.time_sec,
                    "keywords": line.keywords
                })
    
    def _send_active_line(self, index: int):
        """Send active line update to all channels."""
        if 0 <= index < len(self._current_lines):
            line = self._current_lines[index]
            
            # Full lyrics channel
            self._osc.send_karaoke("lyrics", "active", {"index": index})
            
            # Refrain channel (if this line is refrain)
            if line.is_refrain:
                refrain_lines = get_refrain_lines(self._current_lines)
                refrain_index = next((i for i, rline in enumerate(refrain_lines) if rline.text == line.text), -1)
                if refrain_index >= 0:
                    self._osc.send_karaoke("refrain", "active", {
                        "index": refrain_index,
                        "text": line.text
                    })
            
            # Keywords channel
            if line.keywords:
                self._osc.send_karaoke("keywords", "active", {
                    "index": index,
                    "keywords": line.keywords
                })


# =============================================================================
# MAIN - Standalone entry point (prefer vj_console.py)
# =============================================================================

def main():
    """Standalone entry point - prefer using vj_console.py instead."""
    print("=" * 50)
    print("  ℹ️  For full VJ control, use: python vj_console.py")
    print("=" * 50)
    print("  Running karaoke engine in standalone mode...\n")
    
    parser = argparse.ArgumentParser(
        description='Karaoke Engine - Synced lyrics via OSC (standalone mode)',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
For full VJ control with terminal UI, use:
    python vj_console.py

OSC Channels:
  /karaoke/lyrics/*     Full lyrics
  /karaoke/refrain/*    Chorus/refrain only
  /karaoke/keywords/*   Key words only
"""
    )
    parser.add_argument('--osc-host', default=Config.DEFAULT_OSC_HOST)
    parser.add_argument('--osc-port', type=int, default=Config.DEFAULT_OSC_PORT)
    parser.add_argument('--vdj-path', help='VirtualDJ now_playing.txt path (auto-detected)')
    parser.add_argument('--state-file', help='State file path')
    parser.add_argument('--poll-interval', type=float, default=0.1)
    parser.add_argument('-v', '--verbose', action='store_true')
    
    args = parser.parse_args()
    
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    engine = KaraokeEngine(
        osc_host=args.osc_host,
        osc_port=args.osc_port,
        vdj_path=args.vdj_path,
        state_file=args.state_file,
    )
    
    try:
        engine.run(args.poll_interval)
    except KeyboardInterrupt:
        engine.stop()
        print("\nStopped")


if __name__ == '__main__':
    main()
