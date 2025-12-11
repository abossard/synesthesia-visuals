"""Tests for the bank management system."""

import json
import pytest
from pathlib import Path
from unittest.mock import MagicMock

from launchpad_osc_lib import (
    Bank,
    BankManager,
    create_default_banks,
    ButtonId,
    PadMode,
    ButtonGroupType,
    PadBehavior,
    OscCommand,
)

# Color constants
LP_OFF = 0
LP_BLUE = 40
LP_GREEN = 17
LP_RED = 72


# =============================================================================
# BANK TESTS
# =============================================================================


class TestBank:
    """Tests for Bank dataclass."""
    
    def test_create_empty_bank(self):
        """Bank starts with no pads."""
        bank = Bank(name="Test")
        assert bank.name == "Test"
        assert len(bank.pads) == 0
    
    def test_add_grid_pad(self):
        """Can add pads in the 8x8 grid."""
        bank = Bank(name="Test")
        behavior = PadBehavior(
            pad_id=ButtonId(3, 4),
            mode=PadMode.ONE_SHOT,
            idle_color=LP_BLUE,
            osc_action=OscCommand(address="/test", args=[]),
        )
        bank.add_pad(behavior)
        
        assert ButtonId(3, 4) in bank.pads
        assert bank.get_pad(ButtonId(3, 4)) == behavior
    
    def test_add_right_column_pad(self):
        """Can add pads in the right column (x=8)."""
        bank = Bank(name="Test")
        behavior = PadBehavior(
            pad_id=ButtonId(8, 3),
            mode=PadMode.TOGGLE,
            idle_color=LP_GREEN,
            osc_on=OscCommand(address="/toggle/on", args=[1]),
            osc_off=OscCommand(address="/toggle/off", args=[0]),
        )
        bank.add_pad(behavior)
        
        assert ButtonId(8, 3) in bank.pads
    
    def test_cannot_add_top_row_pad(self):
        """Top row pads (y=-1) cannot be added to banks."""
        bank = Bank(name="Test")
        behavior = PadBehavior(
            pad_id=ButtonId(2, -1),
            mode=PadMode.ONE_SHOT,
            idle_color=LP_BLUE,
            osc_action=OscCommand(address="/test", args=[]),
        )
        
        with pytest.raises(ValueError, match="Top row pads cannot be added"):
            bank.add_pad(behavior)
    
    def test_remove_pad(self):
        """Can remove pads from bank."""
        bank = Bank(name="Test")
        pad_id = ButtonId(1, 1)
        bank.add_pad(PadBehavior(
            pad_id=pad_id,
            mode=PadMode.ONE_SHOT,
            idle_color=LP_BLUE,
            osc_action=OscCommand(address="/test", args=[]),
        ))
        
        bank.remove_pad(pad_id)
        assert pad_id not in bank.pads
    
    def test_clear_bank(self):
        """Can clear all pads."""
        bank = Bank(name="Test")
        for i in range(5):
            bank.add_pad(PadBehavior(
                pad_id=ButtonId(i, 0),
                mode=PadMode.ONE_SHOT,
                idle_color=LP_BLUE,
                osc_action=OscCommand(address=f"/test/{i}", args=[]),
            ))
        
        bank.clear()
        assert len(bank.pads) == 0
    
    def test_get_nonexistent_pad(self):
        """Getting unmapped pad returns None."""
        bank = Bank(name="Test")
        assert bank.get_pad(ButtonId(0, 0)) is None


# =============================================================================
# BANK MANAGER TESTS
# =============================================================================


class TestBankManager:
    """Tests for BankManager."""
    
    def test_create_empty_manager(self):
        """Manager starts with no banks."""
        manager = BankManager()
        assert manager.get_bank_count() == 0
        assert manager.get_active_bank() is None
    
    def test_add_banks(self):
        """Can add multiple banks."""
        manager = BankManager()
        idx1 = manager.add_bank(Bank(name="Bank 1"))
        idx2 = manager.add_bank(Bank(name="Bank 2"))
        
        assert idx1 == 0
        assert idx2 == 1
        assert manager.get_bank_count() == 2
    
    def test_max_8_banks(self):
        """Cannot add more than 8 banks."""
        manager = BankManager()
        for i in range(8):
            manager.add_bank(Bank(name=f"Bank {i}"))
        
        with pytest.raises(ValueError, match="Maximum 8 banks"):
            manager.add_bank(Bank(name="Bank 9"))
    
    def test_first_bank_is_active(self):
        """First bank becomes active by default."""
        manager = BankManager()
        manager.add_bank(Bank(name="First"))
        manager.add_bank(Bank(name="Second"))
        
        assert manager.get_active_bank_index() == 0
        assert manager.get_active_bank().name == "First"
    
    def test_switch_bank(self):
        """Can switch between banks."""
        manager = BankManager()
        manager.add_bank(Bank(name="Bank A"))
        manager.add_bank(Bank(name="Bank B"))
        
        assert manager.switch_bank(1) is True
        assert manager.get_active_bank_index() == 1
        assert manager.get_active_bank().name == "Bank B"
    
    def test_switch_invalid_bank(self):
        """Switching to invalid index returns False."""
        manager = BankManager()
        manager.add_bank(Bank(name="Only"))
        
        assert manager.switch_bank(5) is False
        assert manager.get_active_bank_index() == 0


class TestBankManagerTopRow:
    """Tests for top row bank switching."""
    
    def test_handle_top_row_press_switches_bank(self):
        """Pressing top row switches to corresponding bank."""
        manager = BankManager()
        manager.add_bank(Bank(name="Bank 0"))
        manager.add_bank(Bank(name="Bank 1"))
        manager.add_bank(Bank(name="Bank 2"))
        
        # Press top row button 2 (y=-1)
        result = manager.handle_top_row_press(ButtonId(2, -1))
        
        assert result is True
        assert manager.get_active_bank_index() == 2
    
    def test_handle_top_row_no_bank(self):
        """Pressing top row without bank does nothing."""
        manager = BankManager()
        manager.add_bank(Bank(name="Only Bank"))
        
        result = manager.handle_top_row_press(ButtonId(5, -1))
        
        assert result is False
        assert manager.get_active_bank_index() == 0
    
    def test_handle_grid_press_not_top_row(self):
        """Grid pads don't trigger bank switch."""
        manager = BankManager()
        manager.add_bank(Bank(name="Bank"))
        
        result = manager.handle_top_row_press(ButtonId(3, 3))
        
        assert result is False


class TestBankManagerSharedGroups:
    """Tests for shared group state across banks."""
    
    def test_group_state_persists_across_banks(self):
        """Group selection is shared (not per-bank)."""
        manager = BankManager()
        manager.add_bank(Bank(name="Bank A"))
        manager.add_bank(Bank(name="Bank B"))
        
        # Set active scene in group
        scene_pad = ButtonId(0, 0)
        manager.set_active_for_group(ButtonGroupType.SCENES, scene_pad)
        
        # Switch banks
        manager.switch_bank(1)
        
        # Group state should persist
        assert manager.get_active_for_group(ButtonGroupType.SCENES) == scene_pad
    
    def test_is_pad_active_in_group(self):
        """Can check if specific pad is active in group."""
        manager = BankManager()
        manager.add_bank(Bank(name="Test"))
        
        pad1 = ButtonId(0, 0)
        pad2 = ButtonId(1, 0)
        
        manager.set_active_for_group(ButtonGroupType.SCENES, pad1)
        
        assert manager.is_pad_active_in_group(pad1, ButtonGroupType.SCENES) is True
        assert manager.is_pad_active_in_group(pad2, ButtonGroupType.SCENES) is False


class TestBankManagerCallbacks:
    """Tests for callback integration."""
    
    def test_bank_switch_callback(self):
        """Bank switch triggers callback."""
        manager = BankManager()
        bank_a = Bank(name="Bank A")
        bank_b = Bank(name="Bank B")
        manager.add_bank(bank_a)
        manager.add_bank(bank_b)
        
        callback = MagicMock()
        manager.set_bank_switch_callback(callback)
        
        manager.switch_bank(1)
        
        callback.assert_called_once_with(1, bank_b)
    
    def test_led_update_callback_on_switch(self):
        """Bank switch triggers LED updates."""
        manager = BankManager()
        manager.add_bank(Bank(name="Bank A"))
        manager.add_bank(Bank(name="Bank B"))
        
        led_updates = []
        manager.set_led_update_callback(lambda pad, color, blink: led_updates.append((pad, color)))
        
        manager.switch_bank(1)
        
        # Should have LED updates for top row + grid clear
        assert len(led_updates) > 0


class TestBankManagerPadAccess:
    """Tests for pad behavior access through manager."""
    
    def test_get_pad_from_active_bank(self):
        """get_pad_behavior returns from active bank."""
        manager = BankManager()
        
        bank_a = Bank(name="A")
        pad_id = ButtonId(2, 2)
        behavior_a = PadBehavior(
            pad_id=pad_id,
            mode=PadMode.ONE_SHOT,
            idle_color=LP_BLUE,
            label="A",
            osc_action=OscCommand(address="/a", args=[]),
        )
        bank_a.add_pad(behavior_a)
        
        bank_b = Bank(name="B")
        behavior_b = PadBehavior(
            pad_id=pad_id,
            mode=PadMode.ONE_SHOT,
            idle_color=LP_GREEN,
            label="B",
            osc_action=OscCommand(address="/b", args=[]),
        )
        bank_b.add_pad(behavior_b)
        
        manager.add_bank(bank_a)
        manager.add_bank(bank_b)
        
        # Active bank is A
        assert manager.get_pad_behavior(pad_id).label == "A"
        
        # Switch to B
        manager.switch_bank(1)
        assert manager.get_pad_behavior(pad_id).label == "B"
    
    def test_get_pad_top_row_returns_none(self):
        """Top row pads don't have behaviors (handled separately)."""
        manager = BankManager()
        manager.add_bank(Bank(name="Test"))
        
        assert manager.get_pad_behavior(ButtonId(3, -1)) is None


# =============================================================================
# PERSISTENCE TESTS
# =============================================================================


class TestBankManagerPersistence:
    """Tests for save/load functionality."""
    
    def test_save_and_load(self, tmp_path):
        """Banks can be saved and restored."""
        manager = BankManager()
        
        bank = Bank(name="My Bank", color=LP_RED, active_color=LP_GREEN)
        bank.add_pad(PadBehavior(
            pad_id=ButtonId(0, 0),
            mode=PadMode.SELECTOR,
            group=ButtonGroupType.SCENES,
            idle_color=LP_BLUE,
            active_color=LP_GREEN,
            label="Scene 1",
            osc_action=OscCommand(address="/scenes/1", args=[1.0]),
        ))
        bank.add_pad(PadBehavior(
            pad_id=ButtonId(1, 0),
            mode=PadMode.TOGGLE,
            idle_color=LP_BLUE,
            active_color=LP_RED,
            label="Strobe",
            osc_on=OscCommand(address="/strobe", args=[1]),
            osc_off=OscCommand(address="/strobe", args=[0]),
        ))
        
        manager.add_bank(bank)
        manager.set_active_for_group(ButtonGroupType.SCENES, ButtonId(0, 0))
        
        # Save
        save_path = tmp_path / "banks.json"
        manager.save_to_file(save_path)
        
        # Load into new manager
        manager2 = BankManager()
        assert manager2.load_from_file(save_path) is True
        
        # Verify
        assert manager2.get_bank_count() == 1
        restored_bank = manager2.get_bank(0)
        assert restored_bank.name == "My Bank"
        assert restored_bank.color == LP_RED
        assert len(restored_bank.pads) == 2
        
        # Check pad details
        pad = restored_bank.get_pad(ButtonId(0, 0))
        assert pad.label == "Scene 1"
        assert pad.mode == PadMode.SELECTOR
        assert pad.group == ButtonGroupType.SCENES
        assert pad.osc_action.address == "/scenes/1"
        
        # Check group state
        assert manager2.get_active_for_group(ButtonGroupType.SCENES) == ButtonId(0, 0)
    
    def test_load_nonexistent_file(self):
        """Loading missing file returns False."""
        manager = BankManager()
        result = manager.load_from_file(Path("/nonexistent/path.json"))
        assert result is False
    
    def test_json_format(self, tmp_path):
        """Saved JSON is human-readable."""
        manager = BankManager()
        manager.add_bank(Bank(name="Test"))
        
        save_path = tmp_path / "banks.json"
        manager.save_to_file(save_path)
        
        with open(save_path) as f:
            data = json.load(f)
        
        assert "version" in data
        assert "banks" in data
        assert data["banks"][0]["name"] == "Test"


# =============================================================================
# FACTORY TESTS
# =============================================================================


class TestCreateDefaultBanks:
    """Tests for create_default_banks factory."""
    
    def test_creates_8_banks(self):
        """Factory creates 8 default banks (one per top row button)."""
        manager = create_default_banks()
        
        assert manager.get_bank_count() == 8
        assert manager.get_bank(0).name == "Scenes"
        assert manager.get_bank(1).name == "Presets"
        assert manager.get_bank(2).name == "Effects"
        assert manager.get_bank(3).name == "Transitions"
        assert manager.get_bank(4).name == "Media"
        assert manager.get_bank(5).name == "Audio"
        assert manager.get_bank(6).name == "Color"
        assert manager.get_bank(7).name == "Custom"
    
    def test_banks_are_empty(self):
        """Default banks have no pad configurations."""
        manager = create_default_banks()
        
        for i in range(8):
            assert len(manager.get_bank(i).pads) == 0
