# python-vj Target Architecture

## Goals and constraints
- Each major capability runs as a separate, resilient process managed by a supervisor.
- The TUI can crash or restart without stopping workers; it must discover and reconnect on startup.
- Workers stream telemetry (high-rate audio features, logs, debug info) and accept commands/config.
- process_manager supervises workers and restarts them on failure.
- IPC must be robust to partial failures and support idempotent re-sync.

## Process model
- **process_manager (supervisor)**: launches and monitors all workers using `subprocess.Popen` (allows non-Python tools) with exponential-backoff restarts and capped retries. Stores runtime metadata (PID, ports, version) in a shared state file (e.g., `/tmp/python-vj/process_registry.json`).
- **Workers (separate OS processes)**: `audio_analyzer`, `lyrics_fetcher`, `spotify_integration`, `virtualdj_integration`, `osc_debugger`, `log_view` (tail/ingest), and auxiliary `process_manager` controls. Each runs independently of the TUI.
- **TUI**: orchestrator/observer. Starts/stops via process_manager APIs, sends config/commands, aggregates telemetry. If TUI exits, workers continue. On restart, TUI reads registry/heartbeats to reconnect.
- **Shared library (`vj_bus`)**: used by TUI, process_manager, and workers for IPC schemas, OSC helpers, heartbeats, and reconnect logic.

## IPC transport recommendation
- **Hybrid IPC**: use **OSC (UDP)** for high-frequency telemetry streams; use **ZeroMQ (REQ/REP + PUB/SUB over IPC or TCP)** for control/config and discovery.
  - Rationale: OSC over UDP is lightweight and widely used for audio/VJ tools; dropping occasional packets is tolerable for telemetry. Control paths need reliability, request/response semantics, and backpressure—better served by ZeroMQ.
  - All messages share a versioned envelope defined in `vj_bus`, even when transported over different protocols.

## Communication topology
- **Ports/addresses**
  - ZeroMQ control: `ipc:///tmp/python-vj/{worker}.sock` (Linux/macOS) or `tcp://127.0.0.1:{base_port+id}` fallback for portability.
  - OSC telemetry (UDP): `localhost:{8000 + worker_id}` per worker. Each worker publishes to `/vj/{worker}/telemetry/...`.
  - OSC commands (optional fallback): workers also listen on `localhost:{9000 + worker_id}` with command addresses mirroring control schema.

- **Discovery & registration**
  - Workers on boot: load unique `instance_id`, bind ZeroMQ REP socket and OSC listener, emit a **registration heartbeat** to `process_manager` via ZeroMQ PUB (`/registry/register`).
  - process_manager persists registry (instance_id, role, ports, protocol versions) to the shared state file.
  - TUI on startup: reads the registry file and subscribes to process_manager PUB channel to learn about live workers; attempts ZeroMQ REQ handshake with each worker using stored ports; subscribes to OSC telemetry addresses.

- **Message addressing**
  - OSC telemetry paths: `/vj/{worker}/{stream}/{version}`; example `/vj/audio_analyzer/features/v1`.
  - OSC command paths (if used): `/vj/{worker}/cmd/{version}/{verb}`; example `/vj/audio_analyzer/cmd/v1/set_config`.
  - ZeroMQ control topics: multipart messages with topic `worker.{name}` or `registry.*` and JSON payload.

- **Config/command flow**
  1. TUI sends ZeroMQ REQ to worker `control` socket with a `CommandEnvelope` (`verb`, `payload`, `config_version`, `correlation_id`).
  2. Worker applies changes, responds with `CommandAck` (status, message, applied_config_version).
  3. process_manager exposes admin commands to start/stop/restart workers; TUI issues those to process_manager.

- **Telemetry/log flow**
  - Workers publish OSC telemetry (UDP) to their assigned port/address. TUI runs OSC clients per worker to receive and aggregate.
  - For critical events (errors, state changes), workers also send ZeroMQ PUB `EventEnvelope` so the TUI can reliably capture and replay missed events after reconnect.

## Failure handling and reconnection
- **TUI crash/restart**: workers keep running. On TUI boot, it reads the registry, replays latest `config_version` to ensure idempotency, resubscribes to ZeroMQ PUB and OSC telemetry, and issues `state_sync` REQ to each worker to fetch current status.
- **Worker crash/restart**: process_manager restarts with exponential backoff. The new worker instance emits `register` with a new `instance_id` and `generation` number. TUI detects the new generation via PUB stream, re-sends last known config (idempotent) and resumes subscriptions.
- **Network/backpressure**: OSC telemetry is lossy by design; high-rate publishers should support rate limiting and downsampling. Control via ZeroMQ is reliable; REQ timeouts trigger retries with capped attempts and circuit breaker logging.
- **Heartbeats**: every component sends periodic `heartbeat` EventEnvelopes with health and perf metrics. Missed heartbeats trigger reconnection and optional restart commands via process_manager.

## Message schema (versioned)
All messages share a top-level `Envelope` with fields:
- `schema`: semantic version string (e.g., `vj.v1`)
- `type`: `command`, `ack`, `event`, `telemetry`, `heartbeat`, `state_sync`
- `worker`: worker name (e.g., `audio_analyzer`)
- `instance_id`: unique per worker process instance
- `correlation_id`: UUID for request/response pairing
- `generation`: monotonically increasing integer per restart
- `timestamp`: RFC3339 UTC
- `payload`: typed object depending on `type`

Example payloads (v1):
- `CommandPayload`: `verb` (`set_config`, `enable`, `disable`, `restart`, `reload`), `config_version`, `data` (JSON-serializable dict).
- `AckPayload`: `status` (`ok` | `error`), `message`, `applied_config_version`.
- `TelemetryPayload`: `stream` (`features`, `lyrics`, `logs`), `sequence`, `data`.
- `EventPayload`: `level`, `message`, `details`.
- `HeartbeatPayload`: `cpu`, `mem`, `uptime_sec`, `lag_ms` (optional).

## Shared library: `vj_bus`
Responsibilities:
- Dataclasses/Pydantic models for envelopes and payloads with schema validation.
- OSC encode/decode helpers mapping envelope fields to OSC address + arguments.
- ZeroMQ helpers for REQ/REP, PUB/SUB sockets with reconnect, heartbeat, and retry wrappers.
- Worker helper: start control listener, send telemetry/events, emit heartbeats, auto reapply last config on reconnect.
- TUI helper: discover workers from registry, subscribe to PUB streams, attach OSC listeners, send commands with retries, request `state_sync`.

### Example: worker
```python
from vj_bus import WorkerNode, TelemetryPayload

worker = WorkerNode(
    name="audio_analyzer",
    telemetry_port=8001,
    command_endpoint="ipc:///tmp/python-vj/audio_analyzer.sock",
    schema="vj.v1",
)

@worker.command("set_config")
def handle_config(env):
    # env.payload.data contains config
    apply_config(env.payload.data)
    return worker.ack(env, status="ok", applied_config_version=env.payload.config_version)

worker.start()  # spins up ZeroMQ REP + OSC telemetry sender + heartbeat

while True:
    features = compute_features()
    worker.send_telemetry(
        stream="features",
        data=features,
    )
    worker.sleep(0.02)  # 50 fps
```

### Example: TUI
```python
from vj_bus import TuiClient

tui = TuiClient(schema="vj.v1")
tui.load_registry("/tmp/python-vj/process_registry.json")
tui.auto_subscribe()  # ZeroMQ PUB events + OSC telemetry per worker

# send config
resp = tui.command(
    worker="audio_analyzer",
    verb="set_config",
    data={"fft_size": 2048},
    config_version="cfg-2024-09-01",
)

# react to telemetry
@tui.on_telemetry("audio_analyzer", stream="features")
def on_features(env):
    render(env.payload.data)

tui.run()
```

## Testing & integration strategy
- **Unit tests (pytest)** for `vj_bus`:
  - Schema validation, envelope serialization/deserialization for OSC and ZeroMQ paths.
  - Retry logic, heartbeat parsing, and idempotent config application helpers.
  - Use `pytest-asyncio` for async helpers.

- **Integration tests** using temp ports and forked processes:
  - Spin up fake workers (minimal scripts using `vj_bus.WorkerNode`) and a TUI client.
  - Assert workers keep running after TUI exits; restart TUI and verify it re-discovers from registry and receives telemetry.
  - Simulate worker crash; assert process_manager restarts and publishes new generation; TUI resends config and resumes streams.
  - Stress test telemetry: send high-frequency OSC packets, ensure TUI event loop handles without blocking (measure drop rate within acceptable bounds).

- **Fixtures/helpers**:
  - `ports` fixture to allocate ephemeral OSC and ZeroMQ endpoints.
  - `worker_proc` fixture to spawn fake worker via `multiprocessing.Process`.
  - `tui_client` fixture to manage subscriptions and teardown.

- **Dev harness**:
  - `scripts/dev_harness.py` to launch process_manager + all workers + TUI in one terminal session; supports `--kill worker` to test restarts.
  - Optional `docker-compose` or `justfile` to run the stack with mounted `/tmp/python-vj` for registry/IPC sockets.

## Concrete recommendations
- Use **OSC for high-volume telemetry** and **ZeroMQ for control/config + reliable events**. This balances low-latency streaming with reliable orchestration and reconnection semantics. Pure OSC would require custom reliability/replay and backpressure handling, while pure ZeroMQ would add unnecessary overhead for very high-rate telemetry.
- Standardize on the `Envelope` schema across transports to simplify tooling, logging, and future migrations.

## Iterative implementation plan
Progress tracker (checked items are validated by automated tests in `tests/`):

- [x] Introduce `vj_bus` library with envelopes, OSC encoding, ZeroMQ helpers, and REQ/REP + PUB/SUB utilities (see `tests/test_vj_bus.py`).
- [x] Validate worker heartbeats, multi-worker event subscriptions, and command/ack loops against the TUI client helpers (see `tests/test_python_vj.py`).
- [x] process_manager integration (spawn workers via supervisor, registry file + PUB channel) — validated via registry + restart test.
- [x] Workers adopt `vj_bus` end-to-end (per-worker config replay, telemetry plumbing) — lyrics + osc debugger workers implemented.
- [x] TUI discovery and reconnection over registry/PUB/OSC with state sync — basic worker bus adapter wired into `vj_console.py`.
- [x] Failure drills & stress (crash/restart, telemetry flood behavior) — covered by multi-worker restart, TUI restart, and OSC stress tests.
- [x] Polish & monitoring (logging/metrics exporters, registry CLI, telemetry rate limiting) — baseline registry writer + PUB broadcast in process_manager with restart coverage.

1. **Introduce `vj_bus` library**
   - Add models for `Envelope`/payloads, OSC encode/decode, and ZeroMQ sockets with basic REQ/REP + PUB/SUB helpers.
   - Tests: serialization, validation, simple request/reply loopback.
   - Manual: run sample worker + client scripts exchanging commands.

2. **process_manager integration**
   - Update `process_manager.py` to spawn workers as subprocesses, write registry file, and expose ZeroMQ PUB for registration/events.
   - Tests: worker launch/restart, registry file contents.
   - Manual: start process_manager, kill a worker, observe restart + registry update.

3. **Workers adopt `vj_bus`**
   - Migrate each worker to use WorkerNode helpers for control/telemetry and heartbeats.
   - Tests: per-worker config application via REQ/REP; telemetry reception via OSC mock client.
   - Manual: start audio_analyzer, send config, observe telemetry in osc_debugger.

4. **TUI discovery and reconnection**
   - Update TUI to read registry, subscribe to PUB/OSC, and issue `state_sync` + idempotent config replay on startup.
   - Tests: TUI restart scenario with existing workers; ensure config_version stability.
   - Manual: start TUI, kill/restart it while workers run; verify live data resumes.

5. **Failure drills & stress**
   - Add integration tests for worker crash/restart generation handling and telemetry flood behavior.
   - Manual: run `dev_harness.py`, simulate crashes, confirm reconnection and minimal packet loss.

6. **Polish & monitoring**
   - Add logging/metrics exporters, CLI tools for registry inspection, and configurable rate limiting for telemetry.
   - Tests: heartbeat drop detection triggers reconnect/restart commands as expected.
