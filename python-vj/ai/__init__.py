"""
AI Module - LLM and image generation services

Handles LLM analysis, song categorization, and image generation.

Public API:
    Classes:
        LLMAnalyzer - Analyze songs using LLM (local LM Studio or OpenAI)
        SongCategorizer - Categorize songs by genre, mood, era, etc.
        ComfyUIGenerator - Generate images via ComfyUI

Usage:
    from ai import LLMAnalyzer, SongCategorizer

    analyzer = LLMAnalyzer()
    result = await analyzer.analyze_song("Artist", "Title")
"""

import sys
from pathlib import Path

_parent = str(Path(__file__).parent.parent)
if _parent not in sys.path:
    sys.path.insert(0, _parent)

from ai_services import (
    LLMAnalyzer,
    SongCategorizer,
)

try:
    from karaoke_engine import ComfyUIGenerator
except ImportError:
    ComfyUIGenerator = None

__all__ = [
    "LLMAnalyzer",
    "SongCategorizer",
    "ComfyUIGenerator",
]
