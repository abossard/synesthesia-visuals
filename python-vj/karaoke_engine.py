#!/usr/bin/env python3
"""
Karaoke Engine - Monitors Spotify/VirtualDJ and sends lyrics via OSC

This module monitors music playback from Spotify and VirtualDJ,
fetches synced lyrics from LRCLIB, and sends them via OSC to Processing.

Requirements:
    pip install spotipy python-osc requests

Spotify Setup:
    1. Create an app at https://developer.spotify.com/dashboard
    2. Set environment variables:
       - SPOTIPY_CLIENT_ID
       - SPOTIPY_CLIENT_SECRET
       - SPOTIPY_REDIRECT_URI (e.g., http://localhost:8888/callback)

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
from dataclasses import dataclass, asdict, field
from pathlib import Path
from typing import Optional, List
from threading import Thread, Event

# OSC
from pythonosc import udp_client

# Spotify (optional - graceful degradation)
try:
    import spotipy
    from spotipy.oauth2 import SpotifyOAuth
    SPOTIFY_AVAILABLE = True
except ImportError:
    SPOTIFY_AVAILABLE = False

# HTTP requests for LRCLIB
import requests

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('karaoke_engine')


@dataclass
class LyricLine:
    """A single lyric line with timing."""
    time_sec: float
    text: str


@dataclass
class SongState:
    """Current song playback state."""
    active: bool = False
    source: Optional[str] = None  # "spotify" or "virtualdj"
    artist: Optional[str] = None
    title: Optional[str] = None
    album: Optional[str] = None
    duration_sec: Optional[float] = None
    position_sec: float = 0.0
    updated_at: float = 0.0
    has_synced_lyrics: bool = False
    plain_lyrics: Optional[str] = None
    lines: List[LyricLine] = field(default_factory=list)


class LRCLibClient:
    """Client for fetching lyrics from LRCLIB API."""
    
    BASE_URL = "https://lrclib.net/api"
    
    def __init__(self, cache_dir: Optional[Path] = None):
        self.cache_dir = cache_dir or Path.home() / ".cache" / "karaoke_engine"
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": "KaraokeEngine/1.0 (https://github.com/abossard/synesthesia-visuals)"
        })
    
    def _cache_key(self, artist: str, title: str) -> Path:
        """Generate cache file path."""
        safe_name = re.sub(r'[^\w\s-]', '', f"{artist}_{title}".lower())
        safe_name = re.sub(r'\s+', '_', safe_name)
        return self.cache_dir / f"{safe_name}.json"
    
    def get_lyrics(self, artist: str, title: str, 
                   album: Optional[str] = None,
                   duration: Optional[float] = None) -> Optional[dict]:
        """Fetch lyrics for a song, using cache if available."""
        cache_file = self._cache_key(artist, title)
        
        # Check cache first
        if cache_file.exists():
            try:
                with open(cache_file, 'r', encoding='utf-8') as f:
                    cached = json.load(f)
                    logger.debug(f"Using cached lyrics for {artist} - {title}")
                    return cached
            except (json.JSONDecodeError, IOError):
                pass
        
        # Fetch from API
        params = {
            "artist_name": artist,
            "track_name": title,
        }
        if album:
            params["album_name"] = album
        if duration:
            params["duration"] = int(duration)
        
        try:
            response = self.session.get(f"{self.BASE_URL}/get", params=params, timeout=10)
            if response.status_code == 200:
                data = response.json()
                # Cache the result
                with open(cache_file, 'w', encoding='utf-8') as f:
                    json.dump(data, f)
                logger.info(f"Fetched lyrics for {artist} - {title}")
                return data
            elif response.status_code == 404:
                logger.info(f"No lyrics found for {artist} - {title}")
                return None
            else:
                logger.warning(f"LRCLIB API error: {response.status_code}")
                return None
        except requests.RequestException as e:
            logger.error(f"Failed to fetch lyrics: {e}")
            return None
    
    def parse_synced_lyrics(self, synced_lyrics: str) -> List[LyricLine]:
        """Parse LRC format synced lyrics into LyricLine objects."""
        lines = []
        # LRC format: [mm:ss.xx] text or [mm:ss.xxx] text
        pattern = r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)$'
        
        for line in synced_lyrics.split('\n'):
            line = line.strip()
            match = re.match(pattern, line)
            if match:
                minutes = int(match.group(1))
                seconds = int(match.group(2))
                centisec = match.group(3)
                # Handle both .xx and .xxx formats
                if len(centisec) == 2:
                    millisec = int(centisec) * 10
                else:
                    millisec = int(centisec)
                
                time_sec = minutes * 60 + seconds + millisec / 1000.0
                text = match.group(4).strip()
                
                if text:  # Only add non-empty lines
                    lines.append(LyricLine(time_sec=time_sec, text=text))
        
        return lines


class SpotifyMonitor:
    """Monitors Spotify playback."""
    
    def __init__(self):
        self.sp = None
        self.available = SPOTIFY_AVAILABLE
        
        if not self.available:
            logger.warning("Spotipy not installed. Spotify monitoring disabled.")
            return
        
        # Check for required environment variables
        required_vars = ['SPOTIPY_CLIENT_ID', 'SPOTIPY_CLIENT_SECRET', 'SPOTIPY_REDIRECT_URI']
        missing = [v for v in required_vars if not os.environ.get(v)]
        
        if missing:
            logger.warning(f"Missing Spotify credentials: {missing}")
            logger.info("Set environment variables or create a .env file to enable Spotify monitoring")
            self.available = False
            return
        
        try:
            self.sp = spotipy.Spotify(auth_manager=SpotifyOAuth(
                scope="user-read-playback-state user-read-currently-playing"
            ))
            # Test the connection
            self.sp.current_user()
            logger.info("Spotify connected successfully")
        except Exception as e:
            logger.error(f"Failed to initialize Spotify: {e}")
            self.available = False
    
    def get_current_playback(self) -> Optional[dict]:
        """Get current playback state from Spotify."""
        if not self.available or not self.sp:
            return None
        
        try:
            playback = self.sp.current_playback()
            if playback and playback.get('item'):
                return {
                    'is_playing': playback.get('is_playing', False),
                    'progress_ms': playback.get('progress_ms', 0),
                    'artist': playback['item']['artists'][0]['name'] if playback['item'].get('artists') else 'Unknown',
                    'title': playback['item'].get('name', 'Unknown'),
                    'album': playback['item'].get('album', {}).get('name', ''),
                    'duration_ms': playback['item'].get('duration_ms', 0),
                    'track_id': playback['item'].get('id', ''),
                }
            return None
        except Exception as e:
            logger.error(f"Spotify API error: {e}")
            return None


class VirtualDJMonitor:
    """Monitors VirtualDJ now playing file."""
    
    def __init__(self, file_path: Optional[str] = None):
        # Common VirtualDJ now playing file locations
        default_paths = [
            Path.home() / "Documents" / "VirtualDJ" / "now_playing.txt",
            Path("/tmp/virtualdj_now_playing.txt"),
            Path("virtualdj_now_playing.txt"),
        ]
        
        if file_path:
            self.file_path = Path(file_path)
        else:
            # Find the first existing path
            self.file_path = None
            for path in default_paths:
                if path.exists():
                    self.file_path = path
                    break
            
            if not self.file_path:
                self.file_path = default_paths[0]  # Default location
        
        self.last_modified = 0
        self.last_content = ""
        self.start_time = 0
        
        logger.info(f"VirtualDJ monitoring: {self.file_path}")
    
    def get_current_track(self) -> Optional[dict]:
        """Get current track from VirtualDJ now_playing.txt."""
        if not self.file_path.exists():
            return None
        
        try:
            stat = self.file_path.stat()
            content = self.file_path.read_text(encoding='utf-8').strip()
            
            if not content:
                return None
            
            # Check if content changed (new track)
            if content != self.last_content:
                self.last_content = content
                self.last_modified = stat.st_mtime
                self.start_time = time.time()
            
            # Parse "Artist - Title" format
            if " - " in content:
                artist, title = content.split(" - ", 1)
            else:
                artist = "Unknown"
                title = content
            
            # Estimate position based on time since detection
            position_sec = time.time() - self.start_time
            
            return {
                'is_playing': True,
                'progress_ms': int(position_sec * 1000),
                'artist': artist.strip(),
                'title': title.strip(),
                'album': '',
                'duration_ms': 0,  # Unknown for VirtualDJ
            }
        except Exception as e:
            logger.error(f"VirtualDJ file error: {e}")
            return None


class OSCSender:
    """Sends karaoke state via OSC."""
    
    def __init__(self, host: str = "127.0.0.1", port: int = 9000):
        self.client = udp_client.SimpleUDPClient(host, port)
        self.host = host
        self.port = port
        logger.info(f"OSC sender configured: {host}:{port}")
    
    def send_track(self, state: SongState):
        """Send /karaoke/track message."""
        self.client.send_message("/karaoke/track", [
            1 if state.active else 0,
            state.source or "",
            state.artist or "",
            state.title or "",
            state.album or "",
            float(state.duration_sec or 0),
            1 if state.has_synced_lyrics else 0
        ])
    
    def send_lyrics_reset(self, song_id: str):
        """Send /karaoke/lyrics/reset message."""
        self.client.send_message("/karaoke/lyrics/reset", [song_id])
    
    def send_lyric_line(self, index: int, time_sec: float, text: str):
        """Send /karaoke/lyrics/line message."""
        self.client.send_message("/karaoke/lyrics/line", [index, time_sec, text])
    
    def send_position(self, position_sec: float, playing: bool):
        """Send /karaoke/pos message."""
        self.client.send_message("/karaoke/pos", [position_sec, 1 if playing else 0])
    
    def send_active_line(self, index: int):
        """Send /karaoke/line/active message."""
        self.client.send_message("/karaoke/line/active", [index])
    
    def send_no_track(self):
        """Send inactive track message."""
        self.client.send_message("/karaoke/track", [0, "", "", "", "", 0.0, 0])
        self.client.send_message("/karaoke/pos", [0.0, 0])


class KaraokeEngine:
    """Main engine that coordinates monitoring and OSC output."""
    
    def __init__(self, osc_host: str = "127.0.0.1", osc_port: int = 9000,
                 vdj_path: Optional[str] = None,
                 state_file: Optional[str] = None):
        
        self.osc = OSCSender(osc_host, osc_port)
        self.lrclib = LRCLibClient()
        self.spotify = SpotifyMonitor()
        self.vdj = VirtualDJMonitor(vdj_path)
        
        self.state = SongState()
        self.last_song_key = None
        self.running = False
        self.stop_event = Event()
        
        # State file for debugging
        self.state_file = Path(state_file) if state_file else Path("karaoke_state.json")
    
    def get_song_key(self, artist: str, title: str) -> str:
        """Generate unique song identifier."""
        return f"{artist.lower().strip()} - {title.lower().strip()}"
    
    def compute_active_line(self) -> int:
        """Compute the active lyric line index based on position."""
        if not self.state.lines:
            return -1
        
        position = self.state.position_sec
        active_index = -1
        
        for i, line in enumerate(self.state.lines):
            if line.time_sec <= position:
                active_index = i
            else:
                break
        
        return active_index
    
    def update_from_spotify(self) -> bool:
        """Update state from Spotify, return True if active."""
        playback = self.spotify.get_current_playback()
        if not playback or not playback.get('is_playing'):
            return False
        
        self.state.active = True
        self.state.source = "spotify"
        self.state.artist = playback['artist']
        self.state.title = playback['title']
        self.state.album = playback['album']
        self.state.duration_sec = playback['duration_ms'] / 1000.0
        self.state.position_sec = playback['progress_ms'] / 1000.0
        self.state.updated_at = time.time()
        
        return True
    
    def update_from_vdj(self) -> bool:
        """Update state from VirtualDJ, return True if active."""
        track = self.vdj.get_current_track()
        if not track or not track.get('artist'):
            return False
        
        self.state.active = True
        self.state.source = "virtualdj"
        self.state.artist = track['artist']
        self.state.title = track['title']
        self.state.album = track.get('album', '')
        self.state.duration_sec = track.get('duration_ms', 0) / 1000.0 if track.get('duration_ms') else None
        self.state.position_sec = track['progress_ms'] / 1000.0
        self.state.updated_at = time.time()
        
        return True
    
    def fetch_lyrics(self):
        """Fetch lyrics for current track."""
        if not self.state.artist or not self.state.title:
            return
        
        result = self.lrclib.get_lyrics(
            self.state.artist,
            self.state.title,
            self.state.album,
            self.state.duration_sec
        )
        
        if result:
            # Parse synced lyrics if available
            synced = result.get('syncedLyrics')
            if synced:
                self.state.lines = self.lrclib.parse_synced_lyrics(synced)
                self.state.has_synced_lyrics = len(self.state.lines) > 0
            else:
                self.state.lines = []
                self.state.has_synced_lyrics = False
            
            # Store plain lyrics
            self.state.plain_lyrics = result.get('plainLyrics') or synced
        else:
            self.state.lines = []
            self.state.has_synced_lyrics = False
            self.state.plain_lyrics = None
    
    def write_state_file(self):
        """Write current state to JSON file for debugging."""
        try:
            # Convert to serializable dict
            state_dict = {
                'active': self.state.active,
                'source': self.state.source,
                'artist': self.state.artist,
                'title': self.state.title,
                'album': self.state.album,
                'duration_sec': self.state.duration_sec,
                'position_sec': self.state.position_sec,
                'updated_at': self.state.updated_at,
                'has_synced_lyrics': self.state.has_synced_lyrics,
                'plain_lyrics': self.state.plain_lyrics,
                'lines': [{'time_sec': l.time_sec, 'text': l.text} for l in self.state.lines]
            }
            
            # Atomic write
            temp_file = self.state_file.with_suffix('.tmp')
            with open(temp_file, 'w', encoding='utf-8') as f:
                json.dump(state_dict, f, indent=2)
            temp_file.rename(self.state_file)
        except Exception as e:
            logger.error(f"Failed to write state file: {e}")
    
    def run_loop(self, poll_interval: float = 0.1):
        """Main engine loop."""
        logger.info("Karaoke Engine started")
        self.running = True
        
        while not self.stop_event.is_set():
            try:
                # Check VirtualDJ first (higher priority)
                if self.update_from_vdj():
                    pass  # VirtualDJ active
                elif self.update_from_spotify():
                    pass  # Spotify active
                else:
                    # No active source
                    if self.state.active:
                        logger.info("Playback stopped")
                    self.state.active = False
                    self.state.source = None
                    self.osc.send_no_track()
                    self.last_song_key = None
                    time.sleep(poll_interval * 5)  # Slow down when inactive
                    continue
                
                # Check for track change
                current_key = self.get_song_key(self.state.artist or '', self.state.title or '')
                if current_key != self.last_song_key:
                    logger.info(f"Track change: {self.state.artist} - {self.state.title}")
                    self.last_song_key = current_key
                    
                    # Fetch lyrics
                    self.fetch_lyrics()
                    
                    # Send track info via OSC
                    self.osc.send_track(self.state)
                    self.osc.send_lyrics_reset(current_key)
                    
                    # Send all lyric lines
                    for i, line in enumerate(self.state.lines):
                        self.osc.send_lyric_line(i, line.time_sec, line.text)
                    
                    if self.state.has_synced_lyrics:
                        logger.info(f"Loaded {len(self.state.lines)} synced lyric lines")
                
                # Send position update
                self.osc.send_position(self.state.position_sec, self.state.active)
                
                # Send active line index
                active_line = self.compute_active_line()
                self.osc.send_active_line(active_line)
                
                # Write state file
                self.write_state_file()
                
                time.sleep(poll_interval)
                
            except KeyboardInterrupt:
                break
            except Exception as e:
                logger.error(f"Engine error: {e}")
                time.sleep(1)
        
        self.running = False
        logger.info("Karaoke Engine stopped")
    
    def start(self, poll_interval: float = 0.1):
        """Start the engine in a background thread."""
        self.stop_event.clear()
        self.thread = Thread(target=self.run_loop, args=(poll_interval,), daemon=True)
        self.thread.start()
    
    def stop(self):
        """Stop the engine."""
        self.stop_event.set()
        if hasattr(self, 'thread'):
            self.thread.join(timeout=2)


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description='Karaoke Engine - Lyrics via OSC')
    parser.add_argument('--osc-host', default='127.0.0.1', help='OSC destination host')
    parser.add_argument('--osc-port', type=int, default=9000, help='OSC destination port')
    parser.add_argument('--vdj-path', help='Path to VirtualDJ now_playing.txt')
    parser.add_argument('--state-file', default='karaoke_state.json', help='State JSON file path')
    parser.add_argument('--poll-interval', type=float, default=0.1, help='Poll interval in seconds')
    parser.add_argument('-v', '--verbose', action='store_true', help='Verbose logging')
    
    args = parser.parse_args()
    
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    engine = KaraokeEngine(
        osc_host=args.osc_host,
        osc_port=args.osc_port,
        vdj_path=args.vdj_path,
        state_file=args.state_file
    )
    
    try:
        engine.run_loop(poll_interval=args.poll_interval)
    except KeyboardInterrupt:
        logger.info("Shutting down...")


if __name__ == '__main__':
    main()
