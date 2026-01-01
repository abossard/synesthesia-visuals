"""
Shaders Module - Shader indexing and matching.

Wraps ShaderIndexer and ShaderMatcher with a Module interface.

Usage as module:
    from modules.shaders import ShadersModule, ShadersConfig

    shaders = ShadersModule()
    shaders.start()
    print(f"Loaded {shaders.shader_count} shaders")
    match = shaders.find_best_match(energy=0.8, valence=0.5)
    if match:
        print(f"Best match: {match.name}")
    shaders.stop()

Standalone CLI:
    python -m modules.shaders --list
    python -m modules.shaders --energy 0.8 --valence 0.6
    python -m modules.shaders --search "colorful waves"
    python -m modules.shaders --info "isf/BitStreamer"
"""
import argparse
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from modules.base import Module


@dataclass
class ShadersConfig:
    """Configuration for Shaders module."""
    shaders_dir: Optional[str] = None  # Auto-detect if None
    use_chromadb: bool = True  # Use ChromaDB for fast search


@dataclass
class ShaderInfo:
    """Information about a shader."""
    name: str
    path: str
    energy_score: float
    mood_valence: float
    color_warmth: float
    motion_speed: float
    mood: str
    colors: List[str]
    effects: List[str]
    rating: int  # 1=BEST, 2=GOOD, 3=NORMAL, 4=MASK, 5=SKIP


@dataclass
class ShaderMatchResult:
    """Result from shader matching."""
    name: str
    path: str
    score: float  # Lower is better
    energy_score: float
    mood_valence: float
    mood: str


class ShadersModule(Module):
    """
    Shaders module for indexing and matching.

    Provides:
    - Shader indexing from ISF and GLSL files
    - Feature-based matching (energy, valence)
    - Text/semantic search
    - Rating-aware selection (prefers quality shaders)
    """

    def __init__(self, config: Optional[ShadersConfig] = None):
        super().__init__()
        self._config = config or ShadersConfig()
        self._indexer = None
        self._matcher = None

    @property
    def config(self) -> ShadersConfig:
        return self._config

    @property
    def shader_count(self) -> int:
        """Number of loaded shaders."""
        if not self._matcher:
            return 0
        return len(self._matcher.shaders)

    @property
    def shaders_dir(self) -> Optional[str]:
        """Path to shaders directory."""
        if self._indexer:
            return str(self._indexer.shaders_base)
        return self._config.shaders_dir

    def start(self) -> bool:
        """Initialize the module and load shaders."""
        if self._started:
            return True

        import logging
        logger = logging.getLogger(__name__)

        from shader_matcher import ShaderIndexer, ShaderMatcher

        # Initialize indexer
        self._indexer = ShaderIndexer(
            shaders_dir=self._config.shaders_dir,
            use_chromadb=self._config.use_chromadb
        )

        # Sync from JSON files
        stats = self._indexer.sync()
        loaded = stats.get('loaded', 0)

        if loaded == 0:
            logger.warning(
                f"No analyzed shaders found at {self._indexer.shaders_base}. "
                f"Run shader analysis first: python -m shader_matcher --analyze"
            )
        else:
            logger.info(f"Loaded {loaded} analyzed shaders")

        # Initialize matcher with same directory
        self._matcher = ShaderMatcher(str(self._indexer.shaders_base))

        self._started = True
        return True

    def stop(self) -> None:
        """Stop the module."""
        if not self._started:
            return

        self._indexer = None
        self._matcher = None
        self._started = False

    def list_shaders(self) -> List[ShaderInfo]:
        """
        List all available shaders.

        Returns:
            List of ShaderInfo with basic info about each shader.
        """
        if not self._started:
            self.start()

        result = []
        for shader in self._matcher.shaders:
            result.append(ShaderInfo(
                name=shader.name,
                path=shader.path,
                energy_score=shader.energy_score,
                mood_valence=shader.mood_valence,
                color_warmth=shader.color_warmth,
                motion_speed=shader.motion_speed,
                mood=shader.mood,
                colors=shader.colors,
                effects=shader.effects,
                rating=shader.get_effective_rating()
            ))
        return result

    def get_shader(self, name: str) -> Optional[ShaderInfo]:
        """
        Get info about a specific shader.

        Args:
            name: Shader name (e.g., "isf/BitStreamer" or "BitStreamer")

        Returns:
            ShaderInfo or None if not found.
        """
        if not self._started:
            self.start()

        # Try exact match first
        for shader in self._matcher.shaders:
            if shader.name == name:
                return ShaderInfo(
                    name=shader.name,
                    path=shader.path,
                    energy_score=shader.energy_score,
                    mood_valence=shader.mood_valence,
                    color_warmth=shader.color_warmth,
                    motion_speed=shader.motion_speed,
                    mood=shader.mood,
                    colors=shader.colors,
                    effects=shader.effects,
                    rating=shader.get_effective_rating()
                )

        # Try partial match (without prefix)
        for shader in self._matcher.shaders:
            if shader.name.endswith(f"/{name}") or shader.name == f"isf/{name}" or shader.name == f"glsl/{name}":
                return ShaderInfo(
                    name=shader.name,
                    path=shader.path,
                    energy_score=shader.energy_score,
                    mood_valence=shader.mood_valence,
                    color_warmth=shader.color_warmth,
                    motion_speed=shader.motion_speed,
                    mood=shader.mood,
                    colors=shader.colors,
                    effects=shader.effects,
                    rating=shader.get_effective_rating()
                )

        return None

    def find_best_match(
        self,
        energy: float,
        valence: float,
        top_k: int = 5,
        require_quality: bool = True
    ) -> Optional[ShaderMatchResult]:
        """
        Find best matching shader for energy/valence.

        Args:
            energy: Energy level 0.0-1.0 (calm to intense)
            valence: Mood valence -1.0 to 1.0 (dark to bright)
            top_k: Number of candidates to consider
            require_quality: Only consider rating 1-2 shaders

        Returns:
            ShaderMatchResult or None if no shaders available.
        """
        if not self._started:
            self.start()

        # Build target feature vector
        # [energy, valence, warmth, motion, geometric, density]
        target = [
            energy,
            valence,
            0.5 + (valence * 0.3),  # Warmth correlates with valence
            energy * 0.7,  # Motion correlates with energy
            0.5,  # Neutral geometric
            energy * 0.5 + 0.25  # Density correlates with energy
        ]

        matches = self._matcher.match_to_features(
            target,
            top_k=top_k,
            require_quality=require_quality
        )

        if not matches:
            return None

        shader, score = matches[0]
        return ShaderMatchResult(
            name=shader.name,
            path=shader.path,
            score=score,
            energy_score=shader.energy_score,
            mood_valence=shader.mood_valence,
            mood=shader.mood
        )

    def find_matches(
        self,
        energy: float,
        valence: float,
        top_k: int = 5,
        require_quality: bool = True
    ) -> List[ShaderMatchResult]:
        """
        Find multiple matching shaders for energy/valence.

        Args:
            energy: Energy level 0.0-1.0
            valence: Mood valence -1.0 to 1.0
            top_k: Number of results
            require_quality: Only consider rating 1-2 shaders

        Returns:
            List of ShaderMatchResult sorted by score (best first).
        """
        if not self._started:
            self.start()

        target = [
            energy,
            valence,
            0.5 + (valence * 0.3),
            energy * 0.7,
            0.5,
            energy * 0.5 + 0.25
        ]

        matches = self._matcher.match_to_features(
            target,
            top_k=top_k,
            require_quality=require_quality
        )

        return [
            ShaderMatchResult(
                name=shader.name,
                path=shader.path,
                score=score,
                energy_score=shader.energy_score,
                mood_valence=shader.mood_valence,
                mood=shader.mood
            )
            for shader, score in matches
        ]

    def match_by_mood(
        self,
        mood: str,
        energy: float = 0.5,
        top_k: int = 5,
        require_quality: bool = True
    ) -> List[ShaderMatchResult]:
        """
        Find shaders matching a mood keyword.

        Args:
            mood: Mood keyword (energetic, calm, dark, bright, psychedelic, etc.)
            energy: Energy level 0.0-1.0
            top_k: Number of results
            require_quality: Only consider rating 1-2 shaders

        Returns:
            List of ShaderMatchResult.
        """
        if not self._started:
            self.start()

        matches = self._matcher.match_by_mood(
            mood,
            energy=energy,
            top_k=top_k,
            require_quality=require_quality
        )

        return [
            ShaderMatchResult(
                name=shader.name,
                path=shader.path,
                score=score,
                energy_score=shader.energy_score,
                mood_valence=shader.mood_valence,
                mood=shader.mood
            )
            for shader, score in matches
        ]

    def search(self, query: str, top_k: int = 10) -> List[Tuple[str, float]]:
        """
        Semantic text search for shaders.

        Args:
            query: Search query (e.g., "colorful waves", "dark geometric")
            top_k: Number of results

        Returns:
            List of (shader_name, score) tuples.
        """
        if not self._started:
            self.start()

        results = self._indexer.text_search(query, top_k=top_k)
        return [(name, score) for name, score, _ in results]

    def get_stats(self) -> Dict[str, Any]:
        """Get module status and statistics."""
        status = super().get_status()

        if self._matcher:
            matcher_stats = self._matcher.get_stats()
            status["shader_count"] = matcher_stats.get("count", 0)
            status["with_features"] = matcher_stats.get("with_features", 0)
            status["rating_best"] = matcher_stats.get("rating_best", 0)
            status["rating_good"] = matcher_stats.get("rating_good", 0)
            status["quality_count"] = matcher_stats.get("quality_count", 0)

        if self._indexer:
            indexer_stats = self._indexer.get_stats()
            status["shaders_dir"] = indexer_stats.get("shaders_dir", "")
            status["chromadb_enabled"] = indexer_stats.get("chromadb_enabled", False)

        return status


def main():
    """CLI entry point for standalone shaders module."""
    parser = argparse.ArgumentParser(
        description="Shaders Module - Index and match shaders"
    )
    parser.add_argument(
        "--list", "-l",
        action="store_true",
        help="List all available shaders"
    )
    parser.add_argument(
        "--energy", "-e",
        type=float,
        help="Energy level 0.0-1.0 for matching"
    )
    parser.add_argument(
        "--valence", "-v",
        type=float,
        help="Valence -1.0 to 1.0 for matching"
    )
    parser.add_argument(
        "--mood", "-m",
        help="Mood keyword (energetic, calm, dark, bright, etc.)"
    )
    parser.add_argument(
        "--search", "-s",
        help="Text search query"
    )
    parser.add_argument(
        "--info", "-i",
        help="Get info about a specific shader"
    )
    parser.add_argument(
        "--top", "-k",
        type=int,
        default=5,
        help="Number of results (default: 5)"
    )
    parser.add_argument(
        "--all-ratings",
        action="store_true",
        help="Include all ratings (not just quality 1-2)"
    )
    parser.add_argument(
        "--stats",
        action="store_true",
        help="Show statistics"
    )
    args = parser.parse_args()

    shaders = ShadersModule()
    shaders.start()

    require_quality = not args.all_ratings

    if args.stats:
        stats = shaders.get_stats()
        print(f"\n{'='*60}")
        print("Shaders Module Statistics")
        print(f"{'='*60}\n")
        for key, value in stats.items():
            print(f"  {key}: {value}")
        return

    if args.info:
        info = shaders.get_shader(args.info)
        if info:
            print(f"\n{'='*60}")
            print(f"Shader: {info.name}")
            print(f"{'='*60}\n")
            print(f"  Path: {info.path}")
            print(f"  Mood: {info.mood}")
            print(f"  Rating: {info.rating}")
            print(f"  Energy: {info.energy_score:.2f}")
            print(f"  Valence: {info.mood_valence:+.2f}")
            print(f"  Warmth: {info.color_warmth:.2f}")
            print(f"  Motion: {info.motion_speed:.2f}")
            if info.colors:
                print(f"  Colors: {', '.join(info.colors)}")
            if info.effects:
                print(f"  Effects: {', '.join(info.effects)}")
        else:
            print(f"Shader not found: {args.info}", file=sys.stderr)
            sys.exit(1)
        return

    if args.list:
        all_shaders = shaders.list_shaders()
        print(f"\n{'='*60}")
        print(f"Available Shaders ({len(all_shaders)})")
        print(f"{'='*60}\n")

        # Group by rating
        by_rating = {1: [], 2: [], 3: [], 4: [], 5: []}
        for s in all_shaders:
            by_rating[s.rating].append(s)

        rating_names = {1: "BEST", 2: "GOOD", 3: "NORMAL", 4: "MASK", 5: "SKIP"}
        for rating in [1, 2, 3, 4, 5]:
            group = by_rating[rating]
            if group:
                print(f"\n[{rating_names[rating]}] ({len(group)} shaders)")
                for s in sorted(group, key=lambda x: x.name)[:10]:
                    print(f"  {s.name} ({s.mood}, e={s.energy_score:.1f})")
                if len(group) > 10:
                    print(f"  ... and {len(group) - 10} more")
        return

    if args.search:
        print(f"\n{'='*60}")
        print(f"Search: '{args.search}'")
        print(f"{'='*60}\n")

        results = shaders.search(args.search, top_k=args.top)
        if results:
            for name, score in results:
                info = shaders.get_shader(name)
                mood = info.mood if info else "?"
                print(f"  {name} ({mood}) - score: {score:.3f}")
        else:
            print("No results found")
        return

    if args.mood:
        energy = args.energy if args.energy is not None else 0.5
        print(f"\n{'='*60}")
        print(f"Mood: '{args.mood}', Energy: {energy}")
        print(f"{'='*60}\n")

        matches = shaders.match_by_mood(
            args.mood,
            energy=energy,
            top_k=args.top,
            require_quality=require_quality
        )
        if matches:
            for m in matches:
                print(f"  {m.name}")
                print(f"    score: {m.score:.3f}, mood: {m.mood}")
                print(f"    energy: {m.energy_score:.2f}, valence: {m.mood_valence:+.2f}")
        else:
            print("No matching shaders found")
        return

    if args.energy is not None or args.valence is not None:
        energy = args.energy if args.energy is not None else 0.5
        valence = args.valence if args.valence is not None else 0.0

        print(f"\n{'='*60}")
        print(f"Energy: {energy}, Valence: {valence:+.2f}")
        print(f"{'='*60}\n")

        matches = shaders.find_matches(
            energy=energy,
            valence=valence,
            top_k=args.top,
            require_quality=require_quality
        )
        if matches:
            for m in matches:
                print(f"  {m.name}")
                print(f"    score: {m.score:.3f}, mood: {m.mood}")
                print(f"    energy: {m.energy_score:.2f}, valence: {m.mood_valence:+.2f}")
        else:
            print("No matching shaders found")
        return

    # Default: show stats
    stats = shaders.get_stats()
    print(f"\nShaders Module")
    print(f"  Loaded: {stats.get('shader_count', 0)} shaders")
    print(f"  Quality (1-2): {stats.get('quality_count', 0)}")
    print(f"\nUsage:")
    print(f"  python -m modules.shaders --list")
    print(f"  python -m modules.shaders --energy 0.8 --valence 0.5")
    print(f"  python -m modules.shaders --mood energetic")
    print(f"  python -m modules.shaders --search 'colorful waves'")
    print(f"  python -m modules.shaders --info 'isf/BitStreamer'")

    shaders.stop()


if __name__ == "__main__":
    main()
