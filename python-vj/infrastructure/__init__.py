"""
Infrastructure Module - Settings and external process management

Handles:
- Persistent settings
- Process management (Processing apps)
- External service coordination

Usage:
    from infrastructure import Settings, ProcessManager
"""

import sys
from pathlib import Path

_parent = str(Path(__file__).parent.parent)
if _parent not in sys.path:
    sys.path.insert(0, _parent)

from infra import Settings
from process_manager import ProcessManager, ProcessingApp

__all__ = [
    "Settings",
    "ProcessManager",
    "ProcessingApp",
]
