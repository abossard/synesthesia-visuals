"""UI panels for VJ Console."""

from .base import ReactivePanel
from .startup import StartupControlPanel
from .osc import OSCControlPanel, OSCPanel
from .playback import NowPlayingPanel, PlaybackSourcePanel
from .categories import CategoriesPanel
from .pipeline import PipelinePanel
from .services import ServicesPanel
from .apps import AppsListPanel
from .logs import LogsPanel
from .master import MasterControlPanel
from .shaders import (
    ShaderIndexPanel,
    ShaderMatchPanel,
    ShaderAnalysisPanel,
    ShaderSearchPanel,
    ShaderActionsPanel,
)

__all__ = [
    "ReactivePanel",
    "StartupControlPanel",
    "OSCControlPanel",
    "OSCPanel",
    "NowPlayingPanel",
    "PlaybackSourcePanel",
    "CategoriesPanel",
    "PipelinePanel",
    "ServicesPanel",
    "AppsListPanel",
    "LogsPanel",
    "MasterControlPanel",
    "ShaderIndexPanel",
    "ShaderMatchPanel",
    "ShaderAnalysisPanel",
    "ShaderSearchPanel",
    "ShaderActionsPanel",
]
