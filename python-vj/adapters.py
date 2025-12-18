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

from domain_types import sanitize_cache_filename
from infra import ServiceHealth, Config
from osc_hub import osc

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
# OSC SENDER - Consolidated send_karaoke pattern
# =============================================================================

class OSCSender:
    """
    Consolidated OSC sender for karaoke messages.
    
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
    
    def __init__(self):
        self._current_track_active = False
        self._current_source = "unknown"
        self._current_track_info = {}
        osc.start()  # Ensure OSC hub is running
    
    def send(self, address: str, *args):
        """Send a raw OSC message to karaoke channel and record for monitoring."""
        from osc_hub import osc_monitor
        osc.karaoke.send(address, *args)
        osc_monitor.record_outgoing("kar", address, list(args))
    
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
            osc.karaoke.send("/karaoke/track",
                1,  # active
                self._current_source,
                data.get("artist", ""),
                data.get("title", ""),
                data.get("album", ""),
                data.get("duration", 0.0),
                1  # has_lyrics (will be updated by lyrics/reset if false)
            )
            return
        
        elif channel == "track" and event == "none":
            # Send inactive track
            self._current_track_active = False
            osc.karaoke.send("/karaoke/track", 0, "", "", "", "", 0.0, 0)
            return
        
        elif channel == "lyrics" and event == "reset":
            has_lyrics = data.get("has_lyrics", True) if isinstance(data, dict) else True
            # Update track message with has_lyrics flag
            if self._current_track_active and not has_lyrics:
                osc.karaoke.send("/karaoke/track",
                    1,
                    self._current_source,
                    self._current_track_info.get("artist", ""),
                    self._current_track_info.get("title", ""),
                    self._current_track_info.get("album", ""),
                    self._current_track_info.get("duration", 0.0),
                    0  # has_lyrics = false
                )
            osc.karaoke.send("/karaoke/lyrics/reset")
            return
        
        elif channel == "lyrics" and event == "line":
            # Send: [index, time, text]
            osc.karaoke.send("/karaoke/lyrics/line",
                data.get("index", 0),
                data.get("time", 0.0),
                data.get("text", "")
            )
            return
        
        elif channel == "position" and event == "update":
            # Send: [position_sec, is_playing]
            osc.karaoke.send("/karaoke/pos",
                data.get("time", 0.0),
                1 if data.get("playing", True) else 0
            )
            return
        
        elif channel == "lyrics" and event == "active":
            # Send: [index]
            index = data.get("index", -1) if isinstance(data, dict) else data
            osc.karaoke.send("/karaoke/line/active", index)
            return
        
        elif channel == "refrain" and event == "reset":
            osc.karaoke.send("/karaoke/refrain/reset")
            return
        
        elif channel == "refrain" and event == "line":
            # Send: [index, time, text]
            osc.karaoke.send("/karaoke/refrain/line",
                data.get("index", 0),
                data.get("time", 0.0),
                data.get("text", "")
            )
            return
        
        elif channel == "refrain" and event == "active":
            # Send: [index, text]
            osc.karaoke.send("/karaoke/refrain/active",
                data.get("index", -1),
                data.get("text", "")
            )
            return
        
        # Generic fallback for new-style messages
        address = f"/karaoke/{channel}/{event}"
        args = self._prepare_args(data)
        osc.karaoke.send(address, *args)
    
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
        osc.karaoke.send(address, *args)
    
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
        osc.karaoke.send("/shader/load", shader_name, float(energy), float(valence))
    
    def get_recent_messages(self, count: int = 20) -> List[tuple]:
        """Get recent OSC messages for debug display."""
        return []  # No longer tracked
    
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


# =============================================================================
# PLAYBACK SOURCE REGISTRY - All available monitors
# =============================================================================

# Enum-like constants for playback sources
PLAYBACK_SOURCES = {
    'spotify_applescript': {
        'key': 'spotify_applescript',
        'label': 'Spotify (AppleScript)',
        'description': 'Local Spotify app via AppleScript',
        'factory': lambda: AppleScriptSpotifyMonitor(),
    },
}


def create_monitor(source_key: str):
    """Create a monitor instance from source key."""
    source = PLAYBACK_SOURCES.get(source_key)
    if source:
        return source['factory']()
    return None
