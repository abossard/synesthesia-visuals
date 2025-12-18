"""Rendering utilities for VJ Console."""

import time
from typing import Any, Tuple

from .colors import color_by_score, color_by_level, color_by_osc_channel
from .formatting import format_bar


def render_category_line(name: str, score: float) -> str:
    """Render a single category with bar."""
    color = color_by_score(score)
    bar = format_bar(score)
    return f"  [{color}]{name:15s} {bar} {score:.2f}[/]"


def render_osc_message(msg: Tuple[float, str, Any]) -> str:
    """Render a single OSC message with full args (legacy format)."""
    ts, address, args = msg
    time_str = time.strftime("%H:%M:%S", time.localtime(ts))
    args_str = str(args)
    color = color_by_osc_channel(address)
    return f"[dim]{time_str}[/] [{color}]{address}[/] {args_str}"


def render_aggregated_osc(msg) -> str:
    """Render aggregated OSC message: direction, channel, address, value, count."""
    time_str = time.strftime("%H:%M:%S", time.localtime(msg.last_time))

    # Determine direction and channel
    if msg.channel.startswith("→"):
        # Outgoing message
        direction = "[cyan]→[/]"
        ch_name = msg.channel[1:]  # Remove arrow prefix
    else:
        # Incoming message
        direction = "[green]←[/]"
        ch_name = msg.channel

    # Channel-specific colors
    if "vdj" in ch_name.lower():
        ch_label_color = "blue"
    elif "syn" in ch_name.lower():
        ch_label_color = "magenta"
    elif "kar" in ch_name.lower():
        ch_label_color = "yellow"
    else:
        ch_label_color = "white"

    # Format args compactly
    args_str = str(msg.last_args) if msg.last_args else ""
    if len(args_str) > 50:
        args_str = args_str[:47] + "..."

    # Count indicator
    count_str = f" [dim]×{msg.count}[/]" if msg.count > 1 else ""

    color = color_by_osc_channel(msg.address)
    return f"[dim]{time_str}[/] {direction} [{ch_label_color}]{ch_name:>5}[/] [{color}]{msg.address:30s}[/] {args_str}{count_str}"


def render_log_line(log: str) -> str:
    """Render a single log line with color."""
    return f"[{color_by_level(log)}]{log}[/]"
