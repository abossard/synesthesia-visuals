#!/usr/bin/env python3
"""
External Service Adapters

Deep modules that hide protocol complexity behind simple interfaces.
Each adapter handles one external service (Spotify, VirtualDJ, LRCLIB, OSC).
"""

import json
import time
import logging
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
# LYRICS FETCHER - Deep module hiding LRCLIB API complexity
# =============================================================================

class LyricsFetcher:
    """
    Fetches lyrics from LRCLIB API with caching.
    
    Deep module - simple interface, complex implementation.
    Public interface: fetch(artist, title) -> Optional[str]
    Hides: HTTP requests, cache management, TTL expiration, retry logic
    """
    
    BASE_URL = "https://lrclib.net/api"
    CACHE_TTL_SECONDS = 86400  # 24 hours for "not found" entries
    
    def __init__(self, cache_dir: Optional[Path] = None):
        self._cache_dir = cache_dir or Config.DEFAULT_LYRICS_CACHE_DIR
        self._cache_dir.mkdir(parents=True, exist_ok=True)
        self._session = requests.Session()
        self._session.headers["User-Agent"] = "KaraokeEngine/1.0"
    
    def fetch(self, artist: str, title: str, album: str = "", duration: float = 0) -> Optional[str]:
        """
        Fetch synced lyrics for a track. Returns LRC format string or None.
        Automatically uses cache to avoid redundant API calls.
        """
        # Check cache first
        cache_file = self._get_cache_path(artist, title)
        cached_result = self._check_cache(cache_file)
        if cached_result is not None:
            return cached_result if cached_result != "" else None
        
        # Fetch from API
        lrc_text = self._fetch_from_api(artist, title, album, duration)
        
        # Save to cache
        if lrc_text:
            self._save_to_cache(cache_file, {'syncedLyrics': lrc_text})
            logger.info(f"Fetched and cached lyrics: {artist} - {title}")
        else:
            # Cache "not found" with TTL
            self._save_to_cache(cache_file, {'not_found': True, 'cached_at': time.time()})
            logger.debug(f"No lyrics found: {artist} - {title}")
        
        return lrc_text
    
    def get_cached_count(self) -> int:
        """Return number of cached lyrics files."""
        if self._cache_dir.exists():
            return len(list(self._cache_dir.glob("*.json")))
        return 0
    
    # Private methods - implementation details
    
    def _check_cache(self, cache_file: Path) -> Optional[str]:
        """Check cache, returns lyrics string, empty string for not-found, or None for cache miss."""
        if not cache_file.exists():
            return None
        
        try:
            data = json.loads(cache_file.read_text())
            
            # Check for expired "not found" entries
            if data.get('not_found'):
                cached_at = data.get('cached_at', 0)
                if time.time() - cached_at > self.CACHE_TTL_SECONDS:
                    cache_file.unlink()  # Delete expired entry
                    return None
                return ""  # Still within TTL, return empty to signal not-found
            
            logger.debug(f"Using cached lyrics: {cache_file.stem}")
            return data.get('syncedLyrics')
        except (json.JSONDecodeError, IOError):
            return None
    
    def _fetch_from_api(self, artist: str, title: str, album: str, duration: float) -> Optional[str]:
        """Fetch from LRCLIB API."""
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
            logger.error(f"Lyrics fetch error: {e}")
        
        return None
    
    def _save_to_cache(self, cache_file: Path, data: Dict):
        """Save data to cache file."""
        try:
            cache_file.write_text(json.dumps(data, indent=2))
        except IOError:
            pass
    
    def _get_cache_path(self, artist: str, title: str) -> Path:
        """Generate cache file path from artist/title."""
        safe = sanitize_cache_filename(artist, title)
        return self._cache_dir / f"{safe}.json"


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
    
    def __init__(self):
        self._sp = None
        self._health = ServiceHealth("Spotify")
        self._logged_no_credentials = False  # Only log once
        self._init_client()
    
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
    
    def __init__(self, file_path: Optional[str] = None):
        self._health = ServiceHealth("VirtualDJ")
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
