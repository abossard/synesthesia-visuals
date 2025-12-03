from typing import Any, List

from pythonosc import dispatcher as osc_dispatcher
from pythonosc import osc_server, udp_client

from .models import Envelope
from .utils import json_dumps


def build_osc_address(envelope: Envelope) -> str:
    if envelope.type == "telemetry":
        stream = getattr(envelope.payload, "stream", "generic")
        return f"/vj/{envelope.worker}/{stream}/{envelope.schema}"
    if envelope.type == "command":
        verb = getattr(envelope.payload, "verb", "noop")
        return f"/vj/{envelope.worker}/cmd/{envelope.schema}/{verb}"
    return f"/vj/{envelope.worker}/{envelope.type}/{envelope.schema}"


def encode_osc_args(envelope: Envelope) -> List[Any]:
    return [json_dumps(envelope.to_dict())]


def decode_osc_envelope(address: str, *osc_args: Any) -> Envelope:
    raw = str(osc_args[0]) if osc_args else "{}"
    return Envelope.from_json(raw)


def make_osc_client(host: str, port: int) -> udp_client.SimpleUDPClient:
    return udp_client.SimpleUDPClient(host, port)


def make_osc_server(host: str, port: int, handler) -> osc_server.ThreadingOSCUDPServer:
    disp = osc_dispatcher.Dispatcher()
    disp.set_default_handler(handler)
    return osc_server.ThreadingOSCUDPServer((host, port), disp)


def osc_send(client: udp_client.SimpleUDPClient, envelope: Envelope) -> None:
    client.send_message(build_osc_address(envelope), encode_osc_args(envelope))


def osc_send_raw(host: str, port: int, address: str, *args: Any) -> None:
    """Send a raw OSC message for debugging/capture workers."""
    client = udp_client.SimpleUDPClient(host, port)
    client.send_message(address, list(args) if args else [])
