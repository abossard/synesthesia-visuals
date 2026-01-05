"""Base module class for VJ system modules."""
from abc import ABC, abstractmethod
from typing import Any, Dict


class Module(ABC):
    """
    Base class for all VJ system modules.

    Modules follow a simple lifecycle:
    - __init__(config) - Construct with configuration
    - start() - Start background processing
    - stop() - Clean shutdown

    Modules can be run standalone via CLI for testing/debugging.
    """

    def __init__(self):
        self._started = False

    @property
    def is_started(self) -> bool:
        return self._started

    @abstractmethod
    def start(self) -> bool:
        """Start the module. Returns True on success."""
        pass

    @abstractmethod
    def stop(self) -> None:
        """Stop the module and clean up resources."""
        pass

    def get_status(self) -> Dict[str, Any]:
        """Get module status for monitoring."""
        return {"started": self._started}
