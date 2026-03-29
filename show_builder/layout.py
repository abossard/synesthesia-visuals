"""Launchpad and Virtual Console layout definitions.

Data + Calculations: pad geometry, input channel mapping, row definitions.
Layout structure is stable — edit scenes.py for content changes.
"""

from .palette import LP


# ── VC Geometry Constants ──

FRAME_W = 1100
BTN_W = 130
BTN_H = 55
PAD = 5
FRAME_H = 90
FRAME_GAP = 5
BTN_Y = 25  # button y offset inside frame (below header)


def launchpad_channel(row, col):
    """Launchpad pad (row 1-8, col 1-8) → QLC+ input channel."""
    return 128 + row * 10 + col


# ── Granular VC Categories (not on Launchpad) ──

GRANULAR_CATEGORIES = [
    ("vc_gobos",     "GOBOS — Spot Patterns",    True),
    ("vc_positions", "POSITIONS — Pan/Tilt",      True),
    ("vc_rotations", "ROTATION — Gobo Spin",      True),
    ("vc_beams",     "BEAMS — Focus/Prism/Color", True),
]


def get_launchpad_layout():
    """Launchpad layout definition — 8 rows of buttons.

    Each entry defines a row or split-row of Launchpad pads.
    Button references (key/idx) are resolved at build time against the ids dict.
    """
    return [
        # ── Row 8: Phase Select ──
        {"lp_row": 8, "caption": "PHASES", "solo": True, "x": 0, "w": FRAME_W, "buttons": [
            {"key": "phase_collections", "idx": 0, "label": "P1\nJungle",  "action": "toggle",
             "idle": LP["dim_green"],  "active": LP["green"],    "mode": "pulsing"},
            {"key": "phase_collections", "idx": 1, "label": "P2\nBuild",   "action": "toggle",
             "idle": LP["dim_blue"],   "active": LP["blue"],     "mode": "pulsing"},
            {"key": "phase_collections", "idx": 2, "label": "P3\nPeak",    "action": "toggle",
             "idle": LP["dim_purple"], "active": LP["purple"],   "mode": "pulsing"},
            {"key": "phase_collections", "idx": 3, "label": "P4\nRelease", "action": "toggle",
             "idle": LP["dim_cyan"],   "active": LP["cyan"],     "mode": "pulsing"},
            None, None,
            {"special": "blackout", "label": "BLACK\nOUT",
             "idle": LP["dim_red"],    "active": LP["red"],      "mode": "flashing"},
            {"special": "stopall",  "label": "STOP\nALL",
             "idle": LP["dim_red"],    "active": LP["fire_red"], "mode": "flashing"},
        ]},

        # ── Row 7: Energy Level ──
        {"lp_row": 7, "caption": "ENERGY", "solo": True, "x": 0, "w": FRAME_W, "buttons": [
            {"key": "energy",  "idx": 0, "label": "Entry",  "action": "toggle",
             "idle": LP["dim_green"],  "active": LP["dim_green"], "mode": "static"},
            {"key": "energy",  "idx": 1, "label": "Flow",   "action": "toggle",
             "idle": LP["dim_green"],  "active": LP["green"],     "mode": "static"},
            {"key": "energy",  "idx": 2, "label": "Build",  "action": "toggle",
             "idle": LP["dim_yellow"], "active": LP["yellow"],    "mode": "static"},
            {"key": "energy",  "idx": 3, "label": "Bullet", "action": "toggle",
             "idle": LP["dim_orange"], "active": LP["orange"],    "mode": "static"},
            {"key": "energy",  "idx": 4, "label": "Peak",   "action": "toggle",
             "idle": LP["dim_red"],    "active": LP["red"],       "mode": "static"},
            {"key": "energy",  "idx": 5, "label": "Accent", "action": "toggle",
             "idle": LP["dim_white"],  "active": LP["white"],     "mode": "flashing"},
            {"key": "energy",  "idx": 6, "label": "Exit",   "action": "toggle",
             "idle": LP["dim_green"],  "active": LP["dim_green"], "mode": "static"},
            {"key": "auto_energy", "idx": 0, "label": "AUTO\nENERGY", "action": "toggle",
             "idle": LP["dim_cyan"],   "active": LP["cyan"],      "mode": "pulsing"},
        ]},

        # ── Row 6: Mood Color ──
        {"lp_row": 6, "caption": "MOOD COLOR", "solo": True, "x": 0, "w": FRAME_W, "buttons": [
            {"key": "moods", "idx": 0, "label": "Jungle",  "action": "toggle",
             "idle": LP["dim_green"],  "active": LP["green"],  "mode": "static"},
            {"key": "moods", "idx": 1, "label": "Amber",   "action": "toggle",
             "idle": LP["dim_orange"], "active": LP["orange"], "mode": "static"},
            {"key": "moods", "idx": 2, "label": "Blue",    "action": "toggle",
             "idle": LP["dim_blue"],   "active": LP["blue"],   "mode": "static"},
            {"key": "moods", "idx": 3, "label": "Blood",   "action": "toggle",
             "idle": LP["dim_red"],    "active": LP["red"],    "mode": "static"},
            {"key": "moods", "idx": 4, "label": "Violet",  "action": "toggle",
             "idle": LP["dim_purple"], "active": LP["purple"], "mode": "static"},
            {"key": "moods", "idx": 5, "label": "Arctic",  "action": "toggle",
             "idle": LP["dim_white"],  "active": LP["white"],  "mode": "static"},
            {"key": "moods", "idx": 6, "label": "Cyan",    "action": "toggle",
             "idle": LP["dim_cyan"],   "active": LP["cyan"],   "mode": "static"},
            {"key": "moods", "idx": 7, "label": "Solar",   "action": "toggle",
             "idle": LP["dim_yellow"], "active": LP["yellow"], "mode": "static"},
        ]},

        # ── Row 5: Automatisms ──
        {"lp_row": 5, "caption": "AUTOMATISMS", "solo": False, "x": 0, "w": FRAME_W, "buttons": [
            {"key": "auto_chasers", "idx": 0, "label": "P1\nAuto",     "action": "toggle",
             "idle": LP["dim_green"],  "active": LP["green"],    "mode": "pulsing"},
            {"key": "auto_chasers", "idx": 1, "label": "P2\nAuto",     "action": "toggle",
             "idle": LP["dim_blue"],   "active": LP["blue"],     "mode": "pulsing"},
            {"key": "auto_chasers", "idx": 2, "label": "P3\nAuto",     "action": "toggle",
             "idle": LP["dim_purple"], "active": LP["purple"],   "mode": "pulsing"},
            {"key": "auto_chasers", "idx": 3, "label": "P4\nAuto",     "action": "toggle",
             "idle": LP["dim_cyan"],   "active": LP["cyan"],     "mode": "pulsing"},
            {"key": "buildups",     "idx": 0, "label": "Strobe\nRamp", "action": "toggle",
             "idle": LP["dim_red"],    "active": LP["red"],      "mode": "flashing"},
            {"key": "buildups",     "idx": 1, "label": "UV\nSurge",    "action": "toggle",
             "idle": LP["dim_purple"], "active": LP["purple"],   "mode": "flashing"},
            {"key": "buildups",     "idx": 2, "label": "Haze\nPump",   "action": "toggle",
             "idle": LP["dim_white"],  "active": LP["white"],    "mode": "static"},
            {"key": "buildups",     "idx": 3, "label": "BLK\nHit",     "action": "toggle",
             "idle": LP["dim_red"],    "active": LP["fire_red"], "mode": "flashing"},
        ]},

        # ── Row 4: Movement EFX ──
        {"lp_row": 4, "caption": "MOVEMENT", "solo": True, "x": 0, "w": FRAME_W, "buttons": [
            {"key": "efx", "idx": 0, "label": "Gentle\nSway",   "action": "toggle",
             "idle": LP["dim_cyan"],   "active": LP["cyan"],     "mode": "pulsing"},
            {"key": "efx", "idx": 1, "label": "Rhythmic\nScan", "action": "toggle",
             "idle": LP["dim_cyan"],   "active": LP["cyan"],     "mode": "pulsing"},
            {"key": "efx", "idx": 2, "label": "Bar\nSweep",     "action": "toggle",
             "idle": LP["dim_cyan"],   "active": LP["cyan"],     "mode": "pulsing"},
            {"key": "efx", "idx": 3, "label": "Beat\nSnap",     "action": "toggle",
             "idle": LP["dim_yellow"], "active": LP["yellow"],   "mode": "pulsing"},
            {"key": "efx", "idx": 4, "label": "½Beat\nTwitch",  "action": "toggle",
             "idle": LP["dim_orange"], "active": LP["orange"],   "mode": "pulsing"},
            {"key": "efx", "idx": 5, "label": "Glitch\nJitter", "action": "toggle",
             "idle": LP["dim_red"],    "active": LP["red"],      "mode": "flashing"},
            {"key": "efx", "idx": 6, "label": "Seizure\nMode",  "action": "toggle",
             "idle": LP["dim_red"],    "active": LP["fire_red"], "mode": "flashing"},
            {"key": "efx", "idx": 7, "label": "Chaos\nEngine",  "action": "toggle",
             "idle": LP["dim_purple"], "active": LP["purple"],   "mode": "flashing"},
        ]},

        # ── Row 3: Master Intensity (left) + Haze (right) ──
        {"lp_row": 3, "caption": "MASTER", "solo": True, "x": 0, "w": 685, "buttons": [
            {"key": "master", "idx": 0, "label": "25%",  "action": "toggle",
             "idle": LP["dim_white"], "active": LP["dim_white"],    "mode": "static"},
            {"key": "master", "idx": 1, "label": "50%",  "action": "toggle",
             "idle": LP["dim_white"], "active": LP["white"],        "mode": "static"},
            {"key": "master", "idx": 2, "label": "75%",  "action": "toggle",
             "idle": LP["dim_white"], "active": LP["white"],        "mode": "static"},
            {"key": "master", "idx": 3, "label": "100%", "action": "toggle",
             "idle": LP["dim_white"], "active": LP["bright_white"], "mode": "static"},
            {"key": "master", "idx": 4, "label": "KILL", "action": "toggle",
             "idle": LP["dim_red"],   "active": LP["red"],          "mode": "flashing"},
        ]},
        {"lp_row": 3, "caption": "HAZE", "solo": True, "x": 690, "w": 410, "buttons": [
            {"key": "haze", "idx": 0, "label": "Haze\nOff",  "action": "toggle",
             "idle": LP["dim_white"], "active": LP["dim_white"], "mode": "static"},
            {"key": "haze", "idx": 1, "label": "Haze\nLow",  "action": "toggle",
             "idle": LP["dim_white"], "active": LP["white"],     "mode": "static"},
            {"key": "haze", "idx": 2, "label": "Haze\nFull", "action": "toggle",
             "idle": LP["dim_white"], "active": LP["white"],     "mode": "static"},
        ]},

        # ── Row 2: Strobe Control (Spot left, UV right) ──
        {"lp_row": 2, "caption": "SPOT STROBE", "solo": True, "x": 0, "w": 545, "buttons": [
            {"key": "strobes", "idx": 0, "label": "Spot\nOff",  "action": "toggle",
             "idle": LP["dim_red"],    "active": LP["dim_red"],  "mode": "static"},
            {"key": "strobes", "idx": 1, "label": "Spot\nSlow", "action": "toggle",
             "idle": LP["dim_yellow"], "active": LP["yellow"],   "mode": "static"},
            {"key": "strobes", "idx": 2, "label": "Spot\nMed",  "action": "toggle",
             "idle": LP["dim_orange"], "active": LP["orange"],   "mode": "static"},
            {"key": "strobes", "idx": 3, "label": "Spot\nFast", "action": "toggle",
             "idle": LP["dim_red"],    "active": LP["red"],      "mode": "flashing"},
        ]},
        {"lp_row": 2, "caption": "UV STROBE", "solo": True, "x": 550, "w": 545, "buttons": [
            {"key": "strobes", "idx": 4, "label": "UV\nOff",  "action": "toggle",
             "idle": LP["dim_purple"], "active": LP["dim_purple"], "mode": "static"},
            {"key": "strobes", "idx": 5, "label": "UV\nSlow", "action": "toggle",
             "idle": LP["dim_purple"], "active": LP["dim_purple"], "mode": "static"},
            {"key": "strobes", "idx": 6, "label": "UV\nMed",  "action": "toggle",
             "idle": LP["dim_purple"], "active": LP["purple"],     "mode": "static"},
            {"key": "strobes", "idx": 7, "label": "UV\nFast", "action": "toggle",
             "idle": LP["dim_purple"], "active": LP["purple"],     "mode": "flashing"},
        ]},

        # ── Row 1: Quick Shots (all flash) ──
        {"lp_row": 1, "caption": "QUICK SHOTS", "solo": False, "x": 0, "w": FRAME_W, "buttons": [
            {"key": "shots", "idx": 0, "label": "UV\nBurst",    "action": "flash",
             "idle": LP["dim_purple"], "active": LP["purple"],   "mode": "static"},
            {"key": "shots", "idx": 1, "label": "Strobe\n1",    "action": "flash",
             "idle": LP["dim_red"],    "active": LP["red"],      "mode": "static"},
            {"key": "shots", "idx": 2, "label": "Strobe\n2",    "action": "flash",
             "idle": LP["dim_red"],    "active": LP["fire_red"], "mode": "static"},
            {"key": "shots", "idx": 3, "label": "Double\nFlash", "action": "flash",
             "idle": LP["dim_white"],  "active": LP["white"],    "mode": "static"},
            {"key": "shots", "idx": 4, "label": "Snap\n←",      "action": "flash",
             "idle": LP["dim_blue"],   "active": LP["blue"],     "mode": "static"},
            {"key": "shots", "idx": 5, "label": "Snap\n→",      "action": "flash",
             "idle": LP["dim_blue"],   "active": LP["blue"],     "mode": "static"},
            {"key": "shots", "idx": 6, "label": "Snap\n↑",      "action": "flash",
             "idle": LP["dim_blue"],   "active": LP["blue"],     "mode": "static"},
            {"key": "shots", "idx": 7, "label": "Gobo\nSnap",   "action": "flash",
             "idle": LP["dim_orange"], "active": LP["orange"],   "mode": "static"},
        ]},
    ]
