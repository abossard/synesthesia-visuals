"""
VJController - Single deep module for VJ system

One class that hides everything:
- Track detection (Spotify/VDJ)
- Lyrics fetching (LRCLIB)
- Refrain detection
- OSC output
- Pipeline tracking

Simple interface:
    controller.start() / stop()
    controller.tick()
    controller.playback → Playback
    controller.lines → List[LyricLine]
"""

import logging
import re
import threading
import time
from dataclasses import dataclass, field, replace
from typing import Dict, List, Optional

logger = logging.getLogger(__name__)


# =============================================================================
# IMMUTABLE DATA (calculations operate on these)
# =============================================================================

@dataclass(frozen=True)
class Track:
    artist: str = ""
    title: str = ""
    album: str = ""
    duration_sec: float = 0.0
    bpm: float = 0.0
    
    @property
    def key(self) -> str:
        return f"{self.artist}|{self.title}".lower()
    
    def __bool__(self) -> bool:
        return bool(self.artist or self.title)


@dataclass(frozen=True)
class Playback:
    track: Optional[Track] = None
    position_sec: float = 0.0
    is_playing: bool = False
    updated_at: float = field(default_factory=time.time)
    
    @property
    def has_track(self) -> bool:
        return self.track is not None and bool(self.track)


@dataclass(frozen=True)
class LyricLine:
    time_sec: float
    text: str
    is_refrain: bool = False
    keywords: str = ""


# =============================================================================
# PURE FUNCTIONS (no side effects)
# =============================================================================

def parse_lrc(lrc_text: str) -> List[LyricLine]:
    """Parse LRC format into list of LyricLine."""
    if not lrc_text:
        return []
    
    lines = []
    pattern = re.compile(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)')
    
    for raw in lrc_text.splitlines():
        m = pattern.match(raw.strip())
        if m:
            mins, secs, frac_str, text = m.groups()
            frac = int(frac_str) / (100.0 if len(frac_str) == 2 else 1000.0)
            time_sec = int(mins) * 60 + int(secs) + frac
            if text.strip():
                lines.append(LyricLine(time_sec=time_sec, text=text.strip()))
    
    return sorted(lines, key=lambda x: x.time_sec)


def detect_refrains(lines: List[LyricLine], min_repeats: int = 2) -> List[LyricLine]:
    """Mark lines that repeat as refrains."""
    counts: Dict[str, int] = {}
    for line in lines:
        key = line.text.lower().strip()
        counts[key] = counts.get(key, 0) + 1
    
    refrain_texts = {k for k, v in counts.items() if v >= min_repeats}
    
    return [
        LyricLine(line.time_sec, line.text, line.text.lower().strip() in refrain_texts, line.keywords)
        for line in lines
    ]


STOPWORDS = {
    'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for', 'of',
    'with', 'by', 'from', 'is', 'are', 'was', 'were', 'be', 'been', 'i', 'you',
    'he', 'she', 'it', 'we', 'they', 'me', 'him', 'her', 'us', 'my', 'your',
    'do', 'does', 'did', 'have', 'has', 'had', 'will', 'would', 'could', 'can',
    'just', 'like', 'get', 'got', 'go', 'yeah', 'oh', 'ah', 'uh', 'ooh', 'na',
}


def extract_keywords(lines: List[LyricLine]) -> List[LyricLine]:
    """Extract keywords from each line."""
    result = []
    for line in lines:
        words = re.findall(r"[a-zA-Z']+", line.text.lower())
        kw = [w for w in words if len(w) > 2 and w not in STOPWORDS][:5]
        result.append(LyricLine(line.time_sec, line.text, line.is_refrain, ' '.join(kw)))
    return result


def get_active_index(lines: List[LyricLine], position: float) -> int:
    """Find active line index for position."""
    active = -1
    for i, line in enumerate(lines):
        if line.time_sec <= position:
            active = i
        else:
            break
    return active


# =============================================================================
# SOURCES (internal config)
# =============================================================================

def _create_spotify():
    from adapters import AppleScriptSpotifyMonitor
    return AppleScriptSpotifyMonitor()

def _create_vdj():
    from vdj_monitor import VDJMonitor
    return VDJMonitor()

_SOURCES = {
    "Spotify": ("spotify_applescript", _create_spotify),
    "VirtualDJ": ("vdj_osc", _create_vdj),
}


# =============================================================================
# VJ CONTROLLER (single deep module)
# =============================================================================

class VJController:
    """
    Deep module for VJ system.
    
    Hides: sources, monitors, OSC, LRCLIB, parsing, analysis.
    Exposes: playback, lines, tick().
    """
    
    def __init__(self):
        self._lock = threading.RLock()
        
        # Playback
        self._monitor = None
        self._source_key = ""
        self._source_name = ""
        self._playback = Playback()
        self._last_lookup_ms = 0.0
        
        # Lyrics
        self._fetcher = None
        self._lines: List[LyricLine] = []
        self._last_track_key = ""
        self._last_active_index = -1
        
        # OSC
        self._osc = None
        
        # Pipeline (simple list of tuples)
        self._pipeline_steps: List[tuple] = []  # (name, status, message)
        
        # Running state
        self._running = False
        
        # Restore saved source
        self._restore_source()
    
    # =========================================================================
    # LIFECYCLE
    # =========================================================================
    
    def start(self) -> None:
        self._running = True
        self._ensure_osc()
        logger.info("VJController started")
    
    def stop(self) -> None:
        self._running = False
        if self._monitor and hasattr(self._monitor, 'stop'):
            self._monitor.stop()
        logger.info("VJController stopped")
    
    def tick(self) -> None:
        """Main tick - poll playback, update active line."""
        if not self._running:
            return
        
        with self._lock:
            self._poll_playback()
            self._update_active_line()
    
    # =========================================================================
    # PLAYBACK (internal)
    # =========================================================================
    
    def _poll_playback(self) -> None:
        if not self._monitor:
            return
        
        start = time.time()
        try:
            raw = self._monitor.get_playback()
            self._last_lookup_ms = (time.time() - start) * 1000.0
            
            if raw:
                track = Track(
                    artist=raw.get('artist', ''),
                    title=raw.get('title', ''),
                    album=raw.get('album', ''),
                    duration_sec=raw.get('duration_ms', 0) / 1000.0,
                    bpm=raw.get('bpm', 0.0),
                )
                position = raw.get('progress_ms', 0) / 1000.0
                is_playing = raw.get('is_playing', False)
                
                # Track change?
                if track.key != self._last_track_key:
                    self._handle_track_change(track)
                
                self._playback = Playback(track, position, is_playing, time.time())
            else:
                if self._playback.has_track:
                    self._playback = replace(self._playback, is_playing=False)
        except Exception as e:
            logger.debug(f"Playback poll error: {e}")
    
    def _handle_track_change(self, track: Track) -> None:
        """Process new track: fetch lyrics, send OSC."""
        self._last_track_key = track.key
        self._last_active_index = -1
        self._lines = []
        self._pipeline_steps = []
        
        logger.info(f"♪ {track.artist} - {track.title}")
        
        # Pipeline: detect_playback
        self._pipeline_steps.append(("detect_playback", "complete", f"{track.artist} - {track.title}"))
        
        # Fetch lyrics
        self._pipeline_steps.append(("fetch_lyrics", "running", ""))
        self._ensure_fetcher()
        
        try:
            lrc_text = self._fetcher.fetch(track.artist, track.title, track.album, track.duration_sec)
            
            if lrc_text:
                lines = parse_lrc(lrc_text)
                lines = detect_refrains(lines)
                lines = extract_keywords(lines)
                self._lines = lines
                
                # Update pipeline
                self._pipeline_steps[-1] = ("fetch_lyrics", "complete", f"{len(lines)} lines")
                
                refrain_count = sum(1 for ln in lines if ln.is_refrain)
                if refrain_count:
                    self._pipeline_steps.append(("detect_refrain", "complete", f"{refrain_count} refrains"))
                else:
                    self._pipeline_steps.append(("detect_refrain", "skip", "none found"))
                
                kw_count = len({w for ln in lines for w in ln.keywords.split() if w})
                if kw_count:
                    self._pipeline_steps.append(("extract_keywords", "complete", f"{kw_count} keywords"))
                else:
                    self._pipeline_steps.append(("extract_keywords", "skip", "none"))
            else:
                self._pipeline_steps[-1] = ("fetch_lyrics", "skip", "no lyrics found")
                self._pipeline_steps.append(("detect_refrain", "skip", "no lyrics"))
                self._pipeline_steps.append(("extract_keywords", "skip", "no lyrics"))
        except Exception as e:
            self._pipeline_steps[-1] = ("fetch_lyrics", "error", str(e)[:30])
            logger.error(f"Lyrics fetch error: {e}")
        
        # Send to OSC
        self._send_track(track, has_lyrics=bool(self._lines))
        if self._lines:
            self._send_lyrics()
    
    def _update_active_line(self) -> None:
        if not self._lines or not self._playback.has_track:
            return
        
        idx = get_active_index(self._lines, self._playback.position_sec)
        if idx != self._last_active_index:
            self._last_active_index = idx
            self._ensure_osc()
            self._osc.textler.send("/textler/line/active", idx)
            
            # Check refrain
            if 0 <= idx < len(self._lines) and self._lines[idx].is_refrain:
                self._osc.textler.send("/textler/refrain/active", idx, self._lines[idx].text)
    
    # =========================================================================
    # OSC OUTPUT (internal)
    # =========================================================================
    
    def _ensure_osc(self):
        if self._osc is None:
            from osc import osc
            self._osc = osc
            self._osc.start()
    
    def _send_track(self, track: Track, has_lyrics: bool) -> None:
        self._ensure_osc()
        self._osc.textler.send(
            "/textler/track", 1, self._source_name or "unknown",
            track.artist, track.title, track.album,
            float(track.duration_sec), 1 if has_lyrics else 0
        )
    
    def _send_lyrics(self) -> None:
        self._ensure_osc()
        self._osc.textler.send("/textler/lyrics/reset")
        for i, line in enumerate(self._lines):
            self._osc.textler.send("/textler/lyrics/line", i, float(line.time_sec), line.text)
        
        # Refrains
        self._osc.textler.send("/textler/refrain/reset")
        for i, line in enumerate(self._lines):
            if line.is_refrain:
                self._osc.textler.send("/textler/refrain/line", i, float(line.time_sec), line.text)
    
    # =========================================================================
    # FETCHER (internal)
    # =========================================================================
    
    def _ensure_fetcher(self):
        if self._fetcher is None:
            from adapters import LyricsFetcher
            self._fetcher = LyricsFetcher()
    
    # =========================================================================
    # SOURCE MANAGEMENT
    # =========================================================================
    
    def _restore_source(self) -> None:
        try:
            from infra import Settings
            saved = Settings().playback_source or ""
            for name, (key, factory) in _SOURCES.items():
                if key == saved:
                    self._activate_source(name, persist=False)
                    return
        except Exception:
            pass
    
    def _activate_source(self, name: str, persist: bool = True) -> bool:
        if name not in _SOURCES:
            return False
        
        key, factory = _SOURCES[name]
        
        with self._lock:
            if self._monitor and hasattr(self._monitor, 'stop'):
                try:
                    self._monitor.stop()
                except Exception:
                    pass
            
            try:
                self._monitor = factory()
                if hasattr(self._monitor, 'start'):
                    self._monitor.start()
                self._source_key = key
                self._source_name = name
                self._playback = Playback()
                self._last_track_key = ""
                
                if persist:
                    from infra import Settings
                    Settings().playback_source = key
                
                logger.info(f"Source: {name}")
                return True
            except Exception as e:
                logger.error(f"Failed to activate {name}: {e}")
                return False
    
    @property
    def sources(self) -> List[str]:
        return list(_SOURCES.keys())
    
    def set_source(self, name: str) -> bool:
        return self._activate_source(name)
    
    @property
    def current_source(self) -> str:
        return self._source_name
    
    # =========================================================================
    # PUBLIC ACCESSORS
    # =========================================================================
    
    @property
    def playback(self) -> Playback:
        with self._lock:
            return self._playback
    
    @property
    def lines(self) -> List[LyricLine]:
        return self._lines
    
    @property
    def refrain_lines(self) -> List[LyricLine]:
        return [ln for ln in self._lines if ln.is_refrain]
    
    @property
    def keywords(self) -> List[str]:
        return sorted({w for ln in self._lines for w in ln.keywords.split() if w})
    
    @property
    def has_lyrics(self) -> bool:
        return bool(self._lines)
    
    @property
    def last_lookup_ms(self) -> float:
        return self._last_lookup_ms
    
    @property
    def is_running(self) -> bool:
        return self._running
    
    # =========================================================================
    # PIPELINE (for UI)
    # =========================================================================
    
    @property
    def pipeline(self):
        """Return pipeline-like object for UI compatibility."""
        return self._PipelineView(self._pipeline_steps)
    
    class _PipelineView:
        """Minimal view for pipeline panel."""
        def __init__(self, steps: List[tuple]):
            self._steps = steps
        
        def get_display_lines(self) -> List[tuple]:
            """Return (label, status, color, message) for each step."""
            result = []
            colors = {"complete": "green", "skip": "dim", "running": "yellow", "error": "red"}
            for name, status, msg in self._steps:
                label = name.replace("_", " ").title()
                color = colors.get(status, "white")
                result.append((label, status.upper(), color, msg))
            return result
    
    # =========================================================================
    # COMPATIBILITY API (for vj_console.py)
    # =========================================================================
    
    def get_snapshot(self):
        """Get PlaybackSnapshot for UI."""
        from domain_types import PlaybackSnapshot, PlaybackState, Track as DomainTrack
        
        pb = self._playback
        track = None
        if pb.has_track and pb.track:
            track = DomainTrack(
                artist=pb.track.artist,
                title=pb.track.title,
                album=pb.track.album,
                duration=pb.track.duration_sec,
            )
        
        state = PlaybackState(
            track=track,
            position=pb.position_sec,
            is_playing=pb.is_playing,
            last_update=pb.updated_at,
        )
        
        # Monitor status
        monitor_status = {}
        if self._source_name:
            if self._monitor and hasattr(self._monitor, 'status'):
                raw = self._monitor.status
                if isinstance(raw, dict):
                    monitor_status[self._source_name] = raw
        
        return PlaybackSnapshot(
            state=state,
            source=self._source_name,
            monitor_status=monitor_status,
            error="",
        )
    
    def set_playback_source(self, key: str) -> bool:
        """Set source by internal key."""
        for name, (k, _) in _SOURCES.items():
            if k == key:
                return self.set_source(name)
        return self.set_source(key)
    
    @property
    def playback_source(self) -> str:
        return self._source_key
    
    @property
    def current_shader(self) -> str:
        return ""
    
    @property
    def current_categories(self):
        return None
    
    @property
    def current_lines(self) -> List[LyricLine]:
        """Alias for lines (vj_console compatibility)."""
        return self._lines
    
    @property
    def timing_offset_ms(self) -> int:
        """Lyrics timing offset in ms."""
        return self._timing_offset_ms if hasattr(self, '_timing_offset_ms') else 0
    
    @property
    def last_llm_result(self) -> Optional[Dict]:
        """LLM analysis result (not yet implemented)."""
        return None
    
    def adjust_timing(self, ms: int) -> None:
        if not hasattr(self, '_timing_offset_ms'):
            self._timing_offset_ms = 0
        self._timing_offset_ms += ms
        logger.debug(f"Timing offset: {self._timing_offset_ms}ms")
