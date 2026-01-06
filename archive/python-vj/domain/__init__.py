"""
Domain Module - Core domain types

Pure data types with no external dependencies.

Public API:
    Types:
        LyricLine - Single lyric line with timing
        Track - Song metadata (artist, title, album)
        PlaybackState - Current playback state
        PlaybackSnapshot - Complete snapshot of playback state
        SongCategory - Single category with score
        SongCategories - Collection of category scores

    Functions:
        parse_lrc() - Parse LRC format lyrics
        extract_keywords() - Extract important words from text
        detect_refrains() - Mark refrain lines
        analyze_lyrics() - Full lyrics analysis pipeline
        get_active_line_index() - Find active line for position
        get_refrain_lines() - Filter to refrain lines only
        sanitize_cache_filename() - Create safe cache filename

    Constants:
        STOP_WORDS - Common words to filter out

Usage:
    from domain import PlaybackSnapshot, PlaybackState, LyricLine
"""

import sys
from pathlib import Path

_parent = str(Path(__file__).parent.parent)
if _parent not in sys.path:
    sys.path.insert(0, _parent)

from domain_types import (
    # Types
    LyricLine,
    Track,
    PlaybackState,
    PlaybackSnapshot,
    SongCategory,
    SongCategories,
    # Functions
    parse_lrc,
    extract_keywords,
    detect_refrains,
    analyze_lyrics,
    get_active_line_index,
    get_refrain_lines,
    sanitize_cache_filename,
    # Constants
    STOP_WORDS,
)

__all__ = [
    # Types
    "LyricLine",
    "Track",
    "PlaybackState",
    "PlaybackSnapshot",
    "SongCategory",
    "SongCategories",
    # Functions
    "parse_lrc",
    "extract_keywords",
    "detect_refrains",
    "analyze_lyrics",
    "get_active_line_index",
    "get_refrain_lines",
    "sanitize_cache_filename",
    # Constants
    "STOP_WORDS",
]
