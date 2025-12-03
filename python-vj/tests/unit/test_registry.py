"""
Unit tests for service registry.
"""

import pytest
import time
import tempfile
from pathlib import Path

from vj_bus.registry import ServiceRegistry


@pytest.fixture
def temp_registry():
    """Create a temporary registry for testing."""
    with tempfile.TemporaryDirectory() as tmpdir:
        registry = ServiceRegistry(registry_dir=Path(tmpdir))
        yield registry


class TestServiceRegistry:
    """Test ServiceRegistry."""

    def test_register_service(self, temp_registry):
        """Service can be registered."""
        temp_registry.register_service(
            name="test_worker",
            pid=12345,
            command_port=5001,
            telemetry_port=5002,
            metadata={"version": "1.0"}
        )

        services = temp_registry.get_services()
        assert "test_worker" in services
        assert services["test_worker"]["pid"] == 12345
        assert services["test_worker"]["ports"]["command"] == 5001
        assert services["test_worker"]["metadata"]["version"] == "1.0"

    def test_unregister_service(self, temp_registry):
        """Service can be unregistered."""
        temp_registry.register_service(
            name="test_worker",
            pid=12345,
            command_port=5001,
            telemetry_port=5002
        )

        temp_registry.unregister_service("test_worker")

        services = temp_registry.get_services()
        assert "test_worker" not in services

    def test_update_heartbeat(self, temp_registry):
        """Heartbeat timestamp can be updated."""
        temp_registry.register_service(
            name="test_worker",
            pid=12345,
            command_port=5001,
            telemetry_port=5002
        )

        # Get initial heartbeat
        service = temp_registry.get_service("test_worker")
        initial_heartbeat = service["heartbeat_at"]

        # Wait and update
        time.sleep(0.1)
        temp_registry.update_heartbeat("test_worker")

        # Check heartbeat updated
        service = temp_registry.get_service("test_worker")
        assert service["heartbeat_at"] > initial_heartbeat

    def test_get_service(self, temp_registry):
        """Get specific service."""
        temp_registry.register_service(
            name="worker_a",
            pid=1,
            command_port=5001,
            telemetry_port=5002
        )
        temp_registry.register_service(
            name="worker_b",
            pid=2,
            command_port=5011,
            telemetry_port=5012
        )

        service = temp_registry.get_service("worker_a")
        assert service is not None
        assert service["pid"] == 1

    def test_get_service_not_found(self, temp_registry):
        """Get non-existent service returns None."""
        service = temp_registry.get_service("nonexistent")
        assert service is None

    def test_is_service_healthy(self, temp_registry):
        """Health check based on heartbeat."""
        temp_registry.register_service(
            name="test_worker",
            pid=12345,
            command_port=5001,
            telemetry_port=5002
        )

        # Should be healthy immediately after registration
        assert temp_registry.is_service_healthy("test_worker")

    def test_stale_service(self, temp_registry):
        """Stale services are detected."""
        # Register with old heartbeat (hack the registry file)
        temp_registry.register_service(
            name="stale_worker",
            pid=12345,
            command_port=5001,
            telemetry_port=5002
        )

        # Manually set old heartbeat
        with temp_registry._lock_registry():
            registry_data = temp_registry._read_registry()
            registry_data["services"]["stale_worker"]["heartbeat_at"] = time.time() - 20.0  # 20 seconds ago
            temp_registry._write_registry(registry_data)

        # Should not be healthy
        assert not temp_registry.is_service_healthy("stale_worker")

    def test_get_services_exclude_stale(self, temp_registry):
        """Can filter out stale services."""
        # Register healthy worker
        temp_registry.register_service(
            name="healthy_worker",
            pid=1,
            command_port=5001,
            telemetry_port=5002
        )

        # Register stale worker
        temp_registry.register_service(
            name="stale_worker",
            pid=2,
            command_port=5011,
            telemetry_port=5012
        )

        # Make stale
        with temp_registry._lock_registry():
            registry_data = temp_registry._read_registry()
            registry_data["services"]["stale_worker"]["heartbeat_at"] = time.time() - 20.0
            temp_registry._write_registry(registry_data)

        # Get services excluding stale
        services = temp_registry.get_services(include_stale=False)
        assert "healthy_worker" in services
        assert "stale_worker" not in services

    def test_cleanup_stale_services(self, temp_registry):
        """Cleanup marks stale services as crashed."""
        temp_registry.register_service(
            name="test_worker",
            pid=12345,
            command_port=5001,
            telemetry_port=5002
        )

        # Make stale
        with temp_registry._lock_registry():
            registry_data = temp_registry._read_registry()
            registry_data["services"]["test_worker"]["heartbeat_at"] = time.time() - 20.0
            temp_registry._write_registry(registry_data)

        # Cleanup
        temp_registry.cleanup_stale_services()

        # Check status
        service = temp_registry.get_service("test_worker")
        assert service["status"] == "crashed"

    def test_concurrent_access(self, temp_registry):
        """Registry handles concurrent access via file locking."""
        import threading

        def register_worker(worker_id):
            temp_registry.register_service(
                name=f"worker_{worker_id}",
                pid=worker_id,
                command_port=5000 + worker_id,
                telemetry_port=5100 + worker_id
            )

        # Register 10 workers concurrently
        threads = [threading.Thread(target=register_worker, args=(i,)) for i in range(10)]

        for t in threads:
            t.start()

        for t in threads:
            t.join()

        # All workers should be registered
        services = temp_registry.get_services()
        assert len(services) == 10
