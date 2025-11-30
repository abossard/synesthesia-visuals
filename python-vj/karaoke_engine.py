#!/usr/bin/env python3
"""
Karaoke Engine - Monitors Spotify/VirtualDJ and sends lyrics via OSC

Architecture follows "A Philosophy of Software Design" principles:
- Deep modules with simple interfaces
- Information hiding
- Separation of concerns

Sends lyrics on 3 OSC channels:
- /karaoke/... - Full lyrics
- /karaoke/refrain/... - Chorus/refrain lines only  
- /karaoke/keywords/... - Key words extracted from each line

Usage:
    python karaoke_engine.py [--osc-host HOST] [--osc-port PORT]
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
        self._cache_dir = cache_dir or Path.home() / ".cache" / "karaoke"
        self._cache_dir.mkdir(parents=True, exist_ok=True)
        self._session = requests.Session()
        self._session.headers["User-Agent"] = "KaraokeEngine/1.0"
    
    def fetch(self, artist: str, title: str, album: str = "", duration: float = 0) -> Optional[str]:
        """
        Fetch synced lyrics for a track.
        Returns LRC format string or None.
        """
        # Check cache
        cache_file = self._get_cache_path(artist, title)
        if cache_file.exists():
            try:
                data = json.loads(cache_file.read_text())
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
                cache_file.write_text(json.dumps(data))
                logger.info(f"Fetched lyrics: {artist} - {title}")
                return data.get('syncedLyrics')
            elif resp.status_code == 404:
                logger.debug(f"No lyrics found: {artist} - {title}")
            else:
                logger.warning(f"LRCLIB error {resp.status_code}")
                
        except requests.RequestException as e:
            logger.error(f"Lyrics fetch error: {e}")
        
        return None
    
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
            logger.info("Spotify: spotipy not installed")
            return
        
        required = ['SPOTIPY_CLIENT_ID', 'SPOTIPY_CLIENT_SECRET', 'SPOTIPY_REDIRECT_URI']
        if any(not os.environ.get(v) for v in required):
            logger.info("Spotify: credentials not configured")
            return
        
        try:
            self._sp = spotipy.Spotify(auth_manager=SpotifyOAuth(
                scope="user-read-playback-state"
            ))
            self._sp.current_user()  # Test connection
            self._available = True
            logger.info("Spotify: connected")
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
    """Monitors VirtualDJ now_playing.txt file."""
    
    DEFAULT_PATHS = [
        Path.home() / "Documents" / "VirtualDJ" / "now_playing.txt",
        Path("/tmp/virtualdj_now_playing.txt"),
    ]
    
    def __init__(self, file_path: Optional[str] = None):
        self._path = Path(file_path) if file_path else self._find_path()
        self._last_content = ""
        self._start_time = 0.0
        logger.info(f"VirtualDJ: monitoring {self._path}")
    
    def _find_path(self) -> Path:
        for p in self.DEFAULT_PATHS:
            if p.exists():
                return p
        return self.DEFAULT_PATHS[0]
    
    def get_playback(self) -> Optional[Dict[str, Any]]:
        """Get current VirtualDJ track or None."""
        if not self._path.exists():
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
    
    Simple interface: start(), stop(), run()
    """
    
    def __init__(
        self,
        osc_host: str = "127.0.0.1",
        osc_port: int = 9000,
        vdj_path: Optional[str] = None,
        state_file: str = "karaoke_state.json"
    ):
        # Dependencies
        self._osc = OSCSender(osc_host, osc_port)
        self._lyrics = LyricsFetcher()
        self._spotify = SpotifyMonitor()
        self._vdj = VirtualDJMonitor(vdj_path)
        
        # State
        self._state = PlaybackState()
        self._last_track_key = ""
        self._state_file = Path(state_file)
        
        # Threading
        self._stop = Event()
        self._thread: Optional[Thread] = None
    
    def run(self, poll_interval: float = 0.1):
        """Run the engine (blocking). Use start() for background."""
        logger.info("Karaoke Engine started")
        print("\n" + "="*50)
        print("  🎤 Karaoke Engine Running")
        print("="*50)
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
        """Send position and active line updates."""
        pos = self._state.position_sec
        self._osc.send_position(pos, True)
        
        active = get_active_line_index(self._state.lines, pos)
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
# MAIN
# =============================================================================

def main():
    parser = argparse.ArgumentParser(
        description='Karaoke Engine - Synced lyrics via OSC',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
OSC Channels:
  /karaoke/...          Full lyrics
  /karaoke/refrain/...  Chorus/refrain only
  /karaoke/keywords/... Key words only

Each channel sends:
  .../reset [song_id]
  .../line [index, time_sec, text]
  .../active [index, text?]
"""
    )
    parser.add_argument('--osc-host', default='127.0.0.1')
    parser.add_argument('--osc-port', type=int, default=9000)
    parser.add_argument('--vdj-path', help='VirtualDJ now_playing.txt path')
    parser.add_argument('--state-file', default='karaoke_state.json')
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
