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
from dataclasses import replace
from threading import Lock
from typing import Optional

# Domain and infrastructure
from domain import (
    LyricLine, Track, PlaybackState, SongCategory, SongCategories,
    parse_lrc, extract_keywords, detect_refrains, analyze_lyrics,
    get_active_line_index, get_refrain_lines,
    SongCategories,  # Export for vj_console.py
    PlaybackSnapshot,
    PlaybackState,
)
from infrastructure import Config, Settings, PipelineTracker, ServiceHealth, PipelineStep, BackoffState

# Re-export for compatibility with vj_console.py and test_python_vj.py
__all__ = [
    'KaraokeEngine', 'Config', 'Settings', 'ServiceHealth',
    'LyricLine', 'Track', 'PlaybackState', 'SongCategory', 'SongCategories',
    'parse_lrc', 'extract_keywords', 'detect_refrains', 'analyze_lyrics',
    'get_active_line_index', 'get_refrain_lines',
    'PipelineTracker', 'PipelineStep',
    'LLMAnalyzer', 'SongCategorizer', 'ComfyUIGenerator',
    'LyricsFetcher', 'SpotifyMonitor', 'VirtualDJMonitor', 'OSCSender',
    'PlaybackSnapshot', 'BackoffState',
]

# External adapters
from adapters import (
    AppleScriptSpotifyMonitor,
    SpotifyMonitor,
    VirtualDJMonitor,
    LyricsFetcher,
    OSCSender,
)

# AI services
from ai_services import LLMAnalyzer, SongCategorizer, ComfyUIGenerator

# Shader matching (optional)
try:
    from shader_matcher import ShaderIndexer, ShaderSelector, categories_to_song_features
    SHADER_MATCHER_AVAILABLE = True
except ImportError:
    SHADER_MATCHER_AVAILABLE = False

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
        
        # Playback monitors (priority order)
        monitors = []
        if Config.SPOTIFY_APPLESCRIPT_ENABLED:
            monitors.append(AppleScriptSpotifyMonitor())
        if Config.SPOTIFY_WEBAPI_ENABLED:
            monitors.append(SpotifyMonitor())
        monitors.append(VirtualDJMonitor(vdj_path))
        self._playback = PlaybackCoordinator(monitors=monitors)
        
        # AI services (all optional)
        self._llm = LLMAnalyzer()
        self._categorizer = SongCategorizer(llm=self._llm)
        self._image_gen = ComfyUIGenerator()
        
        # Orchestrators
        self._lyrics_orchestrator = LyricsOrchestrator(self._lyrics_fetcher, self._pipeline)
        self._ai_orchestrator = AIOrchestrator(
            self._llm, self._categorizer, self._image_gen, self._pipeline, self._osc
        )
        
        # Shader matching (optional)
        self._shader_indexer = None
        self._shader_selector = None
        if SHADER_MATCHER_AVAILABLE:
            try:
                self._shader_indexer = ShaderIndexer()
                self._shader_indexer.sync()
                self._shader_selector = ShaderSelector(self._shader_indexer)
                logger.info(f"Shader selector loaded: {len(self._shader_indexer.shaders)} shaders")
            except Exception as e:
                logger.warning(f"Shader selector init failed: {e}")
        
        # Current state
        self._current_lines = []
        self._last_active_index = -1
        self._running = False
        self._last_track_key = ""
        self._snapshot_lock = Lock()
        self._snapshot = PlaybackSnapshot(state=PlaybackState())
        self._backoff = BackoffState()
        self._last_matched_track = ""  # Track when we last matched shaders
    
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
        return self.get_snapshot().state
    
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

    def get_snapshot(self) -> PlaybackSnapshot:
        """Get latest playback snapshot."""
        with self._snapshot_lock:
            return self._snapshot

    def _set_snapshot(self, snapshot: PlaybackSnapshot) -> None:
        with self._snapshot_lock:
            self._snapshot = snapshot
    
    def start(self, poll_interval: float = 2.0):
        """Start in background thread. Polls every 2 seconds."""
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
    
    def run(self, poll_interval: float = 2.0):
        """Run in foreground (blocking). Polls every 2 seconds."""
        self._running = True
        self._ai_orchestrator.start()
        try:
            self._run_loop(poll_interval)
        finally:
            self._ai_orchestrator.stop()
    
    # Private implementation
    
    def _run_loop(self, poll_interval: float):
        """Main loop with fast lyrics checking, slow position updates."""
        last_position_update = 0
        lyrics_check_interval = 0.1  # Check lyrics every 100ms for precision
        
        while self._running:
            try:
                current_time = time.time()
                snapshot = self._refresh_snapshot()
                
                # Fast: Check lyrics every 100ms
                self._check_lyrics(snapshot)
                
                # Slow: Update position every poll_interval (2s)
                if current_time - last_position_update >= poll_interval:
                    self._send_position_update(snapshot)
                    last_position_update = current_time
                
                time.sleep(lyrics_check_interval)
            except KeyboardInterrupt:
                break
            except Exception as e:
                logger.error(f"Loop error: {e}")
                time.sleep(1)
    
    def _check_lyrics(self, snapshot: PlaybackSnapshot):
        """Fast check for lyric changes (100ms precision)."""
        state = snapshot.state
        self._handle_track_change(state.track)
        
        # Check if categories arrived and we need to match shaders
        self._check_shader_match(state.track)
        
        if state.track and self._current_lines:
            offset_sec = self._settings.timing_offset_ms / 1000.0
            position = self._effective_position(state)
            active_index = get_active_line_index(self._current_lines, position + offset_sec)
            if active_index != self._last_active_index:
                self._last_active_index = active_index
                if active_index >= 0:
                    self._send_active_line(active_index)
    
    def _send_position_update(self, snapshot: PlaybackSnapshot):
        """Send position update (less frequent to reduce OSC traffic)."""
        state = snapshot.state
        if state.track:
            self._osc.send_karaoke("position", "update", {
                "time": self._effective_position(state),
                "playing": state.is_playing
            })

    def _effective_position(self, state: PlaybackState) -> float:
        """Estimate live position from latest state."""
        if not state.is_playing:
            return state.position
        return state.position + max(0.0, time.time() - state.last_update)

    def _handle_track_change(self, track):
        track_key = track.key if track else ""
        if track_key == self._last_track_key:
            return
        self._last_track_key = track_key
        if track:
            self._on_track_change(track)
        else:
            self._on_no_track()
    
    def _check_shader_match(self, track):
        """Match shaders when categories become available for a new track."""
        if not self._shader_selector or not track:
            return
        
        track_key = track.key
        if track_key == self._last_matched_track:
            return  # Already matched this track
        
        # Check if categories are ready
        categories = self.current_categories
        if not categories or not categories.primary_mood:
            return  # Not ready yet
        
        # Convert categories to song features and select shader
        try:
            song_features = categories_to_song_features(
                categories,
                track_title=track.title,
                track_artist=track.artist
            )
            
            match = self._shader_selector.select_for_song(song_features, top_k=5)
            
            if match:
                logger.info(
                    f"Shader: {match.name} → "
                    f"energy={song_features.energy:.2f} "
                    f"valence={song_features.valence:.2f} "
                    f"(usage={match.usage_count})"
                )
                
                # Send OSC command to load shader
                self._osc.send_shader(
                    match.name,
                    energy=match.features.energy_score,
                    valence=match.features.mood_valence
                )
                
                self._last_matched_track = track_key
            else:
                logger.debug(f"No shader match for {track.title}")
                
        except Exception as e:
            logger.warning(f"Shader match skipped: {e}")

    def _refresh_snapshot(self, force: bool = False) -> PlaybackSnapshot:
        """Poll playback with exponential backoff and return snapshot."""
        now = time.time()
        snapshot = self.get_snapshot()
        if not force and not self._backoff.ready(now):
            pending = self._backoff.time_remaining(now)
            updated = replace(snapshot, backoff_seconds=pending, error=self._backoff.last_error)
            self._set_snapshot(updated)
            return updated
        sample = self._playback.poll()
        error = self._select_error(sample)
        if error:
            self._backoff = self._backoff.record_failure(error, now)
        else:
            self._backoff = self._backoff.record_success()
        updated = PlaybackSnapshot(
            state=sample.state,
            source=sample.source,
            track_changed=sample.track_changed,
            updated_at=now,
            error=error or "",
            monitor_status=sample.monitor_status,
            backoff_seconds=self._backoff.time_remaining(now)
        )
        self._set_snapshot(updated)
        return updated

    def _select_error(self, sample) -> str:
        if sample.error:
            return sample.error
        for name, status in sample.monitor_status.items():
            if not status.get('available', True):
                return status.get('error') or f"{name} unavailable"
        return ""
    
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
            # No LRC lyrics - still send track info
            self._osc.send_karaoke("lyrics", "reset", {"song_id": track.key, "has_lyrics": False})
        
        # Fetch metadata via LLM (plain lyrics, keywords, song info) - background thread
        import threading
        def fetch_metadata():
            metadata = self._lyrics_orchestrator.fetch_metadata(track)
            if metadata:
                self._send_metadata(track, metadata)
        threading.Thread(target=fetch_metadata, daemon=True, name="SongMetadata").start()
    
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
    
    def _send_metadata(self, track, metadata: dict):
        """Send song metadata via OSC."""
        import json
        
        # Send keywords (most significant words from lyrics)
        keywords = metadata.get('keywords', [])
        if keywords:
            self._osc.send_karaoke("metadata", "keywords", keywords if isinstance(keywords, list) else [keywords])
        
        # Send themes
        themes = metadata.get('themes', [])
        if themes:
            self._osc.send_karaoke("metadata", "themes", themes if isinstance(themes, list) else [themes])
        
        # Send individual metadata fields
        if metadata.get('release_date'):
            self._osc.send_karaoke("metadata", "release_date", str(metadata['release_date']))
        if metadata.get('album'):
            self._osc.send_karaoke("metadata", "album", str(metadata['album']))
        if metadata.get('genre'):
            genre = metadata['genre']
            if isinstance(genre, list):
                genre = ', '.join(genre)
            self._osc.send_karaoke("metadata", "genre", genre)
        if metadata.get('label'):
            self._osc.send_karaoke("metadata", "label", str(metadata['label']))
        if metadata.get('writers'):
            writers = metadata['writers']
            if isinstance(writers, list):
                writers = ', '.join(writers)
            self._osc.send_karaoke("metadata", "writers", writers)
        
        # Send full metadata as JSON blob for advanced consumers
        self._osc.send_karaoke("metadata", "full", json.dumps(metadata))
        
        kw_count = len(keywords) if keywords else 0
        logger.info(f"Song metadata sent: {kw_count} keywords, {metadata.get('release_date', 'unknown')} / {metadata.get('genre', 'unknown')}")
    
    @property
    def current_song_info(self):
        """Get current song metadata (for vj_console.py)."""
        return self._lyrics_orchestrator.current_metadata
    
    @property
    def shader_selector(self):
        """Access shader selector (for vj_console.py)."""
        return self._shader_selector
    
    @property
    def shader_indexer(self):
        """Access shader indexer (for vj_console.py)."""
        return self._shader_indexer


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
