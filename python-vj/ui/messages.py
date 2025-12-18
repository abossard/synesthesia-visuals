"""Message classes for VJ Console UI events."""

from textual.message import Message


# OSC Messages
class OSCStartRequested(Message):
    """Message posted when user requests to start all OSC channels."""
    pass


class OSCStopRequested(Message):
    """Message posted when user requests to stop all OSC channels."""
    pass


class OSCChannelStartRequested(Message):
    """Message posted when user requests to start a specific OSC channel."""
    def __init__(self, channel: str):
        super().__init__()
        self.channel = channel


class OSCChannelStopRequested(Message):
    """Message posted when user requests to stop a specific OSC channel."""
    def __init__(self, channel: str):
        super().__init__()
        self.channel = channel


class OSCClearRequested(Message):
    """Message posted when user requests to clear OSC log."""
    pass


# Playback Messages
class PlaybackSourceChanged(Message):
    """Message posted when playback source is changed."""
    def __init__(self, source_key: str):
        super().__init__()
        self.source_key = source_key
