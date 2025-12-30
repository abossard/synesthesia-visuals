"""
OutputService - Deep module for OSC output

Hides ALL complexity:
- OSC message formatting
- Multiple destinations
- Protocol details
- Message buffering

Simple interface:
    service.send_track(track)
    service.send_no_track()
    service.send_lyrics(lines)
    service.send_active_line(index, line)
    service.send_refrain_active(index, text)
"""

import logging
from dataclasses import dataclass
from typing import Any, List, Optional, TYPE_CHECKING

if TYPE_CHECKING:
    from services.lyrics import LyricLine

logger = logging.getLogger(__name__)


# =============================================================================
# OUTPUT SERVICE (the deep module)
# =============================================================================

class OutputService:
    """
    Deep module for OSC output.
    
    Hides: OSC protocol, destinations, formatting.
    Exposes: send_track(), send_lyrics(), send_active_line().
    
    All messages are FLAT arrays (no nested structures).
    """
    
    def __init__(self):
        self._osc = None  # Lazy init
        self._last_active_index = -1
    
    def _ensure_osc(self):
        """Lazy init OSC."""
        if self._osc is None:
            from osc import osc
            self._osc = osc
            self._osc.start()
    
    # =========================================================================
    # TRACK MESSAGES
    # =========================================================================
    
    def send_track(self, track, has_lyrics: bool = True) -> None:
        """
        Send track info to Processing.
        
        OSC: /textler/track [1, source, artist, title, album, duration, has_lyrics]
        """
        self._ensure_osc()
        
        if not track:
            self.send_no_track()
            return
        
        duration = getattr(track, 'duration_sec', 0) or getattr(track, 'duration', 0)
        
        self._osc.textler.send(
            "/textler/track",
            1,  # active
            getattr(track, 'source', 'unknown'),
            track.artist,
            track.title,
            getattr(track, 'album', ''),
            float(duration),
            1 if has_lyrics else 0
        )
        logger.debug(f"→ /textler/track: {track.artist} - {track.title}")
    
    def send_no_track(self) -> None:
        """Send no-track state."""
        self._ensure_osc()
        self._osc.textler.send("/textler/track", 0, "", "", "", "", 0.0, 0)
        logger.debug("→ /textler/track: (none)")
    
    # =========================================================================
    # LYRICS MESSAGES
    # =========================================================================
    
    def send_lyrics(self, lines: List["LyricLine"]) -> None:
        """
        Send all lyrics lines to Processing.
        
        OSC: /textler/lyrics/reset
        OSC: /textler/lyrics/line [index, time, text] (for each)
        """
        self._ensure_osc()
        
        self._osc.textler.send("/textler/lyrics/reset")
        
        for i, line in enumerate(lines):
            self._osc.textler.send(
                "/textler/lyrics/line",
                i,
                float(line.time_sec),
                line.text
            )
        
        logger.debug(f"→ /textler/lyrics: {len(lines)} lines")
    
    def send_no_lyrics(self) -> None:
        """Send lyrics reset with no content."""
        self._ensure_osc()
        self._osc.textler.send("/textler/lyrics/reset")
    
    def send_active_line(self, index: int) -> None:
        """
        Send active line index.
        
        OSC: /textler/line/active [index]
        """
        if index == self._last_active_index:
            return  # No change
        
        self._last_active_index = index
        self._ensure_osc()
        self._osc.textler.send("/textler/line/active", index)
    
    # =========================================================================
    # REFRAIN MESSAGES
    # =========================================================================
    
    def send_refrains(self, lines: List["LyricLine"]) -> None:
        """
        Send refrain lines to Processing.
        
        OSC: /textler/refrain/reset
        OSC: /textler/refrain/line [index, time, text] (for each)
        """
        self._ensure_osc()
        
        self._osc.textler.send("/textler/refrain/reset")
        
        for i, line in enumerate(lines):
            self._osc.textler.send(
                "/textler/refrain/line",
                i,
                float(line.time_sec),
                line.text
            )
        
        logger.debug(f"→ /textler/refrain: {len(lines)} refrain lines")
    
    def send_refrain_active(self, index: int, text: str = "") -> None:
        """
        Send active refrain.
        
        OSC: /textler/refrain/active [index, text]
        """
        self._ensure_osc()
        self._osc.textler.send("/textler/refrain/active", index, text)
    
    # =========================================================================
    # SHADER / IMAGE MESSAGES
    # =========================================================================
    
    def send_shader(self, name: str, energy: float = 0.5, valence: float = 0.0) -> None:
        """
        Send shader load command.
        
        OSC: /shader/load [name, energy, valence]
        """
        self._ensure_osc()
        self._osc.textler.send("/shader/load", name, float(energy), float(valence))
        logger.info(f"→ /shader/load: {name} (energy={energy:.2f}, valence={valence:.2f})")
    
    def send_image_folder(self, folder_path: str, fit_mode: str = "cover") -> None:
        """
        Send image folder for beat-synced display.
        
        OSC: /image/fit [mode]
        OSC: /image/folder [path]
        """
        self._ensure_osc()
        self._osc.textler.send("/image/fit", fit_mode)
        self._osc.textler.send("/image/folder", str(folder_path))
        logger.info(f"→ /image/folder: {folder_path}")
    
    # =========================================================================
    # GENERIC
    # =========================================================================
    
    def send(self, address: str, *args) -> None:
        """Send arbitrary OSC message."""
        self._ensure_osc()
        self._osc.textler.send(address, *args)
    
    def reset(self) -> None:
        """Reset output state."""
        self._last_active_index = -1
