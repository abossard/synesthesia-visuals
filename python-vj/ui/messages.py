"""Message classes for VJ Console UI events."""

from textual.message import Message


# OSC Messages
class OSCClearRequested(Message):
    """Message posted when user requests to clear OSC log."""
    pass


class VJUniverseTestRequested(Message):
    """Message posted when user requests VJUniverse OSC test."""
    pass


class VDJTestRequested(Message):
    """Message posted when user requests VDJ OSC connection test."""
    pass


# Playback Messages
class PlaybackSourceChanged(Message):
    """Message posted when playback source is changed."""
    def __init__(self, source_key: str):
        super().__init__()
        self.source_key = source_key
