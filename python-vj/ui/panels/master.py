"""Master control panel for VJ Console."""

from textual.reactive import reactive

from utils import format_status_icon
from .base import ReactivePanel


class MasterControlPanel(ReactivePanel):
    """VJ app control panel."""
    status = reactive({})

    def on_mount(self) -> None:
        """Initialize content when mounted."""
        self._safe_render()

    def watch_status(self, data: dict) -> None:
        self._safe_render()

    def _safe_render(self) -> None:
        """Render only if mounted."""
        if not self.is_mounted:
            return
        syn = format_status_icon(bool(self.status.get('synesthesia')), "● RUNNING", "○ stopped")
        pms = format_status_icon(bool(self.status.get('milksyphon')), "● RUNNING", "○ stopped")
        kar = format_status_icon(bool(self.status.get('karaoke')), "● ACTIVE", "○ inactive")
        proc = self.status.get('processing_apps', 0)

        self.update(
            self.render_section("Master Control", "═") +
            f"  [S] Synesthesia     {syn}\n"
            f"  [M] ProjMilkSyphon  {pms}\n"
            f"  [P] Processing Apps {proc} running\n"
            f"  [K] Karaoke Engine  {kar}\n\n"
            "[dim]Press letter key to toggle app[/dim]"
        )
