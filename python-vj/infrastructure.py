#!/usr/bin/env python3
"""
Infrastructure and Cross-Cutting Concerns

Configuration, settings persistence, service health monitoring,
and pipeline tracking for UI display.
"""

import os
import json
import time
import logging
from pathlib import Path
from typing import Optional, Dict, Any, List
from dataclasses import dataclass, field, replace
from threading import Lock

logger = logging.getLogger('karaoke')


# =============================================================================
# CONFIGURATION - Smart defaults for macOS
# =============================================================================

class Config:
    """Configuration with smart defaults for macOS VJ setups."""
    
    # OSC defaults
    DEFAULT_OSC_HOST = "127.0.0.1"
    DEFAULT_OSC_PORT = 9000  # Standard OSC port for Processing
    
    # VirtualDJ paths to search (in order of priority)
    VDJ_SEARCH_PATHS = [
        Path.home() / "Library" / "Application Support" / "VirtualDJ" / "History" / "tracklist.txt",  # macOS standard
        Path.home() / "Documents" / "VirtualDJ" / "History" / "tracklist.txt",
        Path.home() / "Documents" / "VirtualDJ" / "History" / "now_playing.txt",
        Path.home() / "Documents" / "VirtualDJ" / "now_playing.txt", 
        Path.home() / "Music" / "VirtualDJ" / "now_playing.txt",
        Path("/tmp") / "virtualdj_now_playing.txt",
    ]
    
    # Cache/state locations - stored in application folder
    APP_DATA_DIR = Path(__file__).parent / ".cache"
    DEFAULT_STATE_FILE = APP_DATA_DIR / "state.json"
    DEFAULT_SETTINGS_FILE = APP_DATA_DIR / "settings.json"
    DEFAULT_LYRICS_CACHE_DIR = APP_DATA_DIR / "lyrics"
    SPOTIFY_TOKEN_CACHE = APP_DATA_DIR / "spotify_token.cache"
    SCRIPTS_DIR = Path(__file__).parent / "scripts"
    DEFAULT_SPOTIFY_APPLESCRIPT = SCRIPTS_DIR / "spotify_track.applescript"

    # Timing adjustment step (200ms per key press)
    TIMING_STEP_MS = 200
    
    # Feature flags - ComfyUI is disabled by default (experimental)
    COMFYUI_ENABLED = os.environ.get('COMFYUI_ENABLED', '').lower() in ('1', 'true', 'yes', 'on')

    # Spotify monitor feature flags (AppleScript enabled by default)
    SPOTIFY_WEBAPI_ENABLED = os.environ.get('SPOTIFY_WEBAPI_ENABLED', '0').lower() in ('1', 'true', 'yes', 'on')
    SPOTIFY_APPLESCRIPT_ENABLED = os.environ.get('SPOTIFY_APPLESCRIPT_ENABLED', '1').lower() in ('1', 'true', 'yes', 'on')
    
    @classmethod
    def find_vdj_path(cls) -> Optional[Path]:
        """Auto-detect VirtualDJ now_playing.txt path."""
        for path in cls.VDJ_SEARCH_PATHS:
            if path.exists():
                return path
        return None
    
    @classmethod
    def get_spotify_credentials(cls) -> Dict[str, str]:
        """Extract Spotify credentials from environment."""
        return {
            'client_id': os.environ.get('SPOTIPY_CLIENT_ID', ''),
            'client_secret': os.environ.get('SPOTIPY_CLIENT_SECRET', ''),
            'redirect_uri': os.environ.get('SPOTIFY_REDIRECT_URI', 'http://localhost:8888/callback'),
        }
    
    @classmethod
    def has_spotify_credentials(cls) -> bool:
        """Check if Spotify credentials are configured."""
        creds = cls.get_spotify_credentials()
        return bool(creds['client_id'] and creds['client_secret'])

    @classmethod
    def apple_script_config(cls) -> Dict[str, Any]:
        """Return AppleScript monitor settings (path, timeout, enabled)."""
        script_override = os.environ.get('SPOTIFY_APPLESCRIPT_PATH', '')
        script_path = Path(script_override) if script_override else cls.DEFAULT_SPOTIFY_APPLESCRIPT
        timeout_env = os.environ.get('SPOTIFY_APPLESCRIPT_TIMEOUT', '').strip()
        try:
            timeout = float(timeout_env) if timeout_env else 1.5
        except ValueError:
            timeout = 1.5
        return {
            'enabled': cls.SPOTIFY_APPLESCRIPT_ENABLED,
            'script_path': script_path,
            'timeout': timeout,
        }


# =============================================================================
# SETTINGS - Persistent user settings (timing offset, etc.)
# =============================================================================

class Settings:
    """Persistent settings storage. Handles timing offset and other preferences."""
    
    def __init__(self, file_path: Optional[Path] = None):
        self.file_path = file_path or Config.DEFAULT_SETTINGS_FILE
        self._data = self._load()
    
    def _load(self) -> Dict[str, Any]:
        """Load settings from disk."""
        if self.file_path.exists():
            try:
                with open(self.file_path, 'r') as f:
                    return json.load(f)
            except Exception as e:
                logger.warning(f"Failed to load settings: {e}")
        return {}
    
    def _save(self):
        """Save settings to disk."""
        self.file_path.parent.mkdir(parents=True, exist_ok=True)
        with open(self.file_path, 'w') as f:
            json.dump(self._data, f, indent=2)
    
    @property
    def timing_offset_ms(self) -> int:
        """Get timing offset in milliseconds. Negative = show lyrics early."""
        return self._data.get('timing_offset_ms', -500)  # Default: 500ms early
    
    @timing_offset_ms.setter
    def timing_offset_ms(self, value: int):
        """Set timing offset in milliseconds."""
        self._data['timing_offset_ms'] = value
        self._save()
    
    def adjust_timing(self, delta_ms: int):
        """Adjust timing offset by delta."""
        self.timing_offset_ms = self.timing_offset_ms + delta_ms
    
    @property
    def all_settings(self) -> Dict[str, Any]:
        """Get all settings as dict."""
        return dict(self._data)


# =============================================================================
# SERVICE HEALTH - Tracks service availability with reconnection
# =============================================================================

class ServiceHealth:
    """
    Tracks service health and manages reconnection attempts.
    Designed for live events where services may come and go.
    """
    
    # How often to retry unavailable services (seconds)
    RECONNECT_INTERVAL = 30.0
    
    def __init__(self, name: str):
        self.name = name
        self._available = False
        self._last_check = 0.0
        self._last_error = ""
        self._error_count = 0
        self._lock = Lock()
    
    @property
    def available(self) -> bool:
        """Check if service is currently available."""
        with self._lock:
            return self._available
    
    @property
    def should_retry(self) -> bool:
        """Check if enough time has passed to retry connection."""
        with self._lock:
            return time.time() - self._last_check >= self.RECONNECT_INTERVAL
    
    def mark_available(self, message: str = ""):
        """Mark service as available after successful connection."""
        with self._lock:
            was_unavailable = not self._available
            self._available = True
            self._last_check = time.time()
            self._last_error = ""
            if was_unavailable and message:
                logger.info(f"{self.name}: {message}")
    
    def mark_unavailable(self, error: str = ""):
        """Mark service as unavailable after failure."""
        with self._lock:
            was_available = self._available
            self._available = False
            self._last_check = time.time()
            self._error_count += 1
            if error != self._last_error:
                self._last_error = error
                if was_available or self._error_count == 1:
                    logger.warning(f"{self.name}: {error}")
    
    def get_status(self) -> Dict[str, Any]:
        """Get status dict for UI display."""
        with self._lock:
            return {
                'name': self.name,
                'available': self._available,
                'error': self._last_error,
                'error_count': self._error_count,
                'last_check': self._last_check,
            }


# =============================================================================
# PIPELINE TRACKER - Thread-safe step tracking for UI display
# =============================================================================

@dataclass
class PipelineStep:
    """Single pipeline step with status. Immutable."""
    name: str
    status: str = "pending"  # pending, running, complete, error, skipped
    message: str = ""
    timestamp: float = 0.0


class PipelineTracker:
    """
    Tracks the processing pipeline for the current song.
    Thread-safe with immutable step updates.
    """
    
    STEPS = [
        "detect_playback",
        "fetch_lyrics",
        "parse_lrc",
        "analyze_refrain",
        "extract_keywords",
        "categorize_song",
        "llm_analysis",
        "generate_image_prompt",
        "comfyui_generate",
        "send_osc"
    ]
    
    STEP_LABELS = {
        "detect_playback": "🎵 Detect Playback",
        "fetch_lyrics": "📜 Fetch Lyrics",
        "parse_lrc": "⏱ Parse LRC Timecodes",
        "analyze_refrain": "🔁 Detect Refrain",
        "extract_keywords": "🔑 Extract Keywords",
        "categorize_song": "🏷️ Categorize Song",
        "llm_analysis": "🤖 AI Analysis",
        "generate_image_prompt": "🎨 Generate Image Prompt",
        "comfyui_generate": "🖼 ComfyUI Generate Image",
        "send_osc": "📡 Send OSC"
    }
    
    def __init__(self):
        self._lock = Lock()
        self._track_key = ""
        self._steps: Dict[str, PipelineStep] = {}
        self._logs: List[str] = []
        self._image_prompt = None
        self.reset()
    
    def reset(self, track_key: str = ""):
        """Reset pipeline for new track."""
        with self._lock:
            self._track_key = track_key
            self._steps = {
                step: PipelineStep(name=step, status="pending")
                for step in self.STEPS
            }
            self._logs = []
            self._image_prompt = None
            if track_key:
                self._logs.append(f"Pipeline reset for: {track_key}")
    
    def start(self, step: str, message: str = ""):
        """Mark step as running."""
        with self._lock:
            if step in self._steps:
                self._steps[step] = PipelineStep(
                    name=step,
                    status="running",
                    message=message,
                    timestamp=time.time()
                )
    
    def complete(self, step: str, message: str = ""):
        """Mark step as complete."""
        with self._lock:
            if step in self._steps:
                self._steps[step] = PipelineStep(
                    name=step,
                    status="complete",
                    message=message,
                    timestamp=time.time()
                )
    
    def error(self, step: str, message: str = ""):
        """Mark step as errored."""
        with self._lock:
            if step in self._steps:
                self._steps[step] = PipelineStep(
                    name=step,
                    status="error",
                    message=message,
                    timestamp=time.time()
                )
                self._logs.append(f"❌ {step}: {message}")
    
    def skip(self, step: str, message: str = ""):
        """Mark step as skipped."""
        with self._lock:
            if step in self._steps:
                self._steps[step] = PipelineStep(
                    name=step,
                    status="skipped",
                    message=message,
                    timestamp=time.time()
                )
    
    def log(self, message: str):
        """Add log message."""
        with self._lock:
            self._logs.append(message)
    
    def set_image_prompt(self, prompt):
        """Set image prompt for display."""
        with self._lock:
            self._image_prompt = prompt
    
    def get_display_lines(self) -> List[tuple]:
        """Get formatted display lines for UI. Returns list of (label, status, message)."""
        with self._lock:
            lines = []
            for step_name in self.STEPS:
                step = self._steps[step_name]
                label = self.STEP_LABELS.get(step_name, step_name)
                
                if step.status == "complete":
                    status = "✓"
                    color = "green"
                elif step.status == "running":
                    status = "⟳"
                    color = "yellow"
                elif step.status == "error":
                    status = "✗"
                    color = "red"
                elif step.status == "skipped":
                    status = "○"
                    color = "dim"
                else:
                    status = "○"
                    color = "dim"
                
                lines.append((label, status, color, step.message))
            
            return lines
    
    def get_log_lines(self, max_lines: int = 8) -> List[str]:
        """Get recent log lines."""
        with self._lock:
            return self._logs[-max_lines:]
    
    @property
    def current_track(self) -> str:
        """Get current track key."""
        with self._lock:
            return self._track_key
    
    @property
    def image_prompt(self):
        """Get image prompt."""
        with self._lock:
            return self._image_prompt


# =============================================================================
# BACKGROUND JOB UTILITIES - Functional backoff helpers
# =============================================================================

@dataclass(frozen=True)
class BackoffPolicy:
    """Configuration for exponential backoff."""
    base_delay: float = 0.5
    max_delay: float = 30.0
    factor: float = 2.0

    def delay_for(self, attempts: int) -> float:
        """Calculate delay for given attempt count."""
        return min(self.base_delay * (self.factor ** max(0, attempts)), self.max_delay)


@dataclass(frozen=True)
class BackoffState:
    """Immutable backoff tracking state."""
    attempts: int = 0
    next_allowed: float = 0.0
    last_error: str = ""
    policy: BackoffPolicy = field(default_factory=BackoffPolicy)

    def ready(self, now: float) -> bool:
        """Return True if work may run at the given time."""
        return now >= self.next_allowed

    def record_failure(self, error: str, now: float) -> 'BackoffState':
        """Return new state with updated delay after a failure."""
        delay = self.policy.delay_for(self.attempts)
        return replace(
            self,
            attempts=self.attempts + 1,
            next_allowed=now + delay,
            last_error=error,
        )

    def record_success(self) -> 'BackoffState':
        """Return reset state after successful work."""
        return replace(self, attempts=0, next_allowed=0.0, last_error="")

    def time_remaining(self, now: float) -> float:
        """Seconds until next attempt may run."""
        return max(0.0, self.next_allowed - now)

    def describe(self, now: float) -> Dict[str, Any]:
        """Summarize state for UI display."""
        return {
            'attempts': self.attempts,
            'retry_in': round(self.time_remaining(now), 1),
            'last_error': self.last_error,
        }
