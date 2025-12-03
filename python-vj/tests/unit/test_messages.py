"""
Unit tests for message schemas.
"""

import pytest
from pydantic import ValidationError

from vj_bus.messages import (
    CommandMessage,
    ResponseMessage,
    TelemetryMessage,
    AudioFeaturesPayload,
    LogPayload,
    WorkerStatePayload,
    MessageType,
    CommandType,
    ResponseStatus,
)


class TestCommandMessage:
    """Test CommandMessage schema."""

    def test_valid_command(self):
        """Valid command message."""
        cmd = CommandMessage(
            command=CommandType.HEALTH_CHECK,
            payload={}
        )
        assert cmd.type == MessageType.COMMAND
        assert cmd.id is not None
        assert cmd.timestamp > 0

    def test_custom_command(self):
        """Custom command string."""
        cmd = CommandMessage(
            command="custom_action",
            payload={"key": "value"}
        )
        assert cmd.command == "custom_action"
        assert cmd.payload == {"key": "value"}

    def test_serialization(self):
        """Command can be serialized to JSON."""
        cmd = CommandMessage(
            command=CommandType.HEALTH_CHECK
        )
        json_str = cmd.model_dump_json()
        assert "command" in json_str
        assert "health_check" in json_str


class TestResponseMessage:
    """Test ResponseMessage schema."""

    def test_success_response(self):
        """Success response."""
        resp = ResponseMessage(
            status=ResponseStatus.OK,
            result={"foo": "bar"}
        )
        assert resp.status == ResponseStatus.OK
        assert resp.result == {"foo": "bar"}
        assert resp.error is None

    def test_error_response(self):
        """Error response."""
        resp = ResponseMessage(
            status=ResponseStatus.ERROR,
            error="Something went wrong"
        )
        assert resp.status == ResponseStatus.ERROR
        assert resp.error == "Something went wrong"
        assert resp.result is None


class TestTelemetryMessage:
    """Test TelemetryMessage schema."""

    def test_telemetry(self):
        """Valid telemetry message."""
        msg = TelemetryMessage(
            source="audio_analyzer",
            topic="audio.features",
            payload={"value": 42}
        )
        assert msg.type == MessageType.TELEMETRY
        assert msg.source == "audio_analyzer"
        assert msg.topic == "audio.features"
        assert msg.payload == {"value": 42}


class TestAudioFeaturesPayload:
    """Test AudioFeaturesPayload schema."""

    def test_valid_payload(self):
        """Valid audio features."""
        payload = AudioFeaturesPayload(
            bands=[0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7],
            rms=0.5,
            beat=1,
            bpm=128.0,
            bpm_confidence=0.9
        )
        assert len(payload.bands) == 7
        assert payload.beat in (0, 1)

    def test_invalid_bands_count(self):
        """Must have exactly 7 bands."""
        with pytest.raises(ValidationError):
            AudioFeaturesPayload(
                bands=[0.1, 0.2],  # Too few
                rms=0.5,
                beat=0,
                bpm=120.0,
                bpm_confidence=0.8
            )

    def test_defaults(self):
        """Optional fields have defaults."""
        payload = AudioFeaturesPayload(
            bands=[0.1] * 7,
            rms=0.5,
            beat=0,
            bpm=120.0,
            bpm_confidence=0.8
        )
        assert payload.pitch_hz == 0.0
        assert payload.buildup is False


class TestLogPayload:
    """Test LogPayload schema."""

    def test_valid_log(self):
        """Valid log message."""
        log = LogPayload(
            level="INFO",
            logger="test",
            message="Test message",
            timestamp=1234567890.0
        )
        assert log.level == "INFO"
        assert log.logger == "test"


class TestWorkerStatePayload:
    """Test WorkerStatePayload schema."""

    def test_valid_state(self):
        """Valid worker state."""
        state = WorkerStatePayload(
            status="running",
            uptime_sec=100.5,
            config={"key": "value"},
            metrics={"fps": 60.0}
        )
        assert state.status == "running"
        assert state.uptime_sec == 100.5

    def test_empty_metrics(self):
        """Metrics defaults to empty dict."""
        state = WorkerStatePayload(
            status="idle",
            uptime_sec=0.0,
            config={}
        )
        assert state.metrics == {}
