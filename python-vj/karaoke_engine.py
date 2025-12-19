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
from threading import Lock, Event, Thread
from typing import Optional, Dict, List

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
    'LLMAnalyzer', 'SongCategorizer',
    'LyricsFetcher', 'OSCSender',
    'PlaybackSnapshot', 'BackoffState',
    'create_monitor', 'PLAYBACK_SOURCES',
]

# External adapters
from adapters import (
    LyricsFetcher,
    OSCSender,
    create_monitor,
    PLAYBACK_SOURCES,
)

# AI services
from ai_services import LLMAnalyzer, SongCategorizer

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
        self._pipeline.set_observer(self._handle_pipeline_update)
        
        # External adapters
        self._osc = OSCSender(osc_host or Config.DEFAULT_OSC_HOST, osc_port or Config.DEFAULT_OSC_PORT)
        self._lyrics_fetcher = LyricsFetcher()
        
        # Playback coordinator (no monitor active by default - user must start explicitly)
        self._playback = PlaybackCoordinator(monitor=None)
        
        # AI services (all optional)
        self._llm = LLMAnalyzer()
        self._categorizer = SongCategorizer(llm=self._llm)
        
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
        self._current_shader = ""  # Currently active shader name
        self._current_metadata: Dict = {}
        self._current_categories = None
        self._last_llm_analysis = None
        self._pipeline_thread: Optional[Thread] = None
        self._pipeline_cancel: Optional[Event] = None
    
    @property
    def current_shader(self) -> str:
        """Get the currently active shader name."""
        return self._current_shader
    
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
        return self._current_categories
    
    @property
    def last_llm_result(self) -> Optional[Dict]:
        """Last LLM analysis result with keywords/themes (for shader matching)."""
        return self._last_llm_analysis
    
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
    
    def start(self, poll_interval: Optional[float] = None):
        """Start in background thread. Poll interval from settings if not provided."""
        if self._running:
            return
        
        # Use settings if not provided
        if poll_interval is None:
            poll_interval = self._settings.playback_poll_interval_ms / 1000.0
        
        self._running = True
        thread = Thread(target=self._run_loop, args=(poll_interval,), daemon=True, name="Karaoke-Main")
        thread.start()
        logger.info(f"Karaoke engine started (poll interval: {poll_interval:.1f}s)")
    
    def set_playback_source(self, source_key: str):
        """Switch playback source live. Persists to settings."""
        from adapters import create_monitor
        monitor = create_monitor(source_key)
        if monitor:
            # Start monitor if it has a start method (e.g., VDJMonitor needs OSC subscriptions)
            if hasattr(monitor, 'start'):
                monitor.start()
            self._playback.set_monitor(monitor)
            self._settings.playback_source = source_key
            logger.info(f"Switched playback source to: {source_key}")
        else:
            logger.warning(f"Unknown playback source: {source_key}")
    
    @property
    def playback_source(self) -> str:
        """Get current playback source key."""
        return self._settings.playback_source
    
    @property
    def last_lookup_ms(self) -> float:
        """Get duration of last playback lookup in milliseconds."""
        return self._playback.last_lookup_ms
    
    def stop(self):
        """Stop engine and workers."""
        self._running = False
        logger.info("Karaoke engine stopped")
    
    def run(self, poll_interval: float = 2.0):
        """Run in foreground (blocking). Polls every 2 seconds."""
        self._running = True
        try:
            self._run_loop(poll_interval)
        finally:
            self._running = False
    
    # Private implementation
    
    def _run_loop(self, poll_interval: float):
        """Main loop with fast lyrics checking, slow position updates."""
        last_position_update = 0
        last_lyrics_hash = None  # Track changes to avoid redundant sends
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
        
        if state.track and self._current_lines and state.is_playing:
            offset_sec = self._settings.timing_offset_ms / 1000.0
            position = self._effective_position(state)
            active_index = get_active_line_index(self._current_lines, position + offset_sec)
            if active_index != self._last_active_index and active_index >= 0:
                self._last_active_index = active_index
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
    
    def _select_shader_for_track(self, track, categories, llm_result) -> bool:
        """Select and activate shader for given track data."""
        if not self._shader_selector or not track or not categories or not categories.scores:
            return False

        track_key = track.key
        if track_key == self._last_matched_track:
            return True

        try:
            song_features = categories_to_song_features(
                categories,
                track_title=track.title,
                track_artist=track.artist,
                llm_result=llm_result
            )

            match = self._shader_selector.select_for_song(song_features, top_k=5)

            if match:
                logger.info(
                    f"Shader: {match.name} → "
                    f"energy={song_features.energy:.2f} "
                    f"valence={song_features.valence:.2f} "
                    f"(usage={match.usage_count})"
                )

                self._osc.send_shader(
                    match.name,
                    energy=match.features.energy_score,
                    valence=match.features.mood_valence
                )

                self._current_shader = match.name
                self._last_matched_track = track_key
                return True

            logger.debug(f"No shader match for {track.title}")
        except Exception as e:
            logger.warning(f"Shader match skipped: {e}")

        return False

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
        self._cancel_pipeline_worker()
        self._pipeline.reset(track.key)
        self._current_lines = []
        self._current_metadata = {}
        self._current_categories = None
        self._last_llm_analysis = None
        self._last_active_index = -1
        self._last_matched_track = ""

        # Send track info with source
        self._osc.send_karaoke("track", "info", {
            "source": self._playback.current_source,
            "artist": track.artist,
            "title": track.title,
            "album": track.album,
            "duration": track.duration
        })
        self._osc.send_karaoke("lyrics", "reset", {"song_id": track.key})
        self._osc.send_karaoke("refrain", "reset", {"song_id": track.key})
        self._osc.send_karaoke("keywords", "reset", {"song_id": track.key})

        self._start_pipeline_worker(track)
    
    def _on_no_track(self):
        """Handle no track playing."""
        self._cancel_pipeline_worker()
        self._pipeline.reset()
        self._current_lines = []
        self._osc.send_karaoke("track", "none", {})

    # ------------------------------------------------------------------
    # Pipeline coordination
    # ------------------------------------------------------------------

    def _handle_pipeline_update(self, step: str, status: str, message: str):
        """Broadcast pipeline state changes over OSC."""
        payload = [step, status, message or ""]
        self._osc.send("/pipeline/step", payload)

    def _cancel_pipeline_worker(self):
        if self._pipeline_cancel:
            self._pipeline_cancel.set()
        if self._pipeline_thread and self._pipeline_thread.is_alive():
            self._pipeline_thread.join(timeout=0.5)
        self._pipeline_thread = None
        self._pipeline_cancel = None

    def _start_pipeline_worker(self, track: Track):
        cancel = Event()
        worker = Thread(
            target=self._run_pipeline,
            args=(track, cancel),
            daemon=True,
            name=f"Pipeline-{track.key}"
        )
        self._pipeline_cancel = cancel
        self._pipeline_thread = worker
        worker.start()

    def _run_pipeline(self, track: Track, cancel_event: Event):
        """Execute sequential pipeline for a single track."""
        def cancelled() -> bool:
            return cancel_event.is_set() or not self._running or track.key != self._last_track_key

        try:
            # 1. Detect playback
            self._pipeline.start("detect_playback", self._playback.current_source)
            if cancelled():
                return
            self._pipeline.complete("detect_playback", self._playback.current_source)

            # 2. Fetch LRC lyrics
            self._pipeline.start("fetch_lyrics")
            lrc_text = None
            timed_lines = []
            try:
                lrc_text = self._lyrics_fetcher.fetch(track.artist, track.title, track.album, track.duration)
                if lrc_text:
                    timed_lines = parse_lrc(lrc_text)
                    self._pipeline.complete("fetch_lyrics", f"{len(timed_lines)} lines")
                else:
                    self._pipeline.skip("fetch_lyrics", "No LRC available")
            except Exception as exc:
                logger.error(f"LRC fetch failed: {exc}")
                self._pipeline.error("fetch_lyrics", str(exc))
                lrc_text = None
                timed_lines = []
            if cancelled():
                return

            # 3. Fetch metadata + analysis (merged LLM call)
            self._pipeline.start("metadata_analysis")
            metadata = {}
            plain_lyrics = ""
            try:
                metadata = self._lyrics_fetcher.fetch_metadata(track.artist, track.title)
                if metadata:
                    self._current_metadata = metadata
                    plain_lyrics = metadata.get('plain_lyrics', '') or ''
                    details = []
                    if metadata.get('keywords'):
                        kw = metadata['keywords']
                        kw_count = len(kw) if isinstance(kw, list) else 1
                        details.append(f"{kw_count} keywords")
                    if metadata.get('release_date'):
                        details.append(str(metadata['release_date']))
                    analysis_payload = self._extract_analysis_from_metadata(metadata)
                    if analysis_payload:
                        self._last_llm_analysis = analysis_payload
                        hook_lines = len(analysis_payload.get('refrain_lines', []))
                        if hook_lines:
                            details.append(f"{hook_lines} refrain lines")
                        if analysis_payload.get('summary'):
                            details.append("analysis merged")
                    else:
                        # Fallback to keywords/themes even if analysis missing
                        self._last_llm_analysis = {
                            'keywords': self._coerce_list(metadata.get('keywords')),
                            'themes': self._coerce_list(metadata.get('themes')),
                            'summary': metadata.get('mood', ''),
                            'source': metadata.get('source', 'metadata_only')
                        }

                    message = ', '.join(details) if details else 'metadata + analysis fetched'
                    self._pipeline.complete("metadata_analysis", message)
                    if cancelled():
                        return
                    self._send_metadata(track, metadata)
                else:
                    self._current_metadata = {}
                    self._last_llm_analysis = None
                    self._pipeline.skip("metadata_analysis", "No metadata")
            except Exception as exc:
                logger.error(f"Metadata fetch failed: {exc}")
                self._current_metadata = {}
                self._last_llm_analysis = None
                self._pipeline.error("metadata_analysis", str(exc))
            if cancelled():
                return

            # 4. Detect refrain
            self._pipeline.start("detect_refrain")
            analysis_lines = []
            if timed_lines:
                analysis_lines = analyze_lyrics(timed_lines)
                refrain_count = sum(1 for line in analysis_lines if line.is_refrain)
                self._current_lines = analysis_lines
                self._send_all_lyrics(track.key, analysis_lines)
                self._pipeline.complete("detect_refrain", f"{refrain_count} refrain lines (timed)")
            else:
                fallback = self._build_plain_lyric_lines(plain_lyrics)
                if fallback:
                    analysis_lines = analyze_lyrics(fallback)
                    refrain_count = sum(1 for line in analysis_lines if line.is_refrain)
                    self._pipeline.complete("detect_refrain", f"{refrain_count} refrain lines (metadata)")
                else:
                    self._pipeline.skip("detect_refrain", "No lyrics available")
            if cancelled():
                return

            # 5. Extract keywords (merge sources)
            self._pipeline.start("extract_keywords")
            keyword_set = set()
            for line in analysis_lines:
                if getattr(line, 'keywords', ''):
                    for token in line.keywords.split():
                        keyword_set.add(token.lower())
            meta_keywords = []
            if metadata:
                kw_meta = metadata.get('keywords')
                if isinstance(kw_meta, list):
                    meta_keywords = [k.lower() for k in kw_meta]
                elif isinstance(kw_meta, str) and kw_meta:
                    meta_keywords = [kw_meta.lower()]
                keyword_set.update(meta_keywords)
            if keyword_set:
                consolidated = sorted(keyword_set)
                self._pipeline.complete("extract_keywords", f"{len(consolidated)} keywords")
                self._osc.send_karaoke("metadata", "keywords", consolidated)
            else:
                self._pipeline.skip("extract_keywords", "No keywords found")
            if cancelled():
                return

            # 6. Categorize song
            self._pipeline.start("categorize_song")
            lyric_text = lrc_text or plain_lyrics
            categories = None
            if lyric_text and self._categorizer and self._categorizer.is_available:
                try:
                    categories = self._categorizer.categorize(track.artist, track.title, lyric_text, track.album)
                    if categories:
                        self._current_categories = categories
                        top = categories.get_top(5)
                        self._pipeline.complete("categorize_song", f"{len(top)} moods")
                        for cat in categories.get_top(10):
                            self._osc.send_karaoke("categories", cat.name, cat.score)
                    else:
                        self._pipeline.skip("categorize_song", "No categories returned")
                except Exception as exc:
                    logger.error(f"Categorization failed: {exc}")
                    self._pipeline.error("categorize_song", str(exc))
            else:
                reason = "No lyrics input" if not lyric_text else "Categorizer unavailable"
                self._pipeline.skip("categorize_song", reason)
            if cancelled():
                return

            # 7. Shader selection
            self._pipeline.start("shader_selection")
            success = self._select_shader_for_track(track, self._current_categories, self._last_llm_analysis)
            if success:
                self._pipeline.complete("shader_selection", self._current_shader or "")
            else:
                self._pipeline.skip("shader_selection", "No shader match")

        finally:
            cancel_event.set()

    def _coerce_list(self, value) -> List[str]:
        """Normalize metadata values into a unique, trimmed list of strings."""
        items: List[str] = []
        if isinstance(value, list):
            items = value
        elif isinstance(value, str):
            items = [value]
        else:
            return []

        seen = set()
        result: List[str] = []
        for item in items:
            if item is None:
                continue
            text = str(item).strip()
            if not text:
                continue
            key = text.lower()
            if key in seen:
                continue
            seen.add(key)
            result.append(text)
        return result

    def _extract_analysis_from_metadata(self, metadata: Dict) -> Optional[Dict]:
        """Derive merged analysis payload from metadata response."""
        if not metadata:
            return None

        analysis = metadata.get('analysis') if isinstance(metadata.get('analysis'), dict) else {}

        keywords = self._coerce_list(analysis.get('keywords')) or self._coerce_list(metadata.get('keywords'))
        themes = self._coerce_list(metadata.get('themes')) or self._coerce_list(analysis.get('themes'))
        refrain_lines = self._coerce_list(analysis.get('refrain_lines'))
        emotions = self._coerce_list(analysis.get('emotions'))
        visuals = self._coerce_list(analysis.get('visual_adjectives'))
        summary = (analysis.get('summary') or metadata.get('mood') or '').strip()
        tempo = (analysis.get('tempo') or '').strip()

        payload = {
            'keywords': keywords,
            'themes': themes,
            'refrain_lines': refrain_lines,
            'emotions': emotions,
            'visual_adjectives': visuals,
            'summary': summary,
            'tempo': tempo,
            'source': metadata.get('source', 'metadata_combined')
        }

        # Remove empty values to keep payload lean
        payload = {k: v for k, v in payload.items() if v}

        if payload.get('keywords') or payload.get('themes') or payload.get('summary'):
            return payload
        return None

    def _build_plain_lyric_lines(self, plain_text: str) -> List[LyricLine]:
        """Convert plain lyrics into pseudo-timed LyricLine list for analysis."""
        if not plain_text:
            return []
        lines = []
        time_cursor = 0.0
        for raw in plain_text.splitlines():
            text = raw.strip()
            if not text:
                continue
            lines.append(LyricLine(time_sec=time_cursor, text=text))
            time_cursor += 1.0
        return lines
    
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
        return self._current_metadata
    
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
