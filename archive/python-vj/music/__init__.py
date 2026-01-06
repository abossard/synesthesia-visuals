"""
Music Module - Music tracking and categorization

Handles playback monitoring, song categorization, lyrics, and OSC messaging.

Public API:
    Classes:
        TextlerEngine - Main engine for tracking playback and syncing visuals
        SongCategories - Song metadata container (genre, mood, era, etc.)
        SongCategory - Individual category with confidence score
        Track - Currently playing track info
        PlaybackState - Playback status (playing, paused, etc.)
        PipelineTracker - Track async processing pipeline
        OSCSender - Send OSC messages to visual apps

    Types:
        LyricLine - Single line with timestamp
        PipelineStep - Step in processing pipeline

    Functions:
        parse_lrc() - Parse LRC lyrics format
        detect_refrains() - Find chorus/refrain sections
        get_active_line_index() - Get current lyric line by timestamp
        get_refrain_lines() - Get all refrain line indices
        extract_keywords() - Extract keywords from lyrics

    Config:
        Config - Path configuration
        Settings - Persistent user settings
        PLAYBACK_SOURCES - Available playback sources dict

Usage:
    from music import TextlerEngine, SongCategories

    engine = TextlerEngine()
    engine.start()
"""

# Re-export from original location
import sys
from pathlib import Path

_parent = str(Path(__file__).parent.parent)
if _parent not in sys.path:
    sys.path.insert(0, _parent)

from textler_engine import (
    # Main engine
    TextlerEngine,
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
    "TextlerEngine",
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
