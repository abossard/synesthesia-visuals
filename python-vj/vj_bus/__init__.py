"""Shared IPC helpers for python-vj.

Exposes message models and convenience classes for workers and the TUI.
"""
from .models import (
    Envelope,
    CommandPayload,
    AckPayload,
    TelemetryPayload,
    EventPayload,
    HeartbeatPayload,
    StateSyncPayload,
    EnvelopeBuilder,
)
from .worker import WorkerNode
from .tui import TuiClient
from .osc_helpers import build_osc_address, encode_osc_args, decode_osc_envelope
from .utils import now_ts, generate_instance_id

__all__ = [
    "Envelope",
    "CommandPayload",
    "AckPayload",
    "TelemetryPayload",
    "EventPayload",
    "HeartbeatPayload",
    "StateSyncPayload",
    "EnvelopeBuilder",
    "WorkerNode",
    "TuiClient",
    "build_osc_address",
    "encode_osc_args",
    "decode_osc_envelope",
    "now_ts",
    "generate_instance_id",
]
