"""
E2E tests for Module Registry.

Run with: pytest tests/modules/test_registry.py -v -s
"""


class TestRegistryLifecycle:
    """Test Module Registry lifecycle."""

    def test_registry_starts_and_stops_cleanly(self):
        """Registry starts all modules and stops cleanly."""
        from modules import ModuleRegistry

        registry = ModuleRegistry()

        assert not registry.is_started

        success = registry.start_all()
        assert success, "Registry should start successfully"
        assert registry.is_started

        # Check core modules started
        status = registry.get_status()
        assert status["started"] is True
        assert "osc" in status["modules"]
        assert "playback" in status["modules"]

        registry.stop_all()
        assert not registry.is_started

        print("\nRegistry started and stopped cleanly")

    def test_modules_lazy_load(self):
        """Modules are created on first access."""
        from modules import ModuleRegistry

        registry = ModuleRegistry()

        # Before starting, internal modules are None
        assert registry._osc is None
        assert registry._playback is None

        # Accessing property creates the module
        osc = registry.osc
        assert osc is not None
        assert registry._osc is not None

        print("\nModules lazy-load correctly")

    def test_pipeline_processes_track(self, requires_internet, requires_lm_studio):
        """Registry can process a track through pipeline."""
        from modules import ModuleRegistry

        registry = ModuleRegistry()
        registry.start_all()

        result = registry.process_track("Queen", "Bohemian Rhapsody")

        assert result is not None
        assert result.artist == "Queen"
        assert result.title == "Bohemian Rhapsody"

        registry.stop_all()

        print(f"\nPipeline result: {result.steps_completed}")


class TestRegistryConfig:
    """Test registry configuration."""

    def test_custom_config(self):
        """Registry accepts custom configuration."""
        from modules import ModuleRegistry, ModuleRegistryConfig

        config = ModuleRegistryConfig(
            playback_source="spotify_applescript",
            skip_images=True,
        )

        registry = ModuleRegistry(config)

        assert registry._config.playback_source == "spotify_applescript"
        assert registry._config.skip_images is True

        print("\nCustom config accepted")


class TestRegistryStandalone:
    """Test registry can be used standalone."""

    def test_registry_importable(self):
        """Registry can be imported from modules package."""
        from modules import ModuleRegistry, ModuleRegistryConfig

        assert ModuleRegistry is not None
        assert ModuleRegistryConfig is not None

        print("\nRegistry imports successfully")
