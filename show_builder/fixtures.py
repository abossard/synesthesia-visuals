"""Fixture hardware definitions — stable across show designs.

Data module: channel maps, patch specifications, dimmer curves.
Change these only when physical fixtures change.
"""

# ── Channel Maps ──
# DMX channel offsets for each fixture type

HERO_CHANNELS = {
    "pan": 0, "pan_fine": 1, "tilt": 2, "tilt_fine": 3, "pt_speed": 4,
    "spot_dim": 5, "spot_strobe": 6, "color_wheel": 7,
    "gobo": 8, "gobo_wheel": 9, "gobo_rot": 10,
    "focus": 11, "prism": 12,
    "wash_dim": 13, "wash_strobe": 14,
    "r": 15, "g": 16, "b": 17, "w": 18,
    "color_temp": 19, "color_macro": 20, "color_seq": 21, "auto_shows": 22,
}

HAZE_CHANNELS = {"output": 0, "fan": 1}

UV_CHANNELS = {"dim": 0, "strobe": 1, "duration": 2, "sound": 3}


# ── Patch Specifications ──
# QLC+ fixture library entries

FIXTURE_PATCHES = [
    {"manufacturer": "Varytec", "model": "Hero Spot Wash 140 2in1 RGBW+W",
     "mode": "23 Channel", "name": "Hero Spot"},
    {"manufacturer": "Stairville", "model": "Hz-200 DMX",
     "mode": "2 Channel", "name": "Haze Machine"},
    {"manufacturer": "Cameo", "model": "Thunderwash 600 UV",
     "mode": "4 Channel", "name": "UV Wash"},
]

# Default DMX addresses
DEFAULT_ADDRESSES = {"hero": 0, "haze": 30, "uv": 40}


# ── Dimmer Response Curves ──

CHANNEL_MODIFIERS = [
    {"fixture": "hero", "channel": "spot_dim", "modifier": "Exponential Medium"},
    {"fixture": "hero", "channel": "wash_dim", "modifier": "S-curve"},
    {"fixture": "uv",   "channel": "dim",      "modifier": "Threshold"},
]

# ── Channel map lookup ──

_CHANNEL_MAPS = {
    "hero": HERO_CHANNELS,
    "haze": HAZE_CHANNELS,
    "uv": UV_CHANNELS,
}


def make_rig(hero_id, haze_id, uv_id):
    """Bundle fixture IDs with their channel maps into a rig config.

    The rig is passed to compile functions in scenes.py as the single
    source of truth for fixture→channel resolution.
    """
    return {
        "hero": {"id": hero_id, "channels": HERO_CHANNELS},
        "haze": {"id": haze_id, "channels": HAZE_CHANNELS},
        "uv":   {"id": uv_id,   "channels": UV_CHANNELS},
    }
