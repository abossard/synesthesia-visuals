#!/usr/bin/env python3
"""
Karaoke Engine - Monitors Spotify/VirtualDJ and sends lyrics via OSC

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
from typing import Optional, List, Dict, Any
from threading import Thread, Event

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
    
    # Timing adjustment step (200ms per key press)
    TIMING_STEP_MS = 200
    
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
            'redirect_uri': os.environ.get('SPOTIPY_REDIRECT_URI', 'http://localhost:8888/callback'),
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
        self._available = False
        self._backend = "none"
        self._init_backend()
    
    def _init_backend(self):
        """Initialize the best available LLM backend."""
        # Try OpenAI first
        openai_key = os.environ.get('OPENAI_API_KEY', '')
        if openai_key:
            try:
                import openai
                self._openai_client = openai.OpenAI(api_key=openai_key)
                # Test connection
                self._openai_client.models.list()
                self._available = True
                self._backend = "openai"
                logger.info("LLM: ✓ OpenAI connected")
                return
            except Exception as e:
                logger.debug(f"OpenAI init failed: {e}")
        
        # Fall back to local Ollama
        self._init_ollama()
    
    def _init_ollama(self):
        """Initialize Ollama with auto-detected model."""
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
                
                self._available = True
                self._backend = "ollama"
                logger.info(f"LLM: ✓ Ollama using {self._ollama_model} (from {len(available_names)} models)")
        except requests.RequestException:
            logger.info("LLM: Ollama not available (using basic analysis)")
    
    @property
    def is_available(self) -> bool:
        return self._available
    
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
                'cached': bool                             # True if from cache
            }
        """
        # Check cache first
        cache_file = self._get_cache_path(artist, title)
        if cache_file.exists():
            try:
                data = json.loads(cache_file.read_text())
                data['cached'] = True
                return data
            except (json.JSONDecodeError, IOError):
                pass
        
        if not self._available:
            return self._basic_analysis(lyrics)
        
        # Build prompt
        prompt = f"""Analyze these song lyrics and extract:
1. REFRAIN: The chorus or refrain lines (text that repeats and is the emotional core)
2. KEYWORDS: 5-10 most emotionally impactful or important single words
3. THEMES: 2-3 main themes of the song

Song: "{title}" by {artist}

Lyrics:
{lyrics[:3000]}

Respond in JSON format:
{{"refrain_lines": ["line1", "line2"], "keywords": ["word1", "word2"], "themes": ["theme1", "theme2"]}}
"""
        
        try:
            result = self._call_llm(prompt)
            if result:
                # Cache the result
                self._save_to_cache(cache_file, result)
                result['cached'] = False
                return result
        except Exception as e:
            logger.debug(f"LLM analysis failed: {e}")
        
        return self._basic_analysis(lyrics)
    
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
# PLAYBACK MONITORS - Each monitors one source
# =============================================================================

class SpotifyMonitor:
    """Monitors Spotify playback. Gracefully disabled if unavailable."""
    
    def __init__(self):
        self._sp = None
        self._available = False
        self._init_client()
    
    def _init_client(self):
        if not SPOTIFY_AVAILABLE:
            logger.info("Spotify: spotipy not installed (pip install spotipy)")
            return
        
        if not Config.has_spotify_credentials():
            logger.info("Spotify: credentials not configured")
            logger.info("  Set SPOTIPY_CLIENT_ID and SPOTIPY_CLIENT_SECRET in .env file")
            return
        
        try:
            self._sp = spotipy.Spotify(auth_manager=SpotifyOAuth(
                scope="user-read-playback-state"
            ))
            self._sp.current_user()  # Test connection
            self._available = True
            logger.info("Spotify: ✓ connected")
        except Exception as e:
            logger.warning(f"Spotify: {e}")
    
    def get_playback(self) -> Optional[Dict[str, Any]]:
        """Get current Spotify playback or None."""
        if not self._available:
            return None
        
        try:
            pb = self._sp.current_playback()
            if pb and pb.get('is_playing') and pb.get('item'):
                item = pb['item']
                return {
                    'artist': item['artists'][0]['name'] if item.get('artists') else '',
                    'title': item.get('name', ''),
                    'album': item.get('album', {}).get('name', ''),
                    'duration_ms': item.get('duration_ms', 0),
                    'progress_ms': pb.get('progress_ms', 0),
                }
        except Exception as e:
            logger.debug(f"Spotify error: {e}")
        
        return None


class VirtualDJMonitor:
    """Monitors VirtualDJ now_playing.txt file. Auto-detects folder on macOS."""
    
    def __init__(self, file_path: Optional[str] = None):
        if file_path:
            self._path = Path(file_path)
        else:
            self._path = Config.find_vdj_path()
        
        self._last_content = ""
        self._start_time = 0.0
        
        if self._path:
            if self._path.exists():
                logger.info(f"VirtualDJ: ✓ found {self._path}")
            else:
                logger.info(f"VirtualDJ: monitoring {self._path} (file not yet created)")
        else:
            logger.info("VirtualDJ: folder not found (will use Spotify only)")
    
    def get_playback(self) -> Optional[Dict[str, Any]]:
        """Get current VirtualDJ track or None."""
        if not self._path or not self._path.exists():
            return None
        
        try:
            content = self._path.read_text().strip()
            if not content:
                return None
            
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
        
        # State
        self._state = PlaybackState()
        self._last_track_key = ""
        
        # State file with smart default
        if state_file:
            self._state_file = Path(state_file)
        else:
            self._state_file = Config.DEFAULT_STATE_FILE
            self._state_file.parent.mkdir(parents=True, exist_ok=True)
        
        # Threading
        self._stop = Event()
        self._thread: Optional[Thread] = None
    
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
        """Handle new track."""
        track = self._state.track
        logger.info(f"Now playing: {track.artist} - {track.title}")
        print(f"\n  🎵 {track.artist} - {track.title}")
        
        # Fetch and analyze lyrics
        lrc = self._lyrics.fetch(track.artist, track.title, track.album, track.duration_sec)
        
        if lrc:
            self._state.lines = analyze_lyrics(parse_lrc(lrc))
            refrain_count = len(get_refrain_lines(self._state.lines))
            logger.info(f"Loaded {len(self._state.lines)} lines ({refrain_count} refrain)")
            print(f"     Lyrics: {len(self._state.lines)} lines, {refrain_count} refrain")
        else:
            self._state.lines = []
            print("     No synced lyrics available")
        
        # Send track info
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
            }
            tmp = self._state_file.with_suffix('.tmp')
            tmp.write_text(json.dumps(state, indent=2))
            tmp.rename(self._state_file)
        except Exception:
            pass


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
