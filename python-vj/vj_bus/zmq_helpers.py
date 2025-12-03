import threading
from typing import Callable, Optional

import zmq

from .models import Envelope
from .utils import json_dumps


class ZmqContextSingleton:
    _context: Optional[zmq.Context] = None
    _lock = threading.Lock()

    @classmethod
    def get_context(cls) -> zmq.Context:
        with cls._lock:
            if cls._context is None:
                cls._context = zmq.Context.instance()
            return cls._context


def serve_rep(endpoint: str, handler: Callable[[Envelope], Envelope], stop_event: threading.Event) -> None:
    context = ZmqContextSingleton.get_context()
    socket = context.socket(zmq.REP)
    socket.linger = 0
    socket.bind(endpoint)
    poller = zmq.Poller()
    poller.register(socket, zmq.POLLIN)
    try:
        while not stop_event.is_set():
            events = dict(poller.poll(timeout=100))
            if socket in events:
                raw = socket.recv_string()
                envelope = Envelope.from_json(raw)
                reply = handler(envelope)
                socket.send_string(reply.to_json())
    finally:
        socket.close()


def start_pub(endpoint: str):
    context = ZmqContextSingleton.get_context()
    socket = context.socket(zmq.PUB)
    socket.linger = 0
    socket.bind(endpoint)
    return socket


def publish(socket, envelope: Envelope) -> None:
    socket.send_multipart([
        envelope.worker.encode(),
        json_dumps(envelope.to_dict()).encode(),
    ])


def subscribe(endpoint: str, topic: bytes = b""):
    context = ZmqContextSingleton.get_context()
    socket = context.socket(zmq.SUB)
    socket.linger = 0
    socket.connect(endpoint)
    socket.setsockopt(zmq.SUBSCRIBE, topic)
    return socket


def recv_envelope(socket, timeout_ms: int = 1000) -> Optional[Envelope]:
    poller = zmq.Poller()
    poller.register(socket, zmq.POLLIN)
    events = dict(poller.poll(timeout=timeout_ms))
    if socket not in events:
        return None
    _topic, payload = socket.recv_multipart()
    return Envelope.from_json(payload.decode())
