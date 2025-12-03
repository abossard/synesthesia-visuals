import threading
import time

import pytest

from vj_bus import (
    Envelope,
    EnvelopeBuilder,
    WorkerNode,
    TuiClient,
)
from vj_bus.utils import find_free_port


@pytest.fixture()
def ports():
    return {
        "telemetry": find_free_port(),
        "command": f"tcp://127.0.0.1:{find_free_port()}",
        "events": f"tcp://127.0.0.1:{find_free_port()}",
    }


def test_envelope_round_trip():
    builder = EnvelopeBuilder(schema="vj.v1", worker="audio_analyzer")
    env = builder.command(verb="set_config", config_version="cfg-1", data={"fft_size": 2048})
    raw = env.to_json()
    parsed = Envelope.from_json(raw)
    assert parsed.schema == env.schema
    assert parsed.worker == env.worker
    assert parsed.payload.verb == "set_config"
    assert parsed.payload.data["fft_size"] == 2048


def test_worker_command_and_ack(ports):
    worker = WorkerNode(
        name="audio_analyzer",
        telemetry_port=ports["telemetry"],
        command_endpoint=ports["command"],
        event_endpoint=ports["events"],
    )

    applied_configs = []

    @worker.command("set_config")
    def handle_config(env: Envelope):
        applied_configs.append(env.payload.config_version)
        return worker.ack(env, status="ok", applied_config_version=env.payload.config_version)

    worker.start()

    client = TuiClient(schema="vj.v1")
    builder = EnvelopeBuilder(schema="vj.v1", worker="audio_analyzer")
    response = client.command(ports["command"], builder.command("set_config", "cfg-123", {"gain": 2}))

    worker.stop()

    assert response.type == "ack"
    assert response.payload.status == "ok"
    assert applied_configs == ["cfg-123"]


def test_telemetry_round_trip_over_osc(ports):
    received = []

    worker = WorkerNode(
        name="audio_analyzer",
        telemetry_port=ports["telemetry"],
        command_endpoint=ports["command"],
        event_endpoint=ports["events"],
        heartbeat_interval=0.5,
    )

    worker.start()

    client = TuiClient(schema="vj.v1")
    client.start_osc_listener(port=ports["telemetry"])

    @client.on_telemetry("audio_analyzer", stream="features")
    def _on_features(env: Envelope):
        received.append(env.payload.data)

    # allow server spin
    time.sleep(0.2)
    worker.send_telemetry("features", {"rms": 0.5})
    time.sleep(0.5)

    worker.stop()
    client.stop()

    assert received == [{"rms": 0.5}]


def test_event_subscription(ports):
    worker = WorkerNode(
        name="spotify_integration",
        telemetry_port=ports["telemetry"],
        command_endpoint=ports["command"],
        event_endpoint=ports["events"],
        heartbeat_interval=0.2,
    )
    worker.start()

    client = TuiClient(schema="vj.v1")
    seen = []

    def on_event(env: Envelope):
        if env.type == "event":
            seen.append(env.payload.message)

    client.on_event("spotify_integration", on_event)
    client.subscribe_events(ports["events"])

    time.sleep(0.1)

    worker.send_event("info", "connected")
    time.sleep(0.3)

    worker.stop()
    client.stop()

    assert "connected" in seen
