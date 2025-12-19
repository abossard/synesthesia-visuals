"""
Shaders Module - Feature-based shader-to-music matching

Multi-dimensional semantic matching using normalized feature vectors.

Public API:
    Classes:
        ShaderIndexer - Index shaders from disk, caches features in JSON
        ShaderMatcher - Match songs to shaders using feature vectors
        ShaderSelector - High-level interface combining indexing + matching

    Types:
        ShaderFeatures - 6D feature vector for a shader
        SongFeatures - Song metadata with audio features
        ShaderMatch - Result of matching (shader, score, why)
        AudioSource - Enum: bass, mid, high, etc.
        ModulationType - Enum: add, multiply, etc.

    Functions:
        categories_to_song_features() - Convert SongCategories to SongFeatures

Usage:
    from shaders import ShaderIndexer, ShaderSelector, SongFeatures

    indexer = ShaderIndexer()
    indexer.sync()

    selector = ShaderSelector(indexer)
    match = selector.select_for_song(song_features)
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
