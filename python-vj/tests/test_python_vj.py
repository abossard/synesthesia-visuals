import json
import time
from pathlib import Path

import pytest

from infrastructure import PipelineTracker, ServiceHealth, Settings
from vj_bus import EnvelopeBuilder, TuiClient, WorkerNode
from vj_bus.utils import find_free_port


def test_service_health_state_transitions():
    health = ServiceHealth("spotify")
    status = health.get_status()
    assert status["available"] is False

    health.mark_available("connected")
    status = health.get_status()
    assert status["available"] is True
    assert status["error"] == ""

    health.mark_unavailable("timeout")
    status = health.get_status()
    assert status["available"] is False
    assert status["error"] == "timeout"
    assert status["error_count"] >= 1


def test_settings_persistence(tmp_path: Path):
    settings_path = tmp_path / "settings.json"
    settings = Settings(file_path=settings_path)

    # default
    assert settings.timing_offset_ms == -500

    settings.adjust_timing(200)
    assert settings.timing_offset_ms == -300

    # reload from disk
    settings2 = Settings(file_path=settings_path)
    assert settings2.timing_offset_ms == -300


def test_pipeline_tracker_flow():
    tracker = PipelineTracker()
    assert len(tracker.get_display_lines()) == len(PipelineTracker.STEPS)

    tracker.start("fetch_lyrics", "begin")
    tracker.complete("fetch_lyrics", "done")
    tracker.error("extract_keywords", "no text")
    tracker.skip("comfyui_generate", "disabled")

    lines = tracker.get_display_lines()
    statuses = {label: status for label, status, _, _ in lines}
    assert statuses[PipelineTracker.STEP_LABELS["fetch_lyrics"]] == "✓"
    assert statuses[PipelineTracker.STEP_LABELS["extract_keywords"]] == "✗"
    assert statuses[PipelineTracker.STEP_LABELS["comfyui_generate"]] == "○"
    # log lines capture error marker
    assert any("extract_keywords" in log for log in tracker.get_log_lines())


def test_pipeline_reset_logs_and_track_key():
    tracker = PipelineTracker()
    tracker.reset(track_key="track-1")
    assert tracker.current_track == "track-1"
    tracker.log("custom log")
    assert "custom log" in tracker.get_log_lines()

    tracker.reset()
    assert tracker.current_track == ""
    assert tracker.get_log_lines() == []


@pytest.fixture()
def ipc_ports():
    return {
        "telemetry": find_free_port(),
        "command": f"tcp://127.0.0.1:{find_free_port()}",
        "events": f"tcp://127.0.0.1:{find_free_port()}",
    }


def test_worker_heartbeat_and_status(ipc_ports):
    worker = WorkerNode(
        name="lyrics_fetcher",
        telemetry_port=ipc_ports["telemetry"],
        command_endpoint=ipc_ports["command"],
        event_endpoint=ipc_ports["events"],
        heartbeat_interval=0.2,
    )
    worker.start()

    client = TuiClient(schema="vj.v1")
    heartbeats = []

    def _on_hb(env):
        heartbeats.append(env.payload.uptime_sec)

    client.on_event("lyrics_fetcher", _on_hb)
    client.subscribe_events(ipc_ports["events"])

    time.sleep(0.6)
    worker.stop()
    client.stop()

    assert heartbeats, "expected heartbeat telemetry from worker"


def test_command_round_trip_with_ack(ipc_ports):
    worker = WorkerNode(
        name="osc_debugger",
        telemetry_port=ipc_ports["telemetry"],
        command_endpoint=ipc_ports["command"],
        event_endpoint=ipc_ports["events"],
        heartbeat_interval=0.2,
    )

    @worker.command("reload")
    def _reload(env):
        return worker.ack(env, status="ok", applied_config_version=env.payload.config_version)

    worker.start()

    client = TuiClient(schema="vj.v1")
    builder = EnvelopeBuilder(schema="vj.v1", worker="osc_debugger")
    response = client.command(ipc_ports["command"], builder.command("reload", "v1", {}))

    worker.stop()

    assert response.type == "ack"
    assert response.payload.status == "ok"


def test_multiple_workers_heartbeat_reporting():
    workers = []
    endpoints = []
    names = ["audio_analyzer", "lyrics_fetcher", "spotify_integration"]

    for name in names:
        telemetry_port = find_free_port()
        event_endpoint = f"tcp://127.0.0.1:{find_free_port()}"
        command_endpoint = f"tcp://127.0.0.1:{find_free_port()}"
        node = WorkerNode(
            name=name,
            telemetry_port=telemetry_port,
            command_endpoint=command_endpoint,
            event_endpoint=event_endpoint,
            heartbeat_interval=0.1,
        )
        node.start()
        workers.append(node)
        endpoints.append((name, event_endpoint, command_endpoint))

    client = TuiClient(schema="vj.v1")
    heartbeats: dict[str, int] = {name: 0 for name in names}

    for name, event_endpoint, _ in endpoints:
        client.on_event(name, lambda env, n=name: heartbeats.__setitem__(n, heartbeats[n] + 1))
        client.subscribe_events(event_endpoint, worker_filter=name)

    time.sleep(0.35)

    for worker in workers:
        worker.stop()
    client.stop()

    assert all(count > 0 for count in heartbeats.values()), "each worker should emit at least one heartbeat"

