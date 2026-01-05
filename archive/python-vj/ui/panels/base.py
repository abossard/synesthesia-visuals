"""Base panel class for VJ Console."""

from textual.widgets import Static


class ReactivePanel(Static):
    """Base class for reactive panels with common patterns."""

    def render_section(self, title: str, emoji: str = "═") -> str:
        return f"[bold]{emoji * 3} {title} {emoji * 3}[/]\n"
