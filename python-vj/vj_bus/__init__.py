"""
VJ Bus - Multi-process IPC for python-vj

A robust communication layer for the VJ system with:
- Independent worker processes that survive TUI crashes
- ZeroMQ for reliable control + high-throughput telemetry
- File-based service registry for discovery
- Structured message schemas with validation
"""

__version__ = "1.0.0"

from .messages import (
    MessageType,
    CommandType,
    ResponseStatus,
    EventType,
    Message,
    CommandMessage,
    ResponseMessage,
    TelemetryMessage,
    EventMessage,
    HeartbeatMessage,
    AudioFeaturesPayload,
    LogPayload,
    WorkerStatePayload,
)

from .registry import ServiceRegistry
from .worker import WorkerBase
from .client import VJBusClient

__all__ = [
    "MessageType",
    "CommandType",
    "ResponseStatus",
    "EventType",
    "Message",
    "CommandMessage",
    "ResponseMessage",
    "TelemetryMessage",
    "EventMessage",
    "HeartbeatMessage",
    "AudioFeaturesPayload",
    "LogPayload",
    "WorkerStatePayload",
    "ServiceRegistry",
    "WorkerBase",
    "VJBusClient",
]
