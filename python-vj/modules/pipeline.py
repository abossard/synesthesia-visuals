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
import logging
import sys
import time
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

from modules.base import Module

logger = logging.getLogger(__name__)


class PipelineStep(Enum):
    """Pipeline processing steps."""
    LYRICS = "lyrics"
    METADATA = "metadata"
    AI_ANALYSIS = "ai_analysis"
    SHADER_MATCH = "shader_match"
    IMAGES = "images"


@dataclass
class PipelineConfig:
    """Configuration for Pipeline module."""
    skip_lyrics: bool = False
    skip_metadata: bool = False
    skip_ai: bool = False
    skip_shaders: bool = False
    skip_images: bool = False
    skip_osc: bool = False
    shaders_dir: Optional[str] = None


@dataclass
class PipelineResult:
    """Result from pipeline processing."""
    artist: str
    title: str
    album: str = ""
    success: bool = False

    # Lyrics
    lyrics_found: bool = False
    lyrics_line_count: int = 0
    lyrics_lines: List[Any] = field(default_factory=list)  # LyricLine objects
    refrain_lines: List[str] = field(default_factory=list)
    lyrics_keywords: List[str] = field(default_factory=list)

    # Metadata (from LLM)
    metadata_found: bool = False
    plain_lyrics: str = ""
    keywords: List[str] = field(default_factory=list)
    themes: List[str] = field(default_factory=list)
    release_date: str = ""
    genre: str = ""
    visual_adjectives: List[str] = field(default_factory=list)
    tempo: str = ""
    llm_refrain_lines: List[str] = field(default_factory=list)  # From LLM analysis

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
        self._osc = None
        self._lyrics_fetcher = None

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
        self._osc = None
        self._lyrics_fetcher = None
        self._started = False

    def _get_osc(self):
        """Get OSC sender (lazy loaded)."""
        if self._osc is None and not self._config.skip_osc:
            from adapters import OSCSender
            self._osc = OSCSender()
        return self._osc

    def _get_lyrics_fetcher(self):
        """Get lyrics fetcher for metadata (lazy loaded)."""
        if self._lyrics_fetcher is None:
            from adapters import LyricsFetcher
            self._lyrics_fetcher = LyricsFetcher()
        return self._lyrics_fetcher

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
        result = PipelineResult(artist=artist, title=title, album=album)
        logger.info(f"Pipeline processing: {artist} - {title}")

        lyrics_text = None

        # Send track info via OSC
        self._send_track_osc(result)

        # Step 1: Fetch lyrics (includes refrain + keyword detection)
        if not self._config.skip_lyrics:
            lyrics_text = self._step_lyrics(result, artist, title, album)
            if lyrics_text:
                logger.info(f"  ✓ Lyrics: {result.lyrics_line_count} lines, {len(result.refrain_lines)} refrains, {len(result.lyrics_keywords)} keywords")
                # Send lyrics via OSC
                self._send_lyrics_osc(result)
            else:
                logger.info(f"  ✗ Lyrics: not found")
        else:
            logger.info(f"  ○ Lyrics: skipped")

        # Step 2: Fetch metadata via LLM (keywords, themes, visual adjectives)
        if not self._config.skip_metadata:
            self._step_metadata(result, artist, title)
            if result.metadata_found:
                logger.info(f"  ✓ Metadata: {len(result.keywords)} keywords, {len(result.themes)} themes, {len(result.visual_adjectives)} visuals")
                # Send metadata via OSC
                self._send_metadata_osc(result)
            else:
                logger.info(f"  ✗ Metadata: LLM unavailable")
        else:
            logger.info(f"  ○ Metadata: skipped")

        # Step 3: AI Analysis (categorization)
        if not self._config.skip_ai:
            text_for_analysis = lyrics_text or result.plain_lyrics
            if text_for_analysis:
                self._step_ai_analysis(result, text_for_analysis, artist, title, album)
                if result.mood:
                    logger.info(f"  ✓ AI Analysis: {result.mood} (energy={result.energy:.2f}, valence={result.valence:+.2f})")
                    # Send categories via OSC
                    self._send_categories_osc(result)
                else:
                    logger.info(f"  ✗ AI Analysis: no result")
            else:
                logger.info(f"  ○ AI Analysis: skipped (no lyrics)")
        else:
            logger.info(f"  ○ AI Analysis: skipped")

        # Step 4: Shader matching
        if not self._config.skip_shaders:
            self._step_shader_match(result)
            if result.shader_matched:
                logger.info(f"  ✓ Shader: {result.shader_name} (score={result.shader_score:.3f})")
                # Send shader via OSC
                self._send_shader_osc(result)
            else:
                logger.info(f"  ✗ Shader: no match found")
        else:
            logger.info(f"  ○ Shader: skipped")

        # Step 5: Fetch images
        if not self._config.skip_images:
            self._step_images(result, artist, title, album)
            if result.images_found:
                logger.info(f"  ✓ Images: {result.images_count} images in {result.images_folder}")
                # Send image folder via OSC
                self._send_images_osc(result)
            else:
                logger.info(f"  ✗ Images: not found")
        else:
            logger.info(f"  ○ Images: skipped")

        # Finalize
        result.total_time_ms = int((time.time() - start_time) * 1000)
        result.success = len(result.steps_completed) > 0
        logger.info(f"Pipeline complete in {result.total_time_ms}ms: {result.steps_completed}")

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
        """Fetch lyrics with refrain detection and keyword extraction."""
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

                # Get lines and store them
                lines = self._lyrics.lines
                result.lyrics_lines = list(lines)

                # Get raw lyrics text for AI
                lyrics_text = "\n".join(line.text for line in lines)

                # Extract refrain lines
                refrain_info = self._lyrics.get_refrain_lines()
                result.refrain_lines = [info.text for info in refrain_info]

                # Extract all keywords from lyrics
                all_keywords = set()
                for line in lines:
                    if line.keywords:
                        for kw in line.keywords.split():
                            if kw.strip():
                                all_keywords.add(kw.strip())
                result.lyrics_keywords = sorted(all_keywords)

                result.steps_completed.append("lyrics")
                self._fire_step_complete(PipelineStep.LYRICS, {
                    "found": True,
                    "lines": result.lyrics_line_count,
                    "refrains": len(result.refrain_lines),
                    "keywords": len(result.lyrics_keywords)
                })

                return lyrics_text
            else:
                self._fire_step_complete(PipelineStep.LYRICS, {"found": False})
                return None

        except Exception as e:
            self._fire_step_complete(PipelineStep.LYRICS, {"error": str(e)})
            return None

    def _step_metadata(
        self,
        result: PipelineResult,
        artist: str,
        title: str
    ) -> None:
        """Fetch metadata via LLM (keywords, themes, visual adjectives, etc.)."""
        self._fire_step_start(PipelineStep.METADATA)

        try:
            fetcher = self._get_lyrics_fetcher()
            metadata = fetcher.fetch_metadata(artist, title)

            if metadata:
                result.metadata_found = True

                # Basic info
                result.plain_lyrics = metadata.get('plain_lyrics', '')
                result.release_date = str(metadata.get('release_date', ''))
                genre = metadata.get('genre', '')
                result.genre = genre if isinstance(genre, str) else (genre[0] if genre else '')

                # Keywords/themes from LLM
                kw = metadata.get('keywords', [])
                result.keywords = kw if isinstance(kw, list) else []
                themes = metadata.get('themes', [])
                result.themes = themes if isinstance(themes, list) else []

                # Analysis from LLM (refrain_lines, visual_adjectives, tempo)
                analysis = metadata.get('analysis', {})
                if analysis:
                    result.llm_refrain_lines = analysis.get('refrain_lines', [])
                    result.visual_adjectives = analysis.get('visual_adjectives', [])
                    result.tempo = analysis.get('tempo', '')

                result.steps_completed.append("metadata")
                self._fire_step_complete(PipelineStep.METADATA, {
                    "found": True,
                    "keywords": len(result.keywords),
                    "themes": len(result.themes),
                    "visuals": len(result.visual_adjectives)
                })
            else:
                self._fire_step_complete(PipelineStep.METADATA, {"found": False})

        except Exception as e:
            self._fire_step_complete(PipelineStep.METADATA, {"error": str(e)})

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

    # ─────────────────────────────────────────────────────────────
    # OSC Sending Methods
    # ─────────────────────────────────────────────────────────────

    def _send_track_osc(self, result: PipelineResult) -> None:
        """Send track info via OSC."""
        osc = self._get_osc()
        if not osc:
            return

        try:
            osc.send_textler("track", "info", {
                "artist": result.artist,
                "title": result.title,
                "album": result.album,
            })
            logger.debug(f"OSC: sent track info for {result.artist} - {result.title}")
        except Exception as e:
            logger.debug(f"OSC track send failed: {e}")

    def _send_lyrics_osc(self, result: PipelineResult) -> None:
        """Send lyrics, refrains, and keywords via OSC."""
        osc = self._get_osc()
        if not osc:
            return

        try:
            # Reset and send all lyrics lines
            osc.send_textler("lyrics", "reset")
            for line in result.lyrics_lines:
                osc.send_textler("lyrics", "line", {
                    "time": line.time_sec,
                    "text": line.text,
                    "is_refrain": getattr(line, 'is_refrain', False),
                    "keywords": getattr(line, 'keywords', ''),
                })

            # Reset and send refrain lines
            osc.send_textler("refrain", "reset")
            for text in result.refrain_lines:
                osc.send_textler("refrain", "line", {"text": text})

            # Reset and send keywords
            osc.send_textler("keywords", "reset")
            for kw in result.lyrics_keywords:
                osc.send_textler("keywords", "keyword", {"text": kw})

            logger.debug(f"OSC: sent {len(result.lyrics_lines)} lyrics, {len(result.refrain_lines)} refrains, {len(result.lyrics_keywords)} keywords")
        except Exception as e:
            logger.debug(f"OSC lyrics send failed: {e}")

    def _send_metadata_osc(self, result: PipelineResult) -> None:
        """Send metadata via OSC (keywords, themes, visual adjectives)."""
        osc = self._get_osc()
        if not osc:
            return

        try:
            # Send keywords as comma-separated string (OSC can't handle lists)
            keywords_str = ",".join(result.keywords[:20])
            osc.send_textler("metadata", "keywords", {
                "text": keywords_str,
                "count": len(result.keywords),
            })

            # Send themes as comma-separated string
            themes_str = ",".join(result.themes[:10])
            osc.send_textler("metadata", "themes", {
                "text": themes_str,
                "count": len(result.themes),
            })

            # Send visual adjectives as comma-separated string
            visuals_str = ",".join(result.visual_adjectives[:15])
            osc.send_textler("metadata", "visuals", {
                "text": visuals_str,
                "count": len(result.visual_adjectives),
            })

            # Send refrain lines from LLM as newline-separated string
            if result.llm_refrain_lines:
                refrains_str = " | ".join(result.llm_refrain_lines[:5])
                osc.send_textler("metadata", "refrains", {
                    "text": refrains_str,
                    "count": len(result.llm_refrain_lines),
                })

            # Send tempo
            if result.tempo:
                osc.send_textler("metadata", "tempo", {
                    "text": result.tempo,
                })

            logger.debug(f"OSC: sent metadata - {len(result.keywords)} kw, {len(result.themes)} themes, {len(result.visual_adjectives)} visuals")
        except Exception as e:
            logger.debug(f"OSC metadata send failed: {e}")

    def _send_categories_osc(self, result: PipelineResult) -> None:
        """Send AI categories via OSC."""
        osc = self._get_osc()
        if not osc:
            return

        try:
            # Send primary mood
            osc.send_textler("categories", "mood", {
                "mood": result.mood,
                "energy": result.energy,
                "valence": result.valence,
            })

            # Send all category scores
            for category, score in result.categories.items():
                osc.send_textler("categories", "score", {
                    "category": category,
                    "score": score,
                })

            logger.debug(f"OSC: sent categories - mood={result.mood}, {len(result.categories)} categories")
        except Exception as e:
            logger.debug(f"OSC categories send failed: {e}")

    def _send_shader_osc(self, result: PipelineResult) -> None:
        """Send shader load command via OSC."""
        osc = self._get_osc()
        if not osc:
            return

        try:
            osc.send_shader(
                shader_name=result.shader_name,
                energy=result.energy,
                valence=result.valence
            )
            logger.debug(f"OSC: sent shader load - {result.shader_name}")
        except Exception as e:
            logger.debug(f"OSC shader send failed: {e}")

    def _send_images_osc(self, result: PipelineResult) -> None:
        """Send image folder path via OSC."""
        osc = self._get_osc()
        if not osc:
            return

        try:
            osc.send_image_folder(result.images_folder)
            logger.debug(f"OSC: sent image folder - {result.images_folder}")
        except Exception as e:
            logger.debug(f"OSC images send failed: {e}")

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
        "--skip-metadata",
        action="store_true",
        help="Skip LLM metadata fetching"
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
        "--skip-osc",
        action="store_true",
        help="Skip OSC message sending"
    )
    parser.add_argument(
        "--quiet", "-q",
        action="store_true",
        help="Minimal output"
    )
    args = parser.parse_args()

    config = PipelineConfig(
        skip_lyrics=args.skip_lyrics,
        skip_metadata=args.skip_metadata,
        skip_ai=args.skip_ai,
        skip_shaders=args.skip_shaders,
        skip_images=args.skip_images,
        skip_osc=args.skip_osc
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
                        extra = f", {data.get('refrains', 0)} refrains, {data.get('keywords', 0)} keywords"
                        print(f"  [{step.value}] Found {data['lines']} lines{extra}")
                    else:
                        print(f"  [{step.value}] No lyrics found")
                elif step == PipelineStep.METADATA:
                    if data.get("found"):
                        print(f"  [{step.value}] {data.get('keywords', 0)} keywords, "
                              f"{data.get('themes', 0)} themes, "
                              f"{data.get('visuals', 0)} visuals")
                    else:
                        print(f"  [{step.value}] LLM unavailable")
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
