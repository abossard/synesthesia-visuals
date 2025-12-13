#!/usr/bin/env python3
"""
External Service Adapters

Deep modules that hide protocol complexity behind simple interfaces.
Each adapter handles one external service (Spotify, VirtualDJ, LRCLIB, OSC).
"""

import json
import re
import time
import logging
import subprocess
import requests
from pathlib import Path
from typing import Optional, Dict, Any, List

from domain import sanitize_cache_filename
from infrastructure import ServiceHealth, Config
from osc_manager import osc

logger = logging.getLogger('karaoke')

# Optional Spotify support
try:
    import spotipy
    from spotipy.oauth2 import SpotifyOAuth
    SPOTIFY_AVAILABLE = True
except ImportError:
    SPOTIFY_AVAILABLE = False


# =============================================================================
# LYRICS FETCHER - Deep module with LRCLIB + LM Studio web-search fallback
# =============================================================================

class LyricsFetcher:
    """
    Fetches lyrics and song metadata.
    
    Simple interface:
        fetch_lrc(artist, title) -> Optional[str]  # Synced LRC for karaoke timing
        fetch_metadata(artist, title) -> Dict      # Plain lyrics, keywords, song info, merged AI analysis
    
    Strategy:
    - LRC lyrics: LRCLIB API only (fast, accurate timestamps)
    - Metadata: LM Studio with web-search MCP (plain lyrics, keywords, song info)
    
    Both are cached together but serve different purposes.
    """
    
    BASE_URL = "https://lrclib.net/api"
    LM_STUDIO_URL = "http://localhost:1234"
    CACHE_TTL_SECONDS = 86400 * 7  # 7 days
    LM_RECHECK_INTERVAL = 30  # seconds between availability retries when offline
    
    def __init__(self, cache_dir: Optional[Path] = None):
        self._cache_dir = cache_dir or Config.DEFAULT_LYRICS_CACHE_DIR
        self._cache_dir.mkdir(parents=True, exist_ok=True)
        self._session = requests.Session()
        self._session.headers["User-Agent"] = "KaraokeEngine/1.0"
        self._lmstudio_available = None
        self._lmstudio_model = None
        self._lmstudio_last_check = 0.0
    
    # =========================================================================
    # PUBLIC API
    # =========================================================================
    
    def fetch(self, artist: str, title: str, album: str = "", duration: float = 0) -> Optional[str]:
        """
        Fetch synced LRC lyrics for karaoke timing. Returns LRC string or None.
        Only returns lyrics with timestamps [mm:ss.xx] - never plain lyrics.
        """
        cache = self._load_cache(artist, title)
        
        # Return cached LRC if available
        if cache.get('syncedLyrics'):
            logger.debug(f"Using cached LRC: {artist} - {title}")
            return cache['syncedLyrics']
        
        # Fetch from LRCLIB
        lrc = self._fetch_from_lrclib(artist, title, album, duration)
        if lrc:
            cache['syncedLyrics'] = lrc
            cache['lrc_source'] = 'lrclib'
            cache['lrc_fetched_at'] = time.time()
            self._save_cache(artist, title, cache)
            logger.info(f"Fetched LRC from LRCLIB: {artist} - {title}")
            return lrc
        
        logger.debug(f"No LRC available: {artist} - {title}")
        return None
    
    def fetch_metadata(self, artist: str, title: str) -> Dict[str, Any]:
        """
        Fetch song metadata via LLM: plain lyrics, keywords, song info, and lyric analysis insights.
        Always returns a dict (may be empty if LLM unavailable).
        """
        cache = self._load_cache(artist, title)
        
        # Return cached metadata if fresh
        if cache.get('metadata') and cache.get('metadata_fetched_at'):
            age = time.time() - cache['metadata_fetched_at']
            if age < self.CACHE_TTL_SECONDS:
                logger.debug(f"Using cached metadata: {artist} - {title}")
                return cache['metadata']
        
        # Fetch via LLM
        if not self._check_lmstudio():
            logger.debug("LM Studio not available for metadata fetch")
            return cache.get('metadata', {})
        
        metadata = self._fetch_metadata_via_llm(artist, title)
        if metadata:
            cache['metadata'] = metadata
            cache['metadata_fetched_at'] = time.time()
            self._save_cache(artist, title, cache)
            logger.info(f"Fetched metadata via LLM: {artist} - {title}")
        
        return metadata or {}
    
    def get_cached_count(self) -> int:
        """Return number of cached files."""
        if self._cache_dir.exists():
            return len(list(self._cache_dir.glob("*.json")))
        return 0
    
    # Backwards compatibility
    def get_song_info(self, artist: str, title: str) -> Optional[Dict[str, Any]]:
        """Alias for fetch_metadata."""
        result = self.fetch_metadata(artist, title)
        return result if result else None
    
    # =========================================================================
    # PRIVATE - LRCLIB
    # =========================================================================
    
    def _fetch_from_lrclib(self, artist: str, title: str, album: str, duration: float) -> Optional[str]:
        """Fetch synced LRC from LRCLIB API."""
        try:
            params = {"artist_name": artist, "track_name": title}
            if album:
                params["album_name"] = album
            if duration > 0:
                params["duration"] = str(int(duration))
            
            resp = self._session.get(f"{self.BASE_URL}/get", params=params, timeout=10)
            
            if resp.status_code == 200:
                data = resp.json()
                return data.get('syncedLyrics')
            elif resp.status_code != 404:
                logger.warning(f"LRCLIB error {resp.status_code}")
        except requests.RequestException as e:
            logger.error(f"LRCLIB fetch error: {e}")
        
        return None
    
    # =========================================================================
    # PRIVATE - LM STUDIO
    # =========================================================================
    
    def _check_lmstudio(self) -> bool:
        """Check if LM Studio is available."""
        now = time.time()
        if self._lmstudio_available is not None:
            if self._lmstudio_available:
                return True
            # If previously offline, recheck after interval
            if (now - self._lmstudio_last_check) < self.LM_RECHECK_INTERVAL:
                return False
        
        try:
            resp = self._session.get(f"{self.LM_STUDIO_URL}/v1/models", timeout=2)
            if resp.status_code == 200:
                models = resp.json().get('data', [])
                if models:
                    self._lmstudio_model = models[0].get('id', 'local-model')
                    self._lmstudio_available = True
                    self._lmstudio_last_check = now
                    logger.debug(f"LM Studio available: {self._lmstudio_model}")
                    return True
        except Exception:
            pass
        
        self._lmstudio_available = False
        self._lmstudio_last_check = now
        return False
    
    def _ask_lmstudio(self, system_prompt: str, user_prompt: str, timeout: int = 90) -> Optional[str]:
        """
        Send a prompt to LM Studio and get the response.
        LM Studio has MCP configured with web-search - model uses it automatically.
        """
        if not self._check_lmstudio():
            return None
        
        try:
            resp = self._session.post(
                f"{self.LM_STUDIO_URL}/v1/chat/completions",
                json={
                    "model": self._lmstudio_model,
                    "messages": [
                        {"role": "system", "content": system_prompt},
                        {"role": "user", "content": user_prompt}
                    ],
                    "max_tokens": 3000,
                    "temperature": 0.3
                },
                timeout=timeout
            )
            
            if resp.status_code == 200:
                result = resp.json()
                return result.get('choices', [{}])[0].get('message', {}).get('content', '')
        except requests.Timeout:
            logger.debug("LM Studio request timed out")
        except Exception as e:
            logger.debug(f"LM Studio error: {e}")
        
        return None

    def _fetch_metadata_via_llm(self, artist: str, title: str) -> Optional[Dict[str, Any]]:
        """
        Fetch song metadata via LM Studio: plain lyrics, keywords, song info, and condensed lyric analysis.
        Uses web-search MCP to find accurate information.
        """
        system_prompt = """You are a music information assistant with access to web search.
Search for complete information about the requested song and return a JSON object with:
{
    "plain_lyrics": "full lyrics text without timestamps",
    "keywords": ["list", "of", "significant", "words", "from", "lyrics"],
    "themes": ["main", "themes"],
    "release_date": "year or date",
    "album": "album name",
    "genre": "genre(s)",
    "writers": "songwriters",
    "mood": "overall mood/feeling",
    "analysis": {
        "summary": "two-sentence vivid summary of the song story and energy",
        "refrain_lines": ["notable repeated lyric lines"],
        "emotions": ["dominant emotions"],
        "visual_adjectives": ["adjectives helpful for VJ visuals"],
        "tempo": "slow|mid|fast description",
        "keywords": ["repeat or expand keyword list for redundancy"]
    }
}

For keywords: extract 8-15 most significant/meaningful words from the lyrics - 
words that capture the essence, emotions, and imagery of the song.
Exclude common words like "the", "and", "is", etc.
Keep refrain_lines short (under 80 characters) and only include lines that repeat.

Return ONLY valid JSON, no other text."""

        user_prompt = f'Search the web for complete lyrics and information about "{title}" by {artist}.'

        logger.debug(f"Fetching metadata via LLM: {artist} - {title}")
        content = self._ask_lmstudio(system_prompt, user_prompt, timeout=120)

        if not content:
            return None

        # Extract JSON from response
        try:
            start = content.find('{')
            end = content.rfind('}')
            if start >= 0 and end > start:
                metadata = json.loads(content[start:end+1])
                metadata['fetched_at'] = time.time()
                metadata['source'] = 'llm_web_search'
                return metadata
        except json.JSONDecodeError:
            logger.debug(f"Failed to parse metadata JSON: {content[:200]}")

        return None
    
    # =========================================================================
    # PRIVATE - CACHE
    # =========================================================================
    
    def _load_cache(self, artist: str, title: str) -> Dict:
        """Load cache for artist/title, returns empty dict if not found."""
        cache_file = self._get_cache_path(artist, title)
        if cache_file.exists():
            try:
                return json.loads(cache_file.read_text())
            except (json.JSONDecodeError, IOError):
                pass
        return {}
    
    def _save_cache(self, artist: str, title: str, data: Dict):
        """Save cache data, merging with existing."""
        cache_file = self._get_cache_path(artist, title)
        try:
            existing = self._load_cache(artist, title)
            existing.update(data)
            cache_file.write_text(json.dumps(existing, indent=2))
        except IOError:
            pass
    
    def _get_cache_path(self, artist: str, title: str) -> Path:
        """Generate cache file path from artist/title."""
        safe = sanitize_cache_filename(artist, title)
        return self._cache_dir / f"{safe}.json"


# =============================================================================
# APPLESCRIPT SPOTIFY MONITOR - Local desktop playback via osascript
# =============================================================================

class AppleScriptSpotifyMonitor:
    """Reads Spotify playback via bundled AppleScript (macOS only)."""

    monitor_key = "spotify_local"
    monitor_label = "Spotify (AppleScript)"

    def __init__(self, script_path: Optional[Path] = None, timeout: Optional[float] = None):
        cfg = Config.apple_script_config()
        self._script_path = Path(script_path) if script_path else cfg['script_path']
        self._timeout = timeout if timeout is not None else cfg['timeout']
        self._health = ServiceHealth(self.monitor_label)
        self._notified_online = False

    def get_playback(self) -> Optional[Dict[str, Any]]:
        """Execute AppleScript and convert the JSON payload into playback dict."""
        if not self._script_path.exists():
            self._health.mark_unavailable(f"Missing AppleScript: {self._script_path}")
            return None

        try:
            result = subprocess.run(
                ["osascript", str(self._script_path)],
                capture_output=True,
                text=True,
                timeout=self._timeout,
                check=False,
            )
        except FileNotFoundError:
            self._health.mark_unavailable("osascript not found (macOS only)")
            return None
        except subprocess.TimeoutExpired:
            self._health.mark_unavailable("AppleScript timeout")
            return None

        if result.returncode != 0:
            message = result.stderr.strip() or result.stdout.strip() or f"osascript exit {result.returncode}"
            self._health.mark_unavailable(message)
            return None

        raw_output = (result.stdout or "").strip()
        if not raw_output:
            self._health.mark_unavailable("Empty AppleScript response")
            return None

        try:
            payload = json.loads(raw_output)
        except json.JSONDecodeError as exc:
            self._health.mark_unavailable(f"Invalid AppleScript JSON: {exc}")
            return None

        artist = (payload.get('artist') or '').strip()
        title = (payload.get('title') or '').strip()
        if not artist and not title:
            self._health.mark_unavailable("No Spotify track data")
            return None

        playback = {
            'artist': artist,
            'title': title,
            'album': payload.get('album', ''),
            'duration_ms': int(payload.get('duration_ms', 0) or 0),
            'progress_ms': int(payload.get('progress_ms', 0) or 0),
            'is_playing': bool(payload.get('is_playing', False)),
        }

        self._health.mark_available("AppleScript OK")
        if not self._notified_online:
            logger.info(
                "Spotify (AppleScript): Desktop app detected via AppleScript. Keep Spotify running and online; "
                "Web API fallback stays idle until AppleScript fails."
            )
            self._notified_online = True
        return playback

    @property
    def status(self) -> Dict[str, Any]:
        return self._health.get_status()


# =============================================================================
# SPOTIFY MONITOR - Deep module hiding OAuth complexity
# =============================================================================

class SpotifyMonitor:
    """
    Monitors Spotify playback with automatic reconnection.
    
    Deep module - simple interface, complex implementation.
    Public interface: get_playback() -> Optional[Dict]
    Hides: OAuth flow, token caching, reconnection logic, error handling
    """
    
    monitor_key = "spotify_api"
    monitor_label = "Spotify (Web API)"

    def __init__(self):
        self._sp = None
        self._health = ServiceHealth(self.monitor_label)
        self._logged_no_credentials = False  # Only log once
        # Lazy initialization: only attempt Web API connection if this monitor is actually polled
        # (e.g., AppleScript failed or has been disabled).
    
    @property
    def is_available(self) -> bool:
        """Check if Spotify is currently connected."""
        return self._health.available
    
    def get_playback(self) -> Optional[Dict[str, Any]]:
        """
        Get current Spotify playback or None.
        Never raises exceptions. Auto-reconnects on failure.
        """
        self._try_reconnect()
        
        if not self._health.available or not self._sp:
            return None
        
        try:
            pb = self._sp.current_playback()
            if pb and pb.get('is_playing') and pb.get('item'):
                item = pb['item']
                if not self._health.available:
                    self._health.mark_available()
                return {
                    'artist': item['artists'][0]['name'] if item.get('artists') else '',
                    'title': item.get('name', ''),
                    'album': item.get('album', {}).get('name', ''),
                    'duration_ms': item.get('duration_ms', 0),
                    'progress_ms': pb.get('progress_ms', 0),
                    'is_playing': True,
                }
            return None
        except Exception as e:
            self._health.mark_unavailable(str(e))
            logger.debug(f"Spotify error (will retry): {e}")
            return None
    
    # Private methods - implementation details
    
    def _init_client(self):
        """Initialize Spotify client. Safe to call multiple times for reconnection."""
        if not SPOTIFY_AVAILABLE:
            if not self._logged_no_credentials:
                logger.info("Spotify: spotipy not installed (pip install spotipy)")
                self._logged_no_credentials = True
            return

        if not Config.has_spotify_credentials():
            if not self._logged_no_credentials:
                logger.info("Spotify: credentials not configured")
                logger.info("  Set SPOTIPY_CLIENT_ID and SPOTIPY_CLIENT_SECRET in .env file")
                self._logged_no_credentials = True
            return

        try:
            Config.APP_DATA_DIR.mkdir(parents=True, exist_ok=True)
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

    @property
    def status(self) -> Dict[str, Any]:
        """Public access to health status for UI use."""
        return self._health.get_status()


# =============================================================================
# VIRTUALDJ MONITOR - Deep module hiding file polling complexity
# =============================================================================

class VirtualDJMonitor:
    """
    Monitors VirtualDJ tracklist.txt file with smart parsing.
    
    Deep module - simple interface, complex implementation.
    Public interface: get_playback() -> Optional[Dict]
    Hides: File polling, path detection, tracklist parsing, timing estimation, error handling
    
    Supports both formats:
    - Simple: "Artist - Title" (one line)
    - Tracklist: Multi-line history with timestamps (reads last entry)
    """
    
    monitor_key = "virtualdj"
    monitor_label = "VirtualDJ"

    def __init__(self, file_path: Optional[str] = None):
        self._health = ServiceHealth(self.monitor_label)
        self._path = Path(file_path) if file_path else Config.find_vdj_path()
        self._last_track = ""
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
        """Check if VirtualDJ file is accessible."""
        return self._health.available
    
    def get_playback(self) -> Optional[Dict[str, Any]]:
        """
        Get current VirtualDJ track or None.
        Handles file appearing/disappearing gracefully.
        Supports both single-line and tracklist history formats.
        """
        if not self._path or not self._path.exists():
            if self._path and self._health.available:
                self._health.mark_unavailable("File removed")
            return None
        
        try:
            content = self._path.read_text().strip()
            if not content:
                return None
            
            if not self._health.available:
                self._health.mark_available(str(self._path))
            
            # Extract current track (handles both formats)
            current_track = self._extract_current_track(content)
            if not current_track:
                return None
            
            # Track change detection
            if current_track != self._last_track:
                self._last_track = current_track
                self._start_time = time.time()
            
            # Parse "Artist - Title"
            artist, title = self._parse_track_string(current_track)
            
            return {
                'artist': artist,
                'title': title,
                'album': '',
                'duration_ms': 0,
                'progress_ms': int((time.time() - self._start_time) * 1000),
                'is_playing': True,
            }
        except Exception as e:
            self._health.mark_unavailable(str(e))
            logger.debug(f"VirtualDJ error: {e}")
            return None
    
    # Private methods - implementation details
    
    def _extract_current_track(self, content: str) -> Optional[str]:
        """
        Extract current track from VirtualDJ file content.
        
        Handles two formats:
        1. Single line: "Artist - Title"
        2. Tracklist history:
           VirtualDJ History 2024/11/30
           ------------------------------
           22:50 : Bolier, Joe Stone - Keep This Fire Burning
           
        For tracklist format, returns the last timestamped entry.
        """
        lines = content.strip().split('\n')
        
        # Single-line format (legacy)
        if len(lines) == 1:
            return lines[0].strip()
        
        # Multi-line tracklist format - find last timestamped entry
        # Format: "HH:MM : Artist - Title"
        last_track = None
        for line in reversed(lines):
            line = line.strip()
            # Look for timestamp pattern (HH:MM :)
            if ':' in line and len(line) > 8:
                parts = line.split(' : ', 1)
                if len(parts) == 2 and self._is_timestamp(parts[0]):
                    last_track = parts[1]
                    break
        
        return last_track
    
    def _is_timestamp(self, text: str) -> bool:
        """Check if text looks like a timestamp (HH:MM)."""
        parts = text.split(':')
        if len(parts) != 2:
            return False
        try:
            hours, mins = int(parts[0]), int(parts[1])
            return 0 <= hours <= 23 and 0 <= mins <= 59
        except ValueError:
            return False
    
    def _parse_track_string(self, content: str) -> tuple:
        """Parse 'Artist - Title' format."""
        if " - " in content:
            artist, title = content.split(" - ", 1)
            return artist.strip(), title.strip()
        return "", content.strip()

    @property
    def status(self) -> Dict[str, Any]:
        """Public access to health status for UI use."""
        return self._health.get_status()


# =============================================================================
# DJ.STUDIO MONITOR - Multi-strategy monitor (AppleScript, file, window title)
# =============================================================================

class DJStudioMonitor:
    """
    Monitors DJ.Studio playback using multiple strategies.
    
    Deep module - simple interface, complex implementation.
    Public interface: get_playback() -> Optional[Dict]
    
    Strategies (in order):
    1. AppleScript - if DJ.Studio supports it (check window title)
    2. File monitoring - check for exported track info files
    3. Window title parsing - extract track info from window title
    
    DJ.Studio may export current track to files like:
    - ~/Documents/DJ.Studio/current_track.txt
    - ~/Library/Application Support/DJ.Studio/now_playing.txt
    - Or display track info in window title
    """
    
    monitor_key = "djstudio"
    monitor_label = "DJ.Studio"
    
    # Possible file paths where DJ.Studio might export track info
    DJSTUDIO_FILE_PATHS = [
        Path.home() / "Documents" / "DJ.Studio" / "current_track.txt",
        Path.home() / "Documents" / "DJ.Studio" / "now_playing.txt",
        Path.home() / "Library" / "Application Support" / "DJ.Studio" / "current_track.txt",
        Path.home() / "Library" / "Application Support" / "DJ.Studio" / "now_playing.txt",
        Path("/tmp") / "djstudio_now_playing.txt",
    ]
    
    def __init__(self, script_path: Optional[Path] = None, file_path: Optional[Path] = None, timeout: float = 1.5):
        self._script_path = script_path or (Config.SCRIPTS_DIR / "djstudio_track.applescript")
        self._explicit_file_path = file_path
        self._timeout = timeout
        self._health = ServiceHealth(self.monitor_label)
        self._last_track = ""
        self._start_time = 0.0
        self._notified_online = False
        
        # Find file path if not explicit
        if not self._explicit_file_path:
            for path in self.DJSTUDIO_FILE_PATHS:
                if path.exists():
                    self._explicit_file_path = path
                    logger.info(f"DJ.Studio: found track file at {path}")
                    break
    
    @property
    def is_available(self) -> bool:
        """Check if DJ.Studio is accessible."""
        return self._health.available
    
    def get_playback(self) -> Optional[Dict[str, Any]]:
        """
        Get current DJ.Studio track using available strategy.
        Tries: AppleScript → File monitoring → Window title parsing
        """
        # Strategy 1: AppleScript (if script exists)
        if self._script_path.exists():
            playback = self._try_applescript()
            if playback:
                return playback
        
        # Strategy 2: File monitoring (if file exists)
        if self._explicit_file_path and self._explicit_file_path.exists():
            playback = self._try_file_monitoring()
            if playback:
                return playback
        
        # Strategy 3: Window title parsing (requires osascript)
        playback = self._try_window_title()
        if playback:
            return playback
        
        # No strategy worked
        if self._health.available:
            self._health.mark_unavailable("DJ.Studio not detected or not playing")
        return None
    
    @property
    def status(self) -> Dict[str, Any]:
        """Public access to health status for UI use."""
        return self._health.get_status()
    
    # Private methods - implementation details
    
    def _try_applescript(self) -> Optional[Dict[str, Any]]:
        """Try to get track info via AppleScript."""
        try:
            result = subprocess.run(
                ["osascript", str(self._script_path)],
                capture_output=True,
                text=True,
                timeout=self._timeout,
                check=False,
            )
            
            if result.returncode != 0:
                return None
            
            raw_output = (result.stdout or "").strip()
            if not raw_output:
                return None
            
            payload = json.loads(raw_output)
            
            # Check if we got useful track info
            if not payload.get('running'):
                return None
            
            # If AppleScript worked but DJ.Studio isn't scriptable,
            # we'll fall through to other strategies
            if not payload.get('scriptable', False):
                return None
            
            # Extract track info if available
            artist = payload.get('artist', '').strip()
            title = payload.get('title', '').strip()
            
            if not artist and not title:
                return None
            
            playback = {
                'artist': artist,
                'title': title,
                'album': payload.get('album', ''),
                'duration_ms': int(payload.get('duration_ms', 0) or 0),
                'progress_ms': int(payload.get('progress_ms', 0) or 0),
                'is_playing': bool(payload.get('is_playing', True)),
            }
            
            self._health.mark_available("AppleScript")
            if not self._notified_online:
                logger.info("DJ.Studio: Detected via AppleScript")
                self._notified_online = True
            return playback
            
        except (subprocess.TimeoutExpired, json.JSONDecodeError, Exception):
            return None
    
    def _try_file_monitoring(self) -> Optional[Dict[str, Any]]:
        """Try to get track info from file export."""
        if not self._explicit_file_path or not self._explicit_file_path.exists():
            return None
        
        try:
            content = self._explicit_file_path.read_text().strip()
            if not content:
                return None
            
            # Parse track info from file
            # Support formats:
            # - "Artist - Title"
            # - JSON: {"artist": "...", "title": "...", ...}
            
            if content.startswith('{'):
                # JSON format
                data = json.loads(content)
                artist = data.get('artist', '').strip()
                title = data.get('title', '').strip()
                album = data.get('album', '').strip()
                duration_ms = int(data.get('duration_ms', 0) or 0)
                progress_ms = int(data.get('progress_ms', 0) or 0)
            else:
                # Plain text "Artist - Title" format
                artist, title = self._parse_track_string(content)
                album = ''
                duration_ms = 0
                progress_ms = 0
            
            if not artist and not title:
                return None
            
            # Track change detection for progress estimation
            current_track = f"{artist} - {title}"
            if current_track != self._last_track:
                self._last_track = current_track
                self._start_time = time.time()
            
            if duration_ms == 0 and progress_ms == 0:
                # Estimate progress if not provided
                progress_ms = int((time.time() - self._start_time) * 1000)
            
            playback = {
                'artist': artist,
                'title': title,
                'album': album,
                'duration_ms': duration_ms,
                'progress_ms': progress_ms,
                'is_playing': True,
            }
            
            self._health.mark_available(f"File: {self._explicit_file_path.name}")
            if not self._notified_online:
                logger.info(f"DJ.Studio: Monitoring file {self._explicit_file_path}")
                self._notified_online = True
            return playback
            
        except (json.JSONDecodeError, IOError, Exception) as e:
            logger.debug(f"DJ.Studio file read error: {e}")
            return None
    
    def _try_window_title(self) -> Optional[Dict[str, Any]]:
        """Try to extract track info from DJ.Studio window title."""
        try:
            # Use AppleScript to get window title
            script = '''
            tell application "System Events"
                if exists process "DJ.Studio" then
                    tell process "DJ.Studio"
                        if (count of windows) > 0 then
                            return name of window 1
                        end if
                    end tell
                end if
            end tell
            return ""
            '''
            
            result = subprocess.run(
                ["osascript", "-e", script],
                capture_output=True,
                text=True,
                timeout=self._timeout,
                check=False,
            )
            
            if result.returncode != 0:
                return None
            
            window_title = (result.stdout or "").strip()
            if not window_title or window_title == "":
                return None
            
            # Parse window title for track info
            # Common patterns:
            # - "Artist - Title - DJ.Studio"
            # - "Now Playing: Artist - Title"
            # - "DJ.Studio - Artist - Title"
            
            artist, title = self._parse_window_title(window_title)
            if not artist and not title:
                return None
            
            # Track change detection
            current_track = f"{artist} - {title}"
            if current_track != self._last_track:
                self._last_track = current_track
                self._start_time = time.time()
            
            playback = {
                'artist': artist,
                'title': title,
                'album': '',
                'duration_ms': 0,
                'progress_ms': int((time.time() - self._start_time) * 1000),
                'is_playing': True,
            }
            
            self._health.mark_available("Window title")
            if not self._notified_online:
                logger.info("DJ.Studio: Monitoring window title")
                self._notified_online = True
            return playback
            
        except (subprocess.TimeoutExpired, Exception):
            return None
    
    def _parse_track_string(self, content: str) -> tuple:
        """Parse 'Artist - Title' format."""
        if " - " in content:
            parts = content.split(" - ", 1)
            return parts[0].strip(), parts[1].strip()
        return "", content.strip()
    
    def _parse_window_title(self, title: str) -> tuple:
        """Extract artist and title from window title."""
        # Remove common suffixes
        for suffix in [" - DJ.Studio", " - DJ Studio", " | DJ.Studio"]:
            if title.endswith(suffix):
                title = title[:-len(suffix)].strip()
        
        # Remove common prefixes
        for prefix in ["Now Playing: ", "DJ.Studio - ", "Playing: "]:
            if title.startswith(prefix):
                title = title[len(prefix):].strip()
        
        # Parse remaining "Artist - Title"
        return self._parse_track_string(title)


# =============================================================================
# OSC SENDER - Consolidated send_karaoke pattern
# =============================================================================

class OSCSender:
    """
    Consolidated OSC sender with backward compatibility.
    
    Sends FLAT OSC messages (arrays, no nested structures) for easy parsing:
    - /karaoke/track: [active, source, artist, title, album, duration, has_lyrics]
    - /karaoke/pos: [position_sec, is_playing]
    - /karaoke/lyrics/reset: []
    - /karaoke/lyrics/line: [index, time_sec, text]
    - /karaoke/line/active: [index]
    - /karaoke/refrain/reset: []
    - /karaoke/refrain/line: [index, time_sec, text]
    - /karaoke/refrain/active: [index, text]
    
    All values are primitives (int, float, string) - no dicts or nested arrays.
    """
    
    def __init__(self, host: str = "127.0.0.1", port: int = 9000):
        self._current_track_active = False
        self._current_source = "unknown"
        self._current_track_info = {}
        logger.info(f"OSC: using centralized manager {osc.host}:{osc.port}")
    
    def send(self, address: str, args: Any = None):
        """
        Send a raw OSC message (passthrough to centralized manager).
        
        Args:
            address: OSC address pattern (e.g., "/audio/levels")
            args: Message arguments (single value, list, or None)
        """
        osc.send(address, args)
    
    def send_karaoke(self, channel: str, event: str, data: Any = None):
        """
        Send karaoke OSC message with backward compatibility for Processing.
        
        Args:
            channel: "track", "lyrics", "refrain", "keywords", "position"
            event: "info", "reset", "line", "active", "update", "none"
            data: dict, list, or primitive value
        """
        # Handle legacy message formats for Processing compatibility
        if channel == "track" and event == "info":
            # Store track info for later use
            self._current_track_active = True
            self._current_source = data.get("source", "spotify")
            self._current_track_info = data
            
            # Send legacy format: /karaoke/track [active, source, artist, title, album, duration, has_lyrics]
            osc.send("/karaoke/track", [
                1,  # active
                self._current_source,
                data.get("artist", ""),
                data.get("title", ""),
                data.get("album", ""),
                data.get("duration", 0.0),
                1  # has_lyrics (will be updated by lyrics/reset if false)
            ])
            return
        
        elif channel == "track" and event == "none":
            # Send inactive track
            self._current_track_active = False
            osc.send("/karaoke/track", [0, "", "", "", "", 0.0, 0])
            return
        
        elif channel == "lyrics" and event == "reset":
            has_lyrics = data.get("has_lyrics", True) if isinstance(data, dict) else True
            # Update track message with has_lyrics flag
            if self._current_track_active and not has_lyrics:
                osc.send("/karaoke/track", [
                    1,
                    self._current_source,
                    self._current_track_info.get("artist", ""),
                    self._current_track_info.get("title", ""),
                    self._current_track_info.get("album", ""),
                    self._current_track_info.get("duration", 0.0),
                    0  # has_lyrics = false
                ])
            osc.send("/karaoke/lyrics/reset", [])
            return
        
        elif channel == "lyrics" and event == "line":
            # Send: [index, time, text]
            osc.send("/karaoke/lyrics/line", [
                data.get("index", 0),
                data.get("time", 0.0),
                data.get("text", "")
            ])
            return
        
        elif channel == "position" and event == "update":
            # Send: [position_sec, is_playing]
            osc.send("/karaoke/pos", [
                data.get("time", 0.0),
                1 if data.get("playing", True) else 0
            ])
            return
        
        elif channel == "lyrics" and event == "active":
            # Send: [index]
            index = data.get("index", -1) if isinstance(data, dict) else data
            osc.send("/karaoke/line/active", [index])
            return
        
        elif channel == "refrain" and event == "reset":
            osc.send("/karaoke/refrain/reset", [])
            return
        
        elif channel == "refrain" and event == "line":
            # Send: [index, time, text]
            osc.send("/karaoke/refrain/line", [
                data.get("index", 0),
                data.get("time", 0.0),
                data.get("text", "")
            ])
            return
        
        elif channel == "refrain" and event == "active":
            # Send: [index, text]
            osc.send("/karaoke/refrain/active", [
                data.get("index", -1),
                data.get("text", "")
            ])
            return
        
        # Generic fallback for new-style messages
        address = f"/karaoke/{channel}/{event}"
        args = self._prepare_args(data)
        osc.send(address, args)
    
    def send_vj(self, subsystem: str, event: str, data: Any = None):
        """
        Send VJ app status messages.
        
        Args:
            subsystem: "apps", "synesthesia", "milksyphon", "master"
            event: "status", "all"
            data: dict or value
        
        Examples:
            send_vj("synesthesia", "status", {"running": True})
            send_vj("apps", "all", {"Magic": True, "Resolume": False})
        """
        address = f"/vj/{subsystem}/{event}"
        args = self._prepare_args(data)
        osc.send(address, args)
    
    def send_shader(self, shader_name: str, energy: float = 0.5, valence: float = 0.0):
        """
        Send shader load command to Processing.
        
        Args:
            shader_name: Name of shader to load (without extension)
            energy: Energy score (0.0-1.0)
            valence: Mood valence (-1.0 to 1.0)
        
        OSC Message: /shader/load [name, energy, valence]
        """
        logger.info(f"OSC → /shader/load [{shader_name}, {energy:.2f}, {valence:.2f}]")
        osc.send("/shader/load", [shader_name, float(energy), float(valence)])
    
    def get_recent_messages(self, count: int = 20) -> List[tuple]:
        """Get recent OSC messages for debug display."""
        return osc.get_recent_messages(count)
    
    def send_master_status(self, karaoke_active: bool = False, 
                          synesthesia_running: bool = False,
                          milksyphon_running: bool = False,
                          processing_apps: int = 0):
        """Send master VJ status (for vj_console.py compatibility)."""
        self.send_vj("master", "status", {
            "karaoke": karaoke_active,
            "synesthesia": synesthesia_running,
            "milksyphon": milksyphon_running,
            "processing_apps": processing_apps
        })
    
    # Private methods - implementation details
    
    def _prepare_args(self, data: Any) -> List:
        """Convert data to OSC argument list."""
        if data is None:
            return []
        
        if isinstance(data, dict):
            # Flatten dict to alternating key-value list
            args = []
            for key, value in data.items():
                if isinstance(value, bool):
                    args.append(1 if value else 0)
                else:
                    args.append(value)
            return args
        
        if isinstance(data, (list, tuple)):
            # Convert booleans in list
            return [1 if isinstance(v, bool) and v else (0 if isinstance(v, bool) else v) for v in data]
        
        # Single value
        if isinstance(data, bool):
            return [1 if data else 0]
        return [data]
