#!/usr/bin/env python3
"""
Domain Models and Pure Functions

Pure calculations with no side effects - immutable data structures
and stateless functions following Grokking Simplicity principles.
"""

import re
from dataclasses import dataclass, replace, field
from typing import List, Dict, Optional, Any


# =============================================================================
# STOP WORDS - Constant data for keyword extraction
# =============================================================================

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


# =============================================================================
# IMMUTABLE DATA STRUCTURES - Pure domain models
# =============================================================================

@dataclass(frozen=True)
class LyricLine:
    """A single line of lyrics with timing. Immutable."""
    time_sec: float
    text: str
    is_refrain: bool = False
    keywords: str = ""
    
    def with_refrain(self, is_refrain: bool) -> 'LyricLine':
        """Create new instance with updated refrain flag."""
        return replace(self, is_refrain=is_refrain)
    
    def with_keywords(self, keywords: str) -> 'LyricLine':
        """Create new instance with updated keywords."""
        return replace(self, keywords=keywords)


@dataclass(frozen=True) 
class Track:
    """Song metadata. Immutable."""
    artist: str
    title: str
    album: str = ""
    duration: float = 0.0
    
    @property
    def key(self) -> str:
        """Unique identifier for track."""
        return f"{self.artist}::{self.title}"


@dataclass
class PlaybackState:
    """
    Current playback state. Mutable but updated via replace() for thread safety.
    
    Usage:
        state = state.update(position=120.0)  # Returns new instance
    """
    track: Optional[Track] = None
    position: float = 0.0
    is_playing: bool = False
    last_update: float = 0.0
    
    def update(self, **kwargs) -> 'PlaybackState':
        """Create new instance with updated fields."""
        return replace(self, **kwargs)
    
    @property
    def has_track(self) -> bool:
        return self.track is not None
    
    @property
    def track_key(self) -> str:
        """Generate a normalized track key for caching."""
        if not self.track:
            return ""
        return f"{self.track.artist} - {self.track.title}".lower()


@dataclass(frozen=True)
class PlaybackSnapshot:
    """Snapshot of playback for UI consumption."""
    state: PlaybackState
    source: str = "unknown"
    updated_at: float = 0.0
    track_changed: bool = False
    error: str = ""
    monitor_status: Dict[str, Dict[str, Any]] = field(default_factory=dict)
    backoff_seconds: float = 0.0


@dataclass(frozen=True)
class SongCategory:
    """Single category with score. Immutable."""
    name: str
    score: float
    
    def __lt__(self, other: 'SongCategory') -> bool:
        """Sort by score descending."""
        return self.score > other.score


@dataclass(frozen=True)
class SongCategories:
    """
    Collection of category scores for a song. Immutable.
    
    Usage:
        cats = SongCategories(scores={'happy': 0.8, 'energetic': 0.6})
        top = cats.get_top(5)
    """
    scores: Dict[str, float]
    primary_mood: str = ""
    
    def get_top(self, n: int = 5) -> List[SongCategory]:
        """Get top N categories sorted by score."""
        items = [SongCategory(name=k, score=v) for k, v in self.scores.items()]
        items.sort()
        return items[:n]
    
    def get_score(self, category: str) -> float:
        """Get score for specific category."""
        return self.scores.get(category, 0.0)
    
    def get_dict(self) -> Dict[str, float]:
        """Get raw scores dict."""
        return dict(self.scores)


# =============================================================================
# PURE FUNCTIONS - Calculations with no side effects
# =============================================================================

def sanitize_cache_filename(artist: str, title: str) -> str:
    """
    Create a safe filename from artist and title for cache purposes.
    Removes special characters and normalizes whitespace.
    """
    safe = re.sub(r'[^\w\s-]', '', f"{artist}_{title}".lower())
    safe = re.sub(r'\s+', '_', safe)
    return safe


def parse_lrc(lrc_text: str) -> List[LyricLine]:
    """
    Parse LRC format lyrics into LyricLine objects. Pure function.
    
    LRC Format: [mm:ss.xx] or [mm:ss.xxx]Lyric text
    Returns list of LyricLine instances (immutable).
    """
    lines = []
    pattern = r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)$'
    
    for line in lrc_text.split('\n'):
        match = re.search(pattern, line)
        if match:
            minutes, seconds, centiseconds_str, text = match.groups()
            # Handle both .xx (centiseconds) and .xxx (milliseconds) formats
            if len(centiseconds_str) == 3:
                # .xxx format (milliseconds)
                fraction = int(centiseconds_str) / 1000.0
            else:
                # .xx format (centiseconds)
                fraction = int(centiseconds_str) / 100.0
            
            time_sec = int(minutes) * 60 + int(seconds) + fraction
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
    """
    Mark lines that appear multiple times as refrain. Pure function.
    Returns new list with refrain flags and keywords set.
    """
    if not lines:
        return []
    
    # Count normalized line occurrences
    counts: Dict[str, int] = {}
    for line in lines:
        normalized = re.sub(r'[^\w\s]', '', line.text.lower())
        counts[normalized] = counts.get(normalized, 0) + 1
    
    # Lines appearing 2+ times are refrain
    refrain_keys = {k for k, v in counts.items() if v >= 2}
    
    # Create new list with refrain marked and keywords extracted (immutable)
    return [
        line.with_refrain(
            re.sub(r'[^\w\s]', '', line.text.lower()) in refrain_keys
        ).with_keywords(
            extract_keywords(line.text)
        )
        for line in lines
    ]


def analyze_lyrics(lines: List[LyricLine]) -> List[LyricLine]:
    """Full lyrics analysis pipeline. Pure function."""
    return detect_refrains(lines)


def get_active_line_index(lines: List[LyricLine], position: float) -> int:
    """
    Find the active line index for current position. Pure function.
    Returns -1 if no active line.
    """
    active = -1
    for i, line in enumerate(lines):
        if line.time_sec <= position:
            active = i
        else:
            break
    return active


def get_refrain_lines(lines: List[LyricLine]) -> List[LyricLine]:
    """Filter to only refrain lines. Pure function."""
    return [line for line in lines if line.is_refrain]
