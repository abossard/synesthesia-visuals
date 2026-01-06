"""Process monitoring service for tracking CPU and memory usage."""

from dataclasses import dataclass
from typing import Dict, List, Optional

import psutil


@dataclass
class ProcessStats:
    """Statistics for a single process."""
    pid: int
    name: str
    cpu_percent: float
    memory_mb: float
    running: bool = True


class ProcessMonitor:
    """
    Efficient process monitor that caches Process handles.
    Call get_stats() periodically (e.g., every 5 seconds) for low overhead.
    Uses non-blocking cpu_percent(interval=None) which compares to last call.
    """

    def __init__(self, process_names: List[str]):
        self.targets = {n.lower(): n for n in process_names}
        self._cache: Dict[str, psutil.Process] = {}

    def _find_process(self, target_key: str) -> Optional[psutil.Process]:
        """Find or return cached process handle."""
        # Check cache first
        if target_key in self._cache:
            try:
                proc = self._cache[target_key]
                if proc.is_running():
                    return proc
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass
            del self._cache[target_key]

        # Search for process by name
        for proc in psutil.process_iter(['pid', 'name']):
            try:
                pname = proc.info['name'].lower()
                if target_key in pname or pname in target_key:
                    self._cache[target_key] = proc
                    # Initialize CPU tracking (first call always returns 0)
                    try:
                        proc.cpu_percent()
                    except (psutil.NoSuchProcess, psutil.AccessDenied):
                        pass
                    return proc
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                continue
        return None

    def get_stats(self) -> Dict[str, Optional[ProcessStats]]:
        """
        Get stats for all tracked processes.
        Returns dict mapping original name -> ProcessStats or None if not running.
        """
        results = {}
        for target_key, original_name in self.targets.items():
            proc = self._find_process(target_key)
            if proc:
                try:
                    stats = ProcessStats(
                        pid=proc.pid,
                        name=proc.name(),
                        cpu_percent=proc.cpu_percent(interval=None),  # Non-blocking
                        memory_mb=proc.memory_info().rss / (1024 * 1024),
                        running=True
                    )
                    results[original_name] = stats
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    results[original_name] = None
            else:
                results[original_name] = None
        return results
