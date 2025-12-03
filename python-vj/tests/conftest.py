import multiprocessing
import sys
from pathlib import Path

# Ensure project root on path for module imports
ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

# Set multiprocessing start method to 'spawn' to avoid fork() issues with threads
# This must be done before any multiprocessing code is imported
try:
    multiprocessing.set_start_method('spawn', force=True)
except RuntimeError:
    # Already set, ignore
    pass
