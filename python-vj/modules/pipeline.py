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
import json
import logging
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field, asdict
from enum import Enum
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

from domain import sanitize_cache_filename
from infrastructure import Config
from modules.base import Module

logger = logging.getLogger(__name__)


class PipelineStep(Enum):
    """Pipeline processing steps."""
    LYRICS = "lyrics"
    AI_ANALYSIS = "ai_analysis"  # Combined metadata + categorization (single LLM call)
    SHADER_MATCH = "shader_match"
    IMAGES = "images"


@dataclass
class PipelineConfig:
    """Configuration for Pipeline module."""
    skip_lyrics: bool = False
    skip_ai: bool = False  # Controls combined AI analysis (metadata + categorization)
    skip_shaders: bool = False
    skip_images: bool = False
    skip_osc: bool = False
    skip_cache: bool = False  # Disable result caching
    shaders_dir: Optional[str] = None
    parallel: bool = True  # Enable parallel execution of independent steps
    cache_dir: Optional[Path] = None  # Pipeline result cache directory


@dataclass
class PipelineResult:
    """Result from pipeline processing."""
    artist: str
    title: str
    album: str = ""
    success: bool = False
    cached: bool = False  # True if result was loaded from cache

    # Lyrics (from LRC file)
    lyrics_found: bool = False
    lyrics_line_count: int = 0
    lyrics_lines: List[Any] = field(default_factory=list)  # LyricLine objects
    refrain_lines: List[str] = field(default_factory=list)
    lyrics_keywords: List[str] = field(default_factory=list)
    plain_lyrics: str = ""

    # AI Analysis (combined metadata + categorization from single LLM call)
    ai_analyzed: bool = False
    keywords: List[str] = field(default_factory=list)
    themes: List[str] = field(default_factory=list)
    visual_adjectives: List[str] = field(default_factory=list)
    llm_refrain_lines: List[str] = field(default_factory=list)
    tempo: str = ""
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
    steps_skipped: List[str] = field(default_factory=list)
    step_timings: Dict[str, int] = field(default_factory=dict)  # step_name -> ms
    total_time_ms: int = 0

    def to_cache_dict(self) -> Dict[str, Any]:
        """Convert to dict for caching (excludes non-serializable fields)."""
        d = asdict(self)
        # Convert LyricLine objects to dicts
        d['lyrics_lines'] = [
            {'time_sec': l.time_sec, 'text': l.text, 'keywords': getattr(l, 'keywords', '')}
            for l in self.lyrics_lines
        ] if self.lyrics_lines else []
        return d

    @classmethod
    def from_cache_dict(cls, data: Dict[str, Any]) -> 'PipelineResult':
        """Restore from cached dict."""
        # lyrics_lines need special handling - keep as dicts for now
        result = cls(
            artist=data.get('artist', ''),
            title=data.get('title', ''),
            album=data.get('album', ''),
            success=data.get('success', False),
            cached=True,
            lyrics_found=data.get('lyrics_found', False),
            lyrics_line_count=data.get('lyrics_line_count', 0),
            lyrics_lines=[],  # Will be empty for cached results
            refrain_lines=data.get('refrain_lines', []),
            lyrics_keywords=data.get('lyrics_keywords', []),
            plain_lyrics=data.get('plain_lyrics', ''),
            ai_analyzed=data.get('ai_analyzed', False),
            keywords=data.get('keywords', []),
            themes=data.get('themes', []),
            visual_adjectives=data.get('visual_adjectives', []),
            llm_refrain_lines=data.get('llm_refrain_lines', []),
            tempo=data.get('tempo', ''),
            mood=data.get('mood', ''),
            energy=data.get('energy', 0.5),
            valence=data.get('valence', 0.0),
            categories=data.get('categories', {}),
            shader_matched=data.get('shader_matched', False),
            shader_name=data.get('shader_name', ''),
            shader_score=data.get('shader_score', 0.0),
            images_found=data.get('images_found', False),
            images_folder=data.get('images_folder', ''),
            images_count=data.get('images_count', 0),
            steps_completed=data.get('steps_completed', []),
            steps_skipped=data.get('steps_skipped', []),
            step_timings=data.get('step_timings', {}),
            total_time_ms=data.get('total_time_ms', 0),
        )
        return result


@dataclass
class StepInfo:
    """Information about a pipeline step for UI display."""
    name: str
    status: str  # "pending", "running", "completed", "skipped", "error"
    time_ms: int = 0
    message: str = ""
    data: Dict[str, Any] = field(default_factory=dict)


# Callback types
OnStepStart = Callable[[PipelineStep], None]
OnStepComplete = Callable[[PipelineStep, Any], None]
OnPipelineComplete = Callable[[PipelineResult], None]


class PipelineModule(Module):
    """
    Pipeline module orchestrating song processing.

    Steps:
    1. Fetch lyrics (LyricsModule)
    2. AI analysis - combined metadata + categorization (single LLM call)
    3. Match shader (ShadersModule)
    4. Fetch images (ImageScraper)

    Each step is optional and degrades gracefully if unavailable.
    Results are cached per track for instant replay.
    """

    def __init__(self, config: Optional[PipelineConfig] = None):
        super().__init__()
        self._config = config or PipelineConfig()

        # Cache directory
        self._cache_dir = self._config.cache_dir or (Config.APP_DATA_DIR / "pipeline_cache")
        self._cache_dir.mkdir(parents=True, exist_ok=True)

        # Sub-modules (lazy loaded)
        self._lyrics = None
        self._llm = None  # LLMAnalyzer for combined analysis
        self._shaders = None
        self._images = None
        self._osc = None

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

        if self._shaders:
            self._shaders.stop()
            self._shaders = None

        self._llm = None
        self._images = None
        self._osc = None
        self._started = False

    def _get_osc(self):
        """Get OSC sender (lazy loaded)."""
        if self._osc is None and not self._config.skip_osc:
            from adapters import OSCSender
            self._osc = OSCSender()
        return self._osc

    def _get_llm(self):
        """Get LLM analyzer (lazy loaded)."""
        if self._llm is None:
            from ai_services import LLMAnalyzer
            self._llm = LLMAnalyzer()
        return self._llm

    def _get_cache_path(self, artist: str, title: str, album: str = "") -> Path:
        """Get cache file path for a track."""
        cache_key = sanitize_cache_filename(artist, title)
        if album:
            cache_key = f"{cache_key}_{sanitize_cache_filename('', album)}"
        return self._cache_dir / f"{cache_key}.json"

    def _load_cached_result(self, artist: str, title: str, album: str = "") -> Optional[PipelineResult]:
        """Load cached result if available."""
        if self._config.skip_cache:
            return None

        cache_path = self._get_cache_path(artist, title, album)
        if cache_path.exists():
            try:
                data = json.loads(cache_path.read_text())
                result = PipelineResult.from_cache_dict(data)
                logger.info(f"Pipeline cache hit: {artist} - {title}")
                return result
            except Exception as e:
                logger.debug(f"Failed to load cache: {e}")
        return None

    def _save_cached_result(self, result: PipelineResult) -> None:
        """Save result to cache."""
        if self._config.skip_cache:
            return

        try:
            cache_path = self._get_cache_path(result.artist, result.title, result.album)
            data = result.to_cache_dict()
            cache_path.write_text(json.dumps(data, indent=2))
            logger.debug(f"Saved pipeline cache: {cache_path}")
        except Exception as e:
            logger.warning(f"Failed to save cache: {e}")

    def get_all_steps(self) -> List[StepInfo]:
        """Get info about all pipeline steps for UI display."""
        return [
            StepInfo(name=step.value, status="pending")
            for step in PipelineStep
        ]

    def process(
        self,
        artist: str,
        title: str,
        album: str = ""
    ) -> PipelineResult:
        """
        Process a song through the full pipeline.

        Pipeline flow:
        ```
        [cache check] → lyrics → ai_analysis → shader + images (parallel)
        ```

        Args:
            artist: Artist name
            title: Song title
            album: Optional album name

        Returns:
            PipelineResult with all gathered information.
        """
        if not self._started:
            self.start()

        # Check cache first
        cached_result = self._load_cached_result(artist, title, album)
        if cached_result:
            self._send_all_osc(cached_result)
            self._fire_pipeline_complete(cached_result)
            return cached_result

        start_time = time.time()
        result = PipelineResult(artist=artist, title=title, album=album)
        mode = "parallel" if self._config.parallel else "sequential"
        logger.info(f"Pipeline processing ({mode}): {artist} - {title}")

        # Send track info IMMEDIATELY
        self._send_track_osc(result)

        lyrics_text = None

        # ═══════════════════════════════════════════════════════════
        # PHASE 1: Lyrics (required for AI analysis)
        # ═══════════════════════════════════════════════════════════
        if not self._config.skip_lyrics:
            step_start = time.time()
            lyrics_text = self._step_lyrics(result, artist, title, album)
            result.step_timings["lyrics"] = int((time.time() - step_start) * 1000)
            if lyrics_text:
                logger.info(f"  ✓ Lyrics: {result.lyrics_line_count} lines, {len(result.refrain_lines)} refrains [{result.step_timings['lyrics']}ms]")
                self._send_lyrics_osc(result)  # Send immediately when ready
            else:
                logger.info(f"  ✗ Lyrics: not found [{result.step_timings['lyrics']}ms]")
        else:
            result.steps_skipped.append("lyrics")
            logger.info(f"  ○ Lyrics: skipped")

        # ═══════════════════════════════════════════════════════════
        # PHASE 2: AI Analysis (combined metadata + categorization)
        # ═══════════════════════════════════════════════════════════
        if not self._config.skip_ai and lyrics_text:
            step_start = time.time()
            self._step_ai_combined(result, lyrics_text, artist, title, album)
            result.step_timings["ai_analysis"] = int((time.time() - step_start) * 1000)
            if result.ai_analyzed:
                logger.info(f"  ✓ AI Analysis: {result.mood} (E={result.energy:.2f}, V={result.valence:+.2f}), "
                           f"{len(result.keywords)} kw, {len(result.visual_adjectives)} visuals [{result.step_timings['ai_analysis']}ms]")
                self._send_ai_osc(result)  # Send immediately when ready
            else:
                logger.info(f"  ✗ AI Analysis: failed [{result.step_timings['ai_analysis']}ms]")
        else:
            result.steps_skipped.append("ai_analysis")
            logger.info(f"  ○ AI Analysis: skipped")

        # ═══════════════════════════════════════════════════════════
        # PHASE 3: Shader + Images (parallel, each sends OSC when done)
        # ═══════════════════════════════════════════════════════════
        if self._config.parallel:
            self._run_phase3_parallel(result, artist, title, album)
        else:
            self._run_phase3_sequential(result, artist, title, album)

        # Finalize
        result.total_time_ms = int((time.time() - start_time) * 1000)
        result.success = len(result.steps_completed) > 0

        # Save to cache
        self._save_cached_result(result)

        # Log summary
        timing_str = " + ".join(f"{k}:{v}ms" for k, v in result.step_timings.items())
        logger.info(f"Pipeline complete: {result.steps_completed} in {result.total_time_ms}ms ({timing_str})")

        # Fire completion callback
        self._fire_pipeline_complete(result)

        return result

    def _step_ai_combined(
        self,
        result: PipelineResult,
        lyrics_text: str,
        artist: str,
        title: str,
        album: str
    ) -> None:
        """
        Combined AI analysis: metadata + categorization in single LLM call.

        Extracts: keywords, themes, visual_adjectives, mood, energy, valence, categories.
        """
        self._fire_step_start(PipelineStep.AI_ANALYSIS)

        try:
            llm = self._get_llm()
            analysis = llm.analyze_song_complete(lyrics_text, artist, title, album)

            if analysis:
                result.ai_analyzed = True

                # Metadata fields
                result.keywords = analysis.get('keywords', [])
                result.themes = analysis.get('themes', [])
                result.visual_adjectives = analysis.get('visual_adjectives', [])
                result.llm_refrain_lines = analysis.get('refrain_lines', [])
                result.tempo = analysis.get('tempo', '')

                # Categorization fields
                result.mood = analysis.get('mood', '')
                result.energy = analysis.get('energy', 0.5)
                result.valence = analysis.get('valence', 0.0)
                result.categories = analysis.get('categories', {})

                result.steps_completed.append("ai_analysis")
                self._fire_step_complete(PipelineStep.AI_ANALYSIS, {
                    "mood": result.mood,
                    "energy": result.energy,
                    "valence": result.valence,
                    "keywords": len(result.keywords),
                    "visuals": len(result.visual_adjectives),
                    "cached": analysis.get('cached', False)
                })
            else:
                self._fire_step_complete(PipelineStep.AI_ANALYSIS, {"error": "No result"})

        except Exception as e:
            logger.warning(f"AI combined analysis error: {e}")
            self._fire_step_complete(PipelineStep.AI_ANALYSIS, {"error": str(e)})

    def _run_phase3_parallel(self, result: PipelineResult, artist: str, title: str, album: str) -> None:
        """Run shader matching and image fetching in parallel."""
        futures = {}

        with ThreadPoolExecutor(max_workers=2) as executor:
            # Submit shader task
            if not self._config.skip_shaders:
                futures["shader_match"] = executor.submit(
                    self._run_step_timed, "shader_match",
                    lambda: self._step_shader_match(result)
                )
            else:
                result.steps_skipped.append("shader_match")
                logger.info(f"  ○ Shader: skipped")

            # Submit images task
            if not self._config.skip_images:
                futures["images"] = executor.submit(
                    self._run_step_timed, "images",
                    lambda: self._step_images(result, artist, title, album)
                )
            else:
                result.steps_skipped.append("images")
                logger.info(f"  ○ Images: skipped")

            # Wait for completion and log results
            for future in as_completed(futures.values()):
                step_name, time_ms = future.result()
                result.step_timings[step_name] = time_ms
                self._log_step_result(step_name, result, time_ms)

    def _run_phase3_sequential(self, result: PipelineResult, artist: str, title: str, album: str) -> None:
        """Run shader matching and image fetching sequentially."""
        # Shader
        if not self._config.skip_shaders:
            step_start = time.time()
            self._step_shader_match(result)
            result.step_timings["shader_match"] = int((time.time() - step_start) * 1000)
            self._log_step_result("shader_match", result, result.step_timings["shader_match"])
        else:
            result.steps_skipped.append("shader_match")
            logger.info(f"  ○ Shader: skipped")

        # Images
        if not self._config.skip_images:
            step_start = time.time()
            self._step_images(result, artist, title, album)
            result.step_timings["images"] = int((time.time() - step_start) * 1000)
            self._log_step_result("images", result, result.step_timings["images"])
        else:
            result.steps_skipped.append("images")
            logger.info(f"  ○ Images: skipped")

    def _run_step_timed(self, step_name: str, step_func: Callable) -> tuple:
        """Run a step function and return (step_name, time_ms)."""
        step_start = time.time()
        step_func()
        time_ms = int((time.time() - step_start) * 1000)
        return (step_name, time_ms)

    def _log_step_result(self, step_name: str, result: PipelineResult, time_ms: int) -> None:
        """Log the result of a pipeline step."""
        if step_name == "shader_match":
            if result.shader_matched:
                logger.info(f"  ✓ Shader: {result.shader_name} (score={result.shader_score:.2f}) [{time_ms}ms]")
            else:
                logger.info(f"  ✗ Shader: no match [{time_ms}ms]")
        elif step_name == "images":
            if result.images_found:
                logger.info(f"  ✓ Images: {result.images_count} images [{time_ms}ms]")
            else:
                logger.info(f"  ✗ Images: none found [{time_ms}ms]")

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
                valence=valence
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

            # Build rich metadata for thematic search
            metadata = {'album': album}

            # Best source: visual_adjectives from LLM (e.g., "neon", "cosmic", "ethereal")
            if result.visual_adjectives:
                metadata['themes'] = result.visual_adjectives[:5]
            # Fallback: themes from LLM metadata
            elif result.themes:
                metadata['themes'] = result.themes[:5]
            # Last resort: category names from AI analysis
            elif result.categories:
                top_cats = sorted(
                    result.categories.items(),
                    key=lambda x: x[1],
                    reverse=True
                )[:3]
                metadata['themes'] = [cat for cat, _ in top_cats]

            # Add mood for search
            if result.mood:
                metadata['mood'] = result.mood

            # Add keywords from LLM metadata
            if result.keywords:
                metadata['keywords'] = result.keywords[:10]

            # Log what we're passing to image scraper
            logger.debug(f"Image search metadata: themes={metadata.get('themes', [])}, "
                        f"mood={metadata.get('mood', '')}, keywords={len(metadata.get('keywords', []))} kw")

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
    # Unified OSC & Callbacks
    # ─────────────────────────────────────────────────────────────

    def _send_all_osc(self, result: PipelineResult) -> None:
        """Send all OSC messages for a result. Each method handles empty data gracefully."""
        self._send_track_osc(result)
        self._send_lyrics_osc(result)
        self._send_ai_osc(result)
        self._send_shader_osc(result)
        self._send_images_osc(result)

    def _fire_pipeline_complete(self, result: PipelineResult) -> None:
        """Fire pipeline completion callback safely."""
        if self._on_pipeline_complete:
            try:
                self._on_pipeline_complete(result)
            except Exception:
                pass

    # ─────────────────────────────────────────────────────────────
    # Individual OSC Methods (each handles empty data gracefully)
    # ─────────────────────────────────────────────────────────────

    def _send_track_osc(self, result: PipelineResult) -> None:
        """Send track info via OSC."""
        osc = self._get_osc()
        if not osc:
            logger.debug("OSC: skipped (disabled)")
            return

        try:
            osc.send_textler("track", "info", {
                "artist": result.artist,
                "title": result.title,
                "album": result.album,
            })
            logger.info(f"OSC → /textler/track/info: {result.artist} - {result.title}")
        except Exception as e:
            logger.warning(f"OSC track send failed: {e}")

    def _send_lyrics_osc(self, result: PipelineResult) -> None:
        """Send lyrics, refrains, and keywords via OSC."""
        osc = self._get_osc()
        if not osc:
            return

        try:
            # Reset and send all lyrics lines
            osc.send_textler("lyrics", "reset")
            for i, line in enumerate(result.lyrics_lines):
                # Ensure text is ASCII-safe for OSC (replace non-ASCII with ?)
                text = line.text.encode('ascii', 'replace').decode('ascii') if line.text else ""
                keywords = getattr(line, 'keywords', '') or ""
                keywords = keywords.encode('ascii', 'replace').decode('ascii')
                osc.send_textler("lyrics", "line", {
                    "index": i,
                    "time": line.time_sec,
                    "text": text,
                })

            # Reset and send refrain lines (as summary, not individual)
            osc.send_textler("refrain", "reset")
            if result.refrain_lines:
                # Send count and first few lines as joined text
                refrain_text = " | ".join(
                    t.encode('ascii', 'replace').decode('ascii')
                    for t in result.refrain_lines[:5]
                )
                osc.send_textler("refrain", "summary", {
                    "count": len(result.refrain_lines),
                    "text": refrain_text[:200],  # Limit length
                })

            # Reset and send keywords as single message
            osc.send_textler("keywords", "reset")
            if result.lyrics_keywords:
                keywords_text = ",".join(result.lyrics_keywords[:30])
                osc.send_textler("keywords", "summary", {
                    "count": len(result.lyrics_keywords),
                    "text": keywords_text,
                })

            logger.info(f"OSC → /textler/lyrics: {len(result.lyrics_lines)} lines, {len(result.refrain_lines)} refrains, {len(result.lyrics_keywords)} keywords")
        except Exception as e:
            logger.warning(f"OSC lyrics send failed: {e}")

    def _send_ai_osc(self, result: PipelineResult) -> None:
        """Send combined AI analysis via OSC (metadata + categories)."""
        osc = self._get_osc()
        if not osc:
            return

        try:
            # Send keywords as comma-separated string
            if result.keywords:
                keywords_str = ",".join(result.keywords[:20])
                osc.send_textler("metadata", "keywords", {
                    "text": keywords_str,
                    "count": len(result.keywords),
                })

            # Send themes
            if result.themes:
                themes_str = ",".join(result.themes[:10])
                osc.send_textler("metadata", "themes", {
                    "text": themes_str,
                    "count": len(result.themes),
                })

            # Send visual adjectives
            if result.visual_adjectives:
                visuals_str = ",".join(result.visual_adjectives[:15])
                osc.send_textler("metadata", "visuals", {
                    "text": visuals_str,
                    "count": len(result.visual_adjectives),
                })

            # Send tempo
            if result.tempo:
                osc.send_textler("metadata", "tempo", {"text": result.tempo})

            # Send primary mood and scores
            osc.send_textler("categories", "mood", {
                "mood": result.mood,
                "energy": result.energy,
                "valence": result.valence,
            })

            # Send category scores
            for category, score in result.categories.items():
                osc.send_textler("categories", "score", {
                    "category": category,
                    "score": score,
                })

            logger.info(f"OSC → /textler/ai: {result.mood} (E={result.energy:.2f}, V={result.valence:+.2f}), "
                       f"{len(result.keywords)} kw, {len(result.visual_adjectives)} visuals")
        except Exception as e:
            logger.warning(f"OSC AI send failed: {e}")

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
            logger.info(f"OSC → /shader/load: {result.shader_name}")
        except Exception as e:
            logger.warning(f"OSC shader send failed: {e}")

    def _send_images_osc(self, result: PipelineResult) -> None:
        """Send image folder path via OSC."""
        osc = self._get_osc()
        if not osc:
            return

        try:
            osc.send_image_folder(result.images_folder)
            logger.info(f"OSC → /image/folder: {result.images_folder}")
        except Exception as e:
            logger.warning(f"OSC images send failed: {e}")

    def get_status(self) -> Dict[str, Any]:
        """Get module status."""
        status = super().get_status()

        status["lyrics_ready"] = self._lyrics is not None
        status["llm_ready"] = self._llm is not None
        status["shaders_ready"] = self._shaders is not None
        status["images_ready"] = self._images is not None

        if self._llm:
            status["llm_available"] = self._llm.is_available

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
        help="Skip AI analysis (combined metadata + categorization)"
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
                elif step == PipelineStep.AI_ANALYSIS:
                    mood = data.get('mood', '')
                    if mood:
                        print(f"  [{step.value}] {mood}, "
                              f"E={data.get('energy', 0):.2f}, V={data.get('valence', 0):+.2f}, "
                              f"{data.get('keywords', 0)} kw, {data.get('visuals', 0)} visuals")
                    else:
                        print(f"  [{step.value}] Failed")
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
