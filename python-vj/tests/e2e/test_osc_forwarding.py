"""
E2E tests for OSC hub forwarding and subscription dispatch.
"""

import time
import threading

import pytest

try:
    import pyliblo3 as liblo
except ImportError:
    liblo = None


def _wait_for(predicate, timeout: float = 1.0) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(0.01)
    return False


def _start_server(port: int, bucket: list):
    try:
        server = liblo.ServerThread(port)
    except liblo.ServerError as exc:
        pytest.skip(f"Port {port} unavailable: {exc}")

    def _handler(path, args, _types, _src):
        bucket.append((path, list(args)))

    server.add_method(None, None, _handler)
    server.start()
    return server


@pytest.fixture
def hub():
    if liblo is None:
        pytest.skip("pyliblo3 not installed")
    from osc import osc
    if not osc.start():
        pytest.skip("Hub could not bind to port 9999")
    yield osc
    osc.stop()


def test_hub_forwards_to_targets(hub):
    forwarded_10000 = []
    forwarded_11111 = []
    server_10000 = _start_server(10000, forwarded_10000)
    server_11111 = _start_server(11111, forwarded_11111)

    try:
        liblo.send(("127.0.0.1", 9999), "/test/forward", 7, "ok")
        assert _wait_for(lambda: forwarded_10000 and forwarded_11111), (
            "Forwarding timeout: expected messages on both 10000 and 11111"
        )
        assert forwarded_10000[0][0] == "/test/forward"
        assert forwarded_11111[0][0] == "/test/forward"
        assert forwarded_10000[0][1] == [7, "ok"]
        assert forwarded_11111[0][1] == [7, "ok"]
    finally:
        server_10000.stop()
        server_11111.stop()


def test_hub_dispatches_to_subscribers(hub):
    received = []
    event = threading.Event()

    def _handler(path, args):
        received.append((path, list(args)))
        event.set()

    hub.subscribe("/test/sub/*", _handler)
    try:
        liblo.send(("127.0.0.1", 9999), "/test/sub/one", 3.14)
        assert event.wait(1.0), "Subscriber did not receive message"
        assert received[0][0] == "/test/sub/one"
        assert received[0][1][0] == pytest.approx(3.14)
    finally:
        hub.unsubscribe("/test/sub/*", _handler)
