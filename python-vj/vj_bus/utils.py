import json
import socket
import time
import uuid
from contextlib import closing
from typing import Any


def now_ts() -> str:
    """Return RFC3339-like UTC timestamp string."""
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def generate_instance_id() -> str:
    return str(uuid.uuid4())


def find_free_port() -> int:
    with closing(socket.socket(socket.AF_INET, socket.SOCK_STREAM)) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def json_dumps(data: Any) -> str:
    return json.dumps(data, separators=(",", ":"), sort_keys=True)


def json_loads(data: str) -> Any:
    return json.loads(data)
