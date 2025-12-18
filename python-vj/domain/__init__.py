"""
Domain Module - Core domain types

Pure data types with no external dependencies.

Usage:
    from domain import PlaybackSnapshot, PlaybackState
"""

import sys
from pathlib import Path

_parent = str(Path(__file__).parent.parent)
if _parent not in sys.path:
    sys.path.insert(0, _parent)

from domain_types import (
    PlaybackSnapshot,
    PlaybackState,
)

__all__ = [
    "PlaybackSnapshot",
    "PlaybackState",
]
