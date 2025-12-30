"""
PlaybackService - Deep module for track detection

Hides ALL complexity:
- Source selection (Spotify, VDJ)
- Monitor lifecycle (start/stop/reconnect)
- OSC subscriptions (VDJ)
- AppleScript polling (Spotify)
- Backoff/retry logic
- Settings persistence

Simple interface:
    service.playback → Playback (immutable)
    service.sources → List[str] (display names for UI)
    service.set_source(name) → bool
"""

import logging
import threading
import time
from dataclasses import dataclass, field, replace
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

logger = logging.getLogger(__name__)


# =============================================================================
# IMMUTABLE DATA
# =============================================================================

@dataclass(frozen=True)
class Track:
    """Immutable track info."""
    artist: str = ""
    title: str = ""
    album: str = ""
    duration_sec: float = 0.0
    bpm: float = 0.0
    key: str = ""
    
    @property
    def key_id(self) -> str:
        """Unique identifier for track."""
        return f"{self.artist}|{self.title}".lower()
    
    def __bool__(self) -> bool:
        return bool(self.artist or self.title)


@dataclass(frozen=True)
class Playback:
    """Immutable playback state."""
    track: Optional[Track] = None
    position_sec: float = 0.0
    is_playing: bool = False
    updated_at: float = field(default_factory=time.time)
    
    @property
    def has_track(self) -> bool:
        return self.track is not None and bool(self.track)
    
    def estimated_position(self) -> float:
        """Estimate current position accounting for elapsed time."""
        if not self.is_playing:
            return self.position_sec
        elapsed = time.time() - self.updated_at
        return self.position_sec + max(0.0, elapsed)


# =============================================================================
# SOURCE REGISTRY (internal - never exposed)
# =============================================================================

@dataclass
class _SourceConfig:
    """Internal source configuration."""
    key: str  # Internal key (never exposed)
    label: str  # Display name for UI
    factory: Callable[[], Any]


def _create_spotify_monitor():
    """Factory for Spotify AppleScript monitor."""
    from adapters import AppleScriptSpotifyMonitor
    return AppleScriptSpotifyMonitor()


def _create_vdj_monitor():
    """Factory for VirtualDJ OSC monitor."""
    from vdj_monitor import VDJMonitor
    return VDJMonitor()


_SOURCES: Dict[str, _SourceConfig] = {
    "Spotify": _SourceConfig(
        key="spotify_applescript",
        label="Spotify",
        factory=_create_spotify_monitor,
    ),
    "VirtualDJ": _SourceConfig(
        key="vdj_osc",
        label="VirtualDJ",
        factory=_create_vdj_monitor,
    ),
}

# Reverse lookup: internal key → display name
_KEY_TO_LABEL = {cfg.key: label for label, cfg in _SOURCES.items()}


# =============================================================================
# BACKOFF STATE (internal)
# =============================================================================

@dataclass
class _BackoffState:
    """Exponential backoff for connection failures."""
    failures: int = 0
    last_failure: float = 0.0
    last_error: str = ""
    
    BASE_DELAY = 1.0
    MAX_DELAY = 30.0
    
    def delay(self) -> float:
        if self.failures == 0:
            return 0.0
        return min(self.BASE_DELAY * (2 ** (self.failures - 1)), self.MAX_DELAY)
    
    def ready(self) -> bool:
        if self.failures == 0:
            return True
        return (time.time() - self.last_failure) >= self.delay()
    
    def record_failure(self, error: str) -> "_BackoffState":
        return _BackoffState(
            failures=self.failures + 1,
            last_failure=time.time(),
            last_error=error,
        )
    
    def record_success(self) -> "_BackoffState":
        return _BackoffState()


# =============================================================================
# SETTINGS (internal - only this module accesses)
# =============================================================================

def _load_source_setting() -> str:
    """Load persisted source key."""
    try:
        from infra import Settings
        return Settings().playback_source or ""
    except Exception:
        return ""


def _save_source_setting(key: str) -> None:
    """Persist source key."""
    try:
        from infra import Settings
        Settings().playback_source = key
    except Exception:
        pass


# =============================================================================
# PLAYBACK SERVICE (the deep module)
# =============================================================================

class PlaybackService:
    """
    Deep module for track detection.
    
    Hides: sources, monitors, lifecycle, backoff, settings.
    Exposes: playback state, source names, source switching.
    """
    
    def __init__(self):
        self._lock = threading.RLock()
        self._monitor = None
        self._source_key = ""
        self._playback = Playback()
        self._backoff = _BackoffState()
        self._last_track_key = ""
        self._last_lookup_ms = 0.0
        self._track_change_callbacks: List[Callable[[Optional[Track]], None]] = []
        
        # Restore persisted source
        saved_key = _load_source_setting()
        if saved_key:
            label = _KEY_TO_LABEL.get(saved_key)
            if label:
                self._activate_source(label, persist=False)
    
    # =========================================================================
    # PUBLIC API
    # =========================================================================
    
    @property
    def playback(self) -> Playback:
        """Get current playback state (immutable)."""
        with self._lock:
            return self._playback
    
    @property
    def sources(self) -> List[str]:
        """Available source names for UI (e.g., ['Spotify', 'VirtualDJ'])."""
        return list(_SOURCES.keys())
    
    @property
    def current_source(self) -> str:
        """Current source display name, or empty if none."""
        with self._lock:
            return _KEY_TO_LABEL.get(self._source_key, "")
    
    def set_source(self, name: str) -> bool:
        """
        Switch to source by display name. Persists to settings.
        
        Args:
            name: Display name (e.g., "Spotify", "VirtualDJ")
        
        Returns:
            True if source activated successfully.
        """
        return self._activate_source(name, persist=True)
    
    def poll(self) -> Playback:
        """
        Poll for updates. Call this periodically.
        
        Returns updated Playback state. Handles backoff internally.
        """
        with self._lock:
            if not self._monitor:
                return self._playback
            
            if not self._backoff.ready():
                return self._playback
            
            start_time = time.time()
            try:
                raw = self._monitor.get_playback()
                self._last_lookup_ms = (time.time() - start_time) * 1000.0
                
                if raw:
                    self._backoff = self._backoff.record_success()
                    self._update_from_raw(raw)
                else:
                    # No playback but monitor is working
                    if self._playback.has_track:
                        self._playback = replace(self._playback, is_playing=False)
            except Exception as e:
                self._backoff = self._backoff.record_failure(str(e))
                logger.debug(f"Playback poll error: {e}")
            
            return self._playback
    
    def on_track_change(self, callback: Callable[[Optional[Track]], None]) -> None:
        """Register callback for track changes."""
        self._track_change_callbacks.append(callback)
    
    @property
    def status(self) -> Dict[str, Any]:
        """Status for UI display."""
        with self._lock:
            return {
                "source": self.current_source,
                "connected": self._backoff.failures == 0,
                "error": self._backoff.last_error if self._backoff.failures > 0 else "",
                "has_track": self._playback.has_track,
            }
    
    @property
    def monitor_status(self) -> Dict[str, Dict[str, Any]]:
        """Get monitor status dict for compatibility with PlaybackSnapshot."""
        with self._lock:
            if not self._monitor:
                return {}
            
            source_name = self.current_source or "unknown"
            monitor_status = {}
            
            # Try to get status from monitor
            if hasattr(self._monitor, 'status'):
                raw_status = self._monitor.status
                if isinstance(raw_status, dict):
                    monitor_status[source_name] = raw_status
                else:
                    monitor_status[source_name] = {'available': self._backoff.failures == 0}
            else:
                monitor_status[source_name] = {'available': self._backoff.failures == 0}
            
            return monitor_status
    
    @property
    def last_lookup_ms(self) -> float:
        """Duration of last poll in milliseconds."""
        with self._lock:
            return self._last_lookup_ms
    
    # =========================================================================
    # INTERNAL
    # =========================================================================
    
    def _activate_source(self, name: str, persist: bool = True) -> bool:
        """Activate source by display name."""
        config = _SOURCES.get(name)
        if not config:
            logger.warning(f"Unknown source: {name}")
            return False
        
        with self._lock:
            # Stop old monitor
            if self._monitor and hasattr(self._monitor, 'stop'):
                try:
                    self._monitor.stop()
                except Exception:
                    pass
            
            # Create and start new monitor
            try:
                self._monitor = config.factory()
                if hasattr(self._monitor, 'start'):
                    self._monitor.start()
                self._source_key = config.key
                self._backoff = _BackoffState()
                self._playback = Playback()
                self._last_track_key = ""
                
                if persist:
                    _save_source_setting(config.key)
                
                logger.info(f"Playback source: {name}")
                return True
            except Exception as e:
                logger.error(f"Failed to activate {name}: {e}")
                self._monitor = None
                return False
    
    def _update_from_raw(self, raw: Dict[str, Any]) -> None:
        """Update state from monitor response."""
        track = Track(
            artist=raw.get('artist', ''),
            title=raw.get('title', ''),
            album=raw.get('album', ''),
            duration_sec=raw.get('duration_ms', 0) / 1000.0,
            bpm=raw.get('bpm', 0.0),
            key=raw.get('key', ''),
        )
        
        position = raw.get('progress_ms', 0) / 1000.0
        is_playing = raw.get('is_playing', False)
        
        # Detect track change
        track_key = track.key_id
        if track_key != self._last_track_key:
            self._last_track_key = track_key
            self._notify_track_change(track if track else None)
        
        self._playback = Playback(
            track=track,
            position_sec=position,
            is_playing=is_playing,
            updated_at=time.time(),
        )
    
    def _notify_track_change(self, track: Optional[Track]) -> None:
        """Notify callbacks of track change."""
        for callback in self._track_change_callbacks:
            try:
                callback(track)
            except Exception as e:
                logger.error(f"Track change callback error: {e}")
