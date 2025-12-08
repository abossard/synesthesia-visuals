"""
Configuration Persistence

Loads and saves configuration to YAML file with atomic writes.
"""

import logging
from pathlib import Path
from typing import Optional, Dict, Any
from dataclasses import asdict

try:
    import yaml
    YAML_AVAILABLE = True
except ImportError:
    YAML_AVAILABLE = False
    yaml = None

from ..domain.model import (
    ControllerState, PadId, PadBehavior, PadMode, PadGroupName,
    OscCommand, PadRuntimeState
)

logger = logging.getLogger(__name__)


# =============================================================================
# SERIALIZATION HELPERS
# =============================================================================

def pad_id_to_str(pad_id: PadId) -> str:
    """Convert PadId to string key."""
    return f"{pad_id.x},{pad_id.y}"


def str_to_pad_id(s: str) -> PadId:
    """Convert string key to PadId."""
    x, y = map(int, s.split(','))
    return PadId(x, y)


def serialize_pad_behavior(behavior: PadBehavior) -> Dict[str, Any]:
    """Serialize PadBehavior to dict."""
    data = {
        "mode": behavior.mode.name,
        "idle_color": behavior.idle_color,
        "active_color": behavior.active_color,
        "label": behavior.label,
    }
    
    if behavior.group:
        data["group"] = behavior.group.value
    
    if behavior.osc_on:
        data["osc_on"] = {
            "address": behavior.osc_on.address,
            "args": behavior.osc_on.args
        }
    
    if behavior.osc_off:
        data["osc_off"] = {
            "address": behavior.osc_off.address,
            "args": behavior.osc_off.args
        }
    
    if behavior.osc_action:
        data["osc_action"] = {
            "address": behavior.osc_action.address,
            "args": behavior.osc_action.args
        }
    
    return data


def deserialize_pad_behavior(pad_id: PadId, data: Dict[str, Any]) -> PadBehavior:
    """Deserialize PadBehavior from dict."""
    mode = PadMode[data["mode"]]
    group = PadGroupName(data["group"]) if "group" in data else None
    
    osc_on = None
    if "osc_on" in data:
        osc_on = OscCommand(
            address=data["osc_on"]["address"],
            args=data["osc_on"].get("args", [])
        )
    
    osc_off = None
    if "osc_off" in data:
        osc_off = OscCommand(
            address=data["osc_off"]["address"],
            args=data["osc_off"].get("args", [])
        )
    
    osc_action = None
    if "osc_action" in data:
        osc_action = OscCommand(
            address=data["osc_action"]["address"],
            args=data["osc_action"].get("args", [])
        )
    
    return PadBehavior(
        pad_id=pad_id,
        mode=mode,
        group=group,
        idle_color=data.get("idle_color", 0),
        active_color=data.get("active_color", 5),
        label=data.get("label", ""),
        osc_on=osc_on,
        osc_off=osc_off,
        osc_action=osc_action
    )


# =============================================================================
# CONFIG MANAGER
# =============================================================================

class ConfigManager:
    """
    Manages configuration persistence to YAML file.
    
    Gracefully handles missing YAML library.
    """
    
    def __init__(self, config_path: Path):
        self.config_path = config_path
        self.config_path.parent.mkdir(parents=True, exist_ok=True)
    
    def load(self) -> Optional[ControllerState]:
        """
        Load configuration from file.
        
        Returns:
            ControllerState or None if file doesn't exist or can't be loaded
        """
        if not YAML_AVAILABLE:
            logger.warning("PyYAML not installed - config persistence disabled")
            logger.warning("Install with: pip install pyyaml")
            return None
        
        if not self.config_path.exists():
            logger.info(f"No config file at {self.config_path}")
            return None
        
        try:
            with open(self.config_path, 'r') as f:
                data = yaml.safe_load(f)
            
            if not data:
                return None
            
            # Deserialize pads
            pads = {}
            pad_runtime = {}
            
            for pad_str, pad_data in data.get("pads", {}).items():
                pad_id = str_to_pad_id(pad_str)
                behavior = deserialize_pad_behavior(pad_id, pad_data)
                pads[pad_id] = behavior
                
                # Initialize runtime state
                pad_runtime[pad_id] = PadRuntimeState(
                    is_active=False,
                    current_color=behavior.idle_color,
                    blink_enabled=False
                )
            
            # Create controller state
            state = ControllerState(
                pads=pads,
                pad_runtime=pad_runtime
            )
            
            logger.info(f"Loaded {len(pads)} pad configurations")
            return state
            
        except Exception as e:
            logger.error(f"Failed to load config: {e}")
            return None
    
    def save(self, state: ControllerState):
        """
        Save configuration to file (atomic write).
        
        Args:
            state: ControllerState to save
        """
        if not YAML_AVAILABLE:
            logger.debug("PyYAML not installed - cannot save config")
            return
        
        try:
            # Serialize pads
            pads_data = {}
            for pad_id, behavior in state.pads.items():
                pad_str = pad_id_to_str(pad_id)
                pads_data[pad_str] = serialize_pad_behavior(behavior)
            
            data = {
                "version": "1.0",
                "pads": pads_data
            }
            
            # Atomic write: write to temp file, then move
            temp_path = self.config_path.with_suffix('.tmp')
            
            with open(temp_path, 'w') as f:
                yaml.safe_dump(data, f, default_flow_style=False, sort_keys=False)
            
            temp_path.replace(self.config_path)
            
            logger.info(f"Saved {len(state.pads)} pad configurations")
            
        except Exception as e:
            logger.error(f"Failed to save config: {e}")


def get_default_config_path() -> Path:
    """Get default config file path."""
    return Path.home() / ".config" / "launchpad-synesthesia" / "config.yaml"
