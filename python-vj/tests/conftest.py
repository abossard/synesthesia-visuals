"""
Test prerequisites with interactive prompts.

Tests prompt the user to set up the required environment and press Enter when ready.
When running non-interactively, tests that need prompts are skipped.
Once confirmed, requirements are cached for the session.
"""
import pytest
import subprocess
import socket
import sys
import os

# Cache for confirmed requirements (session-scoped)
_confirmed_requirements: dict[str, bool] = {}
_cached_data: dict[str, any] = {}


def is_interactive() -> bool:
    """Check if we're running in an interactive terminal."""
    return sys.stdin.isatty() and os.environ.get("CI") != "true"


def is_port_open(port: int) -> bool:
    """Check if a port is accepting connections."""
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=1):
            return True
    except (socket.timeout, ConnectionRefusedError, OSError):
        return False


def is_process_running(name: str) -> bool:
    """Check if a process is running by name."""
    try:
        result = subprocess.run(
            ["pgrep", "-f", name],
            capture_output=True,
            timeout=5
        )
        return result.returncode == 0
    except Exception:
        return False


def prompt_user(requirement_key: str, requirements: list[str]) -> bool:
    """
    Prompt user to set up prerequisites.
    Returns True if user is ready, False to skip.
    In non-interactive mode, returns False (skip).
    Once confirmed, the requirement is cached for the session.
    """
    # Check cache first
    if requirement_key in _confirmed_requirements:
        return _confirmed_requirements[requirement_key]

    if not is_interactive():
        return False

    print(f"\n{'='*60}")
    print(f"=== Setup Required: {requirement_key} ===")
    print("Requirements:")
    for req in requirements:
        print(f"  - {req}")
    print()

    response = input("Press Enter when ready (or 's' to skip): ")
    confirmed = response.lower() != 's'

    # Cache the result
    _confirmed_requirements[requirement_key] = confirmed
    return confirmed


@pytest.fixture
def requires_vdj_running(request):
    """Prompt user to start VirtualDJ."""
    if not is_process_running("VirtualDJ"):
        ready = prompt_user(
            "vdj_running",
            ["VirtualDJ running"]
        )
        if not ready:
            pytest.skip("User skipped - VirtualDJ not running")

        if not is_process_running("VirtualDJ"):
            pytest.skip("VirtualDJ still not detected")


@pytest.fixture
def requires_vdj_playing(request):
    """Prompt user to play music in VirtualDJ."""
    # Return cached track if available
    if "vdj_track" in _cached_data:
        return _cached_data["vdj_track"]

    ready = prompt_user(
        "vdj_playing",
        ["VirtualDJ running", "Music playing on Deck 1"]
    )
    if not ready:
        pytest.skip("User skipped - VDJ not playing")

    # Try to get track info using VDJMonitor
    try:
        from vdj_monitor import VDJMonitor
        import time

        monitor = VDJMonitor()
        monitor.start()

        # Wait for track info
        track = None
        for _ in range(10):
            state = monitor.get_playback()
            if state and state.get("artist") and state.get("title"):
                track = {"artist": state["artist"], "title": state["title"]}
                break
            time.sleep(0.3)

        monitor.stop()

        if track:
            _cached_data["vdj_track"] = track
            return track
        else:
            pytest.skip("Could not detect playing track from VDJ")
    except Exception as e:
        pytest.skip(f"VDJ query failed: {e}")


@pytest.fixture
def requires_synesthesia(request):
    """Prompt user to start Synesthesia."""
    if not is_process_running("Synesthesia"):
        ready = prompt_user(
            "synesthesia",
            ["Synesthesia running"]
        )
        if not ready:
            pytest.skip("User skipped - Synesthesia not running")

        if not is_process_running("Synesthesia"):
            pytest.skip("Synesthesia still not detected")


@pytest.fixture
def requires_lm_studio(request):
    """Prompt user to start LM Studio."""
    if not is_port_open(1234):
        ready = prompt_user(
            "lm_studio",
            ["LM Studio running", "API server on port 1234"]
        )
        if not ready:
            pytest.skip("User skipped - LM Studio not running")

        if not is_port_open(1234):
            pytest.skip("LM Studio API still not available on port 1234")


@pytest.fixture
def requires_vjuniverse(request):
    """Prompt user to start VJUniverse (Processing)."""
    if not is_port_open(10000):
        ready = prompt_user(
            "vjuniverse",
            ["VJUniverse (Processing) running", "Listening on port 10000"]
        )
        if not ready:
            pytest.skip("User skipped - VJUniverse not running")

        if not is_port_open(10000):
            pytest.skip("VJUniverse still not listening on port 10000")


@pytest.fixture
def requires_osc_ports_free():
    """Check OSC ports are available. Run 'make kill-osc' first if port is busy."""
    for port in [9999]:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.bind(("127.0.0.1", port))
            s.close()
        except OSError:
            pytest.skip(f"Port {port} in use. Run 'make kill-osc' first.")


@pytest.fixture
def requires_internet():
    """Check internet connectivity (no prompt needed)."""
    try:
        socket.create_connection(("lrclib.net", 443), timeout=5)
    except (socket.timeout, OSError):
        pytest.skip("No internet connection")
