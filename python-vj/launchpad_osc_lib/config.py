"""
Configuration Persistence

Save/load pad configurations to YAML file.
"""

import logging
from pathlib import Path
from typing import Optional, Dict

import yaml

from .button_id import ButtonId
from .model import (
    PadBehavior, PadMode, OscCommand, ButtonGroupType, ControllerState
)

logger = logging.getLogger(__name__)

DEFAULT_CONFIG_PATH = Path.home() / ".config" / "launchpad_osc_lib" / "config.yaml"


def save_config(
    state: ControllerState,
    path: Optional[Path] = None
) -> bool:
    """
    Save pad configuration to YAML file.
    
    Args:
        state: Controller state containing pad configurations
        path: File path (default: ~/.config/launchpad_osc_lib/config.yaml)
    
    Returns:
        True if saved successfully
    """
    path = path or DEFAULT_CONFIG_PATH
    
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        
        data: Dict = {"pads": {}}
        
        for pad_id, behavior in state.pads.items():
            key = f"{pad_id.x},{pad_id.y}"
            
            pad_data = {
                "x": pad_id.x,
                "y": pad_id.y,
                "mode": behavior.mode.name,
                "idle_color": behavior.idle_color,
                "active_color": behavior.active_color,
                "label": behavior.label,
            }
            
            # Group for SELECTOR mode
            if behavior.group:
                pad_data["group"] = behavior.group.value
            
            # OSC commands based on mode
            if behavior.mode == PadMode.TOGGLE:
                if behavior.osc_on:
                    pad_data["osc_on"] = {
                        "address": behavior.osc_on.address,
                        "args": behavior.osc_on.args,
                    }
                if behavior.osc_off:
                    pad_data["osc_off"] = {
                        "address": behavior.osc_off.address,
                        "args": behavior.osc_off.args,
                    }
            else:
                if behavior.osc_action:
                    pad_data["osc_action"] = {
                        "address": behavior.osc_action.address,
                        "args": behavior.osc_action.args,
                    }
            
            data["pads"][key] = pad_data
        
        with open(path, "w") as f:
            yaml.safe_dump(data, f, default_flow_style=False)
        
        logger.info(f"Saved {len(state.pads)} pads to {path}")
        return True
        
    except Exception as e:
        logger.error(f"Failed to save config: {e}")
        return False


def load_config(path: Optional[Path] = None) -> Dict[ButtonId, PadBehavior]:
    """
    Load pad configuration from YAML file.
    
    Args:
        path: File path (default: ~/.config/launchpad_osc_lib/config.yaml)
    
    Returns:
        Dict mapping ButtonId to PadBehavior
    """
    path = path or DEFAULT_CONFIG_PATH
    
    if not path.exists():
        logger.info(f"No config file at {path}")
        return {}
    
    try:
        with open(path) as f:
            data = yaml.safe_load(f)
        
        if not data or "pads" not in data:
            return {}
        
        pads: Dict[ButtonId, PadBehavior] = {}
        
        for key, pad_data in data["pads"].items():
            pad_id = ButtonId(x=pad_data["x"], y=pad_data["y"])
            mode = PadMode[pad_data["mode"]]
            
            # Parse group
            group = None
            if "group" in pad_data:
                try:
                    group = ButtonGroupType(pad_data["group"])
                except ValueError:
                    group = ButtonGroupType.CUSTOM
            
            # Parse OSC commands
            osc_on = None
            osc_off = None
            osc_action = None
            
            if mode == PadMode.TOGGLE:
                if "osc_on" in pad_data:
                    osc_on = OscCommand(
                        address=pad_data["osc_on"]["address"],
                        args=pad_data["osc_on"].get("args", [])
                    )
                if "osc_off" in pad_data:
                    osc_off = OscCommand(
                        address=pad_data["osc_off"]["address"],
                        args=pad_data["osc_off"].get("args", [])
                    )
            else:
                if "osc_action" in pad_data:
                    osc_action = OscCommand(
                        address=pad_data["osc_action"]["address"],
                        args=pad_data["osc_action"].get("args", [])
                    )
            
            behavior = PadBehavior(
                pad_id=pad_id,
                mode=mode,
                group=group,
                idle_color=pad_data.get("idle_color", 0),
                active_color=pad_data.get("active_color", 5),
                label=pad_data.get("label", ""),
                osc_on=osc_on,
                osc_off=osc_off,
                osc_action=osc_action,
            )
            
            pads[pad_id] = behavior
        
        logger.info(f"Loaded {len(pads)} pads from {path}")
        return pads
        
    except Exception as e:
        logger.error(f"Failed to load config: {e}")
        return {}
