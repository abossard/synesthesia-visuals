"""
Tests for MIDI Launchpad integration with lpminimk3.

Tests that lpminimk3 library is properly integrated.
"""

import pytest

try:
    import lpminimk3
    LPMINIMK3_AVAILABLE = True
except ImportError:
    LPMINIMK3_AVAILABLE = False

from launchpad_osc_lib import ButtonId


class TestLpminimk3Integration:
    """Test lpminimk3 library integration."""
    
    @pytest.mark.skipif(not LPMINIMK3_AVAILABLE, reason="lpminimk3 not available")
    def test_lpminimk3_available(self):
        """Verify lpminimk3 is installed and accessible."""
        assert lpminimk3 is not None
        assert hasattr(lpminimk3, 'find_launchpads')
        assert hasattr(lpminimk3, 'LaunchpadMiniMk3')
    
    @pytest.mark.skipif(not LPMINIMK3_AVAILABLE, reason="lpminimk3 not available")
    def test_mode_enum_prog_mode(self):
        """Verify Mode.PROG exists for Programmer mode."""
        assert hasattr(lpminimk3.Mode, 'PROG')
    
    @pytest.mark.skipif(not LPMINIMK3_AVAILABLE, reason="lpminimk3 not available")
    def test_button_event_types(self):
        """Verify ButtonEvent has PRESS and RELEASE types."""
        assert hasattr(lpminimk3.ButtonEvent, 'PRESS')
        assert hasattr(lpminimk3.ButtonEvent, 'RELEASE')


class TestButtonId:
    """Test ButtonId coordinate system."""
    
    def test_button_id_creation(self):
        """Test creating ButtonId with coordinates."""
        btn = ButtonId(3, 4)
        assert btn.x == 3
        assert btn.y == 4
    
    def test_button_id_grid_detection(self):
        """Test grid button detection."""
        assert ButtonId(0, 0).is_grid()
        assert ButtonId(7, 7).is_grid()
        assert not ButtonId(8, 0).is_grid()
        assert not ButtonId(0, -1).is_grid()
    
    def test_button_id_top_row(self):
        """Test top row button detection."""
        assert ButtonId(0, -1).is_top_row()
        assert ButtonId(7, -1).is_top_row()
        assert not ButtonId(0, 0).is_top_row()
    
    def test_button_id_right_column(self):
        """Test right column (scene) button detection."""
        assert ButtonId(8, 0).is_right_column()
        assert ButtonId(8, 7).is_right_column()
        assert not ButtonId(0, 0).is_right_column()


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
