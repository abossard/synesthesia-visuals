import threading
import time
from typing import Any, Callable, Dict, Optional

from .models import Envelope, EnvelopeBuilder
from .osc_helpers import make_osc_client, osc_send
from .utils import generate_instance_id, now_ts
from .zmq_helpers import publish, serve_rep, start_pub


class WorkerNode:
    def __init__(
        self,
        name: str,
        telemetry_port: int,
        command_endpoint: str,
        event_endpoint: str,
        schema: str = "vj.v1",
        heartbeat_interval: float = 2.0,
        generation: int = 0,
        instance_id: str | None = None,
    ) -> None:
        self.name = name
        self.schema = schema
        self.telemetry_port = telemetry_port
        self.command_endpoint = command_endpoint
        self.event_endpoint = event_endpoint
        self.instance_id = instance_id or generate_instance_id()
        self.generation = generation
        self._builder = EnvelopeBuilder(
            schema=schema, worker=name, instance_id=self.instance_id, generation=generation
        )
        self._handlers: Dict[str, Callable[[Envelope], Envelope]] = {}
        self._stop_event = threading.Event()
        self._threads: Dict[str, threading.Thread] = {}
        self._telemetry_client = make_osc_client("127.0.0.1", telemetry_port)
        self._event_socket = None
        self._heartbeat_interval = heartbeat_interval
        self._started_at = time.time()

    def command(self, verb: str):
        def wrapper(func: Callable[[Envelope], Envelope]):
            self._handlers[verb] = func
            return func

        return wrapper

    def start(self) -> None:
        self._event_socket = start_pub(self.event_endpoint)
        self._start_command_thread()
        self._start_heartbeat_thread()
        self.send_event("info", "worker_started", details={"generation": self.generation})

    def _start_command_thread(self) -> None:
        def dispatch(request: Envelope) -> Envelope:
            handler = self._handlers.get(request.payload.verb) if hasattr(request.payload, "verb") else None
            if handler:
                return handler(request)
            return self._builder.ack(request, status="error", message=f"unknown verb {getattr(request.payload, 'verb', '')}")

        thread = threading.Thread(
            target=serve_rep, args=(self.command_endpoint, dispatch, self._stop_event), daemon=True
        )
        thread.start()
        self._threads["command"] = thread

    def _start_heartbeat_thread(self) -> None:
        def loop():
            while not self._stop_event.wait(self._heartbeat_interval):
                uptime = time.time() - self._started_at
                hb = self._builder.heartbeat(cpu=0.0, mem=0.0, uptime_sec=uptime)
                publish(self._event_socket, hb)

        thread = threading.Thread(target=loop, daemon=True)
        thread.start()
        self._threads["heartbeat"] = thread

    def send_telemetry(self, stream: str, data: Any) -> None:
        envelope = self._builder.telemetry(stream=stream, data=data)
        osc_send(self._telemetry_client, envelope)

    def send_event(self, level: str, message: str, details: Optional[Dict[str, Any]] = None) -> None:
        envelope = self._builder.event(level=level, message=message, details=details)
        publish(self._event_socket, envelope)

    def ack(self, request: Envelope, status: str, message: str = "", applied_config_version: Optional[str] = None) -> Envelope:
        return self._builder.ack(request, status=status, message=message, applied_config_version=applied_config_version)

    def stop(self) -> None:
        self._stop_event.set()
        for thread in self._threads.values():
            thread.join(timeout=1.0)
        if self._event_socket:
            self._event_socket.close(0)

    def sleep(self, seconds: float) -> None:
        time.sleep(seconds)

    def state_sync(self, state: Dict[str, Any]) -> Envelope:
        return self._builder.state_sync(config_version=state.get("config_version"), state=state)

    @property
    def started_at(self) -> str:
        return now_ts()

    def run_forever(self) -> None:
        """Block the current thread, keeping the worker alive until stop() is called."""
        try:
            while not self._stop_event.wait(0.1):
                pass
        finally:
            self.stop()
