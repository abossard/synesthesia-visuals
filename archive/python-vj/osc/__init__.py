"""
OSC Module - Centralized OSC hub for VJ system

Public API:
    Singletons:
        osc - OSCHub instance with send-only channels (vdj, synesthesia, textler)
        osc_monitor - OSCMonitor for aggregating incoming messages for UI display

    Classes:
        OSCHub - Single receive hub (port 9999) with forwarding
        Channel - Send-only OSC channel
        ChannelConfig - Config for a channel (send port, host, shared recv port)
        OSCMonitor - Aggregates OSC messages by address
        AggregatedMessage - Aggregated message stats

    Channel Configs:
        VDJ - VirtualDJ channel (send: 9009, recv: 9999 shared)
        SYNESTHESIA - Synesthesia channel (send: 7777, recv: 9999 shared)
        TEXTLER - VJUniverse channel (send: 10000, recv: None)

Usage:
    from osc import osc, osc_monitor

    osc.start()
    osc.subscribe("/", handler)
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
    TEXTLER,
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
    "TEXTLER",
    "Handler",
    # Monitor
    "OSCMonitor",
    "AggregatedMessage",
    "osc_monitor",
]
