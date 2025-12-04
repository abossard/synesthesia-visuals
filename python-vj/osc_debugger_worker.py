"""OSC Debugger Worker.

Listens for OSC traffic on a capture port, mirrors messages into telemetry, and
supports a REQ command to dump the buffered messages. Intended for local
debugging and for exercising the vj_bus IPC flows.
"""

import threading
import time
from collections import deque
from typing import Any, Deque, List, Tuple

from pythonosc import dispatcher as osc_dispatcher
from pythonosc import osc_server

from vj_bus import Envelope, WorkerNode
from vj_bus.osc_helpers import osc_send_raw


class OSCDebuggerWorker:
    def __init__(
        self,
        capture_port: int,
        telemetry_port: int,
        command_endpoint: str,
        event_endpoint: str,
        buffer_size: int = 128,
        schema: str = "vj.v1",
        generation: int = 0,
        instance_id: str | None = None,
    ) -> None:
        self.buffer: Deque[Tuple[float, str, List[Any]]] = deque(maxlen=buffer_size)
        self.node = WorkerNode(
            name="osc_debugger",
            telemetry_port=telemetry_port,
            command_endpoint=command_endpoint,
            event_endpoint=event_endpoint,
            schema=schema,
            heartbeat_interval=0.5,
            generation=generation,
            instance_id=instance_id,
        )
        self.capture_port = capture_port
        self._capture_thread: threading.Thread | None = None
        self._server: osc_server.ThreadingOSCUDPServer | None = None

        @self.node.command("dump")
        def _dump(env: Envelope) -> Envelope:  # noqa: ANN001
            self._flush_to_telemetry()
            return self.node.ack(
                env,
                status="ok",
                message=f"dumped {len(self.buffer)} messages",
                applied_config_version=env.payload.config_version,
            )

    def start(self) -> None:
        self.node.start()
        self._start_capture_server()

    def stop(self) -> None:
        self.node.stop()
        if self._server:
            self._server.shutdown()
        if self._capture_thread:
            self._capture_thread.join(timeout=1.0)

    def _start_capture_server(self) -> None:
        disp = osc_dispatcher.Dispatcher()
        disp.set_default_handler(self._on_message)
        self._server = osc_server.ThreadingOSCUDPServer(("0.0.0.0", self.capture_port), disp)

        def loop():
            if self._server:
                self._server.serve_forever()

        self._capture_thread = threading.Thread(target=loop, daemon=True)
        self._capture_thread.start()

    def _on_message(self, address: str, *args: Any) -> None:
        self.buffer.append((time.time(), address, list(args)))
        self.node.send_telemetry(
            "osc_debug",
            {"address": address, "args": list(args), "count": len(self.buffer)},
        )

    def _flush_to_telemetry(self) -> None:
        snapshot = list(self.buffer)
        self.node.send_telemetry("osc_buffer", {"messages": snapshot})


def demo_debugger() -> None:
    """Simple manual demo used in docs/tests."""
    from vj_bus.utils import find_free_port

    capture_port = find_free_port()
    telemetry_port = find_free_port()
    command_endpoint = f"tcp://127.0.0.1:{find_free_port()}"
    event_endpoint = f"tcp://127.0.0.1:{find_free_port()}"

    worker = OSCDebuggerWorker(
        capture_port=capture_port,
        telemetry_port=telemetry_port,
        command_endpoint=command_endpoint,
        event_endpoint=event_endpoint,
    )
    worker.start()

    osc_send_raw("127.0.0.1", capture_port, "/test", 1, 2, 3)
    time.sleep(0.5)
    worker.node.stop()


if __name__ == "__main__":
    demo_debugger()
