from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, Optional

from .utils import generate_instance_id, json_dumps, json_loads, now_ts


@dataclass
class CommandPayload:
    verb: str
    config_version: str
    data: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "verb": self.verb,
            "config_version": self.config_version,
            "data": self.data,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "CommandPayload":
        return cls(
            verb=data.get("verb", ""),
            config_version=data.get("config_version", ""),
            data=data.get("data", {}) or {},
        )


auth_status = ("ok", "error")


@dataclass
class AckPayload:
    status: str
    message: str = ""
    applied_config_version: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "status": self.status,
            "message": self.message,
            "applied_config_version": self.applied_config_version,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "AckPayload":
        return cls(
            status=data.get("status", ""),
            message=data.get("message", ""),
            applied_config_version=data.get("applied_config_version"),
        )


@dataclass
class TelemetryPayload:
    stream: str
    sequence: int
    data: Any

    def to_dict(self) -> Dict[str, Any]:
        return {
            "stream": self.stream,
            "sequence": self.sequence,
            "data": self.data,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "TelemetryPayload":
        return cls(
            stream=data.get("stream", ""),
            sequence=int(data.get("sequence", 0)),
            data=data.get("data"),
        )


@dataclass
class EventPayload:
    level: str
    message: str
    details: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "level": self.level,
            "message": self.message,
            "details": self.details,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "EventPayload":
        return cls(
            level=data.get("level", "info"),
            message=data.get("message", ""),
            details=data.get("details", {}) or {},
        )


@dataclass
class HeartbeatPayload:
    cpu: float
    mem: float
    uptime_sec: float
    lag_ms: Optional[float] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "cpu": self.cpu,
            "mem": self.mem,
            "uptime_sec": self.uptime_sec,
            "lag_ms": self.lag_ms,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "HeartbeatPayload":
        return cls(
            cpu=float(data.get("cpu", 0.0)),
            mem=float(data.get("mem", 0.0)),
            uptime_sec=float(data.get("uptime_sec", 0.0)),
            lag_ms=data.get("lag_ms"),
        )


@dataclass
class StateSyncPayload:
    config_version: Optional[str] = None
    state: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "config_version": self.config_version,
            "state": self.state,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "StateSyncPayload":
        return cls(
            config_version=data.get("config_version"),
            state=data.get("state", {}) or {},
        )


@dataclass
class Envelope:
    schema: str
    type: str
    worker: str
    payload: Any
    instance_id: str = field(default_factory=generate_instance_id)
    correlation_id: str = field(default_factory=generate_instance_id)
    generation: int = 0
    timestamp: str = field(default_factory=now_ts)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "schema": self.schema,
            "type": self.type,
            "worker": self.worker,
            "instance_id": self.instance_id,
            "correlation_id": self.correlation_id,
            "generation": self.generation,
            "timestamp": self.timestamp,
            "payload": self.payload.to_dict() if hasattr(self.payload, "to_dict") else self.payload,
        }

    def to_json(self) -> str:
        return json_dumps(self.to_dict())

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "Envelope":
        payload_raw = data.get("payload", {}) or {}
        msg_type = data.get("type", "")
        payload: Any
        if msg_type == "command":
            payload = CommandPayload.from_dict(payload_raw)
        elif msg_type == "ack":
            payload = AckPayload.from_dict(payload_raw)
        elif msg_type == "telemetry":
            payload = TelemetryPayload.from_dict(payload_raw)
        elif msg_type == "event":
            payload = EventPayload.from_dict(payload_raw)
        elif msg_type == "heartbeat":
            payload = HeartbeatPayload.from_dict(payload_raw)
        elif msg_type == "state_sync":
            payload = StateSyncPayload.from_dict(payload_raw)
        else:
            payload = payload_raw
        return cls(
            schema=data.get("schema", ""),
            type=msg_type,
            worker=data.get("worker", ""),
            payload=payload,
            instance_id=data.get("instance_id", generate_instance_id()),
            correlation_id=data.get("correlation_id", generate_instance_id()),
            generation=int(data.get("generation", 0)),
            timestamp=data.get("timestamp", now_ts()),
        )

    @classmethod
    def from_json(cls, raw: str) -> "Envelope":
        return cls.from_dict(json_loads(raw))


class EnvelopeBuilder:
    def __init__(self, schema: str, worker: str, instance_id: Optional[str] = None, generation: int = 0):
        self.schema = schema
        self.worker = worker
        self.instance_id = instance_id or generate_instance_id()
        self.sequence = 0
        self.generation = generation

    def command(self, verb: str, config_version: str, data: Dict[str, Any]) -> Envelope:
        return Envelope(
            schema=self.schema,
            type="command",
            worker=self.worker,
            payload=CommandPayload(verb=verb, config_version=config_version, data=data),
            instance_id=self.instance_id,
            generation=self.generation,
        )

    def ack(self, request: Envelope, status: str, message: str = "", applied_config_version: Optional[str] = None) -> Envelope:
        return Envelope(
            schema=self.schema,
            type="ack",
            worker=self.worker,
            payload=AckPayload(status=status, message=message, applied_config_version=applied_config_version),
            instance_id=self.instance_id,
            correlation_id=request.correlation_id,
            generation=self.generation or request.generation,
        )

    def telemetry(self, stream: str, data: Any) -> Envelope:
        self.sequence += 1
        return Envelope(
            schema=self.schema,
            type="telemetry",
            worker=self.worker,
            payload=TelemetryPayload(stream=stream, sequence=self.sequence, data=data),
            instance_id=self.instance_id,
            generation=self.generation,
        )

    def event(self, level: str, message: str, details: Optional[Dict[str, Any]] = None) -> Envelope:
        return Envelope(
            schema=self.schema,
            type="event",
            worker=self.worker,
            payload=EventPayload(level=level, message=message, details=details or {}),
            instance_id=self.instance_id,
            generation=self.generation,
        )

    def heartbeat(self, cpu: float, mem: float, uptime_sec: float, lag_ms: Optional[float] = None) -> Envelope:
        return Envelope(
            schema=self.schema,
            type="heartbeat",
            worker=self.worker,
            payload=HeartbeatPayload(cpu=cpu, mem=mem, uptime_sec=uptime_sec, lag_ms=lag_ms),
            instance_id=self.instance_id,
            generation=self.generation,
        )

    def state_sync(self, config_version: Optional[str], state: Dict[str, Any]) -> Envelope:
        return Envelope(
            schema=self.schema,
            type="state_sync",
            worker=self.worker,
            payload=StateSyncPayload(config_version=config_version, state=state),
            instance_id=self.instance_id,
            generation=self.generation,
        )
