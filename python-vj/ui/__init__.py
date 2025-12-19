"""UI components for VJ Console."""

from .messages import (
    OSCClearRequested,
    PlaybackSourceChanged,
    VJUniverseTestRequested,
)

from .modals import ShaderSearchModal

from .panels import (
    ReactivePanel,
    StartupControlPanel,
    OSCControlPanel,
    OSCPanel,
    NowPlayingPanel,
    PlaybackSourcePanel,
    CategoriesPanel,
    PipelinePanel,
    ServicesPanel,
    AppsListPanel,
    LogsPanel,
    MasterControlPanel,
    ShaderIndexPanel,
    ShaderMatchPanel,
    ShaderAnalysisPanel,
    ShaderSearchPanel,
    ShaderActionsPanel,
)

__all__ = [
    # Messages
    "OSCClearRequested",
    "PlaybackSourceChanged",
    "VJUniverseTestRequested",
    # Modals
    "ShaderSearchModal",
    # Panels
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
