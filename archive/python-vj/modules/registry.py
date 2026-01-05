"""
Module Registry - Lifecycle management for all modules.

Provides centralized control over module lifecycle:
- Start all modules in correct order
- Stop all modules on shutdown
- Get status of all modules
- Wire callbacks between modules

Usage:
    from modules.registry import ModuleRegistry

    registry = ModuleRegistry()
    registry.start_all()

    # Access individual modules
    if registry.playback.is_started:
        track = registry.playback.current_track

    # Wire callbacks
    registry.playback.on_track_change = handle_track_change

    registry.stop_all()
"""
import logging
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional

from modules.base import Module

logger = logging.getLogger(__name__)


@dataclass
class ModuleRegistryConfig:
    """Configuration for module registry."""
    # OSC
    osc_receive_port: int = 9999
    osc_vdj_port: int = 9009

    # Playback
    playback_source: str = "vdj_osc"

    # Shaders
    shaders_dir: Optional[str] = None

    # Pipeline
    skip_ai: bool = False
    skip_shaders: bool = False
    skip_images: bool = False


class ModuleRegistry:
    """
    Central registry for all VJ Console modules.

    Manages lifecycle of:
    - OSC Runtime (communication)
    - Playback (track detection)
    - Lyrics (lyric fetching/sync)
    - AI Analysis (song categorization)
    - Shaders (shader matching)
    - Pipeline (orchestration)
    """

    def __init__(self, config: Optional[ModuleRegistryConfig] = None):
        self._config = config or ModuleRegistryConfig()
        self._modules: Dict[str, Module] = {}
        self._started = False

        # Lazy-loaded modules
        self._osc: Optional[Any] = None
        self._playback: Optional[Any] = None
        self._lyrics: Optional[Any] = None
        self._ai: Optional[Any] = None
        self._shaders: Optional[Any] = None
        self._pipeline: Optional[Any] = None

    @property
    def is_started(self) -> bool:
        return self._started

    @property
    def osc(self):
        """Get OSC Runtime module (lazy load)."""
        if self._osc is None:
            from modules.osc_runtime import OSCRuntime, OSCConfig
            config = OSCConfig(
                receive_port=self._config.osc_receive_port,
                vdj_port=self._config.osc_vdj_port,
            )
            self._osc = OSCRuntime(config)
            self._modules["osc"] = self._osc
        return self._osc

    @property
    def playback(self):
        """Get Playback module (lazy load)."""
        if self._playback is None:
            from modules.playback import PlaybackModule, PlaybackConfig
            config = PlaybackConfig(default_source=self._config.playback_source)
            self._playback = PlaybackModule(config)
            self._modules["playback"] = self._playback
        return self._playback

    @property
    def lyrics(self):
        """Get Lyrics module (lazy load)."""
        if self._lyrics is None:
            from modules.lyrics import LyricsModule
            self._lyrics = LyricsModule()
            self._modules["lyrics"] = self._lyrics
        return self._lyrics

    @property
    def ai(self):
        """Get AI Analysis module (lazy load)."""
        if self._ai is None:
            from modules.ai_analysis import AIAnalysisModule
            self._ai = AIAnalysisModule()
            self._modules["ai"] = self._ai
        return self._ai

    @property
    def shaders(self):
        """Get Shaders module (lazy load)."""
        if self._shaders is None:
            from modules.shaders import ShadersModule, ShadersConfig
            config = ShadersConfig(shaders_dir=self._config.shaders_dir)
            self._shaders = ShadersModule(config)
            self._modules["shaders"] = self._shaders
        return self._shaders

    @property
    def pipeline(self):
        """Get Pipeline module (lazy load)."""
        if self._pipeline is None:
            from modules.pipeline import PipelineModule, PipelineConfig
            config = PipelineConfig(
                skip_ai=self._config.skip_ai,
                skip_shaders=self._config.skip_shaders,
                skip_images=self._config.skip_images,
                shaders_dir=self._config.shaders_dir,
            )
            self._pipeline = PipelineModule(config)
            self._modules["pipeline"] = self._pipeline
        return self._pipeline

    def start_all(self) -> bool:
        """
        Start all modules in correct order.

        Order:
        1. OSC (communication layer)
        2. Playback (track detection)
        3. Others on-demand (lyrics, ai, shaders, pipeline)

        Returns True if core modules started successfully.
        """
        if self._started:
            return True

        success = True

        # 1. Start OSC first (required for playback)
        logger.info("Starting OSC module...")
        if not self.osc.start():
            logger.error("OSC module failed to start")
            success = False

        # 2. Start Playback
        logger.info("Starting Playback module...")
        if not self.playback.start():
            logger.warning("Playback module failed to start")
            # Continue anyway - playback can retry

        # Other modules are started on-demand by pipeline
        self._started = True
        logger.info(f"Module registry started (success={success})")

        return success

    def stop_all(self) -> None:
        """Stop all modules in reverse order."""
        if not self._started:
            return

        logger.info("Stopping all modules...")

        # Stop in reverse order of importance
        for name in ["pipeline", "shaders", "ai", "lyrics", "playback", "osc"]:
            module = self._modules.get(name)
            if module and module.is_started:
                try:
                    logger.info(f"Stopping {name} module...")
                    module.stop()
                except Exception as e:
                    logger.warning(f"Error stopping {name}: {e}")

        self._started = False
        logger.info("All modules stopped")

    def get_status(self) -> Dict[str, Any]:
        """Get status of all modules."""
        status = {
            "started": self._started,
            "modules": {}
        }

        for name, module in self._modules.items():
            try:
                status["modules"][name] = module.get_status()
            except Exception as e:
                status["modules"][name] = {"error": str(e)}

        return status

    def process_track(
        self,
        artist: str,
        title: str,
        album: str = ""
    ):
        """
        Process a track through the pipeline.

        Convenience method that runs the full pipeline.
        """
        return self.pipeline.process(artist, title, album)

    def set_playback_source(self, source: str) -> None:
        """Change playback source."""
        if self._playback and self._playback.is_started:
            self._playback.set_source(source)
        self._config.playback_source = source

    def wire_track_to_pipeline(
        self,
        on_pipeline_complete: Optional[Callable] = None
    ) -> None:
        """
        Wire playback track changes to pipeline processing.

        When a new track is detected, automatically run the pipeline.
        """
        def on_track_change(track):
            if track:
                logger.info(f"Track changed: {track.artist} - {track.title}")
                result = self.pipeline.process(track.artist, track.title, track.album)
                if on_pipeline_complete:
                    on_pipeline_complete(result)

        self.playback.on_track_change = on_track_change
