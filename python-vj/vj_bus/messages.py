"""
Message schemas for VJ Bus IPC.

Uses Pydantic for validation and serialization.
All messages are JSON over ZMQ.
"""

from typing import Any, Optional, Dict, List
from pydantic import BaseModel, Field
from enum import Enum
import time
import uuid


class MessageType(str, Enum):
    """Message type discriminator."""
    COMMAND = "command"
    RESPONSE = "response"
    TELEMETRY = "telemetry"
    EVENT = "event"
    HEARTBEAT = "heartbeat"


class CommandType(str, Enum):
    """Standard command types."""
    HEALTH_CHECK = "health_check"
    GET_STATE = "get_state"
    SET_CONFIG = "set_config"
    RESTART = "restart"
    SHUTDOWN = "shutdown"
    # Custom commands use plain strings


class ResponseStatus(str, Enum):
    """Response status codes."""
    OK = "ok"
    ERROR = "error"
    TIMEOUT = "timeout"


class EventType(str, Enum):
    """Process manager event types."""
    WORKER_STARTED = "worker_started"
    WORKER_STOPPED = "worker_stopped"
    WORKER_CRASHED = "worker_crashed"
    WORKER_RESTARTED = "worker_restarted"


# Base envelope
class Message(BaseModel):
    """Base message envelope."""
    type: MessageType
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    timestamp: float = Field(default_factory=time.time)
    source: Optional[str] = None


# Command messages (TUI -> Worker)
class CommandMessage(Message):
    """Command from TUI to worker."""
    type: MessageType = MessageType.COMMAND
    command: str  # CommandType or custom string
    payload: Dict[str, Any] = Field(default_factory=dict)


class ResponseMessage(Message):
    """Response from worker to TUI."""
    type: MessageType = MessageType.RESPONSE
    status: ResponseStatus
    result: Optional[Dict[str, Any]] = None
    error: Optional[str] = None


# Telemetry messages (Worker -> TUI)
class TelemetryMessage(Message):
    """High-frequency telemetry from worker."""
    type: MessageType = MessageType.TELEMETRY
    topic: str  # e.g., "audio.features", "logs.error"
    payload: Dict[str, Any]


# Event messages (process_manager -> TUI)
class EventMessage(Message):
    """Process lifecycle events."""
    type: MessageType = MessageType.EVENT
    event: EventType
    worker: str
    payload: Dict[str, Any] = Field(default_factory=dict)


# Heartbeat (Worker -> Registry)
class HeartbeatMessage(Message):
    """Worker heartbeat for registry."""
    type: MessageType = MessageType.HEARTBEAT
    worker: str
    pid: int
    status: str = "running"
    metadata: Dict[str, Any] = Field(default_factory=dict)


# Domain-specific payloads (strongly typed)

class AudioFeaturesPayload(BaseModel):
    """Audio analyzer telemetry."""
    bands: List[float] = Field(..., min_length=7, max_length=7)
    rms: float
    beat: int  # 0 or 1
    bpm: float
    bpm_confidence: float
    pitch_hz: float = 0.0
    pitch_conf: float = 0.0
    buildup: bool = False
    drop: bool = False
    bass_level: float = 0.0
    mid_level: float = 0.0
    high_level: float = 0.0


class LogPayload(BaseModel):
    """Log message telemetry."""
    level: str  # "DEBUG", "INFO", "WARNING", "ERROR"
    logger: str
    message: str
    timestamp: float


class WorkerStatePayload(BaseModel):
    """Worker state snapshot (response to get_state)."""
    status: str  # "idle", "running", "error"
    uptime_sec: float
    config: Dict[str, Any]
    metrics: Dict[str, Any] = Field(default_factory=dict)
