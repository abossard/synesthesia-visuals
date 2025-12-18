"""
Music Module - Music tracking and categorization

Handles:
- Playback monitoring (VirtualDJ, djay, Spotify)
- Song categorization via AI
- Lyrics fetching and parsing
- OSC messaging for visuals

Usage:
    from music import KaraokeEngine, SongCategories

    engine = KaraokeEngine()
    engine.start()

NOTE: Content is re-exported from karaoke_engine.py for now.
      Will be migrated to submodules incrementally.
"""

# Re-export from original location
import sys
from pathlib import Path

_parent = str(Path(__file__).parent.parent)
if _parent not in sys.path:
    sys.path.insert(0, _parent)

from karaoke_engine import (
    # Main engine
    KaraokeEngine,
    # Configuration
    Config,
    Settings,
    PLAYBACK_SOURCES,
    # Song data
    SongCategories,
    SongCategory,
    # Playback state
    PlaybackState,
    Track,
    # Lyrics
    LyricLine,
    parse_lrc,
    detect_refrains,
    get_active_line_index,
    get_refrain_lines,
    extract_keywords,
    # Pipeline
    PipelineTracker,
    PipelineStep,
    # OSC
    OSCSender,
    # Service health
    ServiceHealth,
)

__all__ = [
    "KaraokeEngine",
    "Config",
    "Settings",
    "PLAYBACK_SOURCES",
    "SongCategories",
    "SongCategory",
    "PlaybackState",
    "Track",
    "LyricLine",
    "parse_lrc",
    "detect_refrains",
    "get_active_line_index",
    "get_refrain_lines",
    "extract_keywords",
    "PipelineTracker",
    "PipelineStep",
    "OSCSender",
    "ServiceHealth",
]
