"""Utility functions for VJ Console."""

from .formatting import (
    format_time,
    format_duration,
    format_status_icon,
    format_bar,
    truncate,
)

from .colors import (
    color_by_score,
    color_by_level,
    color_by_osc_channel,
)

from .rendering import (
    render_category_line,
    render_osc_message,
    render_aggregated_osc,
    render_log_line,
)

__all__ = [
    "format_time",
    "format_duration",
    "format_status_icon",
    "format_bar",
    "truncate",
    "color_by_score",
    "color_by_level",
    "color_by_osc_channel",
    "render_category_line",
    "render_osc_message",
    "render_aggregated_osc",
    "render_log_line",
]
