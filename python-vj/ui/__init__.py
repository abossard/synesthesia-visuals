"""UI components for VJ Console."""

from .messages import (
    OSCStartRequested,
    OSCStopRequested,
    OSCChannelStartRequested,
    OSCChannelStopRequested,
    OSCClearRequested,
    PlaybackSourceChanged,
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
    "OSCStartRequested",
    "OSCStopRequested",
    "OSCChannelStartRequested",
    "OSCChannelStopRequested",
    "OSCClearRequested",
    "PlaybackSourceChanged",
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
