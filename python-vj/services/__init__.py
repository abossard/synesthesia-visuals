"""Services for VJ Console - Deep modules with simple interfaces."""

# Core VJ services (NEW - deep modules)
from .playback import PlaybackService, Playback
from .lyrics import LyricsService, LyricLine, SongMetadata
from .output import OutputService
from .controller import VJController

# Background workers (existing)
from .process_monitor import ProcessMonitor, ProcessStats
from .shader_analysis import ShaderAnalysisWorker

__all__ = [
    # Core VJ (NEW)
    "PlaybackService",
    "Playback",
    "LyricsService", 
    "LyricLine",
    "SongMetadata",
    "OutputService",
    "VJController",
    # Background workers
    "ProcessMonitor",
    "ProcessStats",
    "ShaderAnalysisWorker",
]
