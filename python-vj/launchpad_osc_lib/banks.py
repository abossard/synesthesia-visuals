"""
Bank Management System for Launchpad.

Supports multiple configuration banks that can be switched via top row buttons.
Each bank holds pad configurations for the 8x8 grid and right column.
Top row is reserved for bank switching.

Groups (SCENES, PRESETS, etc.) are shared across all banks.
"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

from .launchpad import PadId, LP_OFF, LP_GREEN, LP_BLUE
from .model import PadMode, ButtonGroupType, OscCommand, PadBehavior, PadRuntimeState

logger = logging.getLogger(__name__)


# =============================================================================
# BANK DATA STRUCTURES
# =============================================================================


@dataclass
class Bank:
    """
    A bank holds pad configurations for the 8x8 grid and right column.
    
    Top row is reserved for bank switching and not stored in banks.
    
    Attributes:
        name: Human-readable bank name
        pads: Pad configurations (grid x=0-7, y=0-7 and right column x=8, y=0-7)
        color: LED color for this bank's top row button when inactive
        active_color: LED color when this bank is active
    """
    name: str
    pads: Dict[PadId, PadBehavior] = field(default_factory=dict)
    color: int = LP_BLUE  # Dim color when not active
    active_color: int = LP_GREEN  # Bright color when active
    
    def add_pad(self, behavior: PadBehavior) -> None:
        """Add a pad configuration to this bank."""
        pad_id = behavior.pad_id
        
        # Validate: only grid and right column allowed in banks
        if pad_id.is_top_row():
            raise ValueError(f"Top row pads cannot be added to banks: {pad_id}")
        
        self.pads[pad_id] = behavior
    
    def remove_pad(self, pad_id: PadId) -> None:
        """Remove a pad configuration from this bank."""
        if pad_id in self.pads:
            del self.pads[pad_id]
    
    def get_pad(self, pad_id: PadId) -> Optional[PadBehavior]:
        """Get pad configuration if it exists."""
        return self.pads.get(pad_id)
    
    def clear(self) -> None:
        """Remove all pad configurations."""
        self.pads.clear()


@dataclass
class BankManagerState:
    """
    Mutable state for the bank manager.
    
    Groups are shared across all banks (e.g., active scene persists when switching banks).
    
    Attributes:
        banks: List of banks (up to 8, one per top row button)
        active_bank_index: Currently active bank (0-7)
        runtime: Runtime state for each pad (current colors, active state)
        active_by_group: Currently active pad for each selector group (SHARED)
        beat_pulse: Current beat state for LED blinking
    """
    banks: List[Bank] = field(default_factory=list)
    active_bank_index: int = 0
    runtime: Dict[PadId, PadRuntimeState] = field(default_factory=dict)
    active_by_group: Dict[ButtonGroupType, Optional[PadId]] = field(default_factory=dict)
    beat_pulse: bool = False


# =============================================================================
# BANK MANAGER
# =============================================================================


class BankManager:
    """
    Manages multiple configuration banks with top row switching.
    
    Layout:
        - Top row (y=-1): Bank switching buttons, one per bank
        - Grid (x=0-7, y=0-7): Mapped per bank
        - Right column (x=8, y=0-7): Mapped per bank
    
    Groups are shared across banks:
        - If Scene A is active in bank 0, switching to bank 1 keeps Scene A active
        - The pad for Scene A in bank 1 (if any) will show as active
    
    Usage:
        manager = BankManager()
        manager.add_bank(Bank("Scenes"))
        manager.add_bank(Bank("Effects"))
        
        # Add pads to bank 0
        manager.get_bank(0).add_pad(PadBehavior(...))
        
        # Switch banks
        manager.switch_bank(1)
    """
    
    MAX_BANKS = 8  # One per top row button
    
    def __init__(self):
        self.state = BankManagerState()
        self._on_bank_switch: Optional[Callable[[int, Bank], None]] = None
        self._on_led_update: Optional[Callable[[PadId, int, bool], None]] = None
    
    # =========================================================================
    # CALLBACKS
    # =========================================================================
    
    def set_bank_switch_callback(self, callback: Callable[[int, Bank], None]) -> None:
        """Set callback for bank switch events."""
        self._on_bank_switch = callback
    
    def set_led_update_callback(self, callback: Callable[[PadId, int, bool], None]) -> None:
        """Set callback for LED updates (pad_id, color, blink)."""
        self._on_led_update = callback
    
    # =========================================================================
    # BANK MANAGEMENT
    # =========================================================================
    
    def add_bank(self, bank: Bank) -> int:
        """
        Add a bank.
        
        Returns:
            Index of the added bank
        
        Raises:
            ValueError: If maximum banks (8) reached
        """
        if len(self.state.banks) >= self.MAX_BANKS:
            raise ValueError(f"Maximum {self.MAX_BANKS} banks allowed")
        
        self.state.banks.append(bank)
        index = len(self.state.banks) - 1
        
        logger.info(f"Added bank {index}: {bank.name}")
        return index
    
    def get_bank(self, index: int) -> Optional[Bank]:
        """Get bank by index."""
        if 0 <= index < len(self.state.banks):
            return self.state.banks[index]
        return None
    
    def get_active_bank(self) -> Optional[Bank]:
        """Get currently active bank."""
        return self.get_bank(self.state.active_bank_index)
    
    def get_active_bank_index(self) -> int:
        """Get currently active bank index."""
        return self.state.active_bank_index
    
    def get_bank_count(self) -> int:
        """Get number of banks."""
        return len(self.state.banks)
    
    def switch_bank(self, index: int) -> bool:
        """
        Switch to a different bank.
        
        Updates LEDs for:
        - Top row: Active bank button highlighted
        - Grid/right column: New bank's pad configurations
        
        Args:
            index: Bank index to switch to
        
        Returns:
            True if switch successful
        """
        if index < 0 or index >= len(self.state.banks):
            logger.warning(f"Invalid bank index: {index}")
            return False
        
        if index == self.state.active_bank_index:
            return True  # Already active
        
        old_index = self.state.active_bank_index
        self.state.active_bank_index = index
        
        # Update top row LEDs
        self._update_top_row_leds()
        
        # Refresh grid/right column LEDs for new bank
        self._refresh_bank_leds()
        
        # Notify callback
        if self._on_bank_switch:
            self._on_bank_switch(index, self.state.banks[index])
        
        logger.info(f"Switched from bank {old_index} to bank {index}: {self.state.banks[index].name}")
        return True
    
    # =========================================================================
    # TOP ROW HANDLING
    # =========================================================================
    
    def handle_top_row_press(self, pad_id: PadId) -> bool:
        """
        Handle top row button press for bank switching.
        
        Args:
            pad_id: Top row pad (y=-1)
        
        Returns:
            True if handled as bank switch
        """
        if not pad_id.is_top_row():
            return False
        
        bank_index = pad_id.x
        
        if bank_index < len(self.state.banks):
            self.switch_bank(bank_index)
            return True
        
        return False
    
    def _update_top_row_leds(self) -> None:
        """Update top row LEDs to show bank status."""
        for i in range(self.MAX_BANKS):
            pad_id = PadId(i, -1)
            
            if i < len(self.state.banks):
                bank = self.state.banks[i]
                if i == self.state.active_bank_index:
                    color = bank.active_color
                else:
                    color = bank.color
            else:
                color = LP_OFF  # No bank at this position
            
            self._apply_led(pad_id, color)
    
    # =========================================================================
    # PAD HANDLING (Grid + Right Column)
    # =========================================================================
    
    def get_pad_behavior(self, pad_id: PadId) -> Optional[PadBehavior]:
        """
        Get pad behavior for current bank.
        
        Returns None for:
        - Top row pads (handled separately)
        - Unmapped pads in current bank
        """
        if pad_id.is_top_row():
            return None
        
        bank = self.get_active_bank()
        if bank:
            return bank.get_pad(pad_id)
        return None
    
    def get_runtime_state(self, pad_id: PadId) -> PadRuntimeState:
        """Get runtime state for a pad."""
        return self.state.runtime.get(pad_id, PadRuntimeState())
    
    def set_runtime_state(self, pad_id: PadId, runtime: PadRuntimeState) -> None:
        """Set runtime state for a pad."""
        self.state.runtime[pad_id] = runtime
    
    # =========================================================================
    # GROUP STATE (Shared across banks)
    # =========================================================================
    
    def get_active_for_group(self, group: ButtonGroupType) -> Optional[PadId]:
        """Get currently active pad for a selector group."""
        return self.state.active_by_group.get(group)
    
    def set_active_for_group(self, group: ButtonGroupType, pad_id: Optional[PadId]) -> None:
        """Set currently active pad for a selector group."""
        self.state.active_by_group[group] = pad_id
    
    def is_pad_active_in_group(self, pad_id: PadId, group: ButtonGroupType) -> bool:
        """Check if pad is the active one in its group."""
        return self.state.active_by_group.get(group) == pad_id
    
    # =========================================================================
    # LED MANAGEMENT
    # =========================================================================
    
    def _apply_led(self, pad_id: PadId, color: int, blink: bool = False) -> None:
        """Apply LED color via callback."""
        if self._on_led_update:
            self._on_led_update(pad_id, color, blink)
    
    def _refresh_bank_leds(self) -> None:
        """Refresh all LEDs for current bank."""
        bank = self.get_active_bank()
        if not bank:
            return
        
        # Clear grid and right column first
        for y in range(8):
            for x in range(8):
                pad_id = PadId(x, y)
                if pad_id not in bank.pads:
                    self._apply_led(pad_id, LP_OFF)
            
            # Right column
            right_pad = PadId(8, y)
            if right_pad not in bank.pads:
                self._apply_led(right_pad, LP_OFF)
        
        # Set LEDs for mapped pads
        for pad_id, behavior in bank.pads.items():
            runtime = self.state.runtime.get(pad_id, PadRuntimeState())
            
            # Check if this pad should be active (group shared state)
            if behavior.mode == PadMode.SELECTOR and behavior.group:
                is_active = self.is_pad_active_in_group(pad_id, behavior.group)
                if is_active:
                    self._apply_led(pad_id, behavior.active_color, blink=True)
                else:
                    self._apply_led(pad_id, behavior.idle_color)
            else:
                # Use runtime state
                self._apply_led(pad_id, runtime.current_color or behavior.idle_color)
    
    def refresh_all_leds(self) -> None:
        """Refresh all LEDs (top row + current bank)."""
        self._update_top_row_leds()
        self._refresh_bank_leds()
    
    # =========================================================================
    # PERSISTENCE
    # =========================================================================
    
    def save_to_file(self, path: Path) -> None:
        """
        Save all banks to JSON file.
        
        Args:
            path: File path to save to
        """
        data = {
            "version": 1,
            "active_bank_index": self.state.active_bank_index,
            "banks": [self._bank_to_dict(bank) for bank in self.state.banks],
            "active_by_group": {
                group.value: (pad_id.x, pad_id.y) if pad_id else None
                for group, pad_id in self.state.active_by_group.items()
            },
        }
        
        with open(path, 'w') as f:
            json.dump(data, f, indent=2)
        
        logger.info(f"Saved {len(self.state.banks)} banks to {path}")
    
    def load_from_file(self, path: Path) -> bool:
        """
        Load banks from JSON file.
        
        Args:
            path: File path to load from
        
        Returns:
            True if loaded successfully
        """
        if not path.exists():
            logger.warning(f"Bank file not found: {path}")
            return False
        
        try:
            with open(path, 'r') as f:
                data = json.load(f)
            
            # Clear current state
            self.state.banks.clear()
            self.state.active_by_group.clear()
            
            # Load banks
            for bank_data in data.get("banks", []):
                bank = self._dict_to_bank(bank_data)
                self.state.banks.append(bank)
            
            # Load group state
            for group_str, pad_coords in data.get("active_by_group", {}).items():
                try:
                    group = ButtonGroupType(group_str)
                    if pad_coords:
                        self.state.active_by_group[group] = PadId(pad_coords[0], pad_coords[1])
                except ValueError:
                    pass
            
            # Set active bank
            self.state.active_bank_index = data.get("active_bank_index", 0)
            
            logger.info(f"Loaded {len(self.state.banks)} banks from {path}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to load banks from {path}: {e}")
            return False
    
    def _bank_to_dict(self, bank: Bank) -> dict:
        """Convert bank to dictionary for JSON serialization."""
        return {
            "name": bank.name,
            "color": bank.color,
            "active_color": bank.active_color,
            "pads": {
                f"{pad_id.x},{pad_id.y}": self._behavior_to_dict(behavior)
                for pad_id, behavior in bank.pads.items()
            },
        }
    
    def _dict_to_bank(self, data: dict) -> Bank:
        """Convert dictionary to Bank."""
        bank = Bank(
            name=data.get("name", "Untitled"),
            color=data.get("color", LP_BLUE),
            active_color=data.get("active_color", LP_GREEN),
        )
        
        for pad_key, behavior_data in data.get("pads", {}).items():
            x, y = map(int, pad_key.split(","))
            behavior = self._dict_to_behavior(PadId(x, y), behavior_data)
            bank.pads[behavior.pad_id] = behavior
        
        return bank
    
    def _behavior_to_dict(self, behavior: PadBehavior) -> dict:
        """Convert PadBehavior to dictionary."""
        data: Dict[str, Any] = {
            "mode": behavior.mode.value,
            "idle_color": behavior.idle_color,
            "active_color": behavior.active_color,
            "label": behavior.label,
        }
        
        if behavior.group:
            data["group"] = behavior.group.value
        
        if behavior.osc_action:
            data["osc_action"] = {
                "address": behavior.osc_action.address,
                "args": behavior.osc_action.args,
            }
        
        if behavior.osc_on:
            data["osc_on"] = {
                "address": behavior.osc_on.address,
                "args": behavior.osc_on.args,
            }
        
        if behavior.osc_off:
            data["osc_off"] = {
                "address": behavior.osc_off.address,
                "args": behavior.osc_off.args,
            }
        
        return data
    
    def _dict_to_behavior(self, pad_id: PadId, data: dict) -> PadBehavior:
        """Convert dictionary to PadBehavior."""
        mode = PadMode(data.get("mode", "one_shot"))
        
        group = None
        if "group" in data:
            try:
                group = ButtonGroupType(data["group"])
            except ValueError:
                pass
        
        osc_action = None
        if "osc_action" in data:
            osc_action = OscCommand(
                address=data["osc_action"]["address"],
                args=data["osc_action"].get("args", []),
            )
        
        osc_on = None
        if "osc_on" in data:
            osc_on = OscCommand(
                address=data["osc_on"]["address"],
                args=data["osc_on"].get("args", []),
            )
        
        osc_off = None
        if "osc_off" in data:
            osc_off = OscCommand(
                address=data["osc_off"]["address"],
                args=data["osc_off"].get("args", []),
            )
        
        return PadBehavior(
            pad_id=pad_id,
            mode=mode,
            group=group,
            idle_color=data.get("idle_color", 0),
            active_color=data.get("active_color", 5),
            label=data.get("label", ""),
            osc_action=osc_action,
            osc_on=osc_on,
            osc_off=osc_off,
        )


# =============================================================================
# FACTORY FUNCTIONS
# =============================================================================


def create_default_banks() -> BankManager:
    """
    Create a BankManager with default empty banks.
    
    Creates 4 default banks:
    - Bank 0: Scenes
    - Bank 1: Presets
    - Bank 2: Effects
    - Bank 3: Custom
    """
    manager = BankManager()
    
    manager.add_bank(Bank(name="Scenes", color=LP_BLUE, active_color=LP_GREEN))
    manager.add_bank(Bank(name="Presets", color=LP_BLUE, active_color=LP_GREEN))
    manager.add_bank(Bank(name="Effects", color=LP_BLUE, active_color=LP_GREEN))
    manager.add_bank(Bank(name="Custom", color=LP_BLUE, active_color=LP_GREEN))
    
    return manager
