#!/usr/bin/env python3
"""Simple OSC logger for Synesthesia Live Pro audio engine output."""

import argparse
import logging
import signal
import sys
from pathlib import Path
from typing import Any

from pythonosc.dispatcher import Dispatcher
from pythonosc.osc_server import ThreadingOSCUDPServer


def _format_arg(arg: Any) -> str:
    """Normalize OSC argument output for logging."""
    if isinstance(arg, bytes):
        try:
            return arg.decode("utf-8", errors="replace")
        except Exception:
            return repr(arg)
    if isinstance(arg, float):
        return f"{arg:.6f}"
    return str(arg)


def _build_dispatcher(address_prefix: str | None) -> Dispatcher:
    dispatcher = Dispatcher()

    def _log_message(address: str, *osc_args: object) -> None:
        if address_prefix and not address.startswith(address_prefix):
            return
        message = " ".join(_format_arg(arg) for arg in osc_args)
        logging.info("%s %s", address, message)

    dispatcher.set_default_handler(_log_message)
    return dispatcher


def _configure_logging(level: str, log_file: Path | None) -> None:
    handlers = [logging.StreamHandler(sys.stdout)]
    if log_file:
        log_file.parent.mkdir(parents=True, exist_ok=True)
        handlers.append(logging.FileHandler(log_file, encoding="utf-8"))
    logging.basicConfig(
        level=getattr(logging, level.upper(), logging.INFO),
        format="%(asctime)s %(levelname)s %(message)s",
        handlers=handlers,
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Listen for OSC messages from Synesthesia Live Pro and log them",
    )
    parser.add_argument(
        "--host",
        default="127.0.0.1",
        help="Local interface to bind (default: 127.0.0.1)",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=9999,
        help="UDP port to receive OSC on (default: 9999)",
    )
    parser.add_argument(
        "--prefix",
        default=None,
        help="Optional OSC address prefix filter (e.g. /audio)",
    )
    parser.add_argument(
        "--log-file",
        type=Path,
        default=None,
        help="Optional path to append detailed logs",
    )
    parser.add_argument(
        "--log-level",
        default="INFO",
        help="Logging level (DEBUG, INFO, WARNING, ERROR)",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    _configure_logging(args.log_level, args.log_file)

    dispatcher = _build_dispatcher(args.prefix)
    server = ThreadingOSCUDPServer((args.host, args.port), dispatcher)

    logging.info("Listening for OSC on %s:%s", args.host, args.port)
    if args.prefix:
        logging.info("Filtering addresses starting with: %s", args.prefix)
    if args.log_file:
        logging.info("Appending raw log to %s", args.log_file.resolve())

    def _shutdown_handler(signum, _frame):
        logging.info("Received signal %s, shutting down", signum)
        server.shutdown()

    signal.signal(signal.SIGINT, _shutdown_handler)
    signal.signal(signal.SIGTERM, _shutdown_handler)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logging.info("Interrupted, closing server")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
