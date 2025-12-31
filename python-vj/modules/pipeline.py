"""
Pipeline Module - Orchestrates lyrics → AI → shaders → images.

Coordinates all analysis modules to process a song end-to-end.

Usage as module:
    from modules.pipeline import PipelineModule, PipelineConfig

    pipeline = PipelineModule()
    pipeline.on_step_start = lambda step: print(f"Starting: {step}")
    pipeline.on_step_complete = lambda step, result: print(f"Done: {step}")
    pipeline.start()

    result = pipeline.process("Queen", "Bohemian Rhapsody")
    print(f"Mood: {result.mood}, Shader: {result.shader_name}")

    pipeline.stop()

Standalone CLI:
    python -m modules.pipeline --artist "Queen" --title "Bohemian Rhapsody"
    python -m modules.pipeline --artist "Queen" --title "Bohemian Rhapsody" --skip-images
"""
import argparse
import sys
import time
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

from modules.base import Module


class PipelineStep(Enum):
    """Pipeline processing steps."""
    LYRICS = "lyrics"
    AI_ANALYSIS = "ai_analysis"
    SHADER_MATCH = "shader_match"
    IMAGES = "images"


@dataclass
class PipelineConfig:
    """Configuration for Pipeline module."""
    skip_lyrics: bool = False
    skip_ai: bool = False
    skip_shaders: bool = False
    skip_images: bool = False
    shaders_dir: Optional[str] = None


@dataclass
class PipelineResult:
    """Result from pipeline processing."""
    artist: str
    title: str
    success: bool = False

    # Lyrics
    lyrics_found: bool = False
    lyrics_line_count: int = 0

    # AI Analysis
    ai_available: bool = False
    mood: str = ""
    energy: float = 0.5
    valence: float = 0.0
    categories: Dict[str, float] = field(default_factory=dict)

    # Shader
    shader_matched: bool = False
    shader_name: str = ""
    shader_score: float = 0.0

    # Images
    images_found: bool = False
    images_folder: str = ""
    images_count: int = 0

    # Timing
    steps_completed: List[str] = field(default_factory=list)
    total_time_ms: int = 0


# Callback types
OnStepStart = Callable[[PipelineStep], None]
OnStepComplete = Callable[[PipelineStep, Any], None]
OnPipelineComplete = Callable[[PipelineResult], None]


class PipelineModule(Module):
    """
    Pipeline module orchestrating song processing.

    Steps:
    1. Fetch lyrics (LyricsModule)
    2. AI analysis (AIAnalysisModule)
    3. Match shader (ShadersModule)
    4. Fetch images (ImageScraper)

    Each step is optional and degrades gracefully if unavailable.
    """

    def __init__(self, config: Optional[PipelineConfig] = None):
        super().__init__()
        self._config = config or PipelineConfig()

        # Sub-modules (lazy loaded)
        self._lyrics = None
        self._ai = None
        self._shaders = None
        self._images = None

        # Callbacks
        self._on_step_start: Optional[OnStepStart] = None
        self._on_step_complete: Optional[OnStepComplete] = None
        self._on_pipeline_complete: Optional[OnPipelineComplete] = None

    @property
    def config(self) -> PipelineConfig:
        return self._config

    @property
    def on_step_start(self) -> Optional[OnStepStart]:
        return self._on_step_start

    @on_step_start.setter
    def on_step_start(self, callback: Optional[OnStepStart]) -> None:
        self._on_step_start = callback

    @property
    def on_step_complete(self) -> Optional[OnStepComplete]:
        return self._on_step_complete

    @on_step_complete.setter
    def on_step_complete(self, callback: Optional[OnStepComplete]) -> None:
        self._on_step_complete = callback

    @property
    def on_pipeline_complete(self) -> Optional[OnPipelineComplete]:
        return self._on_pipeline_complete

    @on_pipeline_complete.setter
    def on_pipeline_complete(self, callback: Optional[OnPipelineComplete]) -> None:
        self._on_pipeline_complete = callback

    def start(self) -> bool:
        """Initialize all sub-modules."""
        if self._started:
            return True

        # Initialize sub-modules lazily on first use
        self._started = True
        return True

    def stop(self) -> None:
        """Stop all sub-modules."""
        if not self._started:
            return

        if self._lyrics:
            self._lyrics.stop()
            self._lyrics = None

        if self._ai:
            self._ai.stop()
            self._ai = None

        if self._shaders:
            self._shaders.stop()
            self._shaders = None

        self._images = None
        self._started = False

    def process(
        self,
        artist: str,
        title: str,
        album: str = ""
    ) -> PipelineResult:
        """
        Process a song through the full pipeline.

        Args:
            artist: Artist name
            title: Song title
            album: Optional album name

        Returns:
            PipelineResult with all gathered information.
        """
        if not self._started:
            self.start()

        start_time = time.time()
        result = PipelineResult(artist=artist, title=title)

        lyrics_text = None

        # Step 1: Fetch lyrics
        if not self._config.skip_lyrics:
            lyrics_text = self._step_lyrics(result, artist, title, album)

        # Step 2: AI Analysis
        if not self._config.skip_ai and lyrics_text:
            self._step_ai_analysis(result, lyrics_text, artist, title, album)

        # Step 3: Shader matching
        if not self._config.skip_shaders:
            self._step_shader_match(result)

        # Step 4: Fetch images
        if not self._config.skip_images:
            self._step_images(result, artist, title, album)

        # Finalize
        result.total_time_ms = int((time.time() - start_time) * 1000)
        result.success = len(result.steps_completed) > 0

        # Fire completion callback
        if self._on_pipeline_complete:
            try:
                self._on_pipeline_complete(result)
            except Exception:
                pass

        return result

    def _step_lyrics(
        self,
        result: PipelineResult,
        artist: str,
        title: str,
        album: str
    ) -> Optional[str]:
        """Fetch lyrics. Returns lyrics text or None."""
        self._fire_step_start(PipelineStep.LYRICS)

        try:
            if self._lyrics is None:
                from modules.lyrics import LyricsModule
                self._lyrics = LyricsModule()
                self._lyrics.start()

            success = self._lyrics.fetch(artist, title, album)

            if success:
                result.lyrics_found = True
                result.lyrics_line_count = self._lyrics.line_count

                # Get raw lyrics text for AI
                lines = self._lyrics.lines
                lyrics_text = "\n".join(line.text for line in lines)

                result.steps_completed.append("lyrics")
                self._fire_step_complete(PipelineStep.LYRICS, {
                    "found": True,
                    "lines": result.lyrics_line_count
                })

                return lyrics_text
            else:
                self._fire_step_complete(PipelineStep.LYRICS, {"found": False})
                return None

        except Exception as e:
            self._fire_step_complete(PipelineStep.LYRICS, {"error": str(e)})
            return None

    def _step_ai_analysis(
        self,
        result: PipelineResult,
        lyrics_text: str,
        artist: str,
        title: str,
        album: str
    ) -> None:
        """Run AI analysis on lyrics."""
        self._fire_step_start(PipelineStep.AI_ANALYSIS)

        try:
            if self._ai is None:
                from modules.ai_analysis import AIAnalysisModule
                self._ai = AIAnalysisModule()
                self._ai.start()

            result.ai_available = self._ai.is_available

            analysis = self._ai.categorize(lyrics_text, artist, title, album)

            result.mood = analysis.primary_mood
            result.energy = analysis.energy
            result.valence = analysis.valence
            result.categories = analysis.scores

            result.steps_completed.append("ai_analysis")
            self._fire_step_complete(PipelineStep.AI_ANALYSIS, {
                "mood": result.mood,
                "energy": result.energy,
                "valence": result.valence,
                "backend": analysis.backend
            })

        except Exception as e:
            self._fire_step_complete(PipelineStep.AI_ANALYSIS, {"error": str(e)})

    def _step_shader_match(self, result: PipelineResult) -> None:
        """Match shader based on energy/valence."""
        self._fire_step_start(PipelineStep.SHADER_MATCH)

        try:
            if self._shaders is None:
                from modules.shaders import ShadersModule, ShadersConfig
                config = ShadersConfig(shaders_dir=self._config.shaders_dir)
                self._shaders = ShadersModule(config)
                self._shaders.start()

            # Use AI results if available, otherwise defaults
            energy = result.energy if result.energy else 0.5
            valence = result.valence if result.valence else 0.0

            match = self._shaders.find_best_match(
                energy=energy,
                valence=valence,
                require_quality=True
            )

            if match:
                result.shader_matched = True
                result.shader_name = match.name
                result.shader_score = match.score

                result.steps_completed.append("shader_match")
                self._fire_step_complete(PipelineStep.SHADER_MATCH, {
                    "name": match.name,
                    "score": match.score,
                    "mood": match.mood
                })
            else:
                self._fire_step_complete(PipelineStep.SHADER_MATCH, {"matched": False})

        except Exception as e:
            self._fire_step_complete(PipelineStep.SHADER_MATCH, {"error": str(e)})

    def _step_images(
        self,
        result: PipelineResult,
        artist: str,
        title: str,
        album: str
    ) -> None:
        """Fetch images for the song."""
        self._fire_step_start(PipelineStep.IMAGES)

        try:
            if self._images is None:
                from image_scraper import ImageScraper
                self._images = ImageScraper()

            # Build metadata for thematic search
            metadata = {}
            if result.mood:
                metadata['mood'] = result.mood
            if result.categories:
                # Get top themes from categories
                top_cats = sorted(
                    result.categories.items(),
                    key=lambda x: x[1],
                    reverse=True
                )[:3]
                metadata['themes'] = [cat for cat, _ in top_cats]

            # Create track object
            from domain import Track
            track = Track(artist=artist, title=title, album=album)

            img_result = self._images.fetch_images(track, metadata)

            if img_result:
                result.images_found = True
                result.images_folder = str(img_result.folder)
                result.images_count = img_result.total_images

                result.steps_completed.append("images")
                self._fire_step_complete(PipelineStep.IMAGES, {
                    "folder": result.images_folder,
                    "count": result.images_count,
                    "cached": img_result.cached
                })
            else:
                self._fire_step_complete(PipelineStep.IMAGES, {"found": False})

        except Exception as e:
            self._fire_step_complete(PipelineStep.IMAGES, {"error": str(e)})

    def _fire_step_start(self, step: PipelineStep) -> None:
        """Fire step start callback."""
        if self._on_step_start:
            try:
                self._on_step_start(step)
            except Exception:
                pass

    def _fire_step_complete(self, step: PipelineStep, data: Any) -> None:
        """Fire step complete callback."""
        if self._on_step_complete:
            try:
                self._on_step_complete(step, data)
            except Exception:
                pass

    def get_status(self) -> Dict[str, Any]:
        """Get module status."""
        status = super().get_status()

        status["lyrics_ready"] = self._lyrics is not None
        status["ai_ready"] = self._ai is not None
        status["shaders_ready"] = self._shaders is not None
        status["images_ready"] = self._images is not None

        if self._ai:
            status["ai_available"] = self._ai.is_available

        if self._shaders:
            status["shader_count"] = self._shaders.shader_count

        return status


def main():
    """CLI entry point for standalone pipeline module."""
    parser = argparse.ArgumentParser(
        description="Pipeline Module - Process song through lyrics → AI → shaders → images"
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
        "--skip-lyrics",
        action="store_true",
        help="Skip lyrics fetching"
    )
    parser.add_argument(
        "--skip-ai",
        action="store_true",
        help="Skip AI analysis"
    )
    parser.add_argument(
        "--skip-shaders",
        action="store_true",
        help="Skip shader matching"
    )
    parser.add_argument(
        "--skip-images",
        action="store_true",
        help="Skip image fetching"
    )
    parser.add_argument(
        "--quiet", "-q",
        action="store_true",
        help="Minimal output"
    )
    args = parser.parse_args()

    config = PipelineConfig(
        skip_lyrics=args.skip_lyrics,
        skip_ai=args.skip_ai,
        skip_shaders=args.skip_shaders,
        skip_images=args.skip_images
    )

    pipeline = PipelineModule(config)

    if not args.quiet:
        def on_start(step: PipelineStep):
            print(f"  [{step.value}] Starting...")

        def on_complete(step: PipelineStep, data: Any):
            if "error" in data:
                print(f"  [{step.value}] Error: {data['error']}")
            else:
                # Format based on step
                if step == PipelineStep.LYRICS:
                    if data.get("found"):
                        print(f"  [{step.value}] Found {data['lines']} lines")
                    else:
                        print(f"  [{step.value}] No lyrics found")
                elif step == PipelineStep.AI_ANALYSIS:
                    print(f"  [{step.value}] Mood: {data.get('mood')}, "
                          f"Energy: {data.get('energy', 0):.2f}, "
                          f"Valence: {data.get('valence', 0):+.2f}")
                elif step == PipelineStep.SHADER_MATCH:
                    if data.get("name"):
                        print(f"  [{step.value}] Matched: {data['name']} "
                              f"(score: {data.get('score', 0):.3f})")
                    else:
                        print(f"  [{step.value}] No shader matched")
                elif step == PipelineStep.IMAGES:
                    if data.get("count"):
                        cached = " (cached)" if data.get("cached") else ""
                        print(f"  [{step.value}] {data['count']} images{cached}")
                    else:
                        print(f"  [{step.value}] No images found")

        pipeline.on_step_start = on_start
        pipeline.on_step_complete = on_complete

    print(f"\n{'='*60}")
    print(f"Processing: {args.artist} - {args.title}")
    print(f"{'='*60}\n")

    pipeline.start()
    result = pipeline.process(args.artist, args.title, args.album)
    pipeline.stop()

    print(f"\n{'='*60}")
    print("Result Summary")
    print(f"{'='*60}\n")

    print(f"  Success: {result.success}")
    print(f"  Steps completed: {', '.join(result.steps_completed) or 'none'}")
    print(f"  Total time: {result.total_time_ms}ms")
    print()

    if result.lyrics_found:
        print(f"  Lyrics: {result.lyrics_line_count} lines")

    if result.mood:
        print(f"  Mood: {result.mood}")
        print(f"  Energy: {result.energy:.2f}")
        print(f"  Valence: {result.valence:+.2f}")

    if result.shader_matched:
        print(f"  Shader: {result.shader_name}")

    if result.images_found:
        print(f"  Images: {result.images_count} in {result.images_folder}")

    print()


if __name__ == "__main__":
    main()
