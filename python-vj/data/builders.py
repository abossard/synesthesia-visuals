"""Data builders for VJ Console panels."""

import time
from typing import Dict, Any, Optional, Protocol, List, runtime_checkable

from domain_types import PlaybackSnapshot, PlaybackState


@runtime_checkable
class HasPipeline(Protocol):
    """Protocol for objects with pipeline data."""
    @property
    def pipeline(self) -> Any: ...
    @property
    def current_lines(self) -> Optional[List]: ...
    @property
    def timing_offset_ms(self) -> int: ...
    @property
    def last_llm_result(self) -> Optional[Dict]: ...


def get_active_line_index(lines: List, position: float) -> int:
    """Find active line index for position."""
    if not lines or position < 0:
        return -1
    active = -1
    for i, line in enumerate(lines):
        if hasattr(line, 'time_sec') and line.time_sec <= position:
            active = i
        else:
            break
    return active


def estimate_position(state: PlaybackState) -> float:
    """Estimate real-time playback position from cached state."""
    if not state.is_playing:
        return state.position
    return state.position + max(0.0, time.time() - state.last_update)


def build_track_data(snapshot: PlaybackSnapshot, source_available: bool) -> Dict[str, Any]:
    """Derive track panel data from snapshot."""
    state = snapshot.state
    track = state.track
    base = {
        'error': snapshot.error,
        'backoff': snapshot.backoff_seconds,
        'source': snapshot.source,
        'connected': source_available,
    }
    if not track:
        return base
    return {
        **base,
        'artist': track.artist,
        'title': track.title,
        'duration': track.duration,
        'position': estimate_position(state),
    }


def build_pipeline_data(engine: Any, snapshot: PlaybackSnapshot) -> Dict[str, Any]:
    """
    Assemble pipeline panel payload.
    
    Works with both TextlerEngine (legacy) and VJController (new).
    """
    pipeline_data = {
        'display_lines': [],
        'error': snapshot.error,
        'backoff': getattr(snapshot, 'backoff_seconds', 0.0),
    }
    
    # Try to get pipeline display lines (TextlerEngine has this)
    if hasattr(engine, 'pipeline') and engine.pipeline:
        pipeline_data['display_lines'] = engine.pipeline.get_display_lines()
    
    # Get current lines (works with both engines)
    lines = None
    if hasattr(engine, 'current_lines'):
        lines = engine.current_lines
    elif hasattr(engine, 'lyrics') and hasattr(engine.lyrics, 'lines'):
        lines = engine.lyrics.lines
    
    state = snapshot.state
    if lines and state.track:
        offset_ms = getattr(engine, 'timing_offset_ms', 0)
        position = estimate_position(state)
        idx = get_active_line_index(lines, position + offset_ms / 1000.0)
        if 0 <= idx < len(lines):
            line = lines[idx]
            pipeline_data['current_lyric'] = {
                'text': getattr(line, 'text', ''),
                'keywords': getattr(line, 'keywords', ''),
                'is_refrain': getattr(line, 'is_refrain', False)
            }
    
    # Get LLM analysis (TextlerEngine has this, VJController doesn't yet)
    analysis = getattr(engine, 'last_llm_result', None) or {}
    if analysis:
        pipeline_data['analysis_summary'] = {
            'summary': analysis.get('summary') or analysis.get('lyric_summary') or analysis.get('mood'),
            'keywords': [str(k) for k in (analysis.get('keywords') or []) if str(k).strip()][:8],
            'themes': [str(t) for t in (analysis.get('themes') or []) if str(t).strip()][:4],
            'refrain_lines': [str(r) for r in (analysis.get('refrain_lines') or []) if str(r).strip()][:3],
            'visuals': [str(v) for v in (analysis.get('visual_adjectives') or []) if str(v).strip()][:5],
            'tempo': analysis.get('tempo'),
            'emotions': [str(e) for e in (analysis.get('emotions') or []) if str(e).strip()][:3]
        }
    return pipeline_data


def build_categories_payload(categories) -> Dict[str, Any]:
    """Format categories for UI panels."""
    if not categories:
        return {}
    return {
        'primary_mood': categories.primary_mood,
        'categories': [
            {'name': cat.name, 'score': cat.score}
            for cat in categories.get_top(10)
        ]
    }
