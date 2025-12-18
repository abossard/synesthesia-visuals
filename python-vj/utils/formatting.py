"""Formatting utilities for VJ Console."""


def format_time(seconds: float) -> str:
    """Format seconds as MM:SS."""
    try:
        mins, secs = int(seconds // 60), int(seconds % 60)
        return f"{mins}:{secs:02d}"
    except (ValueError, TypeError):
        return "0:00"


def format_duration(position: float, duration: float) -> str:
    """Format position/duration as MM:SS / MM:SS."""
    return f"{format_time(position)} / {format_time(duration)}"


def format_status_icon(active: bool, running_text: str = "● ON", stopped_text: str = "○ OFF") -> str:
    """Format a status indicator."""
    return f"[green]{running_text}[/]" if active else f"[dim]{stopped_text}[/]"


def format_bar(value: float, width: int = 15) -> str:
    """Create a visual bar from 0.0-1.0 value."""
    filled = int(value * width)
    return "█" * filled + "░" * (width - filled)


def truncate(text: str, max_len: int, suffix: str = "...") -> str:
    """Truncate text with suffix if too long."""
    return text[:max_len - len(suffix)] + suffix if len(text) > max_len else text
