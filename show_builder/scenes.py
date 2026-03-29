"""Show content — the creative/variable part of the show.

PURE DATA + CALCULATIONS — no I/O, no side effects.

This is the primary customization file. Edit the data lists below to change
what the show looks/feels like without touching any infrastructure code.

Scene format:
    {"name": "...", "channels": {"fixture_type": {"channel_name": value, ...}}}

The compile_scene() function maps fixture types → IDs and channel names → DMX
offsets using the rig configuration from fixtures.make_rig().

Gobo reference: Open=0, Spiral=10, Starburst=20, Dots=28, Leaves=36,
                Lightning=44, Web=52, Waves=60
Color wheel:    White=0, Red=18, Orange=36, Green=54, Blue=72,
                Yellow=90, Purple=126
Prism:          Open=0, On=70, Rotating=200
"""


# ═══════════════════════════════════════════════════════════════════════════
# Scene Data — edit these to customize the show
# ═══════════════════════════════════════════════════════════════════════════

# Phase textures: WHAT atmosphere — gobo, prism, UV, color wheel, subtle tint
PHASE_TEXTURES = [
    {"name": "P1 Jungle Texture", "channels": {
        "hero": {"color_wheel": 54, "gobo": 36, "prism": 0,
                 "r": 0, "g": 10, "b": 5, "w": 5},
        "uv": {"dim": 38},
    }},
    {"name": "P2 Buildup Texture", "channels": {
        "hero": {"color_wheel": 72, "gobo": 28, "prism": 70,
                 "r": 0, "g": 5, "b": 10, "w": 5},
        "uv": {"dim": 128},
    }},
    {"name": "P3 Peak Texture", "channels": {
        "hero": {"color_wheel": 126, "gobo": 44, "prism": 200,
                 "r": 10, "g": 0, "b": 10, "w": 0},
        "uv": {"dim": 204},
    }},
    {"name": "P4 Release Texture", "channels": {
        "hero": {"color_wheel": 72, "gobo": 60, "prism": 0,
                 "r": 0, "g": 5, "b": 10, "w": 5},
        "uv": {"dim": 25},
    }},
]

# Mood colors: WHAT color — dominant RGBW wash
MOODS = [
    {"name": "Deep Jungle",   "channels": {"hero": {"r": 0,   "g": 180, "b": 30,  "w": 20}}},
    {"name": "Amber Canopy",  "channels": {"hero": {"r": 255, "g": 100, "b": 0,   "w": 30}}},
    {"name": "Midnight Blue", "channels": {"hero": {"r": 0,   "g": 0,   "b": 255, "w": 30}}},
    {"name": "Blood Moon",    "channels": {"hero": {"r": 255, "g": 0,   "b": 0,   "w": 0}}},
    {"name": "Mystic Violet", "channels": {"hero": {"r": 180, "g": 0,   "b": 255, "w": 0}}},
    {"name": "Arctic White",  "channels": {"hero": {"r": 40,  "g": 40,  "b": 60,  "w": 255}}},
    {"name": "Tropical Cyan", "channels": {"hero": {"r": 0,   "g": 200, "b": 255, "w": 30}}},
    {"name": "Solar Flare",   "channels": {"hero": {"r": 255, "g": 200, "b": 0,   "w": 80}}},
]

# Energy levels: HOW aggressive — movement speed + gobo rotation
# pt_speed: 0=fastest, 255=slowest
ENERGY_LEVELS = [
    {"name": "E1 Entry",  "channels": {"hero": {"pt_speed": 200, "gobo_rot": 0}}},
    {"name": "E2 Flow",   "channels": {"hero": {"pt_speed": 180, "gobo_rot": 20}}},
    {"name": "E3 Build",  "channels": {"hero": {"pt_speed": 140, "gobo_rot": 70}}},
    {"name": "E4 Bullet", "channels": {"hero": {"pt_speed": 100, "gobo_rot": 100}}},
    {"name": "E5 Peak",   "channels": {"hero": {"pt_speed": 40,  "gobo_rot": 120}}},
    {"name": "E6 Accent", "channels": {"hero": {"pt_speed": 0,   "gobo_rot": 245}}},
    {"name": "E7 Exit",   "channels": {"hero": {"pt_speed": 200, "gobo_rot": 0}}},
]

# Master intensity: HOW bright — dimmer levels
MASTER_LEVELS = [
    {"name": "Master 25%",  "channels": {"hero": {"spot_dim": 64,  "wash_dim": 64}}},
    {"name": "Master 50%",  "channels": {"hero": {"spot_dim": 128, "wash_dim": 128}}},
    {"name": "Master 75%",  "channels": {"hero": {"spot_dim": 192, "wash_dim": 192}}},
    {"name": "Master 100%", "channels": {"hero": {"spot_dim": 255, "wash_dim": 255}}},
    {"name": "KILL Dimmer", "channels": {"hero": {"spot_dim": 0,   "wash_dim": 0}}},
]

# Haze control
HAZE_PRESETS = [
    {"name": "Haze Off",  "channels": {"haze": {"output": 0,   "fan": 0}}},
    {"name": "Haze Low",  "channels": {"haze": {"output": 80,  "fan": 120}}},
    {"name": "Haze Full", "channels": {"haze": {"output": 255, "fan": 200}}},
]

# Strobe speeds (spot + UV as separate groups)
STROBE_PRESETS = [
    {"name": "Spot Strobe Off",  "channels": {"hero": {"spot_strobe": 0}}},
    {"name": "Spot Strobe Slow", "channels": {"hero": {"spot_strobe": 40}}},
    {"name": "Spot Strobe Med",  "channels": {"hero": {"spot_strobe": 120}}},
    {"name": "Spot Strobe Fast", "channels": {"hero": {"spot_strobe": 220}}},
    {"name": "UV Strobe Off",    "channels": {"uv": {"strobe": 0}}},
    {"name": "UV Strobe Slow",   "channels": {"uv": {"strobe": 40}}},
    {"name": "UV Strobe Med",    "channels": {"uv": {"strobe": 120}}},
    {"name": "UV Strobe Fast",   "channels": {"uv": {"strobe": 220}}},
]

# Flash-mode accent shots — active while pad is held
QUICK_SHOTS = [
    {"name": "UV Burst",      "channels": {"uv": {"dim": 255, "strobe": 200}}},
    {"name": "Strobe Hit 1",  "channels": {"hero": {"spot_strobe": 80}}},
    {"name": "Strobe Hit 2",  "channels": {"hero": {"spot_strobe": 220}}},
    {"name": "Double Flash",  "channels": {
        "hero": {"spot_strobe": 220},
        "uv": {"dim": 255, "strobe": 220},
    }},
    {"name": "Snap Left",    "channels": {"hero": {"pan": 40, "tilt": 128}}},
    {"name": "Snap Right",   "channels": {"hero": {"pan": 216, "tilt": 128}}},
    {"name": "Snap Up",      "channels": {"hero": {"pan": 128, "tilt": 40}}},
    {"name": "Gobo Snap",    "channels": {"hero": {"gobo": 52}}},
]

# ── Granular Controls (VC-only, not on Launchpad) ──

GOBO_PRESETS = [
    {"name": "Open Beam", "channels": {"hero": {"gobo": 0}}},
    {"name": "Spiral",    "channels": {"hero": {"gobo": 10}}},
    {"name": "Starburst", "channels": {"hero": {"gobo": 20}}},
    {"name": "Dots",      "channels": {"hero": {"gobo": 28}}},
    {"name": "Leaves",    "channels": {"hero": {"gobo": 36}}},
    {"name": "Lightning", "channels": {"hero": {"gobo": 44}}},
    {"name": "Web",       "channels": {"hero": {"gobo": 52}}},
    {"name": "Waves",     "channels": {"hero": {"gobo": 60}}},
]

POSITION_PRESETS = [
    {"name": "Center",      "channels": {"hero": {"pan": 128, "tilt": 128}}},
    {"name": "Stage Left",  "channels": {"hero": {"pan": 40,  "tilt": 128}}},
    {"name": "Stage Right", "channels": {"hero": {"pan": 216, "tilt": 128}}},
    {"name": "Up High",     "channels": {"hero": {"pan": 128, "tilt": 40}}},
    {"name": "Floor",       "channels": {"hero": {"pan": 128, "tilt": 220}}},
    {"name": "Upper Right", "channels": {"hero": {"pan": 200, "tilt": 60}}},
    {"name": "Lower Left",  "channels": {"hero": {"pan": 56,  "tilt": 200}}},
    {"name": "Audience",    "channels": {"hero": {"pan": 128, "tilt": 180}}},
]

ROTATION_PRESETS = [
    {"name": "Rotation Stop", "channels": {"hero": {"gobo_rot": 0}}},
    {"name": "CW Slow",      "channels": {"hero": {"gobo_rot": 20}}},
    {"name": "CW Medium",    "channels": {"hero": {"gobo_rot": 70}}},
    {"name": "CW Fast",      "channels": {"hero": {"gobo_rot": 120}}},
    {"name": "CCW Slow",     "channels": {"hero": {"gobo_rot": 140}}},
    {"name": "CCW Medium",   "channels": {"hero": {"gobo_rot": 190}}},
    {"name": "CCW Fast",     "channels": {"hero": {"gobo_rot": 245}}},
]

BEAM_PRESETS = [
    {"name": "Sharp Focus", "channels": {"hero": {"focus": 0, "prism": 0}}},
    {"name": "Soft Focus",  "channels": {"hero": {"focus": 200, "prism": 0}}},
    {"name": "Prism On",    "channels": {"hero": {"prism": 70}}},
    {"name": "Prism Spin",  "channels": {"hero": {"prism": 200}}},
    {"name": "CW Red",      "channels": {"hero": {"color_wheel": 18}}},
    {"name": "CW Green",    "channels": {"hero": {"color_wheel": 54}}},
    {"name": "CW Blue",     "channels": {"hero": {"color_wheel": 72}}},
    {"name": "CW Purple",   "channels": {"hero": {"color_wheel": 126}}},
]


# ═══════════════════════════════════════════════════════════════════════════
# EFX Definitions — beat-based @ 120 BPM (500ms/beat)
# ═══════════════════════════════════════════════════════════════════════════

EFX_DEFINITIONS = [
    {"name": "Gentle Sway",      "algorithm": "Eight",        "width": 40,  "height": 30,  "speed": 8000},
    {"name": "Rhythmic Scan",    "algorithm": "Lissajous",    "width": 80,  "height": 60,  "speed": 4000,
     "xFrequency": 2, "yFrequency": 3},
    {"name": "Bar Sweep",        "algorithm": "Line",         "width": 120, "height": 20,  "speed": 2000},
    {"name": "Beat Snap",        "algorithm": "SquareTrue",   "width": 100, "height": 80,  "speed": 1000},
    {"name": "Half-Beat Twitch", "algorithm": "Lissajous",    "width": 130, "height": 130, "speed": 500,
     "xFrequency": 3, "yFrequency": 2},
    {"name": "Glitch Jitter",    "algorithm": "Lissajous",    "width": 60,  "height": 60,  "speed": 250,
     "xFrequency": 5, "yFrequency": 7},
    {"name": "Seizure Mode",     "algorithm": "SquareChoppy", "width": 255, "height": 255, "speed": 125},
    {"name": "Chaos Engine",     "algorithm": "Lissajous",    "width": 200, "height": 150, "speed": 333,
     "xFrequency": 7, "yFrequency": 11, "rotation": 45},
]


# ═══════════════════════════════════════════════════════════════════════════
# Chaser & Collection Configuration
# ═══════════════════════════════════════════════════════════════════════════

# Which mood indices auto-cycle per phase, plus fade timing
PHASE_CHASE_CONFIG = {
    "P1": {"mood_indices": [0, 1, 6], "hold": 4000, "fade_in": 2000, "fade_out": 2000},
    "P2": {"mood_indices": [2, 4, 6], "hold": 3000, "fade_in": 1000, "fade_out": 1000},
    "P3": {"mood_indices": [3, 4, 5], "hold": 2000, "fade_in": 500,  "fade_out": 500},
    "P4": {"mood_indices": [2, 5, 6], "hold": 4000, "fade_in": 2000, "fade_out": 2000},
}

# Default mood (index into MOODS) activated with each phase collection
PHASE_DEFAULT_MOOD = {"P1": 0, "P2": 2, "P3": 3, "P4": 6}

PHASE_NAMES = ["P1 Jungle", "P2 Buildup", "P3 Peak", "P4 Release"]


# ═══════════════════════════════════════════════════════════════════════════
# All scene groups — for iteration by the builder
# ═══════════════════════════════════════════════════════════════════════════

SCENE_GROUPS = {
    "phase_textures": PHASE_TEXTURES,
    "energy":         ENERGY_LEVELS,
    "moods":          MOODS,
    "master":         MASTER_LEVELS,
    "haze":           HAZE_PRESETS,
    "strobes":        STROBE_PRESETS,
    "shots":          QUICK_SHOTS,
    "vc_gobos":       GOBO_PRESETS,
    "vc_positions":   POSITION_PRESETS,
    "vc_rotations":   ROTATION_PRESETS,
    "vc_beams":       BEAM_PRESETS,
}


# ═══════════════════════════════════════════════════════════════════════════
# Pure Compile Functions — data + rig → MCP-ready dicts
# ═══════════════════════════════════════════════════════════════════════════

def compile_scene(preset, rig):
    """Single preset dict → MCP scene dict.

    Maps fixture type names to IDs and channel names to DMX offsets
    using the rig configuration.
    """
    fixture_ids = []
    channel_values = []
    for fixture_type, channels in preset["channels"].items():
        fixture = rig[fixture_type]
        fid = fixture["id"]
        ch_map = fixture["channels"]
        fixture_ids.append(fid)
        for ch_name, value in channels.items():
            channel_values.append(
                {"fixtureID": fid, "channel": ch_map[ch_name], "value": value}
            )
    return {
        "name": preset["name"],
        "fixtureIDs": sorted(set(fixture_ids)),
        "channelValues": channel_values,
    }


def compile_scenes(presets, rig):
    """List of presets → list of MCP scene dicts."""
    return [compile_scene(p, rig) for p in presets]


def compile_all_scenes(rig):
    """Compile every scene group → dict of group_name: [MCP scene dicts]."""
    return {name: compile_scenes(presets, rig) for name, presets in SCENE_GROUPS.items()}


def compile_efx(rig):
    """EFX definitions → MCP EFX items (all target hero fixture)."""
    hero_id = rig["hero"]["id"]
    extras = ("xFrequency", "yFrequency", "xPhase", "yPhase", "rotation")
    items = []
    for d in EFX_DEFINITIONS:
        item = {
            "name": d["name"], "fixtureIDs": [hero_id],
            "algorithm": d["algorithm"], "width": d["width"],
            "height": d["height"], "speed": d["speed"],
        }
        for key in extras:
            if key in d:
                item[key] = d[key]
        items.append(item)
    return items


def compile_auto_chasers(mood_ids):
    """Phase auto-chasers: random mood color cycling per phase."""
    return [
        {
            "name": f"{phase_key} Color Cycle",
            "functionIDs": [mood_ids[i] for i in cfg["mood_indices"]],
            "fadeIn": cfg["fade_in"], "fadeOut": cfg["fade_out"],
            "holdTime": cfg["hold"],
            "runOrder": "random", "direction": "forward", "durationMode": "common",
        }
        for phase_key, cfg in PHASE_CHASE_CONFIG.items()
    ]


def compile_energy_chaser(energy_ids):
    """Auto-energy arc: Entry → Flow → Build → Bullet → Peak → Accent → Exit."""
    return [{
        "name": "Auto Energy Arc",
        "functionIDs": energy_ids,
        "fadeIn": 2000, "fadeOut": 2000, "holdTime": 8000,
        "runOrder": "single", "direction": "forward", "durationMode": "common",
    }]


def compile_buildup_chasers(strobe_ids, haze_ids, master_ids):
    """Single-shot buildup/impact chasers."""
    return [
        {"name": "Strobe Ramp",
         "functionIDs": strobe_ids[:4],
         "fadeIn": 0, "fadeOut": 0, "holdTime": 2000,
         "runOrder": "single", "direction": "forward", "durationMode": "common"},
        {"name": "UV Surge",
         "functionIDs": strobe_ids[4:],
         "fadeIn": 0, "fadeOut": 0, "holdTime": 3000,
         "runOrder": "single", "direction": "forward", "durationMode": "common"},
        {"name": "Haze Pump",
         "functionIDs": haze_ids,
         "fadeIn": 500, "fadeOut": 500, "holdTime": 5000,
         "runOrder": "single", "direction": "forward", "durationMode": "common"},
        {"name": "Blackout Hit",
         "functionIDs": [master_ids[3], master_ids[4], master_ids[3]],
         "fadeIn": 0, "fadeOut": 0, "holdTime": 200,
         "runOrder": "single", "direction": "forward", "durationMode": "common"},
    ]


def compile_vc_chasers(gobo_ids, position_ids):
    """VC-only granular automatisms."""
    return [
        {"name": "Gobo Carousel",
         "functionIDs": gobo_ids,
         "fadeIn": 500, "fadeOut": 500, "holdTime": 2000,
         "runOrder": "loop", "direction": "forward", "durationMode": "common"},
        {"name": "Position Sweep",
         "functionIDs": position_ids[:5],
         "fadeIn": 1500, "fadeOut": 1500, "holdTime": 1000,
         "runOrder": "pingpong", "direction": "forward", "durationMode": "common"},
    ]


def compile_phase_collections(phase_texture_ids, mood_ids):
    """Phase collections: texture + default mood bundled together."""
    return [
        {
            "name": name,
            "functionIDs": [phase_texture_ids[i], mood_ids[PHASE_DEFAULT_MOOD[phase_key]]],
        }
        for i, (name, phase_key) in enumerate(
            zip(PHASE_NAMES, PHASE_CHASE_CONFIG)
        )
    ]
