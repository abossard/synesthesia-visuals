"""
OSC Module - Typed OSC channels for VJ system

Usage:
    from osc import osc, osc_monitor

    osc.start()
    osc.synesthesia.send("/scene/load", "my_scene")
    osc.vdj.send("/deck/1/play")

    osc_monitor.start()
    for msg in osc_monitor.get_aggregated():
        print(f"{msg.channel} {msg.address} = {msg.last_args}")
"""

from .hub import (
    Channel,
    ChannelConfig,
    OSCHub,
    osc,
    VDJ,
    SYNESTHESIA,
    KARAOKE,
    Handler,
)
from .monitor import (
    OSCMonitor,
    AggregatedMessage,
    osc_monitor,
)

__all__ = [
    # Hub
    "Channel",
    "ChannelConfig",
    "OSCHub",
    "osc",
    "VDJ",
    "SYNESTHESIA",
    "KARAOKE",
    "Handler",
    # Monitor
    "OSCMonitor",
    "AggregatedMessage",
    "osc_monitor",
]
