import multiprocessing
import sys
from pathlib import Path

# Set multiprocessing start method to 'spawn' to prevent fork safety issues.
# The 'fork' method can cause deadlocks when forking multi-threaded processes,
# particularly in CI environments and when running tests that use ZMQ/threading.
try:
    multiprocessing.set_start_method('spawn', force=True)
except RuntimeError:
    # Already set, ignore
    pass

# Ensure project root on path for module imports
ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
