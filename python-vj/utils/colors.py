"""Color utility functions for VJ Console."""


def color_by_score(score: float) -> str:
    """Get color name based on score threshold."""
    if score >= 0.7:
        return "green"
    if score >= 0.4:
        return "yellow"
    return "dim"


def color_by_level(text: str) -> str:
    """Get color based on log level in text."""
    if "ERROR" in text or "EXCEPTION" in text:
        return "red"
    if "WARNING" in text:
        return "yellow"
    if "INFO" in text:
        return "green"
    return "dim"


def color_by_osc_channel(address: str) -> str:
    """Get color based on OSC address channel."""
    if "/textler/categories" in address:
        return "yellow"
    if "/vj/" in address:
        return "cyan"
    if "/textler/" in address:
        return "green"
    return "white"
