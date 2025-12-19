"""
Infrastructure Module - Settings, configuration, and process management

Public API:
    Classes:
        Config - Configuration with smart defaults for macOS VJ setups
        Settings - Persistent user settings (JSON-backed)
        ServiceHealth - Track service availability with reconnection
        PipelineTracker - Thread-safe pipeline step tracking for UI
        PipelineStep - Single pipeline step with status
        BackoffState - Exponential backoff state management
        ProcessManager - Manage external processes (Processing apps)
        ProcessingApp - Definition of a Processing application

Usage:
    from infrastructure import Settings, Config, ProcessManager

    settings = Settings()
    print(settings.playback_source)
"""

import sys
from pathlib import Path

_parent = str(Path(__file__).parent.parent)
if _parent not in sys.path:
    sys.path.insert(0, _parent)

from infra import (
    Config,
    Settings,
    ServiceHealth,
    PipelineTracker,
    PipelineStep,
    BackoffState,
)
from process_manager import ProcessManager, ProcessingApp

__all__ = [
    "Config",
    "Settings",
    "ServiceHealth",
    "PipelineTracker",
    "PipelineStep",
    "BackoffState",
    "ProcessManager",
    "ProcessingApp",
]
