import threading
from typing import Any, Callable, Dict

import zmq

from pythonosc import dispatcher as osc_dispatcher
from pythonosc import osc_server

from .models import Envelope, EnvelopeBuilder
from .osc_helpers import decode_osc_envelope
from .zmq_helpers import recv_envelope, subscribe, ZmqContextSingleton


class TuiClient:
    def __init__(self, schema: str = "vj.v1") -> None:
        self.schema = schema
        self._osc_handlers: Dict[str, Callable[[Envelope], None]] = {}
        self._event_callbacks: Dict[str, Callable[[Envelope], None]] = {}
        self._stop_event = threading.Event()
        self._threads: Dict[str, threading.Thread] = {}
        self._event_sockets: Dict[str, zmq.Socket] = {}
        self._osc_servers: Dict[int, osc_server.ThreadingOSCUDPServer] = {}

    def on_telemetry(self, worker: str, stream: str):
        def decorator(func: Callable[[Envelope], None]):
            key = f"/vj/{worker}/{stream}/{self.schema}"
            self._osc_handlers[key] = func
            return func

        return decorator

    def on_event(self, worker: str, callback: Callable[[Envelope], None]):
        self._event_callbacks[worker] = callback

    def _osc_handler(self, address: str, *args: Any) -> None:
        env = decode_osc_envelope(address, *args)
        handler = self._osc_handlers.get(address)
        if handler:
            handler(env)

    def start_osc_listener(self, port: int) -> None:
        if port in self._osc_servers:
            return

        disp = osc_dispatcher.Dispatcher()
        disp.set_default_handler(self._osc_handler)
        server = osc_server.ThreadingOSCUDPServer(("0.0.0.0", port), disp)

        def loop():
            server.serve_forever()

        thread = threading.Thread(target=loop, daemon=True)
        thread.start()
        self._threads[f"osc:{port}"] = thread
        self._osc_servers[port] = server

    def stop(self) -> None:
        self._stop_event.set()
        for server in self._osc_servers.values():
            server.shutdown()
        for thread in list(self._threads.values()):
            thread.join(timeout=1.0)
        self._close_event_sockets()
        self._osc_servers.clear()

    def command(self, endpoint: str, envelope: Envelope) -> Envelope:
        context = ZmqContextSingleton.get_context()
        socket = context.socket(zmq.REQ)
        socket.linger = 0
        socket.connect(endpoint)
        try:
            socket.send_string(envelope.to_json())
            raw = socket.recv_string()
            return Envelope.from_json(raw)
        finally:
            socket.close()

    def subscribe_events(self, endpoint: str, worker_filter: str | None = None) -> None:
        key = f"events:{endpoint}"
        if key in self._threads:
            return

        socket = subscribe(endpoint)

        def loop():
            while not self._stop_event.is_set():
                try:
                    env = recv_envelope(socket, timeout_ms=200)
                except zmq.error.ZMQError:
                    break
                if env is None:
                    continue
                if worker_filter and env.worker != worker_filter:
                    continue
                cb = self._event_callbacks.get(env.worker)
                if cb and env.type in {"event", "heartbeat"}:
                    cb(env)

        thread = threading.Thread(target=loop, daemon=True)
        thread.start()
        self._threads[key] = thread
        self._event_sockets[key] = socket

    def send_state_sync(self, endpoint: str, worker: str, state: Dict[str, Any]) -> Envelope:
        builder = EnvelopeBuilder(schema=self.schema, worker=worker)
        env = builder.state_sync(config_version=state.get("config_version"), state=state)
        return self.command(endpoint, env)

    def _close_event_sockets(self) -> None:
        for socket in self._event_sockets.values():
            socket.close(0)
        self._event_sockets.clear()

    # Registry helpers
    def load_registry(self, path: str) -> Dict[str, Dict[str, Any]]:
        import json
        from pathlib import Path

        p = Path(path)
        if not p.exists():
            return {}
        data = json.loads(p.read_text())
        return data.get("workers", {}) if isinstance(data, dict) else {}

    def subscribe_from_registry(self, registry: Dict[str, Dict[str, Any]]) -> None:
        for name, meta in registry.items():
            events = meta.get("events")
            telemetry = meta.get("telemetry")
            if events:
                self.subscribe_events(events, worker_filter=name)
            if telemetry:
                self.start_osc_listener(int(telemetry))
