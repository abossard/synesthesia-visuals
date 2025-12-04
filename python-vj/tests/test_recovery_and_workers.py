import json
import multiprocessing
import time
from pathlib import Path
from typing import TypedDict

import pytest

from lyrics_worker import LyricsFetcherWorker
from osc_debugger_worker import OSCDebuggerWorker
from process_manager import VJProcessManager
from vj_bus import EnvelopeBuilder, TuiClient, WorkerNode
from vj_bus.osc_helpers import osc_send_raw
from vj_bus.utils import find_free_port


class WorkerPorts(TypedDict):
    """Type definition for worker port configuration."""
    telemetry: int
    command: str
    events: str


def _worker_process(name: str, ports: WorkerPorts, generation: int) -> None:
    node = WorkerNode(
        name=name,
        telemetry_port=ports["telemetry"],
        command_endpoint=ports["command"],
        event_endpoint=ports["events"],
        heartbeat_interval=0.1,
        generation=generation,
    )
    node.start()
    time.sleep(0.15)
    node.send_event("info", "booted", {"generation": generation})
    node.run_forever()


def _spawn_worker_process(name: str, ports: WorkerPorts, generation: int = 0) -> multiprocessing.Process:
    proc = multiprocessing.Process(target=_worker_process, args=(name, ports, generation))
    proc.start()
    return proc


@pytest.fixture()
def endpoints():
    return {
        "telemetry": find_free_port(),
        "command": f"tcp://127.0.0.1:{find_free_port()}",
        "events": f"tcp://127.0.0.1:{find_free_port()}",
    }


def test_process_manager_registry_and_restart(tmp_path: Path):
    manager = VJProcessManager(registry_path=tmp_path / "registry.json")
    spec = manager.make_worker_spec(name="managed")
    manager.add_worker(spec)
    manager.start()

    client = TuiClient(schema="vj.v1")
    beats: list[tuple[str, int]] = []
    client.on_event("managed", lambda env: beats.append((env.instance_id, env.generation)))
    client.subscribe_events(spec.event_endpoint, worker_filter="managed")

    start = time.time()
    while time.time() - start < 2.0 and not beats:
        time.sleep(0.05)

    first = beats[-1][0] if beats else None
    assert first, "expected first heartbeat from managed worker"

    # Crash and let the manager restart the worker with a new generation/instance_id
    managed = manager._workers["managed"]  # noqa: SLF001
    managed.process.terminate()
    managed.process.join()

    start = time.time()
    while time.time() - start < 2.0:
        if beats and beats[-1][0] != first:
            break
        time.sleep(0.05)

    data = json.loads((tmp_path / "registry.json").read_text())
    gen = data["workers"]["managed"]["generation"]

    client.stop()
    manager.stop()

    assert beats[-1][0] != first
    assert gen >= 1


def test_worker_restart_and_tui_reconnect(endpoints):
    client = TuiClient(schema="vj.v1")
    heartbeats = []

    client.on_event("crashy", lambda env: heartbeats.append((env.instance_id, env.generation)))
    client.subscribe_events(endpoints["events"], worker_filter="crashy")

    time.sleep(0.1)
    p1 = _spawn_worker_process("crashy", endpoints, generation=0)
    first_instance = None
    start = time.time()
    while time.time() - start < 1.5:
        if heartbeats:
            first_instance = heartbeats[-1][0]
            break
        time.sleep(0.05)
    p1.terminate()
    p1.join()

    p2 = _spawn_worker_process("crashy", endpoints, generation=1)
    start = time.time()
    saw_new_instance = False
    while time.time() - start < 1.5:
        if heartbeats and heartbeats[-1][0] != first_instance:
            saw_new_instance = True
            break
        time.sleep(0.05)

    client.stop()
    p2.terminate()
    p2.join()

    assert first_instance is not None
    assert saw_new_instance


def test_tui_restarts_and_resubscribes(endpoints):
    worker = WorkerNode(
        name="stable",
        telemetry_port=endpoints["telemetry"],
        command_endpoint=endpoints["command"],
        event_endpoint=endpoints["events"],
        heartbeat_interval=0.1,
    )
    worker.start()

    client1 = TuiClient(schema="vj.v1")
    first = []
    client1.on_event("stable", lambda env: first.append(env.payload.uptime_sec))
    client1.subscribe_events(endpoints["events"], worker_filter="stable")
    time.sleep(0.25)
    client1.stop()

    client2 = TuiClient(schema="vj.v1")
    second = []
    client2.on_event("stable", lambda env: second.append(env.payload.uptime_sec))
    client2.subscribe_events(endpoints["events"], worker_filter="stable")
    time.sleep(0.25)

    worker.stop()
    client2.stop()

    assert first, "first TUI should receive heartbeats"
    assert second, "second TUI should reattach and receive heartbeats"


def test_telemetry_stress_over_osc(endpoints):
    worker = WorkerNode(
        name="audio_analyzer",
        telemetry_port=endpoints["telemetry"],
        command_endpoint=endpoints["command"],
        event_endpoint=endpoints["events"],
        heartbeat_interval=0.2,
    )
    worker.start()

    client = TuiClient(schema="vj.v1")
    received = []

    client.start_osc_listener(endpoints["telemetry"])

    @client.on_telemetry("audio_analyzer", stream="features")
    def _on(env):
        received.append(env.payload.sequence)

    time.sleep(0.1)
    for _ in range(100):
        worker.send_telemetry("features", {"rms": 0.1})
    time.sleep(0.5)

    worker.stop()
    client.stop()

    assert len(received) >= 80


def test_osc_debugger_captures_messages():
    capture_port = find_free_port()
    telemetry_port = find_free_port()
    command_ep = f"tcp://127.0.0.1:{find_free_port()}"
    event_ep = f"tcp://127.0.0.1:{find_free_port()}"

    worker = OSCDebuggerWorker(
        capture_port=capture_port,
        telemetry_port=telemetry_port,
        command_endpoint=command_ep,
        event_endpoint=event_ep,
    )
    worker.start()

    client = TuiClient(schema="vj.v1")
    seen = []
    client.start_osc_listener(telemetry_port)

    @client.on_telemetry("osc_debugger", stream="osc_debug")
    def _on_debug(env):
        seen.append(env.payload.data)

    osc_send_raw("127.0.0.1", capture_port, "/debug", 1, 2, 3)
    time.sleep(0.4)

    worker.stop()
    client.stop()

    assert seen and seen[-1]["args"] == [1, 2, 3]


def test_lyrics_worker_returns_analysis():
    telemetry_port = find_free_port()
    command_ep = f"tcp://127.0.0.1:{find_free_port()}"
    event_ep = f"tcp://127.0.0.1:{find_free_port()}"

    worker = LyricsFetcherWorker(
        telemetry_port=telemetry_port,
        command_endpoint=command_ep,
        event_endpoint=event_ep,
        enable_llm=False,
    )
    worker.start()

    client = TuiClient(schema="vj.v1")
    builder = EnvelopeBuilder(schema="vj.v1", worker="lyrics_fetcher")
    telemetry = []

    client.start_osc_listener(telemetry_port)

    @client.on_telemetry("lyrics_fetcher", stream="lyrics_analysis")
    def _on(env):
        telemetry.append(env.payload.data)

    response = client.command(
        command_ep,
        builder.command(
            "fetch",
            config_version="cfg-lyric-1",
            data={"lyrics": "we party all night", "artist": "DJ", "title": "Party"},
        ),
    )

    time.sleep(0.4)
    worker.stop()
    client.stop()

    assert response.type == "ack"
    assert telemetry, "lyrics telemetry should be emitted"
    assert telemetry[-1]["analysis"]["keywords"]
