"""Data builders for VJ Console panels."""

import time
from typing import Dict, Any

from domain_types import PlaybackSnapshot, PlaybackState
from karaoke_engine import KaraokeEngine, get_active_line_index


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


def build_pipeline_data(engine: KaraokeEngine, snapshot: PlaybackSnapshot) -> Dict[str, Any]:
    """Assemble pipeline panel payload."""
    pipeline_data = {
        'display_lines': engine.pipeline.get_display_lines(),
        'image_prompt': engine.pipeline.image_prompt,
        'error': snapshot.error,
        'backoff': snapshot.backoff_seconds,
    }
    lines = engine.current_lines
    state = snapshot.state
    if lines and state.track:
        offset_ms = engine.timing_offset_ms
        position = estimate_position(state)
        idx = get_active_line_index(lines, position + offset_ms / 1000.0)
        if 0 <= idx < len(lines):
            line = lines[idx]
            pipeline_data['current_lyric'] = {
                'text': line.text,
                'keywords': line.keywords,
                'is_refrain': line.is_refrain
            }
    analysis = engine.last_llm_result or {}
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
