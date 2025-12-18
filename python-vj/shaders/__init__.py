"""
Shaders Module - Feature-based shader-to-music matching

Multi-dimensional semantic matching using normalized feature vectors.
Features: energy_score, mood_valence, color_warmth, motion_speed, geometric_score, visual_density

Usage:
    from shaders import ShaderIndexer, ShaderSelector, SongFeatures

    indexer = ShaderIndexer()
    indexer.sync()

    selector = ShaderSelector(indexer)
    match = selector.select_for_song(song_features)

NOTE: Content is re-exported from shader_matcher.py for now.
      Will be migrated to submodules incrementally.
"""

# Import from original location and re-export
# This allows `from shaders import X` while keeping the original file working
import sys
from pathlib import Path

# Ensure parent is in path for import
_parent = str(Path(__file__).parent.parent)
if _parent not in sys.path:
    sys.path.insert(0, _parent)

# Import everything from the original module
from shader_matcher import (
    # Types
    ShaderInputs,
    AudioSource,
    ModulationType,
    UniformAudioBinding,
    AudioReactiveProfile,
    ShaderFeatures,
    SongFeatures,
    ShaderMatch,
    # Utilities
    categories_to_song_features,
    # Classes
    ShaderMatcher,
    ShaderIndexer,
    ShaderSelector,
)

__all__ = [
    # Types
    "ShaderInputs",
    "AudioSource",
    "ModulationType",
    "UniformAudioBinding",
    "AudioReactiveProfile",
    "ShaderFeatures",
    "SongFeatures",
    "ShaderMatch",
    # Utilities
    "categories_to_song_features",
    # Classes
    "ShaderMatcher",
    "ShaderIndexer",
    "ShaderSelector",
]
