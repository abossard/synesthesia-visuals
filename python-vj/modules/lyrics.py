"""
Lyrics Module - Lyrics fetching and sync.

Wraps LyricsFetcher with a Module interface, adding position sync callbacks.

Usage as module:
    from modules.lyrics import LyricsModule, LyricsConfig

    lyrics = LyricsModule()
    lyrics.on_active_line = lambda idx, line: print(f"[{idx}] {line.text}")
    lyrics.fetch("Queen", "Bohemian Rhapsody")
    lyrics.update_position(45.5)  # Triggers callback if line changed
    lyrics.stop()

Standalone CLI:
    python -m modules.lyrics --artist "Queen" --title "Bohemian Rhapsody"
    python -m modules.lyrics --artist "Queen" --title "Bohemian Rhapsody" --sync
"""
import argparse
import signal
import sys
import time
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional

from modules.base import Module


@dataclass
class LyricsConfig:
    """Configuration for Lyrics module."""
    timing_offset_ms: int = 0  # Negative = show lyrics early


@dataclass(frozen=True)
class LyricLineInfo:
    """Simplified lyric line for callbacks."""
    index: int
    time_sec: float
    text: str
    is_refrain: bool = False
    keywords: str = ""


OnActiveLine = Callable[[int, LyricLineInfo], None]
OnLyricsLoaded = Callable[[int], None]  # Called with line count


class LyricsModule(Module):
    """
    Lyrics module with fetching and sync.

    Provides:
    - Lyrics fetching from LRCLIB
    - LRC parsing with timing
    - Position-based active line detection
    - Refrain detection and keywords
    """

    def __init__(self, config: Optional[LyricsConfig] = None):
        super().__init__()
        self._config = config or LyricsConfig()
        self._fetcher = None
        self._lines: List[Any] = []  # LyricLine objects
        self._current_track: Optional[tuple] = None  # (artist, title)
        self._active_index: int = -1

        # Callbacks
        self._on_active_line: Optional[OnActiveLine] = None
        self._on_lyrics_loaded: Optional[OnLyricsLoaded] = None

    @property
    def config(self) -> LyricsConfig:
        return self._config

    @property
    def lines(self) -> List[LyricLineInfo]:
        """Get all lyrics lines as simplified info objects."""
        return [
            LyricLineInfo(
                index=i,
                time_sec=line.time_sec,
                text=line.text,
                is_refrain=line.is_refrain,
                keywords=line.keywords,
            )
            for i, line in enumerate(self._lines)
        ]

    @property
    def line_count(self) -> int:
        return len(self._lines)

    @property
    def current_track(self) -> Optional[tuple]:
        return self._current_track

    @property
    def active_index(self) -> int:
        return self._active_index

    @property
    def on_active_line(self) -> Optional[OnActiveLine]:
        return self._on_active_line

    @on_active_line.setter
    def on_active_line(self, callback: Optional[OnActiveLine]) -> None:
        self._on_active_line = callback

    @property
    def on_lyrics_loaded(self) -> Optional[OnLyricsLoaded]:
        return self._on_lyrics_loaded

    @on_lyrics_loaded.setter
    def on_lyrics_loaded(self, callback: Optional[OnLyricsLoaded]) -> None:
        self._on_lyrics_loaded = callback

    def start(self) -> bool:
        """Initialize the module."""
        if self._started:
            return True

        from adapters import LyricsFetcher
        self._fetcher = LyricsFetcher()
        self._started = True
        return True

    def stop(self) -> None:
        """Stop the module."""
        if not self._started:
            return

        self._lines = []
        self._current_track = None
        self._active_index = -1
        self._started = False

    def fetch(self, artist: str, title: str, album: str = "", duration: float = 0) -> bool:
        """
        Fetch lyrics for a track.

        Returns True if lyrics were found, False otherwise.
        Fires on_lyrics_loaded callback if lyrics loaded.
        """
        if not self._started:
            self.start()

        # Clear previous lyrics
        self._lines = []
        self._active_index = -1
        self._current_track = (artist, title)

        # Fetch from LRCLIB
        lrc = self._fetcher.fetch(artist, title, album, duration)
        if not lrc:
            return False

        # Parse LRC format
        from domain_types import parse_lrc, detect_refrains
        self._lines = parse_lrc(lrc)

        if not self._lines:
            return False

        # Detect refrains and extract keywords
        self._lines = detect_refrains(self._lines)

        # Fire callback
        if self._on_lyrics_loaded:
            try:
                self._on_lyrics_loaded(len(self._lines))
            except Exception:
                pass

        return True

    def update_position(self, position_sec: float) -> Optional[LyricLineInfo]:
        """
        Update playback position and detect active line.

        Returns the active line info if it changed, None otherwise.
        Fires on_active_line callback when line changes.
        """
        if not self._lines:
            return None

        from domain_types import get_active_line_index

        # Apply timing offset
        offset_sec = self._config.timing_offset_ms / 1000.0
        adjusted_pos = position_sec + offset_sec

        # Find active line
        new_index = get_active_line_index(self._lines, adjusted_pos)

        # Check if changed
        if new_index == self._active_index:
            return None

        self._active_index = new_index

        if new_index < 0:
            return None

        # Create line info
        line = self._lines[new_index]
        line_info = LyricLineInfo(
            index=new_index,
            time_sec=line.time_sec,
            text=line.text,
            is_refrain=line.is_refrain,
            keywords=line.keywords,
        )

        # Fire callback
        if self._on_active_line:
            try:
                self._on_active_line(new_index, line_info)
            except Exception:
                pass

        return line_info

    def get_line(self, index: int) -> Optional[LyricLineInfo]:
        """Get a specific line by index."""
        if index < 0 or index >= len(self._lines):
            return None

        line = self._lines[index]
        return LyricLineInfo(
            index=index,
            time_sec=line.time_sec,
            text=line.text,
            is_refrain=line.is_refrain,
            keywords=line.keywords,
        )

    def get_refrain_lines(self) -> List[LyricLineInfo]:
        """Get only refrain (chorus) lines."""
        return [
            LyricLineInfo(
                index=i,
                time_sec=line.time_sec,
                text=line.text,
                is_refrain=True,
                keywords=line.keywords,
            )
            for i, line in enumerate(self._lines)
            if line.is_refrain
        ]

    def adjust_timing(self, delta_ms: int) -> int:
        """Adjust timing offset. Returns new offset."""
        self._config = LyricsConfig(
            timing_offset_ms=self._config.timing_offset_ms + delta_ms
        )
        return self._config.timing_offset_ms

    def get_status(self) -> Dict[str, Any]:
        """Get module status."""
        status = super().get_status()
        status["line_count"] = len(self._lines)
        status["active_index"] = self._active_index
        status["timing_offset_ms"] = self._config.timing_offset_ms

        if self._current_track:
            status["current_track"] = f"{self._current_track[0]} - {self._current_track[1]}"

        refrain_count = sum(1 for line in self._lines if line.is_refrain)
        status["refrain_count"] = refrain_count

        return status


def main():
    """CLI entry point for standalone lyrics module."""
    parser = argparse.ArgumentParser(
        description="Lyrics Module - Fetch and sync lyrics"
    )
    parser.add_argument(
        "--artist", "-a",
        required=True,
        help="Artist name"
    )
    parser.add_argument(
        "--title", "-t",
        required=True,
        help="Song title"
    )
    parser.add_argument(
        "--album",
        default="",
        help="Album name (optional, improves matching)"
    )
    parser.add_argument(
        "--sync",
        action="store_true",
        help="Simulate sync playback (shows lyrics in real-time)"
    )
    parser.add_argument(
        "--offset",
        type=int,
        default=0,
        help="Timing offset in milliseconds (negative = early)"
    )
    args = parser.parse_args()

    config = LyricsConfig(timing_offset_ms=args.offset)
    lyrics = LyricsModule(config)

    print(f"Fetching lyrics for: {args.artist} - {args.title}")
    if args.album:
        print(f"Album: {args.album}")

    if not lyrics.fetch(args.artist, args.title, args.album):
        print("No synced lyrics found for this track.", file=sys.stderr)
        sys.exit(1)

    print(f"\nLoaded {lyrics.line_count} lines")
    refrain_lines = lyrics.get_refrain_lines()
    print(f"Refrain lines: {len(refrain_lines)}")

    if args.sync:
        # Simulate playback
        print(f"\n{'='*60}")
        print("SYNC MODE - Simulating playback (Ctrl+C to stop)")
        print(f"{'='*60}\n")

        stop_event = [False]

        def signal_handler(sig, frame):
            stop_event[0] = True

        signal.signal(signal.SIGINT, signal_handler)
        signal.signal(signal.SIGTERM, signal_handler)

        def on_line(idx: int, line: LyricLineInfo):
            refrain_marker = " [REFRAIN]" if line.is_refrain else ""
            mins = int(line.time_sec // 60)
            secs = int(line.time_sec % 60)
            print(f"[{mins}:{secs:02d}] {line.text}{refrain_marker}")

        lyrics.on_active_line = on_line

        # Get total duration from last line
        all_lines = lyrics.lines
        if all_lines:
            duration = all_lines[-1].time_sec + 5.0  # Add 5s padding
        else:
            duration = 60.0

        start_time = time.time()
        while not stop_event[0]:
            elapsed = time.time() - start_time
            if elapsed > duration:
                break
            lyrics.update_position(elapsed)
            time.sleep(0.1)

        print("\n\nPlayback complete.")
    else:
        # Just print all lyrics
        print(f"\n{'='*60}")
        print("LYRICS")
        print(f"{'='*60}\n")

        for line in lyrics.lines:
            mins = int(line.time_sec // 60)
            secs = int(line.time_sec % 60)
            refrain_marker = " *" if line.is_refrain else ""
            print(f"[{mins}:{secs:02d}] {line.text}{refrain_marker}")

    lyrics.stop()


if __name__ == "__main__":
    main()
