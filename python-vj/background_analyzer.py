#!/usr/bin/env python3
"""
Background Song Analyzer - Pre-analyze MP3 files for VJ performance

This module processes a folder of MP3 files to prebuild the cache folder,
extracting all metadata and running the full analysis pipeline for each song.

Features:
- Read MP3 tags (ID3) for detailed metadata
- Fetch lyrics and analyze via the karaoke engine pipeline
- Generate AI-powered song categorization
- Extract deeper audio metadata for enhanced OSC control
- Prebuild cache for faster live performance

Following Grokking Simplicity:
- CALCULATIONS: Pure functions with no side effects (extract_*, parse_*, compute_*)
- ACTIONS: Functions that read/write files or external services (fetch_*, save_*, analyze_*)
- DATA: Plain data structures (dataclasses, dicts)

Usage:
    # Analyze all MP3s in a folder:
    python background_analyzer.py /path/to/mp3/folder
    
    # With options:
    python background_analyzer.py /path/to/mp3/folder --cache-dir ./cache --verbose

OSC Output (in addition to standard karaoke engine channels):
    /song/meta/bpm           - BPM from MP3 tags (if available)
    /song/meta/key           - Musical key (if available)
    /song/meta/genre         - Genre from tags
    /song/meta/year          - Release year
    /song/meta/energy        - Computed energy level (0.0-1.0)
    /song/meta/danceability  - Computed danceability (0.0-1.0)
"""

import argparse
import json
import logging
import os
import re
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

# MP3 tag reading
try:
    from mutagen import File as MutagenFile
    from mutagen.id3 import ID3
    from mutagen.mp3 import MP3
    from mutagen.easyid3 import EasyID3
    MUTAGEN_AVAILABLE = True
except ImportError:
    MUTAGEN_AVAILABLE = False

# Import from karaoke engine
from karaoke_engine import (
    Config,
    LyricsFetcher,
    LLMAnalyzer,
    SongCategorizer,
    SongCategories,
    parse_lrc,
    detect_refrains,
    extract_keywords,
    sanitize_cache_filename,
)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('background_analyzer')


# =============================================================================
# DATA STRUCTURES - Plain immutable data
# =============================================================================

@dataclass
class MP3Metadata:
    """
    Extracted metadata from an MP3 file.
    
    Includes both standard ID3 tags and computed analysis results.
    """
    # File info
    file_path: str
    filename: str
    
    # Basic ID3 tags
    artist: str = ""
    title: str = ""
    album: str = ""
    album_artist: str = ""
    genre: str = ""
    year: str = ""
    track_number: str = ""
    disc_number: str = ""
    composer: str = ""
    
    # Audio properties
    duration_sec: float = 0.0
    bitrate: int = 0
    sample_rate: int = 0
    channels: int = 0
    
    # Extended tags (often from professional tagging)
    bpm: Optional[float] = None
    key: Optional[str] = None  # Musical key (e.g., "Am", "C", "F#m")
    energy: Optional[float] = None  # 0.0-1.0 if tagged
    mood: Optional[str] = None
    
    # Comments and custom tags
    comment: str = ""
    lyrics_embedded: str = ""  # USLT frame - embedded lyrics
    
    # All raw tags for debugging
    raw_tags: Dict[str, Any] = field(default_factory=dict)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary, excluding raw_tags for cleaner output."""
        d = asdict(self)
        d.pop('raw_tags', None)  # Remove raw_tags from output
        return d


@dataclass
class AnalysisResult:
    """
    Complete analysis result for a single song.
    
    Combines MP3 metadata with lyrics analysis and AI categorization.
    """
    # Source metadata
    metadata: MP3Metadata
    
    # Lyrics analysis
    lyrics_found: bool = False
    lyrics_source: str = ""  # "embedded", "lrclib", "cache"
    line_count: int = 0
    refrain_count: int = 0
    keywords: List[str] = field(default_factory=list)
    
    # AI categorization
    categories: Optional[SongCategories] = None
    primary_mood: str = ""
    themes: List[str] = field(default_factory=list)
    image_prompt: str = ""
    
    # Computed metrics for OSC control
    computed_energy: float = 0.5  # 0.0-1.0
    computed_danceability: float = 0.5  # 0.0-1.0
    computed_valence: float = 0.5  # emotional positivity 0.0-1.0
    
    # Processing info
    analyzed_at: float = 0.0
    analysis_time_sec: float = 0.0
    errors: List[str] = field(default_factory=list)


# =============================================================================
# CALCULATIONS - Pure functions, no side effects
# =============================================================================

def compute_energy_from_categories(categories: Optional[SongCategories]) -> float:
    """
    Compute energy level from song categories.
    
    Pure function: Same input always produces same output.
    
    Energy is derived from category scores like 'energetic', 'aggressive',
    'calm', 'peaceful'.
    """
    if not categories:
        return 0.5
    
    # Positive energy contributors
    energetic = categories.get_category_score("energetic")
    aggressive = categories.get_category_score("aggressive")
    intense = categories.get_category_score("intense")
    danceable = categories.get_category_score("danceable")
    
    # Negative energy contributors (reduce energy)
    calm = categories.get_category_score("calm")
    peaceful = categories.get_category_score("peaceful")
    introspective = categories.get_category_score("introspective")
    
    # Compute weighted energy
    positive = (energetic * 0.4 + aggressive * 0.25 + intense * 0.2 + danceable * 0.15)
    negative = (calm * 0.4 + peaceful * 0.3 + introspective * 0.3)
    
    # Combine: high positive and low negative = high energy
    energy = 0.5 + (positive - negative) * 0.5
    
    # Clamp to 0.0-1.0
    return max(0.0, min(1.0, energy))


def compute_danceability_from_categories(categories: Optional[SongCategories], bpm: Optional[float] = None) -> float:
    """
    Compute danceability from categories and optional BPM.
    
    Pure function: Same input always produces same output.
    """
    if not categories:
        base = 0.5
    else:
        # Dance-positive categories
        danceable = categories.get_category_score("danceable")
        energetic = categories.get_category_score("energetic")
        happy = categories.get_category_score("happy")
        uplifting = categories.get_category_score("uplifting")
        
        # Dance-negative categories
        introspective = categories.get_category_score("introspective")
        sad = categories.get_category_score("sad")
        melancholic = categories.get_category_score("melancholic")
        
        positive = (danceable * 0.5 + energetic * 0.2 + happy * 0.15 + uplifting * 0.15)
        negative = (introspective * 0.4 + sad * 0.3 + melancholic * 0.3)
        
        base = 0.5 + (positive - negative) * 0.5
    
    # Adjust for BPM if available
    if bpm is not None:
        # Optimal dance BPM range: 100-140
        if 100 <= bpm <= 140:
            bpm_factor = 1.0
        elif 80 <= bpm < 100 or 140 < bpm <= 160:
            bpm_factor = 0.8
        elif 60 <= bpm < 80 or 160 < bpm <= 180:
            bpm_factor = 0.6
        else:
            bpm_factor = 0.4
        
        # BPM contributes 30% to danceability
        base = base * 0.7 + (bpm_factor * 0.5 + 0.25) * 0.3
    
    return max(0.0, min(1.0, base))


def compute_valence_from_categories(categories: Optional[SongCategories]) -> float:
    """
    Compute emotional valence (positivity) from categories.
    
    Pure function: Same input always produces same output.
    """
    if not categories:
        return 0.5
    
    # Positive valence categories
    happy = categories.get_category_score("happy")
    uplifting = categories.get_category_score("uplifting")
    romantic = categories.get_category_score("romantic")
    hope = categories.get_category_score("hope")
    bright = categories.get_category_score("bright")
    
    # Negative valence categories
    sad = categories.get_category_score("sad")
    melancholic = categories.get_category_score("melancholic")
    dark = categories.get_category_score("dark")
    heartbreak = categories.get_category_score("heartbreak")
    death = categories.get_category_score("death")
    
    positive = (happy * 0.3 + uplifting * 0.25 + romantic * 0.2 + hope * 0.15 + bright * 0.1)
    negative = (sad * 0.25 + melancholic * 0.2 + dark * 0.2 + heartbreak * 0.2 + death * 0.15)
    
    valence = 0.5 + (positive - negative) * 0.5
    return max(0.0, min(1.0, valence))


def parse_bpm_from_tag(value: str) -> Optional[float]:
    """
    Parse BPM from various tag formats.
    
    Pure function: handles strings like "120", "120.5", "120 BPM".
    """
    if not value:
        return None
    
    # Extract numeric part
    match = re.search(r'(\d+(?:\.\d+)?)', str(value))
    if match:
        try:
            bpm = float(match.group(1))
            # Sanity check: BPM should be between 40 and 300
            if 40 <= bpm <= 300:
                return bpm
        except ValueError:
            pass
    
    return None


def parse_key_from_tag(value: str) -> Optional[str]:
    """
    Parse musical key from various tag formats.
    
    Pure function: Normalizes key notation like "Am", "A minor", "Amin".
    """
    if not value:
        return None
    
    value = str(value).strip()
    
    # Common key patterns
    # "Am", "A#m", "Bb", "C major", "F# minor"
    key_pattern = r'^([A-Ga-g][#b]?)\s*(m|min|minor|M|maj|major)?$'
    match = re.match(key_pattern, value, re.IGNORECASE)
    
    if match:
        root = match.group(1).upper()
        mode = match.group(2)
        
        if mode and mode.lower() in ('m', 'min', 'minor'):
            return f"{root}m"
        else:
            return root
    
    return value if len(value) <= 4 else None


def extract_keywords_from_lyrics(lyrics: str, max_keywords: int = 20) -> List[str]:
    """
    Extract most significant keywords from full lyrics.
    
    Pure function: Returns list of unique, important words.
    """
    from karaoke_engine import STOP_WORDS
    
    # Tokenize and filter
    words = re.findall(r'\b[a-zA-Z]+\b', lyrics.lower())
    
    # Count occurrences, filtering stop words and short words
    word_counts: Dict[str, int] = {}
    for word in words:
        if word not in STOP_WORDS and len(word) > 3:
            word_counts[word] = word_counts.get(word, 0) + 1
    
    # Sort by frequency and return top N
    sorted_words = sorted(word_counts.keys(), key=lambda w: word_counts[w], reverse=True)
    return sorted_words[:max_keywords]


def generate_track_key(artist: str, title: str) -> str:
    """
    Generate a consistent track identifier.
    
    Pure function: Same artist+title always produces same key.
    """
    return f"{artist.strip().lower()} - {title.strip().lower()}"


def build_osc_data(result: AnalysisResult) -> Dict[str, Any]:
    """
    Build OSC message data from analysis result.
    
    Pure function: Converts AnalysisResult to OSC-ready data structure.
    """
    meta = result.metadata
    
    osc_data = {
        # Standard track info
        "artist": meta.artist,
        "title": meta.title,
        "album": meta.album,
        "duration_sec": meta.duration_sec,
        
        # Extended metadata
        "genre": meta.genre,
        "year": meta.year,
        "bpm": meta.bpm,
        "key": meta.key,
        
        # Lyrics analysis
        "has_lyrics": result.lyrics_found,
        "line_count": result.line_count,
        "refrain_count": result.refrain_count,
        "keywords": result.keywords[:10],  # Top 10
        
        # AI analysis
        "primary_mood": result.primary_mood,
        "themes": result.themes,
        
        # Computed metrics (0.0-1.0 for OSC control)
        "energy": result.computed_energy,
        "danceability": result.computed_danceability,
        "valence": result.computed_valence,
    }
    
    # Add category scores if available
    if result.categories:
        for cat in result.categories.get_top(10):
            osc_data[f"cat_{cat.name}"] = cat.score
    
    return osc_data


# =============================================================================
# ACTIONS - Functions with side effects (file I/O, API calls)
# =============================================================================

def read_mp3_tags(file_path: Path) -> MP3Metadata:
    """
    ACTION: Read MP3 tags from a file.
    
    Side effect: Reads from filesystem.
    """
    metadata = MP3Metadata(
        file_path=str(file_path),
        filename=file_path.name
    )
    
    if not MUTAGEN_AVAILABLE:
        logger.warning("mutagen not installed - cannot read MP3 tags")
        return metadata
    
    try:
        # Use MP3 for audio properties
        audio = MP3(file_path)
        metadata.duration_sec = audio.info.length
        metadata.bitrate = getattr(audio.info, 'bitrate', 0)
        metadata.sample_rate = getattr(audio.info, 'sample_rate', 0)
        metadata.channels = getattr(audio.info, 'channels', 0)
    except Exception as e:
        logger.debug(f"Error reading MP3 audio info: {e}")
    
    try:
        # Try EasyID3 for common tags
        easy = EasyID3(file_path)
        metadata.artist = easy.get('artist', [''])[0]
        metadata.title = easy.get('title', [''])[0]
        metadata.album = easy.get('album', [''])[0]
        metadata.album_artist = easy.get('albumartist', [''])[0]
        metadata.genre = easy.get('genre', [''])[0]
        metadata.year = easy.get('date', [''])[0][:4] if easy.get('date') else ''
        metadata.track_number = easy.get('tracknumber', [''])[0]
        metadata.disc_number = easy.get('discnumber', [''])[0]
        metadata.composer = easy.get('composer', [''])[0]
        
        # BPM from ID3
        bpm_tag = easy.get('bpm', [''])[0]
        metadata.bpm = parse_bpm_from_tag(bpm_tag)
    except Exception as e:
        logger.debug(f"Error reading EasyID3 tags: {e}")
    
    try:
        # Use raw ID3 for extended tags
        tags = ID3(file_path)
        metadata.raw_tags = {str(k): str(v) for k, v in tags.items()}
        
        # BPM (TBPM frame)
        if 'TBPM' in tags and not metadata.bpm:
            metadata.bpm = parse_bpm_from_tag(str(tags['TBPM']))
        
        # Key (TKEY frame)
        if 'TKEY' in tags:
            metadata.key = parse_key_from_tag(str(tags['TKEY']))
        
        # Initial key (often used by DJ software)
        if 'TKEY' not in tags:
            for key in tags:
                if 'initial' in key.lower() or 'key' in key.lower():
                    metadata.key = parse_key_from_tag(str(tags[key]))
                    break
        
        # Embedded lyrics (USLT frame)
        for key in tags:
            if key.startswith('USLT'):
                metadata.lyrics_embedded = str(tags[key])
                break
        
        # Comments (COMM frame)
        for key in tags:
            if key.startswith('COMM'):
                metadata.comment = str(tags[key])[:500]  # Limit length
                break
        
        # Energy/Mood from custom tags (various DJ software)
        for key, value in tags.items():
            key_lower = str(key).lower()
            if 'energy' in key_lower:
                try:
                    energy_val = float(re.search(r'(\d+(?:\.\d+)?)', str(value)).group(1))
                    # Normalize to 0-1 if it's 0-100 scale
                    metadata.energy = energy_val / 100 if energy_val > 1 else energy_val
                except (AttributeError, ValueError):
                    pass
            if 'mood' in key_lower:
                metadata.mood = str(value)[:50]
    except Exception as e:
        logger.debug(f"Error reading raw ID3 tags: {e}")
    
    # Fall back to filename parsing if no tags
    if not metadata.artist or not metadata.title:
        name = file_path.stem
        # Try "Artist - Title" format
        if " - " in name:
            parts = name.split(" - ", 1)
            if not metadata.artist:
                metadata.artist = parts[0].strip()
            if not metadata.title:
                metadata.title = parts[1].strip()
        elif not metadata.title:
            metadata.title = name
    
    return metadata


def find_mp3_files(folder: Path, recursive: bool = True) -> List[Path]:
    """
    ACTION: Find all MP3 files in a folder.
    
    Side effect: Reads filesystem.
    """
    pattern = "**/*.mp3" if recursive else "*.mp3"
    files = list(folder.glob(pattern))
    
    # Also check for .MP3 extension (case insensitive)
    files.extend(folder.glob(pattern.upper()))
    
    # Deduplicate and sort
    unique_files = list(set(files))
    unique_files.sort(key=lambda p: p.name.lower())
    
    return unique_files


def analyze_single_song(
    metadata: MP3Metadata,
    lyrics_fetcher: LyricsFetcher,
    llm_analyzer: LLMAnalyzer,
    categorizer: SongCategorizer,
    cache_dir: Path
) -> AnalysisResult:
    """
    ACTION: Run full analysis pipeline on a single song.
    
    Side effects: Fetches lyrics, calls LLM API, writes cache.
    """
    start_time = time.time()
    result = AnalysisResult(metadata=metadata)
    
    artist = metadata.artist
    title = metadata.title
    
    if not artist or not title:
        result.errors.append("Missing artist or title")
        return result
    
    lyrics = None
    
    # Step 1: Try embedded lyrics first
    if metadata.lyrics_embedded:
        lyrics = metadata.lyrics_embedded
        result.lyrics_source = "embedded"
        logger.debug(f"Using embedded lyrics for {artist} - {title}")
    
    # Step 2: Fetch from LRCLIB if no embedded lyrics
    if not lyrics:
        lyrics = lyrics_fetcher.fetch(artist, title, metadata.album, metadata.duration_sec)
        if lyrics:
            result.lyrics_source = "lrclib"
            logger.debug(f"Fetched lyrics from LRCLIB for {artist} - {title}")
    
    # Step 3: Analyze lyrics if found
    if lyrics:
        result.lyrics_found = True
        
        # Parse LRC format lyrics
        lines = parse_lrc(lyrics)
        if lines:
            lines = detect_refrains(lines)
            result.line_count = len(lines)
            result.refrain_count = len([l for l in lines if l.is_refrain])
        
        # Extract keywords
        result.keywords = extract_keywords_from_lyrics(lyrics)
    
    # Step 4: Categorize song (with or without lyrics)
    try:
        categories = categorizer.categorize(artist, title, lyrics=lyrics, album=metadata.album)
        result.categories = categories
        result.primary_mood = categories.primary_mood
        
        # Send categories via OSC log
        logger.debug(f"Categories for {artist} - {title}: {', '.join(f'{c.name}:{c.score:.2f}' for c in categories.get_top(5))}")
    except Exception as e:
        result.errors.append(f"Categorization error: {str(e)}")
        logger.debug(f"Categorization failed for {artist} - {title}: {e}")
    
    # Step 5: LLM analysis (if lyrics available)
    if lyrics and llm_analyzer.is_available:
        try:
            llm_result = llm_analyzer.analyze_lyrics(lyrics, artist, title)
            result.themes = llm_result.get('themes', [])
            result.image_prompt = llm_result.get('image_prompt', '')
        except Exception as e:
            result.errors.append(f"LLM error: {str(e)}")
            logger.debug(f"LLM analysis failed for {artist} - {title}: {e}")
    
    # Step 6: Compute metrics
    result.computed_energy = compute_energy_from_categories(result.categories)
    result.computed_danceability = compute_danceability_from_categories(result.categories, metadata.bpm)
    result.computed_valence = compute_valence_from_categories(result.categories)
    
    # If metadata has energy, use it to adjust
    if metadata.energy is not None:
        result.computed_energy = metadata.energy * 0.7 + result.computed_energy * 0.3
    
    # Record timing
    result.analyzed_at = time.time()
    result.analysis_time_sec = time.time() - start_time
    
    return result


def save_analysis_cache(result: AnalysisResult, cache_dir: Path) -> bool:
    """
    ACTION: Save analysis result to cache file.
    
    Side effect: Writes to filesystem.
    """
    try:
        cache_dir.mkdir(parents=True, exist_ok=True)
        
        # Create safe filename
        filename = sanitize_cache_filename(result.metadata.artist, result.metadata.title)
        cache_file = cache_dir / f"{filename}_analysis.json"
        
        # Build cacheable data
        data = {
            "metadata": result.metadata.to_dict(),
            "lyrics_found": result.lyrics_found,
            "lyrics_source": result.lyrics_source,
            "line_count": result.line_count,
            "refrain_count": result.refrain_count,
            "keywords": result.keywords,
            "categories": result.categories.to_dict() if result.categories else None,
            "primary_mood": result.primary_mood,
            "themes": result.themes,
            "image_prompt": result.image_prompt,
            "computed_energy": result.computed_energy,
            "computed_danceability": result.computed_danceability,
            "computed_valence": result.computed_valence,
            "analyzed_at": result.analyzed_at,
            "analysis_time_sec": result.analysis_time_sec,
            "errors": result.errors,
            "osc_data": build_osc_data(result),
        }
        
        cache_file.write_text(json.dumps(data, indent=2))
        return True
        
    except Exception as e:
        logger.error(f"Failed to save cache: {e}")
        return False


def load_analysis_cache(artist: str, title: str, cache_dir: Path) -> Optional[Dict[str, Any]]:
    """
    ACTION: Load analysis result from cache.
    
    Side effect: Reads from filesystem.
    """
    try:
        filename = sanitize_cache_filename(artist, title)
        cache_file = cache_dir / f"{filename}_analysis.json"
        
        if cache_file.exists():
            return json.loads(cache_file.read_text())
    except Exception as e:
        logger.debug(f"Cache load failed: {e}")
    
    return None


# =============================================================================
# ORCHESTRATION - Combines calculations and actions
# =============================================================================

class BackgroundSongAnalyzer:
    """
    Orchestrates background analysis of MP3 folders.
    
    This class coordinates:
    - Discovery of MP3 files
    - Reading of MP3 tags
    - Lyrics fetching and analysis
    - AI-powered categorization
    - Cache management
    
    Usage:
        analyzer = BackgroundSongAnalyzer(cache_dir=Path("./cache"))
        results = analyzer.analyze_folder(Path("/music"))
        
        # Or process a single file:
        result = analyzer.analyze_file(Path("/music/song.mp3"))
    """
    
    def __init__(
        self,
        cache_dir: Optional[Path] = None,
        max_workers: int = 4,
        skip_cached: bool = True
    ):
        """
        Initialize the background analyzer.
        
        Args:
            cache_dir: Directory for cache files (default: .cache in python-vj)
            max_workers: Number of parallel workers for analysis
            skip_cached: Skip files that are already cached
        """
        self._cache_dir = cache_dir or Config.APP_DATA_DIR / "song_analysis"
        self._cache_dir.mkdir(parents=True, exist_ok=True)
        
        self._max_workers = max_workers
        self._skip_cached = skip_cached
        
        # Initialize components
        self._lyrics_fetcher = LyricsFetcher()
        self._llm_analyzer = LLMAnalyzer()
        self._categorizer = SongCategorizer(llm=self._llm_analyzer)
        
        logger.info(f"BackgroundSongAnalyzer initialized")
        logger.info(f"  Cache directory: {self._cache_dir}")
        logger.info(f"  LLM backend: {self._llm_analyzer.backend_info}")
        logger.info(f"  Max workers: {self._max_workers}")
    
    @property
    def cache_dir(self) -> Path:
        """Get the cache directory."""
        return self._cache_dir
    
    def analyze_file(self, file_path: Path) -> AnalysisResult:
        """
        Analyze a single MP3 file.
        
        Args:
            file_path: Path to MP3 file
            
        Returns:
            AnalysisResult with all extracted and computed data
        """
        logger.info(f"Analyzing: {file_path.name}")
        
        # Read MP3 tags
        metadata = read_mp3_tags(file_path)
        
        # Check cache
        if self._skip_cached:
            cached = load_analysis_cache(metadata.artist, metadata.title, self._cache_dir)
            if cached:
                logger.debug(f"Using cached analysis for {metadata.artist} - {metadata.title}")
                # Reconstruct result from cache (partial - just return cached data)
                result = AnalysisResult(metadata=metadata)
                result.lyrics_found = cached.get('lyrics_found', False)
                result.lyrics_source = cached.get('lyrics_source', 'cache')
                result.line_count = cached.get('line_count', 0)
                result.refrain_count = cached.get('refrain_count', 0)
                result.keywords = cached.get('keywords', [])
                result.primary_mood = cached.get('primary_mood', '')
                result.themes = cached.get('themes', [])
                result.image_prompt = cached.get('image_prompt', '')
                result.computed_energy = cached.get('computed_energy', 0.5)
                result.computed_danceability = cached.get('computed_danceability', 0.5)
                result.computed_valence = cached.get('computed_valence', 0.5)
                result.analyzed_at = cached.get('analyzed_at', 0)
                
                if cached.get('categories'):
                    result.categories = SongCategories.from_dict(cached['categories'])
                
                return result
        
        # Run full analysis
        result = analyze_single_song(
            metadata,
            self._lyrics_fetcher,
            self._llm_analyzer,
            self._categorizer,
            self._cache_dir
        )
        
        # Save to cache
        save_analysis_cache(result, self._cache_dir)
        
        return result
    
    def analyze_folder(
        self,
        folder: Path,
        recursive: bool = True,
        progress_callback: Optional[callable] = None
    ) -> List[AnalysisResult]:
        """
        Analyze all MP3 files in a folder.
        
        Args:
            folder: Path to folder containing MP3 files
            recursive: Search subdirectories
            progress_callback: Optional callback(current, total, filename)
            
        Returns:
            List of AnalysisResult for each file
        """
        if not folder.exists():
            raise FileNotFoundError(f"Folder not found: {folder}")
        
        # Find all MP3 files
        mp3_files = find_mp3_files(folder, recursive)
        total = len(mp3_files)
        
        if total == 0:
            logger.warning(f"No MP3 files found in {folder}")
            return []
        
        logger.info(f"Found {total} MP3 files in {folder}")
        
        results = []
        errors = []
        
        # Process files in parallel
        with ThreadPoolExecutor(max_workers=self._max_workers) as executor:
            # Submit all tasks
            future_to_file = {
                executor.submit(self.analyze_file, f): f
                for f in mp3_files
            }
            
            # Process results as they complete
            for i, future in enumerate(as_completed(future_to_file), 1):
                file_path = future_to_file[future]
                
                try:
                    result = future.result()
                    results.append(result)
                    
                    if progress_callback:
                        progress_callback(i, total, file_path.name)
                    
                    # Log progress
                    status = "✓" if result.lyrics_found else "○"
                    logger.info(f"[{i}/{total}] {status} {result.metadata.artist} - {result.metadata.title}")
                    
                except Exception as e:
                    errors.append((file_path, str(e)))
                    logger.error(f"[{i}/{total}] ✗ {file_path.name}: {e}")
        
        # Summary
        logger.info(f"\nAnalysis complete:")
        logger.info(f"  Total files: {total}")
        logger.info(f"  Successful: {len(results)}")
        logger.info(f"  With lyrics: {sum(1 for r in results if r.lyrics_found)}")
        logger.info(f"  Errors: {len(errors)}")
        
        return results
    
    def get_analysis(self, artist: str, title: str) -> Optional[Dict[str, Any]]:
        """
        Get cached analysis for a song.
        
        Args:
            artist: Artist name
            title: Song title
            
        Returns:
            Cached analysis data or None
        """
        return load_analysis_cache(artist, title, self._cache_dir)
    
    def get_osc_data(self, artist: str, title: str) -> Optional[Dict[str, Any]]:
        """
        Get OSC-ready data for a song.
        
        Args:
            artist: Artist name
            title: Song title
            
        Returns:
            OSC data dictionary or None
        """
        cached = self.get_analysis(artist, title)
        if cached:
            return cached.get('osc_data')
        return None
    
    def list_analyzed_songs(self) -> List[Tuple[str, str]]:
        """
        List all analyzed songs in cache.
        
        Returns:
            List of (artist, title) tuples
        """
        songs = []
        for cache_file in self._cache_dir.glob("*_analysis.json"):
            try:
                data = json.loads(cache_file.read_text())
                meta = data.get('metadata', {})
                songs.append((meta.get('artist', ''), meta.get('title', '')))
            except Exception:
                pass
        return songs
    
    def get_statistics(self) -> Dict[str, Any]:
        """
        Get statistics about the analysis cache.
        
        Returns:
            Dictionary with cache statistics
        """
        cache_files = list(self._cache_dir.glob("*_analysis.json"))
        
        stats = {
            "total_songs": len(cache_files),
            "with_lyrics": 0,
            "with_bpm": 0,
            "with_key": 0,
            "genres": {},
            "moods": {},
            "avg_energy": 0.0,
            "avg_danceability": 0.0,
        }
        
        energy_sum = 0.0
        dance_sum = 0.0
        
        for cache_file in cache_files:
            try:
                data = json.loads(cache_file.read_text())
                
                if data.get('lyrics_found'):
                    stats['with_lyrics'] += 1
                
                meta = data.get('metadata', {})
                if meta.get('bpm'):
                    stats['with_bpm'] += 1
                if meta.get('key'):
                    stats['with_key'] += 1
                
                genre = meta.get('genre', 'Unknown')
                stats['genres'][genre] = stats['genres'].get(genre, 0) + 1
                
                mood = data.get('primary_mood', 'Unknown')
                stats['moods'][mood] = stats['moods'].get(mood, 0) + 1
                
                energy_sum += data.get('computed_energy', 0.5)
                dance_sum += data.get('computed_danceability', 0.5)
                
            except Exception:
                pass
        
        if stats['total_songs'] > 0:
            stats['avg_energy'] = round(energy_sum / stats['total_songs'], 2)
            stats['avg_danceability'] = round(dance_sum / stats['total_songs'], 2)
        
        return stats


# =============================================================================
# CLI INTERFACE
# =============================================================================

def print_result_summary(result: AnalysisResult):
    """Print a summary of analysis result."""
    meta = result.metadata
    
    print(f"\n{'='*60}")
    print(f"  {meta.artist} - {meta.title}")
    print(f"{'='*60}")
    
    # Metadata
    print(f"\n  📁 File: {meta.filename}")
    print(f"  ⏱  Duration: {meta.duration_sec:.1f}s")
    if meta.album:
        print(f"  💿 Album: {meta.album}")
    if meta.genre:
        print(f"  🎭 Genre: {meta.genre}")
    if meta.year:
        print(f"  📅 Year: {meta.year}")
    if meta.bpm:
        print(f"  🥁 BPM: {meta.bpm}")
    if meta.key:
        print(f"  🎹 Key: {meta.key}")
    
    # Lyrics
    if result.lyrics_found:
        print(f"\n  📜 Lyrics: {result.line_count} lines ({result.refrain_count} refrain)")
        print(f"     Source: {result.lyrics_source}")
        if result.keywords:
            print(f"     Keywords: {', '.join(result.keywords[:8])}")
    else:
        print(f"\n  📜 Lyrics: Not found")
    
    # Categories
    if result.categories:
        print(f"\n  🏷️  Primary Mood: {result.primary_mood}")
        print(f"     Top categories:")
        for cat in result.categories.get_top(5):
            bar = "█" * int(cat.score * 10) + "░" * (10 - int(cat.score * 10))
            print(f"       {cat.name:15s} {bar} {cat.score:.2f}")
    
    # Computed metrics
    print(f"\n  📊 Computed Metrics:")
    print(f"     Energy:       {'█' * int(result.computed_energy * 10)}{'░' * (10 - int(result.computed_energy * 10))} {result.computed_energy:.2f}")
    print(f"     Danceability: {'█' * int(result.computed_danceability * 10)}{'░' * (10 - int(result.computed_danceability * 10))} {result.computed_danceability:.2f}")
    print(f"     Valence:      {'█' * int(result.computed_valence * 10)}{'░' * (10 - int(result.computed_valence * 10))} {result.computed_valence:.2f}")
    
    # Themes
    if result.themes:
        print(f"\n  🎨 Themes: {', '.join(result.themes)}")
    
    # Timing
    print(f"\n  ⚡ Analyzed in {result.analysis_time_sec:.2f}s")
    
    if result.errors:
        print(f"\n  ⚠️  Errors: {', '.join(result.errors)}")


def main():
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description='Pre-analyze MP3 files for VJ performance',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Analyze all MP3s in a folder:
  python background_analyzer.py /path/to/music
  
  # Analyze with custom cache directory:
  python background_analyzer.py /path/to/music --cache-dir ./my_cache
  
  # Single file analysis with verbose output:
  python background_analyzer.py /path/to/song.mp3 -v
  
  # Show statistics for existing cache:
  python background_analyzer.py --stats
  
  # Force re-analysis (don't skip cached):
  python background_analyzer.py /path/to/music --no-skip-cached
"""
    )
    
    parser.add_argument(
        'path',
        nargs='?',
        type=Path,
        help='Path to MP3 file or folder to analyze'
    )
    parser.add_argument(
        '--cache-dir',
        type=Path,
        default=None,
        help='Directory for cache files'
    )
    parser.add_argument(
        '--workers',
        type=int,
        default=4,
        help='Number of parallel workers (default: 4)'
    )
    parser.add_argument(
        '--no-skip-cached',
        action='store_true',
        help='Re-analyze files even if cached'
    )
    parser.add_argument(
        '--no-recursive',
        action='store_true',
        help='Don\'t search subdirectories'
    )
    parser.add_argument(
        '--stats',
        action='store_true',
        help='Show cache statistics and exit'
    )
    parser.add_argument(
        '--list',
        action='store_true',
        help='List all analyzed songs and exit'
    )
    parser.add_argument(
        '-v', '--verbose',
        action='store_true',
        help='Verbose output'
    )
    parser.add_argument(
        '-q', '--quiet',
        action='store_true',
        help='Quiet mode - only show errors'
    )
    
    args = parser.parse_args()
    
    # Set log level
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    elif args.quiet:
        logging.getLogger().setLevel(logging.ERROR)
    
    # Create analyzer
    analyzer = BackgroundSongAnalyzer(
        cache_dir=args.cache_dir,
        max_workers=args.workers,
        skip_cached=not args.no_skip_cached
    )
    
    # Handle --stats flag
    if args.stats:
        stats = analyzer.get_statistics()
        print("\n" + "="*50)
        print("  Cache Statistics")
        print("="*50)
        print(f"\n  Total songs analyzed: {stats['total_songs']}")
        print(f"  With lyrics: {stats['with_lyrics']}")
        print(f"  With BPM: {stats['with_bpm']}")
        print(f"  With musical key: {stats['with_key']}")
        print(f"\n  Average energy: {stats['avg_energy']}")
        print(f"  Average danceability: {stats['avg_danceability']}")
        
        if stats['genres']:
            print(f"\n  Top genres:")
            for genre, count in sorted(stats['genres'].items(), key=lambda x: x[1], reverse=True)[:5]:
                print(f"    {genre}: {count}")
        
        if stats['moods']:
            print(f"\n  Top moods:")
            for mood, count in sorted(stats['moods'].items(), key=lambda x: x[1], reverse=True)[:5]:
                print(f"    {mood}: {count}")
        
        print()
        return
    
    # Handle --list flag
    if args.list:
        songs = analyzer.list_analyzed_songs()
        print(f"\nAnalyzed songs ({len(songs)} total):\n")
        for artist, title in sorted(songs):
            print(f"  {artist} - {title}")
        print()
        return
    
    # Require path for analysis
    if not args.path:
        parser.print_help()
        return
    
    path = args.path
    
    if not path.exists():
        print(f"Error: Path not found: {path}")
        return
    
    print("\n" + "="*60)
    print("  🎵 Background Song Analyzer")
    print("="*60)
    
    if path.is_file():
        # Analyze single file
        result = analyzer.analyze_file(path)
        print_result_summary(result)
    else:
        # Analyze folder
        results = analyzer.analyze_folder(path, recursive=not args.no_recursive)
        
        if args.verbose:
            for result in results:
                print_result_summary(result)
        
        # Print summary
        print("\n" + "="*60)
        print("  Summary")
        print("="*60)
        print(f"\n  Analyzed: {len(results)} files")
        print(f"  With lyrics: {sum(1 for r in results if r.lyrics_found)}")
        print(f"  Cache directory: {analyzer.cache_dir}")
        print()


if __name__ == '__main__':
    main()
