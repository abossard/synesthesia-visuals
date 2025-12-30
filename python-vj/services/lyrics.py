"""
LyricsService - Deep module for lyrics and song metadata

Hides ALL complexity:
- LRCLIB API calls
- LLM fallback for plain lyrics
- Caching (disk + memory)
- LRC parsing
- Refrain detection
- Keyword extraction

Simple interface:
    service.load(track) → bool (found lyrics)
    service.lines → List[LyricLine]
    service.metadata → SongMetadata
    service.get_active_index(position) → int
"""

import logging
import re
import time
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Set

logger = logging.getLogger(__name__)


# =============================================================================
# IMMUTABLE DATA
# =============================================================================

@dataclass(frozen=True)
class LyricLine:
    """Single lyric line with timing."""
    time_sec: float
    text: str
    is_refrain: bool = False
    keywords: str = ""  # Space-separated keywords


@dataclass(frozen=True)
class SongMetadata:
    """Song metadata from LLM analysis."""
    plain_lyrics: str = ""
    keywords: tuple = ()  # Tuple for immutability
    themes: tuple = ()
    mood: str = ""
    genre: str = ""
    release_date: str = ""
    album: str = ""
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "plain_lyrics": self.plain_lyrics,
            "keywords": list(self.keywords),
            "themes": list(self.themes),
            "mood": self.mood,
            "genre": self.genre,
            "release_date": self.release_date,
            "album": self.album,
        }


# =============================================================================
# PURE FUNCTIONS (calculations)
# =============================================================================

def parse_lrc(lrc_text: str) -> List[LyricLine]:
    """Parse LRC format into LyricLine list."""
    if not lrc_text:
        return []
    
    lines = []
    pattern = re.compile(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)')
    
    for raw_line in lrc_text.splitlines():
        match = pattern.match(raw_line.strip())
        if match:
            minutes = int(match.group(1))
            seconds = int(match.group(2))
            centis = match.group(3)
            # Handle both .xx and .xxx formats
            if len(centis) == 2:
                frac = int(centis) / 100.0
            else:
                frac = int(centis) / 1000.0
            
            time_sec = minutes * 60 + seconds + frac
            text = match.group(4).strip()
            
            if text:  # Skip empty lines
                lines.append(LyricLine(time_sec=time_sec, text=text))
    
    return sorted(lines, key=lambda x: x.time_sec)


def detect_refrains(lines: List[LyricLine], min_repeats: int = 2) -> List[LyricLine]:
    """Mark repeated lines as refrains."""
    if not lines:
        return []
    
    # Count occurrences of each line
    text_counts: Dict[str, int] = {}
    for line in lines:
        normalized = line.text.lower().strip()
        text_counts[normalized] = text_counts.get(normalized, 0) + 1
    
    # Mark lines that repeat
    refrain_texts = {text for text, count in text_counts.items() if count >= min_repeats}
    
    result = []
    for line in lines:
        is_refrain = line.text.lower().strip() in refrain_texts
        if is_refrain != line.is_refrain:
            result.append(LyricLine(
                time_sec=line.time_sec,
                text=line.text,
                is_refrain=is_refrain,
                keywords=line.keywords,
            ))
        else:
            result.append(line)
    
    return result


def extract_keywords(lines: List[LyricLine]) -> List[LyricLine]:
    """Extract significant keywords from each line."""
    # Common words to skip
    stopwords = {
        'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for',
        'of', 'with', 'by', 'from', 'is', 'are', 'was', 'were', 'be', 'been',
        'i', 'you', 'he', 'she', 'it', 'we', 'they', 'me', 'him', 'her', 'us',
        'my', 'your', 'his', 'our', 'their', 'this', 'that', 'these', 'those',
        'do', 'does', 'did', 'have', 'has', 'had', 'will', 'would', 'could',
        'should', 'can', 'may', 'might', 'must', 'shall', 'if', 'then', 'so',
        'just', 'like', 'get', 'got', 'go', 'going', 'gone', 'come', 'came',
        'yeah', 'oh', 'ah', 'uh', 'ooh', 'na', 'la', 'da',
    }
    
    result = []
    for line in lines:
        words = re.findall(r"[a-zA-Z']+", line.text.lower())
        keywords = [w for w in words if len(w) > 2 and w not in stopwords]
        
        if keywords != line.keywords.split() if line.keywords else keywords:
            result.append(LyricLine(
                time_sec=line.time_sec,
                text=line.text,
                is_refrain=line.is_refrain,
                keywords=' '.join(keywords[:5]),  # Max 5 keywords per line
            ))
        else:
            result.append(line)
    
    return result


def get_active_index(lines: List[LyricLine], position_sec: float) -> int:
    """Find index of active lyric line for given position."""
    if not lines or position_sec < 0:
        return -1
    
    active = -1
    for i, line in enumerate(lines):
        if line.time_sec <= position_sec:
            active = i
        else:
            break
    
    return active


def get_refrain_lines(lines: List[LyricLine]) -> List[LyricLine]:
    """Filter to only refrain lines."""
    return [line for line in lines if line.is_refrain]


def get_all_keywords(lines: List[LyricLine]) -> List[str]:
    """Extract all unique keywords from lines."""
    keywords: Set[str] = set()
    for line in lines:
        if line.keywords:
            keywords.update(line.keywords.split())
    return sorted(keywords)


# =============================================================================
# LYRICS SERVICE (the deep module)
# =============================================================================

class LyricsService:
    """
    Deep module for lyrics and metadata.
    
    Hides: LRCLIB, LLM, caching, parsing, analysis.
    Exposes: lines, metadata, active index.
    """
    
    def __init__(self):
        self._fetcher = None  # Lazy init
        self._lines: List[LyricLine] = []
        self._metadata = SongMetadata()
        self._current_track_key = ""
    
    def _ensure_fetcher(self):
        """Lazy init fetcher."""
        if self._fetcher is None:
            from adapters import LyricsFetcher
            self._fetcher = LyricsFetcher()
    
    # =========================================================================
    # PUBLIC API
    # =========================================================================
    
    def load(self, track) -> bool:
        """
        Load lyrics for track.
        
        Args:
            track: Track object with artist, title, album, duration_sec
        
        Returns:
            True if lyrics found.
        """
        if not track:
            self.clear()
            return False
        
        track_key = f"{track.artist}|{track.title}".lower()
        if track_key == self._current_track_key:
            return bool(self._lines)
        
        self._current_track_key = track_key
        self._lines = []
        self._metadata = SongMetadata()
        
        self._ensure_fetcher()
        
        # Fetch LRC lyrics
        try:
            duration = getattr(track, 'duration_sec', 0) or getattr(track, 'duration', 0)
            lrc_text = self._fetcher.fetch(
                track.artist, 
                track.title, 
                getattr(track, 'album', ''),
                duration
            )
            
            if lrc_text:
                lines = parse_lrc(lrc_text)
                lines = detect_refrains(lines)
                lines = extract_keywords(lines)
                self._lines = lines
                logger.info(f"Lyrics loaded: {len(lines)} lines")
        except Exception as e:
            logger.error(f"Lyrics fetch error: {e}")
        
        # Fetch metadata (async would be better, but keeping simple)
        try:
            meta_dict = self._fetcher.fetch_metadata(track.artist, track.title)
            if meta_dict:
                self._metadata = SongMetadata(
                    plain_lyrics=meta_dict.get('plain_lyrics', ''),
                    keywords=tuple(meta_dict.get('keywords', []) or []),
                    themes=tuple(meta_dict.get('themes', []) or []),
                    mood=meta_dict.get('mood', ''),
                    genre=meta_dict.get('genre', '') if isinstance(meta_dict.get('genre'), str) 
                          else ', '.join(meta_dict.get('genre', [])),
                    release_date=str(meta_dict.get('release_date', '')),
                    album=meta_dict.get('album', ''),
                )
        except Exception as e:
            logger.debug(f"Metadata fetch error: {e}")
        
        return bool(self._lines)
    
    def clear(self) -> None:
        """Clear current lyrics."""
        self._lines = []
        self._metadata = SongMetadata()
        self._current_track_key = ""
    
    @property
    def lines(self) -> List[LyricLine]:
        """All lyric lines."""
        return self._lines
    
    @property
    def refrain_lines(self) -> List[LyricLine]:
        """Only refrain lines."""
        return get_refrain_lines(self._lines)
    
    @property
    def keywords(self) -> List[str]:
        """All unique keywords."""
        return get_all_keywords(self._lines)
    
    @property
    def metadata(self) -> SongMetadata:
        """Song metadata."""
        return self._metadata
    
    @property
    def has_lyrics(self) -> bool:
        """Check if lyrics are loaded."""
        return bool(self._lines)
    
    def get_active_index(self, position_sec: float) -> int:
        """Get index of active line for position."""
        return get_active_index(self._lines, position_sec)
    
    def get_line(self, index: int) -> Optional[LyricLine]:
        """Get line by index."""
        if 0 <= index < len(self._lines):
            return self._lines[index]
        return None
