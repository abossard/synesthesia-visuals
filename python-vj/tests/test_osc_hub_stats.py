import time

import pytest

try:
    import pyliblo3 as liblo
except ImportError:
    liblo = None

if liblo is None:
    pytest.skip("pyliblo3 not installed", allow_module_level=True)

from osc.hub import OSCHub, QUEUE_MAXSIZE


def _wait_for(predicate, timeout: float = 0.5) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(0.01)
    return False


def test_hub_stats_only_when_enabled():
    hub = OSCHub()
    hub._start_worker()
    try:
        hub._on_message("/test/one", [1], None, None)
        time.sleep(0.05)
        assert hub.get_hub_stats() == {}

        hub.set_stats_enabled(True)
        hub._on_message("/test/two", [2], None, None)

        assert _wait_for(lambda: hub.get_hub_stats().get("processed", 0) >= 1)
        stats = hub.get_hub_stats()
        assert stats["queue_capacity"] == QUEUE_MAXSIZE
        assert stats["queue_latency_samples"] >= 1
    finally:
        hub._stop_worker()
