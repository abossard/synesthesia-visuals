"""
AI Analysis Module - Song categorization with graceful degradation.

Wraps LLMAnalyzer and SongCategorizer with a Module interface.

Usage as module:
    from modules.ai_analysis import AIAnalysisModule, AIAnalysisConfig

    ai = AIAnalysisModule()
    ai.start()
    if ai.is_available:
        result = ai.categorize("Is this the real life...", "Queen", "Bohemian Rhapsody")
        print(f"Primary mood: {result.primary_mood}")
        print(f"Energy: {result.energy}, Valence: {result.valence}")
    ai.stop()

Standalone CLI:
    python -m modules.ai_analysis --artist "Queen" --title "Bohemian Rhapsody"
    python -m modules.ai_analysis --artist "Queen" --title "Bohemian Rhapsody" --lyrics-file lyrics.txt
"""
import argparse
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Optional

from modules.base import Module


@dataclass
class AIAnalysisConfig:
    """Configuration for AI Analysis module."""
    lm_studio_url: str = "http://localhost:1234"
    cache_dir: Optional[Path] = None


@dataclass
class AnalysisResult:
    """Result of song analysis."""
    primary_mood: str
    energy: float  # 0.0 - 1.0
    valence: float  # -1.0 (dark) to 1.0 (bright)
    scores: Dict[str, float]  # All category scores
    cached: bool = False
    backend: str = "none"  # "openai", "lmstudio", "basic"

    def get_top(self, n: int = 5) -> list:
        """Get top N categories sorted by score."""
        items = sorted(self.scores.items(), key=lambda x: x[1], reverse=True)
        return items[:n]


class AIAnalysisModule(Module):
    """
    AI Analysis module for song categorization.

    Provides:
    - Song categorization by mood (dark, happy, energetic, etc.)
    - Energy and valence scores
    - Graceful degradation when LLM unavailable
    - Automatic caching
    """

    def __init__(self, config: Optional[AIAnalysisConfig] = None):
        super().__init__()
        self._config = config or AIAnalysisConfig()
        self._llm = None
        self._categorizer = None

    @property
    def config(self) -> AIAnalysisConfig:
        return self._config

    @property
    def is_available(self) -> bool:
        """Check if AI backend (LLM) is available."""
        if not self._started:
            return False
        return self._llm is not None and self._llm.is_available

    @property
    def backend_info(self) -> str:
        """Get description of current backend."""
        if not self._started or not self._llm:
            return "Not started"
        return self._llm.backend_info

    def start(self) -> bool:
        """Initialize the module and connect to LLM backend."""
        if self._started:
            return True

        from ai_services import LLMAnalyzer, SongCategorizer

        self._llm = LLMAnalyzer(cache_dir=self._config.cache_dir)
        self._categorizer = SongCategorizer(
            llm=self._llm,
            cache_dir=self._config.cache_dir
        )

        self._started = True
        return True

    def stop(self) -> None:
        """Stop the module."""
        if not self._started:
            return

        self._llm = None
        self._categorizer = None
        self._started = False

    def categorize(
        self,
        lyrics: str,
        artist: str,
        title: str,
        album: Optional[str] = None
    ) -> AnalysisResult:
        """
        Categorize a song by mood and theme.

        Args:
            lyrics: Song lyrics text
            artist: Artist name
            title: Song title
            album: Optional album name

        Returns:
            AnalysisResult with primary_mood, energy, valence, and all scores.
            Falls back to basic keyword matching if LLM unavailable.
        """
        if not self._started:
            self.start()

        # Get categorization
        categories = self._categorizer.categorize(artist, title, lyrics, album)

        # Map category scores to energy/valence
        scores = categories.get_dict()

        # Calculate energy from relevant categories
        energy = self._calculate_energy(scores)

        # Calculate valence (mood brightness)
        valence = self._calculate_valence(scores)

        # Determine backend used
        if self._llm and self._llm.is_available:
            backend = self._llm.backend_info
        else:
            backend = "basic"

        return AnalysisResult(
            primary_mood=categories.primary_mood,
            energy=energy,
            valence=valence,
            scores=scores,
            cached=False,  # Categories class handles caching internally
            backend=backend
        )

    def analyze_lyrics(
        self,
        lyrics: str,
        artist: str,
        title: str
    ) -> Dict[str, Any]:
        """
        Analyze lyrics for refrain, keywords, and themes.

        Returns dict with:
        - refrain_lines: List of repeated chorus lines
        - keywords: Key words from lyrics
        - themes: Detected themes
        - cached: Whether result was from cache
        """
        if not self._started:
            self.start()

        return self._llm.analyze_lyrics(lyrics, artist, title)

    def _calculate_energy(self, scores: Dict[str, float]) -> float:
        """Calculate energy score from category scores."""
        # High energy categories
        high_energy = ['energetic', 'aggressive', 'uplifting']
        # Low energy categories
        low_energy = ['calm', 'peaceful', 'sad']

        high_sum = sum(scores.get(cat, 0) for cat in high_energy)
        low_sum = sum(scores.get(cat, 0) for cat in low_energy)

        # Normalize to 0-1 range
        if high_sum + low_sum == 0:
            return 0.5

        return min(1.0, max(0.0, high_sum / (high_sum + low_sum + 0.001)))

    def _calculate_valence(self, scores: Dict[str, float]) -> float:
        """Calculate valence (mood brightness) from category scores."""
        # Positive valence categories
        positive = ['happy', 'uplifting', 'love', 'romantic', 'peaceful']
        # Negative valence categories
        negative = ['dark', 'sad', 'death', 'aggressive']

        pos_sum = sum(scores.get(cat, 0) for cat in positive)
        neg_sum = sum(scores.get(cat, 0) for cat in negative)

        # Map to -1 to 1 range
        total = pos_sum + neg_sum
        if total == 0:
            return 0.0

        return (pos_sum - neg_sum) / total

    def get_status(self) -> Dict[str, Any]:
        """Get module status."""
        status = super().get_status()
        status["is_available"] = self.is_available
        status["backend"] = self.backend_info
        return status


def main():
    """CLI entry point for standalone AI analysis module."""
    parser = argparse.ArgumentParser(
        description="AI Analysis Module - Categorize songs by mood"
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
        help="Album name (optional)"
    )
    parser.add_argument(
        "--lyrics-file", "-l",
        help="Path to file containing lyrics"
    )
    parser.add_argument(
        "--lyrics",
        help="Lyrics text (use --lyrics-file for longer texts)"
    )
    parser.add_argument(
        "--fetch-lyrics",
        action="store_true",
        help="Fetch lyrics from LRCLIB before analysis"
    )
    parser.add_argument(
        "--analyze",
        action="store_true",
        help="Also run lyrics analysis (refrain/keywords/themes)"
    )
    args = parser.parse_args()

    # Get lyrics from various sources
    lyrics = None

    if args.lyrics_file:
        try:
            lyrics = Path(args.lyrics_file).read_text()
            print(f"Loaded lyrics from: {args.lyrics_file}")
        except Exception as e:
            print(f"Error reading lyrics file: {e}", file=sys.stderr)
            sys.exit(1)
    elif args.lyrics:
        lyrics = args.lyrics
    elif args.fetch_lyrics:
        # Fetch from LRCLIB
        print(f"Fetching lyrics for: {args.artist} - {args.title}")
        try:
            from adapters import LyricsFetcher
            fetcher = LyricsFetcher()
            lyrics = fetcher.fetch(args.artist, args.title, args.album)
            if lyrics:
                print(f"Fetched {len(lyrics)} chars of lyrics")
            else:
                print("No lyrics found")
        except Exception as e:
            print(f"Error fetching lyrics: {e}", file=sys.stderr)

    ai = AIAnalysisModule()
    ai.start()

    print(f"\nBackend: {ai.backend_info}")
    print(f"Available: {ai.is_available}")
    print(f"\n{'='*60}")

    if lyrics:
        print(f"Analyzing: {args.artist} - {args.title}")
        print(f"{'='*60}\n")

        result = ai.categorize(lyrics, args.artist, args.title, args.album)

        print(f"Primary Mood: {result.primary_mood}")
        print(f"Energy: {result.energy:.2f}")
        print(f"Valence: {result.valence:+.2f}")
        print(f"\nTop Categories:")

        for name, score in result.get_top(5):
            bar = "█" * int(score * 20)
            print(f"  {name:12} {bar} {score:.2f}")

        if args.analyze:
            print(f"\n{'='*60}")
            print("Lyrics Analysis")
            print(f"{'='*60}\n")

            analysis = ai.analyze_lyrics(lyrics, args.artist, args.title)

            if analysis.get("refrain_lines"):
                print("Refrain lines:")
                for line in analysis["refrain_lines"][:5]:
                    print(f"  ♪ {line}")

            if analysis.get("keywords"):
                print(f"\nKeywords: {', '.join(analysis['keywords'][:10])}")

            if analysis.get("themes"):
                print(f"Themes: {', '.join(analysis['themes'])}")

            print(f"\nCached: {analysis.get('cached', False)}")
    else:
        print("No lyrics provided. Use --lyrics, --lyrics-file, or --fetch-lyrics")
        print("\nExample:")
        print(f"  python -m modules.ai_analysis -a 'Queen' -t 'Bohemian Rhapsody' --fetch-lyrics")
        sys.exit(1)

    ai.stop()


if __name__ == "__main__":
    main()
