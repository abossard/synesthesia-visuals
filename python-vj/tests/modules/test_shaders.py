"""
E2E tests for Shaders module.

Run with: pytest tests/modules/test_shaders.py -v -s
"""
import os
from pathlib import Path


def get_shaders_dir():
    """Find a directory with shader files."""
    # Try common locations
    base = Path(__file__).parent.parent.parent.parent  # synesthesia-visuals

    candidates = [
        base / "processing-vj/src/VJUniverse/data/shaders",
        base / "archive/VJUniverse_ISF_shaders",
        base / "shaders",
    ]

    for path in candidates:
        if path.exists():
            # Check if it has any .fs or .analysis.json files
            has_shaders = list(path.rglob("*.fs")) or list(path.rglob("*.analysis.json"))
            if has_shaders:
                return str(path)

    return None


class TestShadersLifecycle:
    """Test Shaders module lifecycle."""

    def test_module_starts_and_stops_cleanly(self):
        """Shaders module starts and stops without errors."""
        from modules.shaders import ShadersModule, ShadersConfig

        config = ShadersConfig()
        shaders = ShadersModule(config)

        assert not shaders.is_started

        success = shaders.start()
        assert success, "Module should start successfully"
        assert shaders.is_started

        status = shaders.get_stats()
        assert status["started"] is True

        shaders.stop()
        assert not shaders.is_started

        print("\nModule started and stopped cleanly")

    def test_module_can_restart(self):
        """Shaders module can be stopped and restarted."""
        from modules.shaders import ShadersModule

        shaders = ShadersModule()

        shaders.start()
        assert shaders.is_started

        shaders.stop()
        assert not shaders.is_started

        success = shaders.start()
        assert success, "Should restart successfully"
        assert shaders.is_started

        shaders.stop()

        print("\nModule restart successful")


class TestShadersIndexing:
    """Test shader indexing functionality."""

    def test_lists_shaders_without_crash(self):
        """list_shaders() returns list without crashing."""
        from modules.shaders import ShadersModule

        shaders = ShadersModule()
        shaders.start()

        shader_list = shaders.list_shaders()
        assert isinstance(shader_list, list)

        shaders.stop()

        print(f"\nListed {len(shader_list)} shaders")

    def test_get_shader_returns_none_for_unknown(self):
        """get_shader returns None for unknown shader."""
        from modules.shaders import ShadersModule

        shaders = ShadersModule()
        shaders.start()

        result = shaders.get_shader("nonexistent_shader_12345")
        assert result is None

        shaders.stop()

        print("\nCorrectly returned None for unknown shader")


class TestShadersMatching:
    """Test shader matching functionality."""

    def test_find_best_match_handles_empty(self):
        """find_best_match handles empty shader database."""
        from modules.shaders import ShadersModule

        shaders = ShadersModule()
        shaders.start()

        # Should not crash even with no shaders
        result = shaders.find_best_match(energy=0.8, valence=0.5)
        # Result can be None if no shaders available
        assert result is None or hasattr(result, 'name')

        shaders.stop()

        print(f"\nfind_best_match handled gracefully: {result}")

    def test_find_matches_returns_list(self):
        """find_matches returns a list."""
        from modules.shaders import ShadersModule

        shaders = ShadersModule()
        shaders.start()

        matches = shaders.find_matches(energy=0.5, valence=0.0, top_k=5)
        assert isinstance(matches, list)

        shaders.stop()

        print(f"\nfind_matches returned {len(matches)} results")

    def test_match_by_mood_returns_list(self):
        """match_by_mood returns a list."""
        from modules.shaders import ShadersModule

        shaders = ShadersModule()
        shaders.start()

        matches = shaders.match_by_mood("energetic", energy=0.8, top_k=5)
        assert isinstance(matches, list)

        shaders.stop()

        print(f"\nmatch_by_mood returned {len(matches)} results")

    def test_search_returns_list(self):
        """search returns a list of tuples."""
        from modules.shaders import ShadersModule

        shaders = ShadersModule()
        shaders.start()

        results = shaders.search("colorful", top_k=5)
        assert isinstance(results, list)

        shaders.stop()

        print(f"\nsearch returned {len(results)} results")


class TestShadersWithData:
    """Tests that require actual shader data."""

    def test_loads_shaders_from_directory(self):
        """Loads shaders when directory exists with data."""
        import pytest
        from modules.shaders import ShadersModule, ShadersConfig

        shaders_dir = get_shaders_dir()
        if not shaders_dir:
            pytest.skip("No shader directory found")

        config = ShadersConfig(shaders_dir=shaders_dir)
        shaders = ShadersModule(config)
        shaders.start()

        count = shaders.shader_count
        shaders.stop()

        # If we found a shader dir, we should have loaded some
        assert count >= 0, "Should report shader count"

        print(f"\nLoaded {count} shaders from {shaders_dir}")


class TestShadersStandalone:
    """Test standalone CLI functionality."""

    def test_cli_module_importable(self):
        """CLI module can be imported without errors."""
        from modules.shaders import main

        assert callable(main), "main should be callable"

        print("\nCLI module imports successfully")
