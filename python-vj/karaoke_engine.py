#!/usr/bin/env python3
"""
Karaoke Engine - Monitors Spotify/VirtualDJ and sends lyrics via OSC

LIVE EVENT SOFTWARE - Designed for resilience and graceful degradation.
All services are optional and will auto-reconnect if they become available.

Smart defaults for macOS VJ setups:
- Auto-loads .env file for Spotify credentials
- Auto-detects VirtualDJ folder
- Uses standard OSC port 9000

Sends lyrics on 3 OSC channels:
- /karaoke/... - Full lyrics
- /karaoke/refrain/... - Chorus/refrain lines only  
- /karaoke/keywords/... - Key words extracted from each line

Usage:
    python vj_console.py              # Full UI (recommended)
    python vj_console.py --karaoke    # Standalone karaoke mode
"""

import os
import sys
import json
import time
import logging
import argparse
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional, List, Dict, Any, Callable
from threading import Thread, Event, Lock
from functools import wraps

# Load .env file if present
try:
    from dotenv import load_dotenv
    env_locations = [
        Path.cwd() / '.env',
        Path(__file__).parent / '.env',
        Path.home() / '.env',
    ]
    for env_path in env_locations:
        if env_path.exists():
            load_dotenv(env_path)
            break
except ImportError:
    pass

from pythonosc import udp_client
import requests

# Optional Spotify support
try:
    import spotipy
    from spotipy.oauth2 import SpotifyOAuth
    SPOTIFY_AVAILABLE = True
except ImportError:
    SPOTIFY_AVAILABLE = False

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('karaoke')


# =============================================================================
# RESILIENCE HELPERS - For live event reliability
# =============================================================================

def safe_call(func: Callable, *args, default=None, log_error: bool = True, **kwargs):
    """
    Safely call a function, returning default on any exception.
    Isolates failures to prevent cascading errors in live performance.
    """
    try:
        return func(*args, **kwargs)
    except Exception as e:
        if log_error:
            logger.debug(f"Safe call failed ({func.__name__}): {e}")
        return default


def retry_with_backoff(
    func: Callable,
    max_retries: int = 3,
    initial_delay: float = 1.0,
    max_delay: float = 30.0,
    exceptions: tuple = (Exception,)
):
    """
    Retry a function with exponential backoff.
    For use with network operations that may temporarily fail.
    """
    @wraps(func)
    def wrapper(*args, **kwargs):
        delay = initial_delay
        last_exception = None
        
        for attempt in range(max_retries):
            try:
                return func(*args, **kwargs)
            except exceptions as e:
                last_exception = e
                if attempt < max_retries - 1:
                    time.sleep(min(delay, max_delay))
                    delay *= 2
        
        raise last_exception
    
    return wrapper


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
        return self._available
    
    @property
    def should_retry(self) -> bool:
        """Check if enough time has passed to retry connection."""
        return time.time() - self._last_check > self.RECONNECT_INTERVAL
    
    def mark_available(self, message: str = ""):
        """Mark service as available after successful connection."""
        with self._lock:
            was_unavailable = not self._available
            self._available = True
            self._last_check = time.time()
            self._error_count = 0
            self._last_error = ""
            if was_unavailable:
                logger.info(f"{self.name}: ✓ Reconnected {message}")
    
    def mark_unavailable(self, error: str = ""):
        """Mark service as unavailable after failure."""
        with self._lock:
            was_available = self._available
            self._available = False
            self._last_check = time.time()
            self._error_count += 1
            self._last_error = error
            if was_available:
                logger.warning(f"{self.name}: Lost connection - {error}")
    
    def get_status(self) -> Dict[str, Any]:
        """Get status dict for UI display."""
        return {
            'name': self.name,
            'available': self._available,
            'error': self._last_error,
            'error_count': self._error_count,
            'last_check': self._last_check,
        }


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

    # Timing adjustment step (200ms per key press)
    TIMING_STEP_MS = 200
    
    # Feature flags - ComfyUI is disabled by default (experimental)
    COMFYUI_ENABLED = os.environ.get('COMFYUI_ENABLED', '').lower() in ('1', 'true', 'yes', 'on')
    
    @classmethod
    def find_vdj_path(cls) -> Optional[Path]:
        """Auto-detect VirtualDJ now_playing.txt location."""
        for path in cls.VDJ_SEARCH_PATHS:
            if path.exists():
                return path
            if path.parent.exists():
                return path
        vdj_folder = Path.home() / "Documents" / "VirtualDJ"
        if vdj_folder.exists():
            return vdj_folder / "now_playing.txt"
        return None
    
    @classmethod
    def get_spotify_credentials(cls) -> Dict[str, str]:
        """Get Spotify credentials from environment."""
        return {
            'client_id': os.environ.get('SPOTIPY_CLIENT_ID', ''),
            'client_secret': os.environ.get('SPOTIPY_CLIENT_SECRET', ''),
            'redirect_uri': os.environ.get('SPOTIPY_REDIRECT_URI', 'http://127.0.0.1:8888/callback'),
        }
    
    @classmethod
    def has_spotify_credentials(cls) -> bool:
        """Check if Spotify credentials are configured."""
        creds = cls.get_spotify_credentials()
        return bool(creds['client_id'] and creds['client_secret'])


# =============================================================================
# SETTINGS - Persistent user settings (timing offset, etc.)
# =============================================================================

class Settings:
    """Persistent settings storage. Handles timing offset and other preferences."""
    
    def __init__(self, file_path: Optional[Path] = None):
        self._file = file_path or Config.DEFAULT_SETTINGS_FILE
        self._file.parent.mkdir(parents=True, exist_ok=True)
        self._data = self._load()
    
    def _load(self) -> Dict[str, Any]:
        """Load settings from file."""
        if self._file.exists():
            try:
                return json.loads(self._file.read_text())
            except json.JSONDecodeError:
                logger.warning(f"Corrupted settings file, using defaults: {self._file}")
            except IOError as e:
                logger.debug(f"Could not read settings: {e}")
        return {'timing_offset_ms': 0}
    
    def _save(self):
        """Save settings to file."""
        try:
            self._file.write_text(json.dumps(self._data, indent=2))
        except IOError:
            pass
    
    @property
    def timing_offset_ms(self) -> int:
        """Get timing offset in milliseconds (positive = lyrics early, negative = late)."""
        return self._data.get('timing_offset_ms', 0)
    
    @timing_offset_ms.setter
    def timing_offset_ms(self, value: int):
        """Set timing offset in milliseconds."""
        self._data['timing_offset_ms'] = value
        self._save()
    
    def adjust_timing(self, delta_ms: int):
        """Adjust timing offset by delta (e.g., +200 or -200)."""
        self.timing_offset_ms = self.timing_offset_ms + delta_ms
        return self.timing_offset_ms
    
    @property
    def timing_offset_sec(self) -> float:
        """Get timing offset in seconds."""
        return self.timing_offset_ms / 1000.0


# =============================================================================
# PIPELINE TRACKER - Tracks song processing steps for UI display
# =============================================================================

@dataclass
class PipelineStep:
    """A single step in the song processing pipeline."""
    name: str
    status: str = "pending"  # pending, running, done, error
    message: str = ""
    timestamp: float = 0.0
    
    @property
    def icon(self) -> str:
        icons = {
            "pending": "○",
            "running": "◐",
            "done": "✓",
            "error": "✗",
            "skipped": "−"
        }
        return icons.get(self.status, "?")


class PipelineTracker:
    """
    Tracks the processing pipeline for the current song.
    Provides colorful step-by-step status for terminal UI display.
    """
    
    STEPS = [
        "detect_playback",
        "fetch_lyrics",
        "parse_lrc",
        "analyze_refrain",
        "extract_keywords",
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
        "llm_analysis": "🤖 AI Analysis",
        "generate_image_prompt": "🎨 Generate Image Prompt",
        "comfyui_generate": "🖼 ComfyUI Generate Image",
        "send_osc": "📡 Send OSC"
    }
    
    def __init__(self):
        self.steps: Dict[str, PipelineStep] = {}
        self.current_track = ""
        self.logs: List[str] = []
        self.image_prompt = ""
        self.generated_image_path = ""
        self._max_logs = 20
        self.reset()
    
    def reset(self, track_key: str = ""):
        """Reset pipeline for a new track."""
        self.current_track = track_key
        self.image_prompt = ""
        self.generated_image_path = ""
        self.steps = {
            name: PipelineStep(name=name, status="pending")
            for name in self.STEPS
        }
        if track_key:
            self.log(f"New track: {track_key}")
    
    def start(self, step: str, message: str = ""):
        """Mark a step as running."""
        if step in self.steps:
            self.steps[step].status = "running"
            self.steps[step].message = message
            self.steps[step].timestamp = time.time()
            if message:
                self.log(f"[{step}] {message}")
    
    def complete(self, step: str, message: str = ""):
        """Mark a step as done."""
        if step in self.steps:
            self.steps[step].status = "done"
            if message:
                self.steps[step].message = message
                self.log(f"[{step}] ✓ {message}")
    
    def error(self, step: str, message: str = ""):
        """Mark a step as failed."""
        if step in self.steps:
            self.steps[step].status = "error"
            if message:
                self.steps[step].message = message
                self.log(f"[{step}] ✗ {message}")
    
    def skip(self, step: str, message: str = ""):
        """Mark a step as skipped."""
        if step in self.steps:
            self.steps[step].status = "skipped"
            if message:
                self.steps[step].message = message
    
    def log(self, message: str):
        """Add a log entry with timestamp."""
        ts = time.strftime("%H:%M:%S")
        self.logs.append(f"{ts} {message}")
        if len(self.logs) > self._max_logs:
            self.logs = self.logs[-self._max_logs:]
    
    def set_image_prompt(self, prompt: str):
        """Store the generated image prompt."""
        self.image_prompt = prompt
        if prompt:
            self.log(f"Image prompt: {prompt[:60]}...")
    
    def get_display_lines(self) -> List[tuple]:
        """
        Get formatted lines for terminal display.
        Returns list of (color, text) tuples.
        """
        lines = []
        
        # Pipeline steps
        for step_name in self.STEPS:
            step = self.steps.get(step_name)
            if not step:
                continue
            
            label = self.STEP_LABELS.get(step_name, step_name)
            
            if step.status == "done":
                color = "green"
            elif step.status == "running":
                color = "yellow"
            elif step.status == "error":
                color = "red"
            elif step.status == "skipped":
                color = "dim"
            else:
                color = "dim"
            
            msg = f" - {step.message}" if step.message else ""
            lines.append((color, f"  {step.icon} {label}{msg}"))
        
        return lines
    
    def get_log_lines(self, max_lines: int = 8) -> List[str]:
        """Get recent log entries."""
        return self.logs[-max_lines:]


# =============================================================================
# DOMAIN MODELS - Pure data structures
# =============================================================================

@dataclass
class LyricLine:
    """A single lyric line with timing and analysis."""
    time_sec: float
    text: str
    is_refrain: bool = False
    keywords: str = ""


@dataclass 
class Track:
    """Current track metadata."""
    artist: str = ""
    title: str = ""
    album: str = ""
    duration_sec: float = 0.0
    source: str = ""  # "spotify" or "virtualdj"


@dataclass
class PlaybackState:
    """Current playback state - mutable."""
    active: bool = False
    position_sec: float = 0.0
    track: Optional[Track] = None
    lines: List[LyricLine] = field(default_factory=list)
    
    @property
    def track_key(self) -> str:
        """Unique identifier for current track."""
        if not self.track:
            return ""
        return f"{self.track.artist.lower()} - {self.track.title.lower()}"


# =============================================================================
# LYRICS ANALYSIS - Pure functions (no side effects)
# =============================================================================

# Stop words for keyword extraction
STOP_WORDS = frozenset({
    'i', 'me', 'my', 'we', 'our', 'you', 'your', 'he', 'she', 'it', 'they',
    'the', 'a', 'an', 'and', 'but', 'or', 'if', 'so', 'as', 'at', 'by', 'for',
    'in', 'of', 'on', 'to', 'up', 'is', 'am', 'are', 'was', 'be', 'been',
    'have', 'has', 'had', 'do', 'does', 'did', 'will', 'can', 'could', 'would',
    'should', 'may', 'might', 'must', 'shall', 'this', 'that', 'these', 'those',
    'what', 'which', 'who', 'when', 'where', 'why', 'how', 'all', 'each',
    'yeah', 'oh', 'ah', 'ooh', 'uh', 'na', 'la', 'da', 'hey', 'gonna', 'wanna',
    'gotta', 'cause', 'like', 'just', 'now', 'here', 'there', 'with', 'from',
    'into', 'out', 'over', 'under', 'again', 'then', 'once', 'more', 'some',
    'no', 'not', 'only', 'own', 'same', 'too', 'very', 'got', 'get', 'let',
})


def parse_lrc(lrc_text: str) -> List[LyricLine]:
    """Parse LRC format lyrics into LyricLine objects. Pure function."""
    lines = []
    pattern = r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)$'
    
    for line in lrc_text.split('\n'):
        match = re.match(pattern, line.strip())
        if match:
            mins, secs, ms_str, text = match.groups()
            ms = int(ms_str) * (10 if len(ms_str) == 2 else 1)
            time_sec = int(mins) * 60 + int(secs) + ms / 1000.0
            text = text.strip()
            if text:
                lines.append(LyricLine(time_sec=time_sec, text=text))
    
    return lines


def extract_keywords(text: str, max_words: int = 3) -> str:
    """Extract important words from text. Pure function."""
    words = re.findall(r'\b[a-zA-Z]+\b', text.lower())
    keywords = [w for w in words if w not in STOP_WORDS and len(w) > 2]
    return ' '.join(keywords[:max_words]).upper()


def detect_refrains(lines: List[LyricLine]) -> List[LyricLine]:
    """Mark lines that appear multiple times as refrain. Pure function."""
    if not lines:
        return lines
    
    # Count normalized line occurrences
    counts: Dict[str, int] = {}
    for line in lines:
        key = re.sub(r'[^\w\s]', '', line.text.lower())
        counts[key] = counts.get(key, 0) + 1
    
    # Lines appearing 2+ times are refrain
    refrain_keys = {k for k, v in counts.items() if v >= 2}
    
    # Create new list with refrain marked (immutable approach)
    return [
        LyricLine(
            time_sec=line.time_sec,
            text=line.text,
            is_refrain=re.sub(r'[^\w\s]', '', line.text.lower()) in refrain_keys,
            keywords=extract_keywords(line.text)
        )
        for line in lines
    ]


def analyze_lyrics(lines: List[LyricLine]) -> List[LyricLine]:
    """Full lyrics analysis pipeline. Pure function."""
    return detect_refrains(lines)


def get_active_line_index(lines: List[LyricLine], position: float) -> int:
    """Find the active line index for current position. Pure function."""
    active = -1
    for i, line in enumerate(lines):
        if line.time_sec <= position:
            active = i
        else:
            break
    return active


def get_refrain_lines(lines: List[LyricLine]) -> List[LyricLine]:
    """Filter to only refrain lines. Pure function."""
    return [l for l in lines if l.is_refrain]


# =============================================================================
# LYRICS FETCHER - Handles LRCLIB API with caching
# =============================================================================

class LyricsFetcher:
    """Fetches lyrics from LRCLIB API. Deep module - hides caching complexity."""
    
    BASE_URL = "https://lrclib.net/api"
    
    def __init__(self, cache_dir: Optional[Path] = None):
        self._cache_dir = cache_dir or Config.DEFAULT_LYRICS_CACHE_DIR
        self._cache_dir.mkdir(parents=True, exist_ok=True)
        self._session = requests.Session()
        self._session.headers["User-Agent"] = "KaraokeEngine/1.0"
    
    def fetch(self, artist: str, title: str, album: str = "", duration: float = 0) -> Optional[str]:
        """
        Fetch synced lyrics for a track.
        Returns LRC format string or None.
        Uses local cache to avoid re-downloading.
        """
        # Check cache first (persistent across sessions)
        cache_file = self._get_cache_path(artist, title)
        if cache_file.exists():
            try:
                data = json.loads(cache_file.read_text())
                # Check for expired "not found" entries (24h TTL)
                if data.get('not_found'):
                    cached_at = data.get('cached_at', 0)
                    if time.time() - cached_at > 86400:  # 24 hours
                        logger.debug(f"Cache expired, retrying: {artist} - {title}")
                        cache_file.unlink()  # Delete expired entry
                    else:
                        return None  # Still within TTL, return no lyrics
                else:
                    logger.debug(f"Using cached lyrics: {artist} - {title}")
                    return data.get('syncedLyrics')
            except (json.JSONDecodeError, IOError):
                pass
        
        # Fetch from API
        try:
            params = {"artist_name": artist, "track_name": title}
            if album:
                params["album_name"] = album
            if duration > 0:
                params["duration"] = int(duration)
            
            resp = self._session.get(f"{self.BASE_URL}/get", params=params, timeout=10)
            
            if resp.status_code == 200:
                data = resp.json()
                # Store in cache for future use
                self._save_to_cache(cache_file, data)
                logger.info(f"Fetched and cached lyrics: {artist} - {title}")
                return data.get('syncedLyrics')
            elif resp.status_code == 404:
                # Cache the "not found" result with timestamp (expires after 24h)
                self._save_to_cache(cache_file, {'not_found': True, 'cached_at': time.time()})
                logger.debug(f"No lyrics found: {artist} - {title}")
            else:
                logger.warning(f"LRCLIB error {resp.status_code}")
                
        except requests.RequestException as e:
            logger.error(f"Lyrics fetch error: {e}")
        
        return None
    
    def _save_to_cache(self, cache_file: Path, data: Dict):
        """Save data to cache file."""
        try:
            cache_file.write_text(json.dumps(data, indent=2))
        except IOError:
            pass
    
    def _get_cache_path(self, artist: str, title: str) -> Path:
        safe = re.sub(r'[^\w\s-]', '', f"{artist}_{title}".lower())
        safe = re.sub(r'\s+', '_', safe)
        return self._cache_dir / f"{safe}.json"
    
    def get_cached_count(self) -> int:
        """Return number of cached lyrics files."""
        if self._cache_dir.exists():
            return len(list(self._cache_dir.glob("*.json")))
        return 0


# =============================================================================
# LLM ANALYZER - Uses OpenAI or local Ollama for enhanced lyrics analysis
# =============================================================================

class LLMAnalyzer:
    """
    AI-powered lyrics analysis using OpenAI or local Ollama.
    
    LIVE EVENT BEHAVIOR:
    - Auto-reconnects to Ollama if it becomes available
    - Falls back gracefully to basic analysis
    - All LLM errors are caught (never crashes)
    - Results are cached to minimize API calls
    
    Fallback priority:
    1. OpenAI (if OPENAI_API_KEY is set)
    2. Local Ollama (auto-detects installed models)
    3. Basic analysis (no LLM)
    
    Recommended Ollama models for lyrics analysis (in priority order):
    - llama3.2: Best overall for nuanced analysis
    - mistral: Lightweight, good for resource-constrained systems  
    - deepseek-r1: Good reasoning for poetic/metaphorical language
    - llama3.1: Reliable fallback
    - llama2: Widely available
    """
    
    # Models in priority order (best for lyrics analysis first)
    PREFERRED_MODELS = ['llama3.2', 'llama3.1', 'mistral', 'deepseek-r1', 'llama2', 'phi3', 'gemma2']
    OLLAMA_URL = "http://localhost:11434"
    
    def __init__(self, cache_dir: Optional[Path] = None):
        self._cache_dir = (cache_dir or Config.APP_DATA_DIR) / "llm_cache"
        self._cache_dir.mkdir(parents=True, exist_ok=True)
        self._openai_client = None
        self._ollama_model = None
        self._health = ServiceHealth("LLM")
        self._backend = "none"
        self._init_backend()
    
    def _init_backend(self):
        """Initialize the best available LLM backend. Safe to call multiple times."""
        # Try OpenAI first
        openai_key = os.environ.get('OPENAI_API_KEY', '')
        if openai_key:
            try:
                import openai
                self._openai_client = openai.OpenAI(api_key=openai_key)
                # Test connection with a simple API call
                self._openai_client.models.list()
                self._health.mark_available("OpenAI")
                self._backend = "openai"
                logger.info("LLM: ✓ OpenAI connected")
                return
            except Exception as e:
                logger.debug(f"OpenAI init failed: {e}")
        
        # Fall back to local Ollama
        self._init_ollama()
    
    def _init_ollama(self):
        """Initialize Ollama with auto-detected model. Safe to call multiple times."""
        try:
            resp = requests.get(f"{self.OLLAMA_URL}/api/tags", timeout=2)
            if resp.status_code == 200:
                models = resp.json().get('models', [])
                available_names = [m.get('name', '').split(':')[0] for m in models]
                
                if not available_names:
                    logger.info("LLM: Ollama running but no models installed")
                    logger.info("  Install a model: ollama pull llama3.2")
                    return
                
                # Find best available model
                for preferred in self.PREFERRED_MODELS:
                    if preferred in available_names:
                        self._ollama_model = preferred
                        break
                
                if not self._ollama_model:
                    # Use first available model
                    self._ollama_model = available_names[0]
                
                self._health.mark_available(f"Ollama ({self._ollama_model})")
                self._backend = "ollama"
                logger.info(f"LLM: ✓ Ollama using {self._ollama_model} (from {len(available_names)} models)")
        except requests.RequestException:
            if self._health.available:
                self._health.mark_unavailable("Connection failed")
            else:
                logger.info("LLM: Ollama not available (using basic analysis)")
    
    def _try_reconnect(self):
        """Attempt to reconnect if LLM is down and enough time has passed."""
        if not self._health.available and self._health.should_retry:
            logger.debug("LLM: Attempting reconnection...")
            self._init_backend()
    
    @property
    def is_available(self) -> bool:
        return self._health.available
    
    @property
    def backend_info(self) -> str:
        """Return description of active backend."""
        if self._backend == "openai":
            return "OpenAI"
        elif self._backend == "ollama":
            return f"Ollama ({self._ollama_model})"
        return "Basic (no LLM)"
    
    def analyze_lyrics(self, lyrics: str, artist: str, title: str) -> Dict[str, Any]:
        """
        Use LLM to extract refrain lines and important keywords from lyrics.
        
        Returns:
            {
                'refrain_lines': ['line1', 'line2', ...],  # Chorus/refrain text
                'keywords': ['word1', 'word2', ...],      # Most impactful words
                'themes': ['theme1', 'theme2', ...],      # Song themes
                'image_prompt': str,                       # AI image generation prompt
                'cached': bool                             # True if from cache
            }
        """
        # Check cache first (always works even if LLM is down)
        cache_file = self._get_cache_path(artist, title)
        if cache_file.exists():
            try:
                data = json.loads(cache_file.read_text())
                data['cached'] = True
                return data
            except (json.JSONDecodeError, IOError):
                pass
        
        # Try to reconnect if LLM was down
        self._try_reconnect()
        
        if not self._health.available:
            return self._basic_analysis(lyrics)
        
        # Build prompt - now includes image prompt generation
        prompt = f"""Analyze these song lyrics and extract:
1. REFRAIN: The chorus or refrain lines (text that repeats and is the emotional core)
2. KEYWORDS: 5-10 most emotionally impactful or important single words
3. THEMES: 2-3 main themes of the song
4. IMAGE_PROMPT: A detailed visual prompt (50-100 words) that could generate an image capturing the song's mood, themes, and emotional atmosphere. Include colors, lighting, composition, and symbolic elements. Style: cinematic, abstract, suitable for VJ visuals.

Song: "{title}" by {artist}

Lyrics:
{lyrics[:3000]}

Respond in JSON format:
{{"refrain_lines": ["line1", "line2"], "keywords": ["word1", "word2"], "themes": ["theme1", "theme2"], "image_prompt": "detailed visual description..."}}
"""
        
        try:
            result = self._call_llm(prompt)
            if result:
                # Cache the result
                self._save_to_cache(cache_file, result)
                result['cached'] = False
                return result
        except Exception as e:
            self._health.mark_unavailable(str(e))
            logger.debug(f"LLM analysis failed (will retry): {e}")
        
        return self._basic_analysis(lyrics)
    
    def generate_image_prompt(self, artist: str, title: str, keywords: List[str], themes: List[str]) -> str:
        """
        Generate an image prompt for a song based on metadata.
        Used as fallback when full lyrics aren't available.
        """
        cache_file = self._cache_dir / f"imgprompt_{re.sub(r'[^\\w]', '', f'{artist}_{title}'.lower())}.txt"
        
        if cache_file.exists():
            try:
                return cache_file.read_text()
            except IOError:
                pass
        
        # Try reconnecting if we're down
        self._try_reconnect()
        
        if not self._health.available:
            return self._basic_image_prompt(artist, title, keywords, themes)
        
        prompt = f"""Create a detailed visual prompt (50-100 words) for AI image generation that captures the essence of this song:

Song: "{title}" by {artist}
Keywords: {', '.join(keywords[:10]) if keywords else 'unknown'}
Themes: {', '.join(themes[:5]) if themes else 'unknown'}

The image prompt should:
- Describe colors, lighting, mood, and atmosphere
- Include symbolic or abstract elements reflecting the song's themes
- Be suitable for VJ/music visualization use
- Style: cinematic, abstract, high-contrast, suitable for live visuals

Respond with ONLY the image prompt text, no JSON or explanation."""

        try:
            if self._backend == "openai":
                response = self._openai_client.chat.completions.create(
                    model="gpt-3.5-turbo",
                    messages=[{"role": "user", "content": prompt}],
                    max_tokens=200,
                    temperature=0.7
                )
                result = response.choices[0].message.content.strip()
            elif self._backend == "ollama":
                resp = requests.post(
                    f"{self.OLLAMA_URL}/api/generate",
                    json={"model": self._ollama_model, "prompt": prompt, "stream": False},
                    timeout=30
                )
                if resp.status_code == 200:
                    result = resp.json().get('response', '').strip()
                else:
                    result = None
            else:
                result = None
            
            if result:
                cache_file.write_text(result)
                return result
        except Exception as e:
            logger.debug(f"Image prompt generation failed: {e}")
        
        return self._basic_image_prompt(artist, title, keywords, themes)
    
    def _basic_image_prompt(self, artist: str, title: str, keywords: List[str], themes: List[str]) -> str:
        """Generate a basic image prompt without LLM."""
        keyword_str = ', '.join(keywords[:5]) if keywords else 'music, rhythm, emotion'
        theme_str = ', '.join(themes[:3]) if themes else 'energy, movement'
        return f"Abstract cinematic visualization for '{title}' by {artist}. Themes: {theme_str}. Elements: {keyword_str}. Dark background with vibrant light trails, high contrast, suitable for VJ performance."
    
    def _call_llm(self, prompt: str) -> Optional[Dict[str, Any]]:
        """Call the active LLM backend."""
        if self._backend == "openai":
            return self._call_openai(prompt)
        elif self._backend == "ollama":
            return self._call_ollama(prompt)
        return None
    
    def _call_openai(self, prompt: str) -> Optional[Dict[str, Any]]:
        """Call OpenAI API."""
        try:
            response = self._openai_client.chat.completions.create(
                model="gpt-3.5-turbo",
                messages=[{"role": "user", "content": prompt}],
                max_tokens=500,
                temperature=0.3
            )
            content = response.choices[0].message.content
            # Extract JSON from response
            return self._parse_json_response(content)
        except Exception as e:
            logger.debug(f"OpenAI error: {e}")
        return None
    
    def _call_ollama(self, prompt: str) -> Optional[Dict[str, Any]]:
        """Call local Ollama API."""
        try:
            resp = requests.post(
                f"{self.OLLAMA_URL}/api/generate",
                json={
                    "model": self._ollama_model,
                    "prompt": prompt,
                    "stream": False,
                    "options": {"temperature": 0.3}
                },
                timeout=30
            )
            if resp.status_code == 200:
                content = resp.json().get('response', '')
                return self._parse_json_response(content)
        except requests.RequestException as e:
            logger.debug(f"Ollama error: {e}")
        return None
    
    def _parse_json_response(self, text: str) -> Optional[Dict[str, Any]]:
        """Extract JSON from LLM response text."""
        # Find JSON in response
        start = text.find('{')
        end = text.rfind('}')
        if start >= 0 and end > start:
            try:
                return json.loads(text[start:end+1])
            except json.JSONDecodeError:
                pass
        return None
    
    def _basic_analysis(self, lyrics: str) -> Dict[str, Any]:
        """Fallback analysis without LLM."""
        lines = [l.strip() for l in lyrics.split('\n') if l.strip()]
        
        # Find repeated lines (likely refrain)
        counts: Dict[str, int] = {}
        for line in lines:
            key = re.sub(r'[^\w\s]', '', line.lower())
            counts[key] = counts.get(key, 0) + 1
        
        refrain = [l for l in lines if counts.get(re.sub(r'[^\w\s]', '', l.lower()), 0) >= 2]
        
        # Extract keywords
        all_words = re.findall(r'\b[a-zA-Z]+\b', lyrics.lower())
        word_counts: Dict[str, int] = {}
        for w in all_words:
            if w not in STOP_WORDS and len(w) > 3:
                word_counts[w] = word_counts.get(w, 0) + 1
        keywords = sorted(word_counts.keys(), key=lambda x: word_counts[x], reverse=True)[:10]
        
        return {
            'refrain_lines': list(set(refrain))[:5],
            'keywords': keywords,
            'themes': [],
            'cached': False
        }
    
    def _save_to_cache(self, cache_file: Path, data: Dict):
        """Save result to cache."""
        try:
            cache_file.write_text(json.dumps(data, indent=2))
        except IOError:
            pass
    
    def _get_cache_path(self, artist: str, title: str) -> Path:
        safe = re.sub(r'[^\w\s-]', '', f"{artist}_{title}".lower())
        safe = re.sub(r'\s+', '_', safe)
        return self._cache_dir / f"{safe}.json"


# =============================================================================
# COMFYUI IMAGE GENERATOR - Generates images using local ComfyUI
# =============================================================================

class ComfyUIGenerator:
    """
    Generates images using local ComfyUI installation via REST API.
    
    LIVE EVENT BEHAVIOR:
    - Auto-reconnects if ComfyUI becomes available
    - All generation errors are caught (never crashes)
    - Results are cached to minimize regeneration
    
    Creates visuals for songs with black backgrounds (for transparency in VJ compositing).
    Images are cached locally and can be used as overlays in Magic Music Visuals.
    
    API Usage:
        - POST /prompt - Queue a workflow with {"prompt": workflow_json, "client_id": uuid}
        - GET /history/{prompt_id} - Check execution status and get output image info
        - GET /view?filename=... - Download generated images
        - GET /object_info - List available nodes
        
    Workflow Selection:
        - Load workflow JSON files from python-vj/workflows/ directory
        - Each workflow should be exported from ComfyUI in API format (not web format)
        - To export: In ComfyUI, enable Dev Mode, then Save (API Format)
    """
    
    COMFYUI_URL = "http://127.0.0.1:8188"
    
    # Base prompt suffix for VJ-compatible output (black background for transparency)
    VJ_PROMPT_SUFFIX = ", pure black background, isolated subject, high contrast, dramatic lighting, suitable for video overlay, no background elements, centered composition, professional quality"
    
    # Negative prompt to ensure clean black backgrounds
    NEGATIVE_PROMPT = "white background, gray background, busy background, cluttered, low contrast, blurry, text, watermark, logo, frame, border"
    
    # Directory for custom workflow files
    WORKFLOWS_DIR = Path(__file__).parent / "workflows"
    
    def __init__(self, output_dir: Optional[Path] = None, enabled: Optional[bool] = None):
        """
        Initialize ComfyUI generator.
        
        Args:
            output_dir: Directory for generated images
            enabled: Override Config.COMFYUI_ENABLED (None = use config)
        """
        self._enabled = enabled if enabled is not None else Config.COMFYUI_ENABLED
        self._output_dir = output_dir or (Config.APP_DATA_DIR / "generated_images")
        self._output_dir.mkdir(parents=True, exist_ok=True)
        self._health = ServiceHealth("ComfyUI")
        self._client_id = None
        self._available_models = []
        self._custom_workflows = {}
        self._active_workflow = None
        
        if self._enabled:
            self._check_connection()
            self._load_custom_workflows()
        else:
            logger.info("ComfyUI: Disabled (set COMFYUI_ENABLED=1 to enable)")
    
    def _check_connection(self):
        """Check if ComfyUI is running. Safe to call multiple times for reconnection."""
        if not self._enabled:
            return
            
        try:
            resp = requests.get(f"{self.COMFYUI_URL}/system_stats", timeout=2)
            if resp.status_code == 200:
                # Generate a unique client ID for this session
                import uuid
                self._client_id = str(uuid.uuid4())
                
                # Get available checkpoint models
                self._fetch_available_models()
                self._health.mark_available()
                logger.info("ComfyUI: ✓ Connected")
            else:
                self._health.mark_unavailable("Not responding")
        except requests.RequestException:
            if self._health.available:
                self._health.mark_unavailable("Connection lost")
            else:
                logger.info("ComfyUI: Not available (start ComfyUI on port 8188)")
    
    def _try_reconnect(self):
        """Attempt to reconnect if ComfyUI is down and enough time has passed."""
        if not self._enabled:
            return
        if not self._health.available and self._health.should_retry:
            logger.debug("ComfyUI: Attempting reconnection...")
            self._check_connection()
    
    def _fetch_available_models(self):
        """Fetch list of available checkpoint models from ComfyUI."""
        try:
            resp = requests.get(f"{self.COMFYUI_URL}/object_info/CheckpointLoaderSimple", timeout=5)
            if resp.status_code == 200:
                info = resp.json()
                if 'CheckpointLoaderSimple' in info:
                    inputs = info['CheckpointLoaderSimple'].get('input', {})
                    required = inputs.get('required', {})
                    if 'ckpt_name' in required:
                        self._available_models = required['ckpt_name'][0]
                        logger.debug(f"ComfyUI models: {self._available_models}")
        except Exception as e:
            logger.debug(f"Could not fetch models: {e}")
    
    def _load_custom_workflows(self):
        """Load custom workflow JSON files from workflows directory."""
        try:
            self.WORKFLOWS_DIR.mkdir(parents=True, exist_ok=True)
        except Exception:
            return
        
        # Create a sample workflow README
        readme_path = self.WORKFLOWS_DIR / "README.md"
        if not readme_path.exists():
            try:
                readme_path.write_text("""# ComfyUI Workflows

Place your workflow JSON files here. Export from ComfyUI using:

1. Enable "Dev Mode Options" in ComfyUI Settings
2. Click "Save (API Format)" to export the workflow

The JSON file should contain the node graph in API format.

## Usage in VJ Console

The karaoke engine will:
- Auto-detect workflows in this folder
- Let you select which workflow to use
- Substitute the prompt text into CLIPTextEncode nodes

## Naming Convention

- `default_sdxl.json` - Default SDXL workflow
- `flux_artistic.json` - Flux model for artistic styles
- `fast_lcm.json` - Fast LCM-based generation

The engine will look for nodes with specific class_types:
- `CLIPTextEncode` - For prompt injection
- `CheckpointLoaderSimple` - For model selection
- `SaveImage` - For output retrieval
""")
            except Exception:
                pass  # Ignore README write errors
        
        # Load all JSON files
        for wf_path in self.WORKFLOWS_DIR.glob("*.json"):
            try:
                with open(wf_path) as f:
                    workflow = json.load(f)
                self._custom_workflows[wf_path.stem] = workflow
                logger.debug(f"Loaded workflow: {wf_path.stem}")
            except Exception as e:
                logger.warning(f"Failed to load workflow {wf_path}: {e}")
        
        if self._custom_workflows:
            logger.info(f"ComfyUI: {len(self._custom_workflows)} custom workflow(s) loaded")
    
    @property
    def is_enabled(self) -> bool:
        """Check if ComfyUI is enabled in config."""
        return self._enabled
    
    @property
    def is_available(self) -> bool:
        """Check if ComfyUI is enabled AND connected."""
        return self._enabled and self._health.available
    
    @property
    def available_models(self) -> List[str]:
        """List of available checkpoint models."""
        return self._available_models if self._available_models else []
    
    @property
    def available_workflows(self) -> List[str]:
        """List of available custom workflows."""
        return list(self._custom_workflows.keys())
    
    @property
    def active_workflow(self) -> Optional[str]:
        """Currently active workflow name."""
        return self._active_workflow
    
    def set_workflow(self, name: str) -> bool:
        """
        Set the active workflow by name.
        
        Args:
            name: Workflow name (without .json extension)
            
        Returns:
            True if workflow was found and set, False otherwise.
        """
        if name in self._custom_workflows:
            self._active_workflow = name
            logger.info(f"ComfyUI: Using workflow '{name}'")
            return True
        logger.warning(f"ComfyUI: Workflow '{name}' not found")
        return False
    
    def get_status_info(self) -> Dict[str, Any]:
        """Get status information for display in UI."""
        return {
            'enabled': self._enabled,
            'available': self._health.available,
            'models': self._available_models[:5] if self._available_models else [],
            'model_count': len(self._available_models),
            'workflows': list(self._custom_workflows.keys()),
            'active_workflow': self._active_workflow,
            'cached_images': self.get_cached_count(),
            'url': self.COMFYUI_URL,
            'error': self._health._last_error,
        }
    
    def get_vj_prompt(self, base_prompt: str) -> str:
        """
        Enhance a prompt for VJ use with black background requirements.
        """
        # Clean up the base prompt
        prompt = base_prompt.strip()
        if not prompt:
            return ""
        
        # Add VJ-specific requirements
        return prompt + self.VJ_PROMPT_SUFFIX
    
    def generate_image(
        self,
        prompt: str,
        artist: str,
        title: str,
        width: int = 1024,
        height: int = 1024,
        steps: int = 20,
        cfg_scale: float = 7.0
    ) -> Optional[Path]:
        """
        Generate an image using ComfyUI.
        
        RESILIENCE: Auto-reconnects, handles all errors gracefully.
        
        Args:
            prompt: The image generation prompt (will be enhanced for VJ use)
            artist: Artist name (for caching)
            title: Song title (for caching)
            width: Image width
            height: Image height
            steps: Number of diffusion steps
            cfg_scale: Classifier-free guidance scale
            
        Returns:
            Path to the generated image, or None if generation failed.
        """
        # Check if ComfyUI is enabled
        if not self._enabled:
            return None
        
        # Check cache first (always works even if ComfyUI is down)
        cache_file = self._get_image_path(artist, title)
        if cache_file.exists():
            logger.debug(f"Using cached image: {cache_file}")
            return cache_file
        
        # Try to reconnect if we're down
        self._try_reconnect()
        
        if not self._health.available:
            return None
        
        # Enhance prompt for VJ use
        vj_prompt = self.get_vj_prompt(prompt)
        
        # Build ComfyUI workflow
        workflow = self._build_workflow(vj_prompt, width, height, steps, cfg_scale)
        
        try:
            # Queue the prompt
            resp = requests.post(
                f"{self.COMFYUI_URL}/prompt",
                json={"prompt": workflow, "client_id": self._client_id},
                timeout=10
            )
            
            if resp.status_code != 200:
                self._health.mark_unavailable(f"Queue failed: {resp.status_code}")
                return None
            
            prompt_id = resp.json().get('prompt_id')
            if not prompt_id:
                return None
            
            # Poll for completion
            image_path = self._wait_for_image(prompt_id, cache_file)
            if image_path:
                logger.info(f"Generated image: {image_path.name}")
            return image_path
            
        except requests.RequestException as e:
            self._health.mark_unavailable(str(e))
            logger.debug(f"ComfyUI error (will retry): {e}")
            return None
    
    def _build_workflow(
        self,
        prompt: str,
        width: int,
        height: int,
        steps: int,
        cfg_scale: float
    ) -> Dict[str, Any]:
        """
        Build a ComfyUI workflow for image generation.
        
        If a custom workflow is active, it will be used with the prompt injected.
        Otherwise, falls back to a simple SDXL txt2img workflow.
        """
        import copy
        
        # Use custom workflow if one is active
        if self._active_workflow and self._active_workflow in self._custom_workflows:
            workflow = copy.deepcopy(self._custom_workflows[self._active_workflow])
            return self._inject_prompt_into_workflow(workflow, prompt)
        
        # Select a model that's actually available
        model_name = "sd_xl_base_1.0.safetensors"
        if self._available_models:
            # Prefer SDXL models
            for m in self._available_models:
                if 'sdxl' in m.lower() or 'sd_xl' in m.lower():
                    model_name = m
                    break
            else:
                # Fall back to first available model
                model_name = self._available_models[0]
        
        # Default SDXL workflow
        return {
            "3": {
                "class_type": "KSampler",
                "inputs": {
                    "seed": int(time.time()) % 2147483647,
                    "steps": steps,
                    "cfg": cfg_scale,
                    "sampler_name": "euler",
                    "scheduler": "normal",
                    "denoise": 1.0,
                    "model": ["4", 0],
                    "positive": ["6", 0],
                    "negative": ["7", 0],
                    "latent_image": ["5", 0]
                }
            },
            "4": {
                "class_type": "CheckpointLoaderSimple",
                "inputs": {
                    "ckpt_name": model_name
                }
            },
            "5": {
                "class_type": "EmptyLatentImage",
                "inputs": {
                    "width": width,
                    "height": height,
                    "batch_size": 1
                }
            },
            "6": {
                "class_type": "CLIPTextEncode",
                "inputs": {
                    "text": prompt,
                    "clip": ["4", 1]
                }
            },
            "7": {
                "class_type": "CLIPTextEncode",
                "inputs": {
                    "text": self.NEGATIVE_PROMPT,
                    "clip": ["4", 1]
                }
            },
            "8": {
                "class_type": "VAEDecode",
                "inputs": {
                    "samples": ["3", 0],
                    "vae": ["4", 2]
                }
            },
            "9": {
                "class_type": "SaveImage",
                "inputs": {
                    "filename_prefix": "karaoke_vj",
                    "images": ["8", 0]
                }
            }
        }
    
    def _inject_prompt_into_workflow(self, workflow: Dict[str, Any], prompt: str) -> Dict[str, Any]:
        """
        Inject prompt text into a custom workflow.
        
        Finds CLIPTextEncode nodes and injects the prompt into the first one
        (assumed to be the positive prompt).
        """
        positive_injected = False
        negative_injected = False
        
        for node_id, node in workflow.items():
            if not isinstance(node, dict):
                continue
                
            class_type = node.get('class_type', '')
            inputs = node.get('inputs', {})
            
            if class_type == 'CLIPTextEncode' and 'text' in inputs:
                if not positive_injected:
                    # First CLIPTextEncode = positive prompt
                    inputs['text'] = prompt
                    positive_injected = True
                elif not negative_injected:
                    # Second CLIPTextEncode = negative prompt
                    inputs['text'] = self.NEGATIVE_PROMPT
                    negative_injected = True
            
            # Update KSampler seed for variety
            if class_type == 'KSampler' and 'seed' in inputs:
                inputs['seed'] = int(time.time()) % 2147483647
        
        return workflow
    
    def _wait_for_image(self, prompt_id: str, output_path: Path, timeout: int = 120) -> Optional[Path]:
        """Wait for image generation to complete and download result."""
        start = time.time()
        
        while time.time() - start < timeout:
            try:
                # Check history for completion
                resp = requests.get(f"{self.COMFYUI_URL}/history/{prompt_id}", timeout=5)
                if resp.status_code == 200:
                    history = resp.json()
                    if prompt_id in history:
                        outputs = history[prompt_id].get('outputs', {})
                        # Find the SaveImage node output
                        for node_id, node_output in outputs.items():
                            if 'images' in node_output:
                                for img_info in node_output['images']:
                                    filename = img_info.get('filename')
                                    subfolder = img_info.get('subfolder', '')
                                    if filename:
                                        # Download the image
                                        return self._download_image(filename, subfolder, output_path)
                
                time.sleep(2)
                
            except requests.RequestException:
                time.sleep(2)
        
        logger.warning("ComfyUI: Image generation timed out")
        return None
    
    def _download_image(self, filename: str, subfolder: str, output_path: Path) -> Optional[Path]:
        """Download generated image from ComfyUI."""
        try:
            params = {"filename": filename}
            if subfolder:
                params["subfolder"] = subfolder
            
            resp = requests.get(f"{self.COMFYUI_URL}/view", params=params, timeout=30)
            if resp.status_code == 200:
                output_path.write_bytes(resp.content)
                return output_path
        except requests.RequestException as e:
            logger.error(f"Failed to download image: {e}")
        
        return None
    
    def _get_image_path(self, artist: str, title: str) -> Path:
        """Get cache path for a song's generated image."""
        safe = re.sub(r'[^\w\s-]', '', f"{artist}_{title}".lower())
        safe = re.sub(r'\s+', '_', safe)
        return self._output_dir / f"{safe}.png"
    
    def get_cached_image(self, artist: str, title: str) -> Optional[Path]:
        """Get path to cached image if it exists."""
        path = self._get_image_path(artist, title)
        return path if path.exists() else None
    
    def get_cached_count(self) -> int:
        """Return number of cached generated images."""
        if self._output_dir.exists():
            return len(list(self._output_dir.glob("*.png")))
        return 0


# =============================================================================
# PLAYBACK MONITORS - Each monitors one source
# =============================================================================

class SpotifyMonitor:
    """
    Monitors Spotify playback with automatic reconnection.
    
    LIVE EVENT BEHAVIOR:
    - Gracefully disabled if credentials not configured
    - Auto-reconnects if connection is lost
    - All errors are caught and logged (never crashes)
    """
    
    def __init__(self):
        self._sp = None
        self._health = ServiceHealth("Spotify")
        self._init_client()
    
    @property
    def is_available(self) -> bool:
        return self._health.available
    
    def _init_client(self):
        """Initialize Spotify client. Safe to call multiple times for reconnection."""
        if not SPOTIFY_AVAILABLE:
            logger.info("Spotify: spotipy not installed (pip install spotipy)")
            return

        if not Config.has_spotify_credentials():
            logger.info("Spotify: credentials not configured")
            logger.info("  Set SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET in .env file")
            return

        try:
            # Ensure cache directory exists
            Config.APP_DATA_DIR.mkdir(parents=True, exist_ok=True)

            # Get credentials from Config and pass them explicitly to SpotifyOAuth
            creds = Config.get_spotify_credentials()
            self._sp = spotipy.Spotify(auth_manager=SpotifyOAuth(
                client_id=creds['client_id'],
                client_secret=creds['client_secret'],
                redirect_uri=creds['redirect_uri'],
                scope="user-read-playback-state",
                cache_path=str(Config.SPOTIFY_TOKEN_CACHE)
            ))
            self._sp.current_user()  # Test connection
            self._health.mark_available()
            logger.info("Spotify: ✓ connected")
        except Exception as e:
            self._health.mark_unavailable(str(e))
            logger.info(f"Spotify: {e} (will retry in {ServiceHealth.RECONNECT_INTERVAL}s)")
    
    def _try_reconnect(self):
        """Attempt to reconnect if service is down and enough time has passed."""
        if not self._health.available and self._health.should_retry:
            logger.debug("Spotify: Attempting reconnection...")
            self._init_client()
    
    def get_playback(self) -> Optional[Dict[str, Any]]:
        """
        Get current Spotify playback or None.
        
        RESILIENCE: Never raises exceptions. Auto-reconnects on failure.
        """
        # Try reconnecting if we're not available
        self._try_reconnect()
        
        if not self._health.available or not self._sp:
            return None
        
        try:
            pb = self._sp.current_playback()
            if pb and pb.get('is_playing') and pb.get('item'):
                item = pb['item']
                # Successful call - ensure we're marked available
                if not self._health.available:
                    self._health.mark_available()
                return {
                    'artist': item['artists'][0]['name'] if item.get('artists') else '',
                    'title': item.get('name', ''),
                    'album': item.get('album', {}).get('name', ''),
                    'duration_ms': item.get('duration_ms', 0),
                    'progress_ms': pb.get('progress_ms', 0),
                }
            return None  # Not playing, but API is working
        except Exception as e:
            self._health.mark_unavailable(str(e))
            logger.debug(f"Spotify error (will retry): {e}")
            return None


class VirtualDJMonitor:
    """
    Monitors VirtualDJ now_playing.txt file with graceful file handling.
    
    LIVE EVENT BEHAVIOR:
    - Auto-detects VirtualDJ folder on macOS
    - Handles file appearing/disappearing during performance
    - All file errors are caught (never crashes)
    """
    
    def __init__(self, file_path: Optional[str] = None):
        self._health = ServiceHealth("VirtualDJ")
        
        if file_path:
            self._path = Path(file_path)
        else:
            self._path = Config.find_vdj_path()
        
        self._last_content = ""
        self._start_time = 0.0
        
        if self._path:
            if self._path.exists():
                self._health.mark_available(str(self._path))
                logger.info(f"VirtualDJ: ✓ found {self._path}")
            else:
                logger.info(f"VirtualDJ: monitoring {self._path} (file not yet created)")
        else:
            logger.info("VirtualDJ: folder not found (will use Spotify only)")
    
    @property
    def is_available(self) -> bool:
        return self._health.available
    
    def get_playback(self) -> Optional[Dict[str, Any]]:
        """
        Get current VirtualDJ track or None.
        
        RESILIENCE: Handles file appearing/disappearing gracefully.
        """
        if not self._path:
            return None
        
        # Check if file exists now (may have appeared)
        if not self._path.exists():
            if self._health.available:
                self._health.mark_unavailable("File removed")
            return None
        
        try:
            content = self._path.read_text().strip()
            if not content:
                return None
            
            # File is readable - mark available if we weren't
            if not self._health.available:
                self._health.mark_available(str(self._path))
            
            # Track change detection
            if content != self._last_content:
                self._last_content = content
                self._start_time = time.time()
            
            # Parse "Artist - Title"
            if " - " in content:
                artist, title = content.split(" - ", 1)
            else:
                artist, title = "", content
            
            return {
                'artist': artist.strip(),
                'title': title.strip(),
                'album': '',
                'duration_ms': 0,
                'progress_ms': int((time.time() - self._start_time) * 1000),
            }
        except Exception as e:
            self._health.mark_unavailable(str(e))
            logger.debug(f"VirtualDJ error: {e}")
            return None


# =============================================================================
# OSC SENDER - Deep module hiding OSC protocol details
# =============================================================================

class OSCSender:
    """
    Sends karaoke data via OSC on 3 channels:
    - /karaoke/... - Full lyrics
    - /karaoke/refrain/... - Chorus only
    - /karaoke/keywords/... - Key words only
    """
    
    def __init__(self, host: str = "127.0.0.1", port: int = 9000):
        self._client = udp_client.SimpleUDPClient(host, port)
        logger.info(f"OSC: sending to {host}:{port}")
    
    # === Track info ===
    
    def send_track(self, track: Track, has_lyrics: bool):
        """Send track metadata."""
        self._client.send_message("/karaoke/track", [
            1, track.source, track.artist, track.title,
            track.album, track.duration_sec, 1 if has_lyrics else 0
        ])
    
    def send_no_track(self):
        """Send inactive state."""
        self._client.send_message("/karaoke/track", [0, "", "", "", "", 0.0, 0])
        self._client.send_message("/karaoke/pos", [0.0, 0])
    
    # === Position ===
    
    def send_position(self, position: float, playing: bool):
        """Send playback position."""
        self._client.send_message("/karaoke/pos", [position, 1 if playing else 0])
    
    # === Full lyrics channel ===
    
    def send_lyrics_reset(self, song_id: str):
        self._client.send_message("/karaoke/lyrics/reset", [song_id])
    
    def send_lyric_line(self, index: int, time_sec: float, text: str):
        self._client.send_message("/karaoke/lyrics/line", [index, time_sec, text])
    
    def send_active_line(self, index: int):
        self._client.send_message("/karaoke/line/active", [index])
    
    # === Refrain channel ===
    
    def send_refrain_reset(self, song_id: str):
        self._client.send_message("/karaoke/refrain/reset", [song_id])
    
    def send_refrain_line(self, index: int, time_sec: float, text: str):
        self._client.send_message("/karaoke/refrain/line", [index, time_sec, text])
    
    def send_refrain_active(self, index: int, text: str):
        self._client.send_message("/karaoke/refrain/active", [index, text])
    
    # === Keywords channel ===
    
    def send_keywords_reset(self, song_id: str):
        self._client.send_message("/karaoke/keywords/reset", [song_id])
    
    def send_keywords_line(self, index: int, time_sec: float, keywords: str):
        self._client.send_message("/karaoke/keywords/line", [index, time_sec, keywords])
    
    def send_keywords_active(self, index: int, keywords: str):
        self._client.send_message("/karaoke/keywords/active", [index, keywords])
    
    # === Image channel ===
    
    def send_image(self, image_path: str):
        """Send image file path to Processing ImageOverlay."""
        self._client.send_message("/karaoke/image", [image_path])
        logger.debug(f"OSC: /karaoke/image [{image_path}]")
    
    def send_image_clear(self):
        """Clear the displayed image."""
        self._client.send_message("/karaoke/image/clear", [])
    
    def send_image_opacity(self, opacity: float):
        """Set image opacity (0.0-1.0)."""
        self._client.send_message("/karaoke/image/opacity", [opacity])


# =============================================================================
# KARAOKE ENGINE - Orchestrates all components
# =============================================================================

class KaraokeEngine:
    """
    Main engine that coordinates:
    - Playback monitoring (Spotify, VirtualDJ)
    - Lyrics fetching and analysis
    - OSC output on 3 channels
    - Adjustable timing offset (positive = lyrics early, negative = late)
    - Pipeline tracking for UI display
    
    Simple interface: start(), stop(), run(), adjust_timing()
    Uses smart defaults from Config class.
    """
    
    def __init__(
        self,
        osc_host: Optional[str] = None,
        osc_port: Optional[int] = None,
        vdj_path: Optional[str] = None,
        state_file: Optional[str] = None
    ):
        # Use Config defaults
        osc_host = osc_host or Config.DEFAULT_OSC_HOST
        osc_port = osc_port or Config.DEFAULT_OSC_PORT
        
        # Dependencies
        self._osc = OSCSender(osc_host, osc_port)
        self._lyrics = LyricsFetcher()
        self._spotify = SpotifyMonitor()
        self._vdj = VirtualDJMonitor(vdj_path)
        self._settings = Settings()  # Persistent settings (timing offset)
        self._llm = LLMAnalyzer()    # AI-powered analysis
        self._comfyui = ComfyUIGenerator()  # Image generation
        
        # Pipeline tracking for UI
        self.pipeline = PipelineTracker()
        
        # State
        self._state = PlaybackState()
        self._last_track_key = ""
        self._current_image_path: Optional[Path] = None
        
        # State file with smart default
        if state_file:
            self._state_file = Path(state_file)
        else:
            self._state_file = Config.DEFAULT_STATE_FILE
            self._state_file.parent.mkdir(parents=True, exist_ok=True)
        
        # Threading
        self._stop = Event()
        self._thread: Optional[Thread] = None
        self._image_thread: Optional[Thread] = None
    
    @property
    def timing_offset_ms(self) -> int:
        """Current timing offset in milliseconds."""
        return self._settings.timing_offset_ms
    
    def adjust_timing(self, delta_ms: int) -> int:
        """
        Adjust timing offset by delta milliseconds.
        Positive = lyrics appear earlier, negative = later.
        Returns new offset value.
        """
        new_offset = self._settings.adjust_timing(delta_ms)
        logger.info(f"Timing offset adjusted to {new_offset}ms")
        return new_offset
    
    def run(self, poll_interval: float = 0.1):
        """Run the engine (blocking). Use start() for background."""
        logger.info("Karaoke Engine started")
        print("\n" + "="*50)
        print("  🎤 Karaoke Engine Running")
        print("="*50)
        offset = self._settings.timing_offset_ms
        print(f"  Timing offset: {offset:+d}ms")
        print(f"  Lyrics cached: {self._lyrics.get_cached_count()}")
        print("  Waiting for music playback...")
        print("  Press Ctrl+C to stop\n")
        
        while not self._stop.is_set():
            try:
                self._tick()
                time.sleep(poll_interval)
            except KeyboardInterrupt:
                break
            except Exception as e:
                logger.error(f"Error: {e}")
                time.sleep(1)
        
        logger.info("Karaoke Engine stopped")
    
    def start(self, poll_interval: float = 0.1):
        """Start engine in background thread."""
        self._stop.clear()
        self._thread = Thread(target=self.run, args=(poll_interval,), daemon=True)
        self._thread.start()
    
    def stop(self):
        """Stop the engine."""
        self._stop.set()
        if self._thread:
            self._thread.join(timeout=2)
    
    def _tick(self):
        """Single update tick."""
        # Get playback from sources (VDJ has priority)
        playback = self._vdj.get_playback() or self._spotify.get_playback()
        
        if not playback:
            if self._state.active:
                logger.info("Playback stopped")
                self._osc.send_no_track()
            self._state.active = False
            self._state.track = None
            self._last_track_key = ""
            return
        
        # Update state
        self._state.active = True
        self._state.position_sec = playback['progress_ms'] / 1000.0
        
        source = "virtualdj" if self._vdj.get_playback() else "spotify"
        self._state.track = Track(
            artist=playback['artist'],
            title=playback['title'],
            album=playback['album'],
            duration_sec=playback['duration_ms'] / 1000.0,
            source=source
        )
        
        # Handle track change
        if self._state.track_key != self._last_track_key:
            self._on_track_change()
            self._last_track_key = self._state.track_key
        
        # Send updates
        self._send_updates()
        self._write_state()
    
    def _on_track_change(self):
        """Handle new track with full pipeline tracking."""
        track = self._state.track
        track_key = f"{track.artist} - {track.title}"
        
        # Reset pipeline for new track
        self.pipeline.reset(track_key)
        
        logger.info(f"Now playing: {track_key}")
        
        # Step 1: Detect playback
        self.pipeline.start("detect_playback", f"{track.source}: {track.artist}")
        self.pipeline.complete("detect_playback", track.title)
        
        # Step 2: Fetch lyrics
        self.pipeline.start("fetch_lyrics", "Checking cache/LRCLIB...")
        lrc = self._lyrics.fetch(track.artist, track.title, track.album, track.duration_sec)
        
        if lrc:
            self.pipeline.complete("fetch_lyrics", f"Found synced lyrics")
            
            # Step 3: Parse LRC
            self.pipeline.start("parse_lrc", "Parsing timecodes...")
            self._state.lines = parse_lrc(lrc)
            self.pipeline.complete("parse_lrc", f"{len(self._state.lines)} lines")
            
            # Step 4: Analyze refrain
            self.pipeline.start("analyze_refrain", "Detecting repeated lines...")
            self._state.lines = detect_refrains(self._state.lines)
            refrain_count = len(get_refrain_lines(self._state.lines))
            self.pipeline.complete("analyze_refrain", f"{refrain_count} refrain lines")
            
            # Step 5: Extract keywords
            self.pipeline.start("extract_keywords", "Filtering stop words...")
            # Keywords are extracted in detect_refrains, just log
            self.pipeline.complete("extract_keywords", "Done")
            
            # Step 6: LLM analysis (if available)
            if self._llm.is_available:
                self.pipeline.start("llm_analysis", f"Using {self._llm.backend_info}...")
                try:
                    llm_result = self._llm.analyze_lyrics(lrc, track.artist, track.title)
                    if llm_result.get('cached'):
                        self.pipeline.complete("llm_analysis", "Loaded from cache")
                    else:
                        themes = llm_result.get('themes', [])
                        self.pipeline.complete("llm_analysis", f"Themes: {', '.join(themes[:3])}")
                    
                    # Step 7: Generate image prompt
                    if llm_result.get('image_prompt'):
                        self.pipeline.start("generate_image_prompt", "Creating visual prompt...")
                        self.pipeline.set_image_prompt(llm_result['image_prompt'])
                        self.pipeline.complete("generate_image_prompt", "Generated")
                    else:
                        self.pipeline.start("generate_image_prompt", "Generating from metadata...")
                        prompt = self._llm.generate_image_prompt(
                            track.artist, track.title,
                            llm_result.get('keywords', []),
                            llm_result.get('themes', [])
                        )
                        self.pipeline.set_image_prompt(prompt)
                        self.pipeline.complete("generate_image_prompt", "Generated")
                except Exception as e:
                    self.pipeline.error("llm_analysis", str(e)[:40])
                    self.pipeline.skip("generate_image_prompt", "LLM failed")
            else:
                self.pipeline.skip("llm_analysis", "No LLM available")
                self.pipeline.start("generate_image_prompt", "Basic prompt...")
                prompt = self._llm._basic_image_prompt(
                    track.artist, track.title,
                    [l.keywords for l in self._state.lines[:5] if l.keywords],
                    []
                )
                self.pipeline.set_image_prompt(prompt)
                self.pipeline.complete("generate_image_prompt", "Basic prompt")
            
            logger.info(f"Loaded {len(self._state.lines)} lines ({refrain_count} refrain)")
        else:
            self.pipeline.error("fetch_lyrics", "No synced lyrics found")
            self.pipeline.skip("parse_lrc", "No lyrics")
            self.pipeline.skip("analyze_refrain", "No lyrics")
            self.pipeline.skip("extract_keywords", "No lyrics")
            self.pipeline.skip("llm_analysis", "No lyrics")
            self.pipeline.skip("generate_image_prompt", "No lyrics")
            self.pipeline.skip("comfyui_generate", "No prompt")
            self._state.lines = []
        
        # Step 8a: Generate image with ComfyUI (async in background)
        if self.pipeline.image_prompt and self._comfyui.is_available:
            self._start_image_generation(track)
        elif not self._comfyui.is_available:
            self.pipeline.skip("comfyui_generate", "ComfyUI not available")
        
        # Check for cached image and send immediately
        cached_image = self._comfyui.get_cached_image(track.artist, track.title)
        if cached_image:
            self.pipeline.complete("comfyui_generate", f"Using cached: {cached_image.name}")
            self._osc.send_image(str(cached_image))
            self._current_image_path = cached_image
            self.pipeline.generated_image_path = str(cached_image)
        
        # Step 9: Send OSC
        self.pipeline.start("send_osc", "Sending to Processing...")
        self._osc.send_track(track, len(self._state.lines) > 0)
        
        # Send all lines on all channels
        song_id = self._state.track_key
        self._osc.send_lyrics_reset(song_id)
        self._osc.send_refrain_reset(song_id)
        self._osc.send_keywords_reset(song_id)
        
        refrain_idx = 0
        for i, line in enumerate(self._state.lines):
            # Full lyrics
            self._osc.send_lyric_line(i, line.time_sec, line.text)
            # Keywords
            self._osc.send_keywords_line(i, line.time_sec, line.keywords)
            # Refrain (separate index)
            if line.is_refrain:
                self._osc.send_refrain_line(refrain_idx, line.time_sec, line.text)
                refrain_idx += 1
        
        self.pipeline.complete("send_osc", f"Sent {len(self._state.lines)} lines")
    
    def _send_updates(self):
        """Send position and active line updates with timing offset applied."""
        pos = self._state.position_sec
        self._osc.send_position(pos, True)
        
        # Apply timing offset: positive offset = lyrics early (add to position)
        adjusted_pos = pos + self._settings.timing_offset_sec
        
        active = get_active_line_index(self._state.lines, adjusted_pos)
        self._osc.send_active_line(active)
        
        if active >= 0 and active < len(self._state.lines):
            line = self._state.lines[active]
            # Keywords for current line
            self._osc.send_keywords_active(active, line.keywords)
            # Refrain active (find refrain index)
            if line.is_refrain:
                refrain_idx = len([l for l in self._state.lines[:active+1] if l.is_refrain]) - 1
                self._osc.send_refrain_active(refrain_idx, line.text)
    
    def _write_state(self):
        """Write debug state file."""
        try:
            state = {
                'active': self._state.active,
                'position_sec': self._state.position_sec,
                'track': {
                    'artist': self._state.track.artist if self._state.track else '',
                    'title': self._state.track.title if self._state.track else '',
                    'source': self._state.track.source if self._state.track else '',
                } if self._state.track else None,
                'lines_count': len(self._state.lines),
                'refrain_count': len(get_refrain_lines(self._state.lines)),
                'image_path': str(self._current_image_path) if self._current_image_path else None,
            }
            tmp = self._state_file.with_suffix('.tmp')
            tmp.write_text(json.dumps(state, indent=2))
            tmp.rename(self._state_file)
        except Exception:
            pass
    
    def _start_image_generation(self, track: Track):
        """Start ComfyUI image generation in background thread."""
        if self._image_thread and self._image_thread.is_alive():
            logger.debug("Image generation already in progress")
            return
        
        prompt = self.pipeline.image_prompt
        if not prompt:
            return
        
        self.pipeline.start("comfyui_generate", "Generating with ComfyUI...")
        
        def generate():
            try:
                image_path = self._comfyui.generate_image(
                    prompt=prompt,
                    artist=track.artist,
                    title=track.title
                )
                
                if image_path:
                    self._current_image_path = image_path
                    self.pipeline.generated_image_path = str(image_path)
                    self.pipeline.complete("comfyui_generate", f"Generated: {image_path.name}")
                    self.pipeline.log(f"Image saved: {image_path}")
                    
                    # Send the image path via OSC to Processing ImageOverlay
                    self._osc.send_image(str(image_path))
                    logger.info(f"Sent image to Processing: {image_path}")
                else:
                    self.pipeline.error("comfyui_generate", "Generation failed")
                    
            except Exception as e:
                self.pipeline.error("comfyui_generate", str(e)[:40])
                logger.error(f"ComfyUI generation error: {e}")
        
        self._image_thread = Thread(target=generate, daemon=True)
        self._image_thread.start()


# =============================================================================
# MAIN - For standalone testing. Use vj_console.py as main entry point.
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
  /karaoke/...          Full lyrics
  /karaoke/refrain/...  Chorus/refrain only
  /karaoke/keywords/... Key words only
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
        engine.run(poll_interval=args.poll_interval)
    except KeyboardInterrupt:
        print("\n  Goodbye! 👋")


if __name__ == '__main__':
    main()
