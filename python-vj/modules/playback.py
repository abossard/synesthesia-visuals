"""
Playback Module - Track detection and position monitoring.

Wraps PlaybackCoordinator with a Module interface and callbacks.

Usage as module:
    from modules.playback import PlaybackModule, PlaybackConfig

    playback = PlaybackModule()
    playback.on_track_change = lambda track: print(f"Now playing: {track}")
    playback.on_position_update = lambda pos: print(f"Position: {pos}s")
    playback.set_source("vdj_osc")
    playback.start()
    # ... later
    playback.stop()

Standalone CLI:
    python -m modules.playback --source vdj_osc
    python -m modules.playback --source spotify_applescript
"""
import argparse
import signal
import sys
import threading
import time
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional

from modules.base import Module


@dataclass
class PlaybackConfig:
    """Configuration for Playback module."""
    poll_interval: float = 0.5  # How often to poll for updates (seconds)
    default_source: Optional[str] = None  # Default playback source


@dataclass(frozen=True)
class TrackInfo:
    """Simplified track information for callbacks."""
    artist: str
    title: str
    album: str = ""
    duration_sec: float = 0.0

    @property
    def key(self) -> str:
        return f"{self.artist}::{self.title}"

    def __str__(self) -> str:
        return f"{self.artist} - {self.title}"


OnTrackChange = Callable[[TrackInfo], None]
OnPositionUpdate = Callable[[float, float], None]  # (position_sec, duration_sec)


class PlaybackModule(Module):
    """
    Playback monitoring module with callbacks.

    Provides:
    - Track detection from multiple sources (VDJ, Spotify)
    - Position tracking with callbacks
    - Hot-swap of playback source
    - Status reporting
    """

    AVAILABLE_SOURCES = ["vdj_osc", "spotify_applescript"]

    def __init__(self, config: Optional[PlaybackConfig] = None):
        super().__init__()
        self._config = config or PlaybackConfig()
        self._coordinator = None
        self._current_source: Optional[str] = None
        self._current_track: Optional[TrackInfo] = None
        self._current_position: float = 0.0
        self._last_lookup_ms: float = 0.0

        # Callbacks
        self._on_track_change: Optional[OnTrackChange] = None
        self._on_position_update: Optional[OnPositionUpdate] = None

        # Polling thread
        self._poll_thread: Optional[threading.Thread] = None
        self._stop_event = threading.Event()

    @property
    def config(self) -> PlaybackConfig:
        return self._config

    @property
    def current_source(self) -> Optional[str]:
        return self._current_source

    @property
    def current_track(self) -> Optional[TrackInfo]:
        return self._current_track

    @property
    def current_position(self) -> float:
        return self._current_position

    @property
    def on_track_change(self) -> Optional[OnTrackChange]:
        return self._on_track_change

    @on_track_change.setter
    def on_track_change(self, callback: Optional[OnTrackChange]) -> None:
        self._on_track_change = callback

    @property
    def on_position_update(self) -> Optional[OnPositionUpdate]:
        return self._on_position_update

    @on_position_update.setter
    def on_position_update(self, callback: Optional[OnPositionUpdate]) -> None:
        self._on_position_update = callback

    def set_source(self, source_key: str) -> bool:
        """Set playback source. Can be called before or after start()."""
        if source_key not in self.AVAILABLE_SOURCES:
            return False

        from adapters import PLAYBACK_SOURCES
        from orchestrators import PlaybackCoordinator

        source_config = PLAYBACK_SOURCES.get(source_key)
        if not source_config:
            return False

        # Create monitor from factory
        monitor = source_config['factory']()

        # Create or update coordinator
        if self._coordinator is None:
            self._coordinator = PlaybackCoordinator()

        self._coordinator.set_monitor(monitor)
        self._current_source = source_key
        return True

    def start(self) -> bool:
        """Start playback monitoring."""
        if self._started:
            return True

        # Set default source if none set
        if self._current_source is None and self._config.default_source:
            if not self.set_source(self._config.default_source):
                return False

        if self._coordinator is None:
            from orchestrators import PlaybackCoordinator
            self._coordinator = PlaybackCoordinator()

        # Start polling thread
        self._stop_event.clear()
        self._poll_thread = threading.Thread(
            target=self._poll_loop,
            name="PlaybackModulePoll",
            daemon=True,
        )
        self._poll_thread.start()

        self._started = True
        return True

    def stop(self) -> None:
        """Stop playback monitoring."""
        if not self._started:
            return

        self._stop_event.set()
        if self._poll_thread:
            self._poll_thread.join(timeout=2.0)
            self._poll_thread = None

        self._started = False

    def poll_once(self) -> Dict[str, Any]:
        """Poll playback state once. Returns current state dict."""
        if self._coordinator is None:
            return {"error": "No coordinator"}

        sample = self._coordinator.poll()
        state = sample.state

        result = {
            "source": sample.source,
            "track_changed": sample.track_changed,
            "is_playing": state.is_playing,
            "position_sec": state.position,
            "lookup_ms": sample.last_lookup_ms,
            "error": sample.error,
        }

        if state.track:
            result["track"] = {
                "artist": state.track.artist,
                "title": state.track.title,
                "album": state.track.album,
                "duration_sec": state.track.duration,
            }

        return result

    def get_status(self) -> Dict[str, Any]:
        """Get module status."""
        status = super().get_status()
        status["source"] = self._current_source
        status["available_sources"] = self.AVAILABLE_SOURCES

        if self._current_track:
            status["current_track"] = str(self._current_track)

        if self._coordinator:
            status["lookup_ms"] = self._coordinator.last_lookup_ms

        return status

    def _poll_loop(self) -> None:
        """Background polling loop."""
        while not self._stop_event.is_set():
            try:
                self._poll_and_notify()
            except Exception as e:
                # Log but don't crash
                pass

            self._stop_event.wait(self._config.poll_interval)

    def _poll_and_notify(self) -> None:
        """Poll and fire callbacks if needed."""
        if self._coordinator is None:
            return

        sample = self._coordinator.poll()
        state = sample.state

        # Track change callback
        if sample.track_changed and state.track:
            new_track = TrackInfo(
                artist=state.track.artist,
                title=state.track.title,
                album=state.track.album,
                duration_sec=state.track.duration,
            )
            self._current_track = new_track

            if self._on_track_change:
                try:
                    self._on_track_change(new_track)
                except Exception:
                    pass

        # Update current position
        self._current_position = state.position
        self._last_lookup_ms = sample.last_lookup_ms

        # Position callback (only when playing)
        if state.is_playing and self._on_position_update:
            duration = state.track.duration if state.track else 0.0
            try:
                self._on_position_update(state.position, duration)
            except Exception:
                pass


def main():
    """CLI entry point for standalone playback monitoring."""
    parser = argparse.ArgumentParser(
        description="Playback Module - Track detection and position monitoring"
    )
    parser.add_argument(
        "--source", "-s",
        choices=PlaybackModule.AVAILABLE_SOURCES,
        default="vdj_osc",
        help="Playback source (default: vdj_osc)"
    )
    parser.add_argument(
        "--interval", "-i",
        type=float,
        default=0.5,
        help="Poll interval in seconds (default: 0.5)"
    )
    args = parser.parse_args()

    config = PlaybackConfig(
        poll_interval=args.interval,
        default_source=args.source,
    )
    playback = PlaybackModule(config)

    # Track state for display
    current_track = [None]
    position_updates = [0]

    def on_track_change(track: TrackInfo):
        current_track[0] = track
        print(f"\n{'='*60}")
        print(f"NOW PLAYING: {track}")
        if track.album:
            print(f"Album: {track.album}")
        if track.duration_sec > 0:
            mins = int(track.duration_sec // 60)
            secs = int(track.duration_sec % 60)
            print(f"Duration: {mins}:{secs:02d}")
        print(f"{'='*60}")

    def on_position_update(pos: float, duration: float):
        position_updates[0] += 1
        if position_updates[0] % 10 == 0:  # Print every 10th update
            if duration > 0:
                pct = (pos / duration) * 100
                mins = int(pos // 60)
                secs = int(pos % 60)
                print(f"\rPosition: {mins}:{secs:02d} ({pct:.1f}%)", end="", flush=True)

    playback.on_track_change = on_track_change
    playback.on_position_update = on_position_update

    stop_event = [False]

    def signal_handler(sig, frame):
        stop_event[0] = True

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    print(f"Starting Playback Module with source: {args.source}")
    print(f"Poll interval: {args.interval}s")

    if not playback.set_source(args.source):
        print(f"Failed to set source: {args.source}", file=sys.stderr)
        sys.exit(1)

    if not playback.start():
        print("Failed to start Playback Module", file=sys.stderr)
        sys.exit(1)

    print("Playback Module started. Press Ctrl+C to stop.")
    print("Waiting for track...")

    try:
        while not stop_event[0]:
            time.sleep(0.5)
    except KeyboardInterrupt:
        pass

    print("\n\nStopping Playback Module...")
    playback.stop()

    if current_track[0]:
        print(f"Last track: {current_track[0]}")
    print(f"Total position updates: {position_updates[0]}")


if __name__ == "__main__":
    main()
