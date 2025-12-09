"""
Tests for Launchpad Mini Mk3 driver.

Tests Programmer Mode coordinate mapping and color constants.
"""

import pytest
from launchpad_osc_lib.launchpad import (
    PadId,
    pad_to_note,
    note_to_pad,
    LP_OFF, LP_RED, LP_GREEN, LP_BLUE,
    LP_ORANGE, LP_YELLOW, LP_CYAN, LP_PURPLE, LP_PINK, LP_WHITE,
    COLOR_PALETTE,
)


class TestPadId:
    """Test PadId identifier class."""

    def test_grid_pad_creation(self):
        """Grid pads have x,y in range 0-7."""
        pad = PadId(3, 4)
        assert pad.x == 3
        assert pad.y == 4
        assert pad.is_grid()
        assert not pad.is_top_row()
        assert not pad.is_right_column()

    def test_top_row_pad(self):
        """Top row pads have y=-1."""
        pad = PadId(5, -1)
        assert pad.is_top_row()
        assert not pad.is_grid()
        assert not pad.is_right_column()
        assert str(pad) == "Top5"

    def test_right_column_pad(self):
        """Right column pads have x=8."""
        pad = PadId(8, 3)
        assert pad.is_right_column()
        assert not pad.is_grid()
        assert not pad.is_top_row()
        assert str(pad) == "Right3"

    def test_grid_pad_str(self):
        """Grid pads show as (x,y)."""
        pad = PadId(2, 5)
        assert str(pad) == "(2,5)"

    def test_pad_equality(self):
        """PadIds with same coords are equal."""
        pad1 = PadId(3, 4)
        pad2 = PadId(3, 4)
        assert pad1 == pad2

    def test_pad_as_dict_key(self):
        """PadIds can be used as dictionary keys."""
        pads = {PadId(0, 0): "first", PadId(1, 1): "second"}
        assert pads[PadId(0, 0)] == "first"
        assert pads[PadId(1, 1)] == "second"

    def test_pad_immutability(self):
        """PadIds are immutable (frozen dataclass)."""
        pad = PadId(0, 0)
        with pytest.raises(AttributeError):
            pad.x = 1

    @pytest.mark.parametrize("x,y,expected", [
        (0, 0, True), (7, 7, True), (0, 7, True), (7, 0, True),
        (-1, 0, False), (8, 0, False), (0, -1, False), (0, 8, False),
    ])
    def test_is_grid_bounds(self, x, y, expected):
        """Test grid boundary detection."""
        pad = PadId(x, y)
        assert pad.is_grid() == expected


class TestColorConstants:
    """Test Launchpad color constants."""

    def test_color_constants_match_spec(self):
        """Verify color constants match Launchpad Mini MK3 spec."""
        assert LP_OFF == 0
        assert LP_RED == 5
        assert LP_ORANGE == 9
        assert LP_YELLOW == 13
        assert LP_GREEN == 21
        assert LP_CYAN == 37
        assert LP_BLUE == 45
        assert LP_PURPLE == 53
        assert LP_PINK == 57
        assert LP_WHITE == 3

    def test_color_palette_contains_all_colors(self):
        """Color palette dict has all named colors."""
        assert "off" in COLOR_PALETTE
        assert "red" in COLOR_PALETTE
        assert "green" in COLOR_PALETTE
        assert "blue" in COLOR_PALETTE
        assert COLOR_PALETTE["red"] == LP_RED
        assert COLOR_PALETTE["green"] == LP_GREEN


class TestPadCoordinateMapping:
    """Test pad coordinate conversion functions."""

    def test_grid_pad_to_note(self):
        """Test main grid (8x8) coordinate to MIDI note conversion."""
        # Bottom-left corner (0,0) -> note 11
        assert pad_to_note(PadId(0, 0)) == ("note", 11)

        # Top-right corner (7,7) -> note 88
        assert pad_to_note(PadId(7, 7)) == ("note", 88)

        # Middle pad (3,2) -> note 34
        assert pad_to_note(PadId(3, 2)) == ("note", 34)

        # Formula: note = (row+1)*10 + (col+1)
        assert pad_to_note(PadId(4, 5)) == ("note", 65)

    def test_top_row_to_cc(self):
        """Test top row (y=-1) to CC conversion."""
        assert pad_to_note(PadId(0, -1)) == ("cc", 91)
        assert pad_to_note(PadId(7, -1)) == ("cc", 98)
        assert pad_to_note(PadId(3, -1)) == ("cc", 94)

    def test_right_column_to_note(self):
        """Test right column (x=8) to MIDI note conversion."""
        assert pad_to_note(PadId(8, 0)) == ("note", 19)
        assert pad_to_note(PadId(8, 7)) == ("note", 89)
        assert pad_to_note(PadId(8, 3)) == ("note", 49)

    def test_note_to_grid_pad(self):
        """Test MIDI note to grid coordinate conversion."""
        assert note_to_pad("note", 11) == PadId(0, 0)
        assert note_to_pad("note", 88) == PadId(7, 7)
        assert note_to_pad("note", 34) == PadId(3, 2)

    def test_cc_to_top_row(self):
        """Test CC to top row coordinate conversion."""
        assert note_to_pad("cc", 91) == PadId(0, -1)
        assert note_to_pad("cc", 98) == PadId(7, -1)

    def test_note_to_right_column(self):
        """Test MIDI note to right column conversion."""
        assert note_to_pad("note", 19) == PadId(8, 0)
        assert note_to_pad("note", 89) == PadId(8, 7)

    def test_invalid_notes_return_none(self):
        """Test that invalid MIDI notes return None."""
        assert note_to_pad("note", 10) is None
        assert note_to_pad("note", 99) is None
        assert note_to_pad("cc", 90) is None
        assert note_to_pad("cc", 99) is None

    def test_roundtrip_conversion(self):
        """Test that pad->note->pad conversion is consistent."""
        # Main grid
        for y in range(8):
            for x in range(8):
                pad = PadId(x, y)
                msg_type, number = pad_to_note(pad)
                result = note_to_pad(msg_type, number)
                assert result == pad, f"Roundtrip failed for {pad}"

        # Top row
        for x in range(8):
            pad = PadId(x, -1)
            msg_type, number = pad_to_note(pad)
            result = note_to_pad(msg_type, number)
            assert result == pad

        # Right column
        for y in range(8):
            pad = PadId(8, y)
            msg_type, number = pad_to_note(pad)
            result = note_to_pad(msg_type, number)
            assert result == pad


class TestNoteGridFormula:
    """Test the decimal grid formula for MIDI notes."""

    def test_note_formula_examples(self):
        """Test specific examples from documentation."""
        assert (0 + 1) * 10 + (0 + 1) == 11  # (0,0)
        assert (7 + 1) * 10 + (7 + 1) == 88  # (7,7)
        assert (2 + 1) * 10 + (3 + 1) == 34  # (3,2)
        assert (5 + 1) * 10 + (4 + 1) == 65  # (4,5)

    def test_all_valid_notes(self):
        """Test that all grid positions produce valid notes 11-88."""
        valid_notes = set()

        for row in range(8):
            for col in range(8):
                note = (row + 1) * 10 + (col + 1)
                valid_notes.add(note)

        assert len(valid_notes) == 64
        assert min(valid_notes) == 11
        assert max(valid_notes) == 88

        for note in valid_notes:
            assert 1 <= (note % 10) <= 8


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
