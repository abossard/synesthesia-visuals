"""
VJ Bus - Inter-Process Communication Library for Python-VJ

Provides a hybrid IPC architecture:
- Unix Domain Sockets for control plane (commands, config, discovery)
- OSC for data plane (high-frequency telemetry streams)

Usage:
    from vj_bus import Worker, TelemetrySender, WorkerDiscovery
    from vj_bus.schema import CommandMessage, AckMessage
"""

from .schema import (
    MessageType,
    BaseMessage,
    HeartbeatMessage,
    CommandMessage,
    AckMessage,
    ResponseMessage,
    RegisterMessage,
    ErrorMessage,
)

from .control import ControlSocket
from .telemetry import TelemetrySender
from .worker import Worker
from .discovery import WorkerDiscovery

__version__ = "1.0.0"

__all__ = [
    # Schema
    "MessageType",
    "BaseMessage",
    "HeartbeatMessage",
    "CommandMessage",
    "AckMessage",
    "ResponseMessage",
    "RegisterMessage",
    "ErrorMessage",
    # Communication
    "ControlSocket",
    "TelemetrySender",
    # Workers
    "Worker",
    "WorkerDiscovery",
]
