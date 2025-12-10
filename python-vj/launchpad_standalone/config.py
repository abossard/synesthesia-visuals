"""
Configuration Persistence

Save/load pad configurations to YAML file.
"""

import logging
from pathlib import Path
from typing import Optional

import yaml

from .model import (
    ControllerConfig, PadConfig, PadId, PadMode, OscCommand
)

logger = logging.getLogger(__name__)

DEFAULT_CONFIG_PATH = Path.home() / ".config" / "launchpad_standalone" / "config.yaml"


def save_config(config: ControllerConfig, path: Optional[Path] = None) -> bool:
    """Save configuration to YAML file."""
    path = path or DEFAULT_CONFIG_PATH
    
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        
        data = {"pads": {}}
        
        for key, pad in config.pads.items():
            data["pads"][key] = {
                "x": pad.pad_id.x,
                "y": pad.pad_id.y,
                "mode": pad.mode.name,
                "address": pad.osc_command.address,
                "args": pad.osc_command.args,
                "idle_color": pad.idle_color,
                "active_color": pad.active_color,
                "label": pad.label,
                "group": pad.group,
            }
        
        with open(path, "w") as f:
            yaml.safe_dump(data, f, default_flow_style=False)
        
        logger.info(f"Saved config to {path}")
        return True
        
    except Exception as e:
        logger.error(f"Failed to save config: {e}")
        return False


def load_config(path: Optional[Path] = None) -> Optional[ControllerConfig]:
    """Load configuration from YAML file."""
    path = path or DEFAULT_CONFIG_PATH
    
    if not path.exists():
        logger.info(f"No config file at {path}")
        return None
    
    try:
        with open(path) as f:
            data = yaml.safe_load(f)
        
        if not data or "pads" not in data:
            return ControllerConfig()
        
        config = ControllerConfig()
        
        for key, pad_data in data["pads"].items():
            pad_config = PadConfig(
                pad_id=PadId(x=pad_data["x"], y=pad_data["y"]),
                mode=PadMode[pad_data["mode"]],
                osc_command=OscCommand(
                    address=pad_data["address"],
                    args=pad_data.get("args", [])
                ),
                idle_color=pad_data.get("idle_color", 0),
                active_color=pad_data.get("active_color", 5),
                label=pad_data.get("label", ""),
                group=pad_data.get("group"),
            )
            config.add_pad(pad_config)
        
        logger.info(f"Loaded {len(config.pads)} pads from {path}")
        return config
        
    except Exception as e:
        logger.error(f"Failed to load config: {e}")
        return None
