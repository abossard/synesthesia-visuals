"""
Tests for lpminimk3 integration.

Since we now use lpminimk3 directly, these tests verify that
the library is available and properly integrated.
"""

import pytest

try:
    import lpminimk3
    LPMINIMK3_AVAILABLE = True
except ImportError:
    LPMINIMK3_AVAILABLE = False


class TestLpminimk3Integration:
    """Test lpminimk3 library integration."""

    def test_lpminimk3_available(self):
        """Verify lpminimk3 is installed."""
        assert LPMINIMK3_AVAILABLE, "lpminimk3 library should be available"

    @pytest.mark.skipif(not LPMINIMK3_AVAILABLE, reason="lpminimk3 not available")
    def test_find_launchpads_function_exists(self):
        """Verify find_launchpads function exists."""
        assert hasattr(lpminimk3, 'find_launchpads')

    @pytest.mark.skipif(not LPMINIMK3_AVAILABLE, reason="lpminimk3 not available")
    def test_launchpad_class_exists(self):
        """Verify LaunchpadMiniMk3 class exists."""
        assert hasattr(lpminimk3, 'LaunchpadMiniMk3')

    @pytest.mark.skipif(not LPMINIMK3_AVAILABLE, reason="lpminimk3 not available")
    def test_mode_enum_exists(self):
        """Verify Mode enum exists with PROG value."""
        assert hasattr(lpminimk3, 'Mode')
        assert hasattr(lpminimk3.Mode, 'PROG')

    @pytest.mark.skipif(not LPMINIMK3_AVAILABLE, reason="lpminimk3 not available")
    def test_button_event_enum_exists(self):
        """Verify ButtonEvent enum exists."""
        assert hasattr(lpminimk3, 'ButtonEvent')
        assert hasattr(lpminimk3.ButtonEvent, 'PRESS')
        assert hasattr(lpminimk3.ButtonEvent, 'RELEASE')

    @pytest.mark.skipif(not LPMINIMK3_AVAILABLE, reason="lpminimk3 not available")
    def test_color_palette_exists(self):
        """Verify ColorPalette exists with common colors."""
        from lpminimk3.colors import ColorPalette
        assert hasattr(ColorPalette, 'Red')
        assert hasattr(ColorPalette, 'Green')
        assert hasattr(ColorPalette, 'Blue')


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
