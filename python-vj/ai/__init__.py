"""
AI Module - LLM and image generation services

Handles:
- LLM analysis (local LM Studio, OpenAI)
- Song categorization
- ComfyUI image generation
- Text embeddings

Usage:
    from ai import LLMAnalyzer, SongCategorizer

    analyzer = LLMAnalyzer()
    result = await analyzer.analyze_song("Artist", "Title")

NOTE: Content is re-exported from ai_services.py for now.
      Will be migrated to submodules incrementally.
"""

# Re-export from original location
import sys
from pathlib import Path

_parent = str(Path(__file__).parent.parent)
if _parent not in sys.path:
    sys.path.insert(0, _parent)

from ai_services import (
    LLMAnalyzer,
    SongCategorizer,
)

# Also available in karaoke_engine for backwards compat
try:
    from karaoke_engine import ComfyUIGenerator
except ImportError:
    ComfyUIGenerator = None

__all__ = [
    "LLMAnalyzer",
    "SongCategorizer",
    "ComfyUIGenerator",
]
