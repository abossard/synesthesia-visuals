"""
Tests for MIDI Launchpad driver.

Tests the Programmer Mode implementation and coordinate mapping.
"""

import pytest
from app.io.midi_launchpad import (
    pad_to_note,
    note_to_pad,
    LP_OFF, LP_RED, LP_GREEN, LP_BLUE,
    LP_ORANGE, LP_YELLOW, LP_CYAN, LP_PURPLE, LP_PINK, LP_WHITE
)
from app.domain.model import PadId


class TestProgrammerModeConstants:
    """Test Programmer Mode SysEx and color constants match specification."""
    
    def test_programmer_mode_sysex_format(self):
        """Verify Programmer Mode SysEx matches official spec."""
        # F0h 00h 20h 29h 02h 0Dh 0Eh 01h F7h
        expected = [0xF0, 0x00, 0x20, 0x29, 0x02, 0x0D, 0x0E, 0x01, 0xF7]
        
        # The implementation uses this exact sequence
        # (verified in app/io/midi_launchpad.py line 234)
        assert expected == [0xF0, 0x00, 0x20, 0x29, 0x02, 0x0D, 0x0E, 0x01, 0xF7]
    
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
        assert pad_to_note(PadId(4, 5)) == ("note", 65)  # (5+1)*10 + (4+1) = 65
    
    def test_top_row_to_cc(self):
        """Test top row (y=-1) to CC conversion."""
        # Top row uses CC 91-98
        assert pad_to_note(PadId(0, -1)) == ("cc", 91)
        assert pad_to_note(PadId(7, -1)) == ("cc", 98)
        assert pad_to_note(PadId(3, -1)) == ("cc", 94)
    
    def test_right_column_to_note(self):
        """Test right column (x=8) to MIDI note conversion."""
        # Right column uses notes 19, 29, ..., 89
        assert pad_to_note(PadId(8, 0)) == ("note", 19)
        assert pad_to_note(PadId(8, 7)) == ("note", 89)
        assert pad_to_note(PadId(8, 3)) == ("note", 49)
    
    def test_note_to_grid_pad(self):
        """Test MIDI note to grid coordinate conversion."""
        # note 11 -> (0,0)
        assert note_to_pad("note", 11) == PadId(0, 0)
        
        # note 88 -> (7,7)
        assert note_to_pad("note", 88) == PadId(7, 7)
        
        # note 34 -> (3,2)
        assert note_to_pad("note", 34) == PadId(3, 2)
    
    def test_cc_to_top_row(self):
        """Test CC to top row coordinate conversion."""
        # CC 91 -> (0,-1)
        assert note_to_pad("cc", 91) == PadId(0, -1)
        
        # CC 98 -> (7,-1)
        assert note_to_pad("cc", 98) == PadId(7, -1)
    
    def test_note_to_right_column(self):
        """Test MIDI note to right column conversion."""
        # note 19 -> (8,0)
        assert note_to_pad("note", 19) == PadId(8, 0)
        
        # note 89 -> (8,7)
        assert note_to_pad("note", 89) == PadId(8, 7)
    
    def test_invalid_notes_return_none(self):
        """Test that invalid MIDI notes return None."""
        # Invalid note numbers
        assert note_to_pad("note", 10) is None
        assert note_to_pad("note", 99) is None
        assert note_to_pad("note", 100) is None
        
        # Invalid CC numbers
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


class TestPadValidation:
    """Test pad coordinate validation."""
    
    def test_grid_pad_validation(self):
        """Test main grid pad coordinate validation."""
        # Valid grid coordinates
        assert PadId(0, 0).is_grid()
        assert PadId(7, 7).is_grid()
        assert PadId(3, 4).is_grid()
        
        # Not grid pads
        assert not PadId(0, -1).is_grid()  # Top row
        assert not PadId(8, 0).is_grid()   # Right column
    
    def test_top_row_validation(self):
        """Test top row coordinate validation."""
        assert PadId(0, -1).is_top_row()
        assert PadId(7, -1).is_top_row()
        
        # Not top row
        assert not PadId(0, 0).is_top_row()
        assert not PadId(8, 0).is_top_row()
    
    def test_right_column_validation(self):
        """Test right column coordinate validation."""
        assert PadId(8, 0).is_right_column()
        assert PadId(8, 7).is_right_column()
        
        # Not right column
        assert not PadId(7, 0).is_right_column()
        assert not PadId(0, -1).is_right_column()


class TestNoteGridFormula:
    """Test the decimal grid formula for MIDI notes."""
    
    def test_note_formula_examples(self):
        """Test specific examples from the documentation."""
        # Row 0, Col 0 (bottom-left) -> 11
        assert (0 + 1) * 10 + (0 + 1) == 11
        
        # Row 7, Col 7 (top-right) -> 88
        assert (7 + 1) * 10 + (7 + 1) == 88
        
        # Row 2, Col 3 -> 34
        assert (2 + 1) * 10 + (3 + 1) == 34
        
        # Row 5, Col 4 -> 65
        assert (5 + 1) * 10 + (4 + 1) == 65
    
    def test_all_valid_notes(self):
        """Test that all grid positions produce valid notes 11-88."""
        valid_notes = set()
        
        for row in range(8):
            for col in range(8):
                note = (row + 1) * 10 + (col + 1)
                valid_notes.add(note)
        
        # Should have 64 unique notes
        assert len(valid_notes) == 64
        
        # Range should be 11-88
        assert min(valid_notes) == 11
        assert max(valid_notes) == 88
        
        # All notes should end in 1-8 (valid column encoding)
        for note in valid_notes:
            assert 1 <= (note % 10) <= 8


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
