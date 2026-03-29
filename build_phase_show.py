#!/usr/bin/env python3
"""
Phase-Based DJ Show Builder v2.0 — Creative Performance Controller
===================================================================

Creates a phase-aware DJ lighting show for QLC+ with orthogonal layers:
  Phase  (Row 8) = WHAT texture/gobo/UV atmosphere
  Mood   (Row 6) = WHAT color (RGBW wash)
  Energy (Row 7) = HOW aggressive (movement speed, gobo rotation)
  Master (Row 3) = HOW bright (dimmer levels)

Each channel has exactly ONE owner layer — no HTP conflicts.

Launchpad Mini MK3: per-pad colors matching what the light produces.
Beat-synced chasers via OS2L (tempoType: "beats", 120 BPM baseline).

Usage:
    python3 build_phase_show.py --skip-patch --hero-id 0 --haze-id 2 --uv-id 1
"""

import json
import urllib.request
import argparse
import sys
import time


# ═══════════════════════════════════════════════════════════════════════════
# MCP Client
# ═══════════════════════════════════════════════════════════════════════════

class MCPClient:
    def __init__(self, host="127.0.0.1", port=9696):
        self.url = f"http://{host}:{port}/mcp"
        self.session = None
        self._id = 0

    def connect(self, max_retries=10, retry_delay=2):
        body = json.dumps({
            "jsonrpc": "2.0", "method": "initialize", "id": 1,
            "params": {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "phase-builder", "version": "2.0"}
            }
        }).encode()
        for attempt in range(max_retries):
            try:
                req = urllib.request.Request(self.url, body, {"Content-Type": "application/json"})
                resp = urllib.request.urlopen(req, timeout=5)
                for h in resp.headers.items():
                    if h[0].lower() == "mcp-session-id":
                        self.session = h[1]
                if not self.session:
                    raise RuntimeError("No MCP session ID in response")
                print(f"  ✓ Connected (session: {self.session[:12]}...)")
                return
            except (ConnectionRefusedError, urllib.error.URLError) as e:
                if attempt < max_retries - 1:
                    print(f"  ⏳ Waiting for server... ({attempt+1}/{max_retries})")
                    time.sleep(retry_delay)
                else:
                    raise RuntimeError(f"Cannot connect to MCP server at {self.url}: {e}")

    def call(self, tool, args, retries=2):
        self._id += 1
        body = json.dumps({
            "jsonrpc": "2.0", "method": "tools/call", "id": self._id,
            "params": {"name": tool, "arguments": args}
        }).encode()
        headers = {"Content-Type": "application/json", "Mcp-Session-Id": self.session}
        for attempt in range(retries + 1):
            try:
                req = urllib.request.Request(self.url, body, headers)
                resp = urllib.request.urlopen(req, timeout=30)
                r = json.loads(resp.read())
                return json.loads(r["result"]["content"][0]["text"])
            except Exception as e:
                if attempt < retries:
                    print(f"  ⚠ Retry {attempt+1}/{retries}: {e}")
                    time.sleep(1)
                else:
                    raise


# ═══════════════════════════════════════════════════════════════════════════
# Fixture Definitions
# ═══════════════════════════════════════════════════════════════════════════

HERO_CH = {
    "pan": 0, "pan_fine": 1, "tilt": 2, "tilt_fine": 3, "pt_speed": 4,
    "spot_dim": 5, "spot_strobe": 6, "color_wheel": 7,
    "gobo": 8, "gobo_wheel": 9, "gobo_rot": 10,
    "focus": 11, "prism": 12,
    "wash_dim": 13, "wash_strobe": 14,
    "r": 15, "g": 16, "b": 17, "w": 18,
    "color_temp": 19, "color_macro": 20, "color_seq": 21, "auto_shows": 22,
}

HAZE_CH = {"output": 0, "fan": 1}
UV_CH = {"dim": 0, "strobe": 1, "duration": 2, "sound": 3}

FIXTURE_PATCH = [
    {"manufacturer": "Varytec", "model": "Hero Spot Wash 140 2in1 RGBW+W",
     "mode": "23 Channel", "name": "Hero Spot"},
    {"manufacturer": "Cameo", "model": "Thunderwash 600 UV",
     "mode": "4 Channel", "name": "UV Wash"},
    {"manufacturer": "Stairville", "model": "Hz-200 DMX",
     "mode": "2 Channel", "name": "Haze Machine"},
]

# Gobo values: Open=0, G1=10, G2=20, G3=28, G4=36, G5=44, G6=52, G7=60, G8=70
# Color wheel: White=0, Red=18, Orange=36, Green=54, Blue=72, Yellow=90, Purple=126
# Prism: Open=0, On=70, Rotating=200


# ═══════════════════════════════════════════════════════════════════════════
# Launchpad Colors (Novation LP Mini MK3 velocity values)
# ═══════════════════════════════════════════════════════════════════════════

LP = {
    "off": 0,
    "dim_white": 2, "white": 6,
    "dim_red": 14, "red": 10, "fire_red": 120,
    "dim_orange": 22, "orange": 18,
    "dim_yellow": 30, "yellow": 26,
    "dim_green": 46, "green": 42,
    "dim_cyan": 78, "cyan": 74,
    "dim_blue": 86, "blue": 82,
    "dim_purple": 102, "purple": 98,
    "dim_magenta": 110, "magenta": 106,
    "dim_pink": 118, "pink": 114,
    "bright_white": 6,
}


# ═══════════════════════════════════════════════════════════════════════════
# Helper
# ═══════════════════════════════════════════════════════════════════════════

def cv(fid, ch, val):
    return {"fixtureID": fid, "channel": ch, "value": val}

def launchpad_channel(row, col):
    """Launchpad pad → QLC+ input channel. Row 1-8, col 1-8."""
    return 128 + row * 10 + col

# LP velocity → dark VC hex color (for button backgrounds matching pad color)
LP_TO_HEX = {
    0:   "#111111",  # off
    2:   "#3a3a3a",  # dim_white
    6:   "#555555",  # white
    10:  "#551111",  # red
    14:  "#331111",  # dim_red
    18:  "#553311",  # orange
    22:  "#332211",  # dim_orange
    26:  "#555511",  # yellow
    30:  "#333311",  # dim_yellow
    42:  "#115511",  # green
    46:  "#113311",  # dim_green
    74:  "#114455",  # cyan
    78:  "#112233",  # dim_cyan
    82:  "#112255",  # blue
    86:  "#111533",  # dim_blue
    98:  "#331155",  # purple
    102: "#221133",  # dim_purple
    106: "#551155",  # magenta
    110: "#331133",  # dim_magenta
    114: "#551133",  # pink
    118: "#331122",  # dim_pink
    120: "#552211",  # fire_red
}

def lp_bg(velocity):
    """Get dark VC background hex for a Launchpad velocity color."""
    return LP_TO_HEX.get(velocity, "#222222")

# Beat timing: 1000 = 1 beat in QLC+ beat mode
B = 1000     # 1 beat
B2 = 500     # 1/2 beat
B4 = 250     # 1/4 beat
B8 = 125     # 1/8 beat


# ═══════════════════════════════════════════════════════════════════════════
# Scene Definitions
# ═══════════════════════════════════════════════════════════════════════════

def make_phase_textures(hero_id, uv_id):
    """Phase texture scenes: gobo + prism + UV dimmer + color wheel + subtle RGBW tint.
    These set the ATMOSPHERE — not the dominant color (that's mood scenes)."""
    h = HERO_CH
    u = UV_CH
    return [
        # P1: Jungle — organic gobo, no prism, low UV glow, green spot filter
        {"name": "P1 Jungle Texture", "fixtureIDs": [hero_id, uv_id], "channelValues": [
            cv(hero_id, h["color_wheel"], 54), cv(hero_id, h["gobo"], 36),
            cv(hero_id, h["prism"], 0), cv(uv_id, u["dim"], 38),
            cv(hero_id, h["r"], 0), cv(hero_id, h["g"], 10),
            cv(hero_id, h["b"], 5), cv(hero_id, h["w"], 5)]},
        # P2: Buildup — geometric gobo, prism spread, mid UV, blue spot filter
        {"name": "P2 Buildup Texture", "fixtureIDs": [hero_id, uv_id], "channelValues": [
            cv(hero_id, h["color_wheel"], 72), cv(hero_id, h["gobo"], 28),
            cv(hero_id, h["prism"], 70), cv(uv_id, u["dim"], 128),
            cv(hero_id, h["r"], 0), cv(hero_id, h["g"], 5),
            cv(hero_id, h["b"], 10), cv(hero_id, h["w"], 5)]},
        # P3: Peak — aggressive gobo, prism rotating, high UV, purple spot filter
        {"name": "P3 Peak Texture", "fixtureIDs": [hero_id, uv_id], "channelValues": [
            cv(hero_id, h["color_wheel"], 126), cv(hero_id, h["gobo"], 44),
            cv(hero_id, h["prism"], 200), cv(uv_id, u["dim"], 204),
            cv(hero_id, h["r"], 10), cv(hero_id, h["g"], 0),
            cv(hero_id, h["b"], 10), cv(hero_id, h["w"], 0)]},
        # P4: Release — soft gobo, no prism, minimal UV, blue spot filter
        {"name": "P4 Release Texture", "fixtureIDs": [hero_id, uv_id], "channelValues": [
            cv(hero_id, h["color_wheel"], 72), cv(hero_id, h["gobo"], 60),
            cv(hero_id, h["prism"], 0), cv(uv_id, u["dim"], 25),
            cv(hero_id, h["r"], 0), cv(hero_id, h["g"], 5),
            cv(hero_id, h["b"], 10), cv(hero_id, h["w"], 5)]},
    ]


def make_energy_scenes(hero_id):
    """Energy level scenes: pan/tilt speed + gobo rotation.
    0=fastest pt_speed on Hero Spot. Higher=slower."""
    h = HERO_CH
    return [
        {"name": "E1 Entry",   "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["pt_speed"], 200), cv(hero_id, h["gobo_rot"], 0)]},
        {"name": "E2 Flow",    "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["pt_speed"], 180), cv(hero_id, h["gobo_rot"], 20)]},
        {"name": "E3 Build",   "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["pt_speed"], 140), cv(hero_id, h["gobo_rot"], 70)]},
        {"name": "E4 Bullet",  "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["pt_speed"], 100), cv(hero_id, h["gobo_rot"], 100)]},
        {"name": "E5 Peak",    "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["pt_speed"], 40),  cv(hero_id, h["gobo_rot"], 120)]},
        {"name": "E6 Accent",  "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["pt_speed"], 0),   cv(hero_id, h["gobo_rot"], 245)]},
        {"name": "E7 Exit",    "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["pt_speed"], 200), cv(hero_id, h["gobo_rot"], 0)]},
    ]


def make_mood_scenes(hero_id):
    """Wash color scenes: RGBW only. These are the dominant color source."""
    h = HERO_CH
    return [
        {"name": "Deep Jungle",   "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["r"], 0),   cv(hero_id, h["g"], 180), cv(hero_id, h["b"], 30),  cv(hero_id, h["w"], 20)]},
        {"name": "Amber Canopy",  "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["r"], 255), cv(hero_id, h["g"], 100), cv(hero_id, h["b"], 0),   cv(hero_id, h["w"], 30)]},
        {"name": "Midnight Blue", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["r"], 0),   cv(hero_id, h["g"], 0),   cv(hero_id, h["b"], 255), cv(hero_id, h["w"], 30)]},
        {"name": "Blood Moon",    "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["r"], 255), cv(hero_id, h["g"], 0),   cv(hero_id, h["b"], 0),   cv(hero_id, h["w"], 0)]},
        {"name": "Mystic Violet", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["r"], 180), cv(hero_id, h["g"], 0),   cv(hero_id, h["b"], 255), cv(hero_id, h["w"], 0)]},
        {"name": "Arctic White",  "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["r"], 40),  cv(hero_id, h["g"], 40),  cv(hero_id, h["b"], 60),  cv(hero_id, h["w"], 255)]},
        {"name": "Tropical Cyan", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["r"], 0),   cv(hero_id, h["g"], 200), cv(hero_id, h["b"], 255), cv(hero_id, h["w"], 30)]},
        {"name": "Solar Flare",   "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["r"], 255), cv(hero_id, h["g"], 200), cv(hero_id, h["b"], 0),   cv(hero_id, h["w"], 80)]},
    ]


def make_master_scenes(hero_id):
    """Dimmer step scenes: spot_dim + wash_dim. Sole owner of dimmer channels."""
    h = HERO_CH
    return [
        {"name": "Master 25%",  "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_dim"], 64),  cv(hero_id, h["wash_dim"], 64)]},
        {"name": "Master 50%",  "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_dim"], 128), cv(hero_id, h["wash_dim"], 128)]},
        {"name": "Master 75%",  "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_dim"], 192), cv(hero_id, h["wash_dim"], 192)]},
        {"name": "Master 100%", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_dim"], 255), cv(hero_id, h["wash_dim"], 255)]},
        {"name": "KILL Dimmer", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_dim"], 0),   cv(hero_id, h["wash_dim"], 0)]},
    ]


def make_haze_scenes(haze_id):
    """Haze control scenes."""
    z = HAZE_CH
    return [
        {"name": "Haze Off",  "fixtureIDs": [haze_id], "channelValues": [
            cv(haze_id, z["output"], 0),   cv(haze_id, z["fan"], 0)]},
        {"name": "Haze Low",  "fixtureIDs": [haze_id], "channelValues": [
            cv(haze_id, z["output"], 80),  cv(haze_id, z["fan"], 120)]},
        {"name": "Haze Full", "fixtureIDs": [haze_id], "channelValues": [
            cv(haze_id, z["output"], 255), cv(haze_id, z["fan"], 200)]},
    ]


def make_strobe_scenes(hero_id, uv_id):
    """Strobe preset scenes. Spot strobe + UV strobe independent."""
    h = HERO_CH
    u = UV_CH
    return [
        {"name": "Spot Strobe Off",  "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_strobe"], 0)]},
        {"name": "Spot Strobe Slow", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_strobe"], 40)]},
        {"name": "Spot Strobe Med",  "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_strobe"], 120)]},
        {"name": "Spot Strobe Fast", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_strobe"], 220)]},
        {"name": "UV Strobe Off",    "fixtureIDs": [uv_id], "channelValues": [
            cv(uv_id, u["strobe"], 0)]},
        {"name": "UV Strobe Slow",   "fixtureIDs": [uv_id], "channelValues": [
            cv(uv_id, u["strobe"], 40)]},
        {"name": "UV Strobe Med",    "fixtureIDs": [uv_id], "channelValues": [
            cv(uv_id, u["strobe"], 120)]},
        {"name": "UV Strobe Fast",   "fixtureIDs": [uv_id], "channelValues": [
            cv(uv_id, u["strobe"], 220)]},
    ]


def make_quick_shots(hero_id, uv_id):
    """Flash-mode accent scenes — fire while pad is held."""
    h = HERO_CH
    u = UV_CH
    return [
        {"name": "UV Burst",     "fixtureIDs": [uv_id], "channelValues": [
            cv(uv_id, u["dim"], 255), cv(uv_id, u["strobe"], 200)]},
        {"name": "Strobe Hit 1", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_strobe"], 80)]},
        {"name": "Strobe Hit 2", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_strobe"], 220)]},
        {"name": "Double Flash", "fixtureIDs": [hero_id, uv_id], "channelValues": [
            cv(hero_id, h["spot_strobe"], 220), cv(uv_id, u["dim"], 255), cv(uv_id, u["strobe"], 220)]},
        {"name": "Snap Left",    "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["pan"], 40), cv(hero_id, h["tilt"], 128)]},
        {"name": "Snap Right",   "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["pan"], 216), cv(hero_id, h["tilt"], 128)]},
        {"name": "Snap Up",      "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["pan"], 128), cv(hero_id, h["tilt"], 40)]},
        {"name": "Snap Down",    "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["pan"], 128), cv(hero_id, h["tilt"], 220)]},
        {"name": "Gobo Snap",    "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["gobo"], 52)]},  # Web gobo — surprise texture
    ]


# Color wheel DMX values for the Hero Spot 140
CW_WHITE = 0
CW_RED = 10
CW_ORANGE = 18
CW_GREEN = 26
CW_BLUE = 34
CW_YELLOW = 42
CW_PURPLE = 50
CW_LIGHT_BLUE = 58


def make_phantom_scan_pairs(hero_id):
    """Phantom Scan: dark snap out → beam reveal + slow sweep back.
    Returns list of (dark_scene, beam_scene, color_name) tuples.
    Each pair becomes a 2-step beat-synced chaser."""
    h = HERO_CH
    variants = [
        ("Red",        CW_RED,        8),   # gobo 1 (spiral pattern)
        ("Blue",       CW_BLUE,       0),   # open beam
        ("Green",      CW_GREEN,      36),  # gobo 4 (leaves)
        ("Purple",     CW_PURPLE,     20),  # gobo 2 (starburst)
    ]
    pairs = []
    for color_name, cw_val, gobo_val in variants:
        # Step 1: DARK — snap to start position, lights off, max speed
        dark = {"name": f"Phantom {color_name} Dark", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_dim"], 0),       # spot off
            cv(hero_id, h["wash_dim"], 0),       # wash off (clean beam only)
            cv(hero_id, h["pan"], 0),             # far left (full range)
            cv(hero_id, h["tilt"], 128),          # center tilt
            cv(hero_id, h["pt_speed"], 0),        # max speed (instant snap)
            cv(hero_id, h["color_wheel"], cw_val),# arm color for next step
            cv(hero_id, h["gobo"], gobo_val),     # arm gobo
            cv(hero_id, h["focus"], 0),           # sharp focus
            cv(hero_id, h["prism"], 0),           # no prism
        ]}
        # Step 2: BEAM — reveal at far right, then slow sweep back
        beam = {"name": f"Phantom {color_name} Beam", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_dim"], 255),      # BEAM ON
            cv(hero_id, h["wash_dim"], 0),        # wash stays off (spot beam only)
            cv(hero_id, h["pan"], 255),            # far right (full range)
            cv(hero_id, h["tilt"], 128),           # center tilt
            cv(hero_id, h["pt_speed"], 220),       # SLOW speed for dramatic return
            cv(hero_id, h["color_wheel"], cw_val), # beam color
            cv(hero_id, h["gobo"], gobo_val),      # beam pattern
            cv(hero_id, h["focus"], 0),            # sharp focus
        ]}
        pairs.append((dark, beam, color_name))
    return pairs


def make_granular_scenes(hero_id):
    """VC-only granular controls: gobos, positions, rotations, beams."""
    h = HERO_CH
    gobos = [
        {"name": "Open Beam",  "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["gobo"], 0)]},
        {"name": "Spiral",     "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["gobo"], 10)]},
        {"name": "Starburst",  "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["gobo"], 20)]},
        {"name": "Dots",       "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["gobo"], 28)]},
        {"name": "Leaves",     "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["gobo"], 36)]},
        {"name": "Lightning",  "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["gobo"], 44)]},
        {"name": "Web",        "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["gobo"], 52)]},
        {"name": "Waves",      "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["gobo"], 60)]},
    ]
    positions = [
        {"name": "Center",      "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["pan"], 128), cv(hero_id, h["tilt"], 128)]},
        {"name": "Stage Left",  "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["pan"], 40),  cv(hero_id, h["tilt"], 128)]},
        {"name": "Stage Right", "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["pan"], 216), cv(hero_id, h["tilt"], 128)]},
        {"name": "Up High",     "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["pan"], 128), cv(hero_id, h["tilt"], 40)]},
        {"name": "Floor",       "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["pan"], 128), cv(hero_id, h["tilt"], 220)]},
        {"name": "Upper Right", "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["pan"], 200), cv(hero_id, h["tilt"], 60)]},
        {"name": "Lower Left",  "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["pan"], 56),  cv(hero_id, h["tilt"], 200)]},
        {"name": "Audience",    "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["pan"], 128), cv(hero_id, h["tilt"], 180)]},
    ]
    rotations = [
        {"name": "Rotation Stop", "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["gobo_rot"], 0)]},
        {"name": "CW Slow",       "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["gobo_rot"], 20)]},
        {"name": "CW Medium",     "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["gobo_rot"], 70)]},
        {"name": "CW Fast",       "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["gobo_rot"], 120)]},
        {"name": "CCW Slow",      "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["gobo_rot"], 140)]},
        {"name": "CCW Medium",    "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["gobo_rot"], 190)]},
        {"name": "CCW Fast",      "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["gobo_rot"], 245)]},
    ]
    beams = [
        {"name": "Sharp Focus", "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["focus"], 0),   cv(hero_id, h["prism"], 0)]},
        {"name": "Soft Focus",  "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["focus"], 200), cv(hero_id, h["prism"], 0)]},
        {"name": "Prism On",    "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["prism"], 70)]},
        {"name": "Prism Spin",  "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["prism"], 200)]},
        {"name": "CW Red",      "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["color_wheel"], 18)]},
        {"name": "CW Green",    "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["color_wheel"], 54)]},
        {"name": "CW Blue",     "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["color_wheel"], 72)]},
        {"name": "CW Purple",   "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["color_wheel"], 126)]},
    ]
    return {"gobos": gobos, "positions": positions, "rotations": rotations, "beams": beams}


# ═══════════════════════════════════════════════════════════════════════════
# EFX Definitions — beat-based @ 120 BPM (500ms/beat)
# ═══════════════════════════════════════════════════════════════════════════

EFX_DEFS = [
    # Gentle — 16 beats
    {"name": "Gentle Sway",      "algorithm": "Eight",        "width": 40,  "height": 30,  "speed": 8000},
    # Musical — 8 beats, off-axis Lissajous
    {"name": "Rhythmic Scan",    "algorithm": "Lissajous",    "width": 80,  "height": 60,  "speed": 4000,
     "xFrequency": 2, "yFrequency": 3},
    # Directional — 4 beats horizontal
    {"name": "Bar Sweep",        "algorithm": "Line",         "width": 120, "height": 20,  "speed": 2000},
    # Punchy — 2 beats corner snaps
    {"name": "Beat Snap",        "algorithm": "SquareTrue",   "width": 100, "height": 80,  "speed": 1000},
    # Nervous — 1 beat twitchy
    {"name": "Half-Beat Twitch", "algorithm": "Lissajous",    "width": 130, "height": 130, "speed": 500,
     "xFrequency": 3, "yFrequency": 2},
    # Micro — 1/2 beat jitter
    {"name": "Glitch Jitter",    "algorithm": "Lissajous",    "width": 60,  "height": 60,  "speed": 250,
     "xFrequency": 5, "yFrequency": 7},
    # Extreme — 1/4 beat full-range
    {"name": "Seizure Mode",     "algorithm": "SquareChoppy", "width": 255, "height": 255, "speed": 125},
    # Polyrhythmic chaos
    {"name": "Chaos Engine",     "algorithm": "Lissajous",    "width": 200, "height": 150, "speed": 333,
     "xFrequency": 7, "yFrequency": 11, "rotation": 45},
]

# Which moods belong to each phase's auto-chaser (indices into mood_ids)
PHASE_CHASE_MOODS = {
    "P1": [0, 1, 6],  # Deep Jungle, Amber Canopy, Tropical Cyan
    "P2": [2, 4, 6],  # Midnight Blue, Mystic Violet, Tropical Cyan
    "P3": [3, 4, 5],  # Blood Moon, Mystic Violet, Arctic White
    "P4": [2, 5, 6],  # Midnight Blue, Arctic White, Tropical Cyan
}

# Phase chaser timing (holdTime, fadeIn, fadeOut) in BEATS (1000 = 1 beat)
PHASE_CHASE_TIMING = {
    "P1": (8 * B, 4 * B, 4 * B),   # 8 beats hold, 4 beats fade — slow
    "P2": (6 * B, 2 * B, 2 * B),   # 6 beats hold, 2 beats fade
    "P3": (4 * B, 1 * B, 1 * B),   # 4 beats hold, 1 beat fade — fast snaps
    "P4": (8 * B, 4 * B, 4 * B),   # same as P1 — back to slow
}

# Default mood per phase (index into mood_ids)
PHASE_DEFAULT_MOOD = {"P1": 0, "P2": 2, "P3": 3, "P4": 6}


def create_scenes_batch(client, label, scenes):
    """Create a batch of scenes and return their IDs."""
    print(f"  🎬 {label:20s} ({len(scenes):2d})...", end=" ", flush=True)
    results = client.call("create_scenes", {"items": scenes})
    ids = [s["id"] for s in results]
    print(f"✓ IDs: {ids}")
    return ids


def create_all_functions(client, hero_id, haze_id, uv_id):
    """Create all scenes, EFX, chasers, collections. Returns ids dict."""
    ids = {}

    print("\n══════════════════════════════════════════")
    print("  CREATING SCENES")
    print("══════════════════════════════════════════")

    ids["phase_textures"] = create_scenes_batch(client, "Phase textures", make_phase_textures(hero_id, uv_id))
    ids["energy"]         = create_scenes_batch(client, "Energy levels",  make_energy_scenes(hero_id))
    ids["moods"]          = create_scenes_batch(client, "Mood colors",    make_mood_scenes(hero_id))
    ids["master"]         = create_scenes_batch(client, "Master intensity", make_master_scenes(hero_id))
    ids["haze"]           = create_scenes_batch(client, "Haze control",   make_haze_scenes(haze_id))
    ids["strobes"]        = create_scenes_batch(client, "Strobe presets", make_strobe_scenes(hero_id, uv_id))
    ids["shots"]          = create_scenes_batch(client, "Quick shots",    make_quick_shots(hero_id, uv_id))

    # Granular scenes (VC only)
    granular = make_granular_scenes(hero_id)
    for cat, scenes in granular.items():
        ids[f"vc_{cat}"] = create_scenes_batch(client, f"VC {cat}", scenes)

    print("\n══════════════════════════════════════════")
    print("  CREATING EFX")
    print("══════════════════════════════════════════")

    efx_items = []
    for d in EFX_DEFS:
        item = {"name": d["name"], "fixtureIDs": [hero_id],
                "algorithm": d["algorithm"], "width": d["width"],
                "height": d["height"], "speed": d["speed"]}
        for extra in ("xFrequency", "yFrequency", "xPhase", "yPhase", "rotation"):
            if extra in d:
                item[extra] = d[extra]
        efx_items.append(item)

    print(f"  ✨ {'EFX':20s} ({len(efx_items):2d})...", end=" ", flush=True)
    efx_results = client.call("create_efxs", {"items": efx_items})
    ids["efx"] = [e["id"] for e in efx_results]
    print(f"✓ IDs: {ids['efx']}")

    # Phantom Scan scenes (dark+beam pairs per color)
    phantom_pairs = make_phantom_scan_pairs(hero_id)
    phantom_dark_scenes = [p[0] for p in phantom_pairs]
    phantom_beam_scenes = [p[1] for p in phantom_pairs]
    all_phantom = phantom_dark_scenes + phantom_beam_scenes
    print(f"  🔦 {'Phantom scenes':20s} ({len(all_phantom):2d})...", end=" ", flush=True)
    phantom_results = client.call("create_scenes", {"items": all_phantom})
    phantom_ids = [s["id"] for s in phantom_results]
    n = len(phantom_pairs)
    dark_ids = phantom_ids[:n]
    beam_ids = phantom_ids[n:]
    print(f"✓ dark={dark_ids}, beam={beam_ids}")

    # Phantom Scan chasers — per-step timing now possible!
    phantom_chaser_items = []
    for i, (_, _, color_name) in enumerate(phantom_pairs):
        phantom_chaser_items.append({
            "name": f"Phantom {color_name}",
            "steps": [
                {"functionID": dark_ids[i], "fadeIn": 0, "hold": 1 * B, "fadeOut": 0},  # 1 beat dark (head snap time)
                {"functionID": beam_ids[i], "fadeIn": 0, "hold": 8 * B, "fadeOut": 0},  # 8 beat beam sweep
            ],
            "runOrder": "loop", "direction": "forward", "tempoType": "beats",
        })
    print(f"  🔁 {'Phantom chasers':20s} ({len(phantom_chaser_items):2d})...", end=" ", flush=True)
    phantom_ch_results = client.call("create_chasers", {"items": phantom_chaser_items})
    ids["phantoms"] = [c["id"] for c in phantom_ch_results]
    print(f"✓ IDs: {ids['phantoms']}")

    print("\n══════════════════════════════════════════")
    print("  CREATING CHASERS")
    print("══════════════════════════════════════════")

    # Helper: build uniform steps from function IDs + common timing
    def uniform_steps(func_ids, fade_in, hold, fade_out):
        return [{"functionID": fid, "fadeIn": fade_in, "hold": hold, "fadeOut": fade_out}
                for fid in func_ids]

    # Phase auto-chasers (random mood cycling per phase, beat-synced)
    auto_chaser_items = []
    for phase_key, mood_indices in PHASE_CHASE_MOODS.items():
        hold, fi, fo = PHASE_CHASE_TIMING[phase_key]
        auto_chaser_items.append({
            "name": f"{phase_key} Color Cycle",
            "steps": uniform_steps([ids["moods"][i] for i in mood_indices], fi, hold, fo),
            "runOrder": "random", "direction": "forward", "tempoType": "beats",
        })
    print(f"  🔁 {'Phase auto-chasers':20s} ({len(auto_chaser_items):2d})...", end=" ", flush=True)
    auto_results = client.call("create_chasers", {"items": auto_chaser_items})
    ids["auto_chasers"] = [c["id"] for c in auto_results]
    print(f"✓ IDs: {ids['auto_chasers']}")

    # Auto-energy chaser (Entry→Flow→Build→Bullet→Peak→Accent→Exit, beat-synced)
    print(f"  🔁 {'Auto-energy chaser':20s} ( 1)...", end=" ", flush=True)
    ae_result = client.call("create_chasers", {"items": [{
        "name": "Auto Energy Arc",
        "steps": uniform_steps(ids["energy"], 2 * B, 8 * B, 2 * B),
        "runOrder": "single", "direction": "forward", "tempoType": "beats",
    }]})
    ids["auto_energy"] = [ae_result[0]["id"]]
    print(f"✓ IDs: {ids['auto_energy']}")

    # Buildup chasers (single-shot ramps, beat-synced)
    buildup_items = [
        {"name": "Strobe Ramp",
         "steps": uniform_steps(
             [ids["strobes"][0], ids["strobes"][1], ids["strobes"][2], ids["strobes"][3]],
             0, 4 * B, 0),
         "runOrder": "single", "direction": "forward", "tempoType": "beats"},
        {"name": "UV Surge",
         "steps": uniform_steps(
             [ids["strobes"][4], ids["strobes"][5], ids["strobes"][6], ids["strobes"][7]],
             0, 6 * B, 0),
         "runOrder": "single", "direction": "forward", "tempoType": "beats"},
        {"name": "Haze Pump",
         "steps": uniform_steps(
             [ids["haze"][0], ids["haze"][1], ids["haze"][2]],
             1 * B, 8 * B, 1 * B),
         "runOrder": "single", "direction": "forward", "tempoType": "beats"},
        {"name": "Blackout Hit",
         "steps": [
             {"functionID": ids["master"][3], "fadeIn": 0, "hold": B4, "fadeOut": 0},
             {"functionID": ids["master"][4], "fadeIn": 0, "hold": B4, "fadeOut": 0},
             {"functionID": ids["master"][3], "fadeIn": 0, "hold": B4, "fadeOut": 0},
         ],
         "runOrder": "single", "direction": "forward", "tempoType": "beats"},
    ]
    print(f"  🔁 {'Buildups':20s} ({len(buildup_items):2d})...", end=" ", flush=True)
    bu_results = client.call("create_chasers", {"items": buildup_items})
    ids["buildups"] = [c["id"] for c in bu_results]
    print(f"✓ IDs: {ids['buildups']}")

    # Gobo carousel + position sweep (VC automatisms, beat-synced)
    vc_chasers = [
        {"name": "Gobo Carousel",
         "steps": uniform_steps(ids["vc_gobos"], 1 * B, 4 * B, 1 * B),
         "runOrder": "loop", "direction": "forward", "tempoType": "beats"},
        {"name": "Position Sweep",
         "steps": uniform_steps(ids["vc_positions"][:5], 3 * B, 2 * B, 3 * B),
         "runOrder": "pingpong", "direction": "forward", "tempoType": "beats"},
    ]
    print(f"  🔁 {'VC chasers':20s} ({len(vc_chasers):2d})...", end=" ", flush=True)
    vc_ch_results = client.call("create_chasers", {"items": vc_chasers})
    ids["vc_chasers"] = [c["id"] for c in vc_ch_results]
    print(f"✓ IDs: {ids['vc_chasers']}")

    print("\n══════════════════════════════════════════")
    print("  CREATING COLLECTIONS")
    print("══════════════════════════════════════════")

    # Phase collections: texture + default mood
    phase_keys = ["P1", "P2", "P3", "P4"]
    phase_names = ["P1 Jungle", "P2 Buildup", "P3 Peak", "P4 Release"]
    coll_items = []
    for i, (pk, pn) in enumerate(zip(phase_keys, phase_names)):
        mood_idx = PHASE_DEFAULT_MOOD[pk]
        coll_items.append({
            "name": pn,
            "functionIDs": [ids["phase_textures"][i], ids["moods"][mood_idx]],
        })
    print(f"  📦 {'Phase collections':20s} ({len(coll_items):2d})...", end=" ", flush=True)
    coll_results = client.call("create_collections", {"items": coll_items})
    ids["phase_collections"] = [c["id"] for c in coll_results]
    print(f"✓ IDs: {ids['phase_collections']}")

    print("\n══════════════════════════════════════════")
    print("  CREATING SCRIPTS")
    print("══════════════════════════════════════════")

    # EFX per phase (index into efx list): P1=gentle, P2=rhythmic, P3=snap, P4=gentle(same)
    phase_efx = [ids["efx"][0], ids["efx"][1], ids["efx"][3], ids["efx"][0]]

    # Phase transition scripts — stop everything old, start everything new
    # Deduplicates stops and never stops a function it's about to start
    transition_scripts = []
    for i, (pk, pn) in enumerate(zip(phase_keys, phase_names)):
        # What this phase will start
        start_ids = {ids["phase_collections"][i], ids["auto_chasers"][i], phase_efx[i]}
        # What other phases own — deduplicated, excluding what we're starting
        stop_ids = set()
        for j in range(4):
            if j != i:
                stop_ids.add(ids["phase_collections"][j])
                stop_ids.add(ids["auto_chasers"][j])
                stop_ids.add(phase_efx[j])
        stop_ids -= start_ids  # never stop what we're about to start

        commands = [{"type": "stopfunction", "functionID": fid} for fid in sorted(stop_ids)]
        commands += [{"type": "startfunction", "functionID": fid} for fid in sorted(start_ids)]
        transition_scripts.append({"name": f"GO {pn}", "commands": commands})

    # Impact scripts — layer accents on top of current phase
    impact_scripts = [
        # Drop Hit: blackout flash + strobe ramp + peak energy
        {"name": "DROP HIT", "commands": [
            {"type": "startfunction", "functionID": ids["buildups"][3]},   # Blackout Hit chaser
            {"type": "startfunction", "functionID": ids["buildups"][0]},   # Strobe Ramp chaser
            {"type": "startfunction", "functionID": ids["energy"][4]},     # E5 Peak energy
        ]},
        # UV + Strobe Blast: UV surge + spot strobe + accent energy
        {"name": "UV STROBE BLAST", "commands": [
            {"type": "startfunction", "functionID": ids["buildups"][1]},   # UV Surge chaser
            {"type": "startfunction", "functionID": ids["strobes"][3]},    # Spot Strobe Fast
            {"type": "startfunction", "functionID": ids["energy"][5]},     # E6 Accent
        ]},
        # Tension Build: haze pump + slow strobe ramp + build energy
        {"name": "TENSION BUILD", "commands": [
            {"type": "startfunction", "functionID": ids["buildups"][2]},   # Haze Pump chaser
            {"type": "startfunction", "functionID": ids["buildups"][0]},   # Strobe Ramp chaser
            {"type": "startfunction", "functionID": ids["energy"][2]},     # E3 Build energy
            {"type": "startfunction", "functionID": ids["efx"][4]},        # Half-Beat Twitch
        ]},
        # Calm Reset: stop all strobes/buildups, set entry energy, gentle EFX
        {"name": "CALM RESET", "commands": [
            {"type": "stopfunction", "functionID": ids["buildups"][0]},    # Stop Strobe Ramp
            {"type": "stopfunction", "functionID": ids["buildups"][1]},    # Stop UV Surge
            {"type": "stopfunction", "functionID": ids["strobes"][3]},     # Stop Spot Strobe Fast
            {"type": "stopfunction", "functionID": ids["strobes"][7]},     # Stop UV Strobe Fast
            {"type": "startfunction", "functionID": ids["strobes"][0]},    # Spot Strobe Off
            {"type": "startfunction", "functionID": ids["strobes"][4]},    # UV Strobe Off
            {"type": "startfunction", "functionID": ids["energy"][0]},     # E1 Entry
            {"type": "startfunction", "functionID": ids["efx"][0]},        # Gentle Sway
        ]},
        # Chaos Moment: everything extreme, then self-resolves via single-run chasers
        {"name": "CHAOS MOMENT", "commands": [
            {"type": "startfunction", "functionID": ids["efx"][7]},        # Chaos Engine
            {"type": "startfunction", "functionID": ids["buildups"][0]},   # Strobe Ramp
            {"type": "startfunction", "functionID": ids["buildups"][1]},   # UV Surge
            {"type": "startfunction", "functionID": ids["energy"][5]},     # E6 Accent
        ]},
        # Clean Stop: stop all running effects, return to neutral
        {"name": "CLEAN STOP", "commands": [
            {"type": "stopfunction", "functionID": ids["buildups"][0]},
            {"type": "stopfunction", "functionID": ids["buildups"][1]},
            {"type": "stopfunction", "functionID": ids["buildups"][2]},
            {"type": "stopfunction", "functionID": ids["buildups"][3]},
            {"type": "stopfunction", "functionID": ids["strobes"][3]},
            {"type": "stopfunction", "functionID": ids["strobes"][7]},
            {"type": "startfunction", "functionID": ids["strobes"][0]},    # Spot Strobe Off
            {"type": "startfunction", "functionID": ids["strobes"][4]},    # UV Strobe Off
            {"type": "startfunction", "functionID": ids["energy"][0]},     # E1 Entry
        ]},
    ]

    all_scripts = transition_scripts + impact_scripts
    print(f"  📜 {'Scripts':20s} ({len(all_scripts):2d})...", end=" ", flush=True)
    script_results = client.call("create_scripts", {"items": all_scripts})
    ids["transition_scripts"] = [s["id"] for s in script_results[:4]]
    ids["impact_scripts"] = [s["id"] for s in script_results[4:]]
    print(f"✓ IDs: transitions={ids['transition_scripts']}, impacts={ids['impact_scripts']}")

    # Count total
    total = sum(len(v) for v in ids.values())
    print(f"\n  ═══ {total} functions created ═══")

    return ids


# ═══════════════════════════════════════════════════════════════════════════
# VC + Launchpad — Declarative Show Page
# ═══════════════════════════════════════════════════════════════════════════

def lp(row, col):
    """Pad grid → QLC+ input channel."""
    return 128 + row * 10 + col

def btn(name, action="toggle", idle=0, active=0, mode="pulsing", ch=None):
    """Build a button dict for build_show_page. ch=LP input channel.
    Monitor = idle color but pulsing (shows function is running via another trigger)."""
    b = {
        "caption": name, "action": action, "functionName": name,
        "bgColor": lp_bg(idle), "fgColor": "#ffffff",
        "idleValue": idle, "activeValue": active, "activeMode": mode,
        "monitorValue": idle, "monitorMode": "pulsing",
    }
    if ch is not None:
        b["inputChannel"] = ch
    if action in ("blackout", "stopall"):
        del b["functionName"]
    return b

def build_show_page(client, lp_universe):
    """Build the full VC + Launchpad layout via single build_show_page call."""
    print("\n══════════════════════════════════════════")
    print("  BUILDING SHOW PAGE")
    print("══════════════════════════════════════════")

    L = LP  # shorthand
    u = lp_universe

    W = L["white"]       # default active color
    R = L["fire_red"]    # DANGER active color

    sections = [
        # ── Row 8: Phase Transitions ──
        {"caption": "PHASES", "solo": False, "buttons": [
            btn("GO P1 Jungle",  "flash", L["dim_green"],  W, "flashing", lp(8,1)),
            btn("GO P2 Buildup", "flash", L["dim_blue"],   W, "flashing", lp(8,2)),
            btn("GO P3 Peak",    "flash", L["dim_purple"], W, "flashing", lp(8,3)),
            btn("GO P4 Release", "flash", L["dim_cyan"],   W, "flashing", lp(8,4)),
            btn("STOP ALL", "stopall", L["dim_red"], R, "flashing", lp(8,8)),
        ]},

        # ── Row 7: Energy ──
        {"caption": "ENERGY", "solo": True, "buttons": [
            btn("E1 Entry",  "toggle", L["dim_green"],  W, "pulsing", lp(7,1)),
            btn("E2 Flow",   "toggle", L["dim_green"],  W, "pulsing", lp(7,2)),
            btn("E3 Build",  "toggle", L["dim_yellow"], W, "pulsing", lp(7,3)),
            btn("E4 Bullet", "toggle", L["dim_orange"], W, "pulsing", lp(7,4)),
            btn("E5 Peak",   "toggle", L["dim_red"],    W, "pulsing", lp(7,5)),
            btn("E6 Accent", "toggle", L["dim_white"],  W, "pulsing", lp(7,6)),
            btn("E7 Exit",   "toggle", L["dim_green"],  W, "pulsing", lp(7,7)),
            btn("Auto Energy Arc", "toggle", L["dim_cyan"], W, "pulsing", lp(7,8)),
        ]},

        # ── Row 6: Mood Color ──
        {"caption": "MOOD COLOR", "solo": True, "buttons": [
            btn("Deep Jungle",   "toggle", L["dim_green"],  W, "pulsing", lp(6,1)),
            btn("Amber Canopy",  "toggle", L["dim_orange"], W, "pulsing", lp(6,2)),
            btn("Midnight Blue", "toggle", L["dim_blue"],   W, "pulsing", lp(6,3)),
            btn("Blood Moon",    "toggle", L["dim_red"],    W, "pulsing", lp(6,4)),
            btn("Mystic Violet", "toggle", L["dim_purple"], W, "pulsing", lp(6,5)),
            btn("Arctic White",  "toggle", L["dim_white"],  W, "pulsing", lp(6,6)),
            btn("Tropical Cyan", "toggle", L["dim_cyan"],   W, "pulsing", lp(6,7)),
            btn("Solar Flare",   "toggle", L["dim_yellow"], W, "pulsing", lp(6,8)),
        ]},

        # ── Row 5: Impact Scripts ──
        {"caption": "IMPACTS", "solo": False, "buttons": [
            btn("DROP HIT",        "flash", L["dim_red"],    R, "flashing", lp(5,1)),      # DANGER
            btn("UV STROBE BLAST", "flash", L["dim_purple"], R, "flashing", lp(5,2)),      # heavy strobe
            btn("TENSION BUILD",   "flash", L["dim_orange"], W, "flashing", lp(5,3)),
            btn("CALM RESET",      "flash", L["dim_green"],  W, "flashing", lp(5,4)),
            btn("CHAOS MOMENT",    "flash", L["dim_red"],    R, "flashing", lp(5,5)),      # DANGER
            btn("CLEAN STOP",      "flash", L["dim_white"],  W, "flashing", lp(5,6)),
        ]},

        # ── Row 4: Movement EFX ──
        {"caption": "MOVEMENT", "solo": True, "buttons": [
            btn("Gentle Sway",      "toggle", L["dim_cyan"],   W, "pulsing",  lp(4,1)),
            btn("Rhythmic Scan",    "toggle", L["dim_blue"],   W, "pulsing",  lp(4,2)),
            btn("Bar Sweep",        "toggle", L["dim_blue"],   W, "pulsing",  lp(4,3)),
            btn("Beat Snap",        "toggle", L["dim_yellow"], W, "pulsing",  lp(4,4)),
            btn("Half-Beat Twitch", "toggle", L["dim_orange"], W, "pulsing",  lp(4,5)),
            btn("Glitch Jitter",    "toggle", L["dim_red"],    W, "pulsing",  lp(4,6)),
            btn("Seizure Mode",     "toggle", L["dim_red"],    R, "flashing", lp(4,7)),    # DANGER
            btn("Chaos Engine",     "toggle", L["dim_red"],    R, "flashing", lp(4,8)),    # DANGER
        ]},

        # ── Row 3: Master Intensity ──
        {"caption": "MASTER", "solo": True, "buttons": [
            btn("Master 25%",  "toggle", L["dim_white"], W, "pulsing",  lp(3,1)),
            btn("Master 50%",  "toggle", L["dim_white"], W, "pulsing",  lp(3,2)),
            btn("Master 75%",  "toggle", L["dim_white"], W, "pulsing",  lp(3,3)),
            btn("Master 100%", "toggle", L["dim_white"], W, "pulsing",  lp(3,4)),
            btn("KILL Dimmer", "toggle", L["dim_red"],   R, "flashing", lp(3,5)),          # DANGER
        ]},

        # ── Row 3 right: Haze ──
        {"caption": "HAZE", "solo": True, "buttons": [
            btn("Haze Off",  "toggle", L["dim_white"], W, "pulsing", lp(3,6)),
            btn("Haze Low",  "toggle", L["dim_white"], W, "pulsing", lp(3,7)),
            btn("Haze Full", "toggle", L["dim_white"], W, "pulsing", lp(3,8)),
        ]},

        # ── Row 2: Spot Strobe ──
        {"caption": "SPOT STROBE", "solo": True, "buttons": [
            btn("Spot Strobe Off",  "toggle", L["dim_green"],  W, "pulsing",  lp(2,1)),
            btn("Spot Strobe Slow", "toggle", L["dim_yellow"], W, "pulsing",  lp(2,2)),
            btn("Spot Strobe Med",  "toggle", L["dim_orange"], W, "pulsing",  lp(2,3)),
            btn("Spot Strobe Fast", "toggle", L["dim_red"],    R, "flashing", lp(2,4)),    # DANGER
        ]},

        # ── Row 2 right: UV Strobe ──
        {"caption": "UV STROBE", "solo": True, "buttons": [
            btn("UV Strobe Off",  "toggle", L["dim_green"],  W, "pulsing",  lp(2,5)),
            btn("UV Strobe Slow", "toggle", L["dim_purple"], W, "pulsing",  lp(2,6)),
            btn("UV Strobe Med",  "toggle", L["dim_purple"], W, "pulsing",  lp(2,7)),
            btn("UV Strobe Fast", "toggle", L["dim_red"],    R, "flashing", lp(2,8)),      # DANGER
        ]},

        # ── Row 1: Quick Shots ──
        {"caption": "QUICK SHOTS", "solo": False, "buttons": [
            btn("UV Burst",     "flash", L["dim_purple"], W, "flashing", lp(1,1)),
            btn("Strobe Hit 1", "flash", L["dim_yellow"], W, "flashing", lp(1,2)),
            btn("Strobe Hit 2", "flash", L["dim_red"],    R, "flashing", lp(1,3)),         # heavy strobe
            btn("Double Flash", "flash", L["dim_red"],    R, "flashing", lp(1,4)),         # heavy strobe
            btn("Snap Left",    "flash", L["dim_blue"],   W, "flashing", lp(1,5)),
            btn("Snap Right",   "flash", L["dim_blue"],   W, "flashing", lp(1,6)),
            btn("Snap Up",      "flash", L["dim_blue"],   W, "flashing", lp(1,7)),
            btn("Snap Down",    "flash", L["dim_blue"],   W, "flashing", lp(1,8)),
        ]},

        # ── Top Row (CC 91-98): Phantom Scans + Directional ──
        {"caption": "PHANTOMS + ARROWS", "solo": False, "buttons": [
            btn("Phantom Red",    "toggle", L["dim_red"],    W, "pulsing",  91),
            btn("Phantom Blue",   "toggle", L["dim_blue"],   W, "pulsing",  92),
            btn("Phantom Green",  "toggle", L["dim_green"],  W, "pulsing",  93),
            btn("Phantom Purple", "toggle", L["dim_purple"], W, "pulsing",  94),
            btn("Snap Up",        "flash",  L["dim_blue"],   W, "flashing", 95),
            btn("Snap Down",      "flash",  L["dim_blue"],   W, "flashing", 96),
            btn("Snap Left",      "flash",  L["dim_blue"],   W, "flashing", 97),
            btn("Snap Right",     "flash",  L["dim_blue"],   W, "flashing", 98),
        ]},

        # ── Right Column (CC 89→19): Safe-Auto per layer ──
        {"caption": "SAFE / AUTO (Side Column)", "solo": False, "buttons": [
            btn("GO P1 Jungle",    "flash",  L["dim_green"],  W, "flashing", 89),
            btn("Auto Energy Arc", "toggle", L["dim_cyan"],   W, "pulsing",  79),
            btn("P1 Color Cycle",  "toggle", L["dim_cyan"],   W, "pulsing",  69),
            btn("CLEAN STOP",      "flash",  L["dim_white"],  W, "flashing", 59),
            btn("Gentle Sway",     "toggle", L["dim_cyan"],   W, "pulsing",  49),
            btn("Master 100%",     "toggle", L["dim_white"],  W, "pulsing",  39),
            btn("CALM RESET",      "flash",  L["dim_green"],  W, "flashing", 29),
            btn("BLACKOUT",        "blackout", L["dim_red"],  R, "flashing", 19),          # DANGER
        ]},

        # ── VC-only Granular Controls ──
        {"caption": "GOBOS — Spot Patterns", "solo": True, "buttons": [
            btn("Open Beam"), btn("Spiral"), btn("Starburst"), btn("Dots"),
            btn("Leaves"), btn("Lightning"), btn("Web"), btn("Waves"),
        ]},
        {"caption": "POSITIONS — Pan/Tilt", "solo": True, "buttons": [
            btn("Center"), btn("Stage Left"), btn("Stage Right"), btn("Up High"),
            btn("Floor"), btn("Upper Right"), btn("Lower Left"), btn("Audience"),
        ]},
        {"caption": "ROTATION — Gobo Spin", "solo": True, "buttons": [
            btn("Rotation Stop"), btn("CW Slow"), btn("CW Medium"), btn("CW Fast"),
            btn("CCW Slow"), btn("CCW Medium"), btn("CCW Fast"),
        ]},
        {"caption": "BEAMS — Focus/Prism/Color", "solo": True, "buttons": [
            btn("Sharp Focus"), btn("Soft Focus"), btn("Prism On"), btn("Prism Spin"),
            btn("CW Red"), btn("CW Green"), btn("CW Blue"), btn("CW Purple"),
        ]},
        {"caption": "VC AUTOMATISMS", "solo": False, "buttons": [
            btn("Gobo Carousel", "toggle"), btn("Position Sweep", "toggle"),
            btn("Gobo Snap", "flash", L["dim_orange"], L["orange"], "flashing"),
        ]},
    ]

    # Add inputUniverse to all buttons that have inputChannel
    for section in sections:
        for b in section.get("buttons", []):
            if "inputChannel" in b:
                b["inputUniverse"] = u

    print(f"  Calling build_show_page ({len(sections)} sections)...", end=" ", flush=True)
    result = client.call("build_show_page", {
        "pageName": "Show Control",
        "sections": sections,
    })
    print(f"✓")
    return result


# ═══════════════════════════════════════════════════════════════════════════
# Channel Modifiers
# ═══════════════════════════════════════════════════════════════════════════

def setup_channel_modifiers(client, hero_id, uv_id):
    """Apply dimmer response curves + invert pan/tilt for upside-down ceiling mount."""
    print("\n  Applying channel modifiers...")
    try:
        client.call("set_channel_modifiers", {"items": [
            {"fixtureID": hero_id, "modifications": [
                {"channel": HERO_CH["pan"],       "modifier": "Invert"},
                {"channel": HERO_CH["tilt"],      "modifier": "Invert"},
                {"channel": HERO_CH["spot_dim"],  "modifier": "Exponential Medium"},
                {"channel": HERO_CH["wash_dim"],  "modifier": "S-curve"},
            ]},
            {"fixtureID": uv_id, "modifications": [
                {"channel": UV_CH["dim"], "modifier": "Threshold"},
            ]},
        ]})
        print("  ✓ Pan       → Invert (ceiling mount)")
        print("  ✓ Tilt      → Invert (ceiling mount)")
        print("  ✓ Spot Dim  → Exponential Medium")
        print("  ✓ Wash Dim  → S-curve")
        print("  ✓ UV Dim    → Threshold")
    except Exception as e:
        print(f"  ⚠ Channel modifiers failed: {e}")


# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

def main():
    parser = argparse.ArgumentParser(description="Phase-Based DJ Show Builder v2.0")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=9696)
    parser.add_argument("--skip-patch", action="store_true", help="Skip fixture patching")
    parser.add_argument("--skip-vc", action="store_true", help="Skip Virtual Console layout")
    parser.add_argument("--hero-id", type=int, default=None)
    parser.add_argument("--haze-id", type=int, default=None)
    parser.add_argument("--uv-id", type=int, default=None)
    parser.add_argument("--hero-addr", type=int, default=0)
    parser.add_argument("--haze-addr", type=int, default=30)
    parser.add_argument("--uv-addr", type=int, default=40)
    args = parser.parse_args()

    print("╔══════════════════════════════════════════════╗")
    print("║  Phase-Based DJ Show Builder v2.0            ║")
    print("║  Creative Performance Controller for QLC+    ║")
    print("╚══════════════════════════════════════════════╝")

    # Connect
    print("\n📡 Connecting to MCP server...")
    client = MCPClient(args.host, args.port)
    client.connect()

    # Clean up existing functions (non-fatal — server may restart)
    print("\n🧹 Cleaning up existing functions...")
    try:
        existing = client.call("query_functions", {})
        if existing:
            del_ids = [f["id"] for f in existing]
            try:
                client.call("delete_functions", {"functionIDs": del_ids})
                print(f"  ✓ Deleted {len(del_ids)} existing functions")
            except Exception:
                print(f"  ⚠ Delete failed, reconnecting...")
                client.connect()
        else:
            print("  ✓ No existing functions")
    except Exception:
        print("  ⚠ Query failed, reconnecting...")
        client.connect()

    # Patch fixtures
    if not args.skip_patch:
        print("\n🔌 Patching fixtures...")
        patch_items = [{
            **{k: FIXTURE_PATCH[i][k] for k in ("manufacturer", "model", "mode", "name")},
            "universe": 0, "address": [args.hero_addr, args.uv_addr, args.haze_addr][i],
        } for i in range(3)]
        results = client.call("patch_fixtures", {"items": patch_items})
        hero_id, uv_id, haze_id = results[0]["id"], results[1]["id"], results[2]["id"]
        for r in results:
            if "error" in r:
                print(f"  ✗ {r['error']}")
                sys.exit(1)
            print(f"  ✓ {r['name']} → ID {r['id']} (addr {r['address']})")
    else:
        hero_id = args.hero_id if args.hero_id is not None else 0
        haze_id = args.haze_id if args.haze_id is not None else 2
        uv_id = args.uv_id if args.uv_id is not None else 1
        print(f"\n🔌 Using existing fixtures: hero={hero_id}, haze={haze_id}, uv={uv_id}")

    # Create all functions
    ids = create_all_functions(client, hero_id, haze_id, uv_id)

    # Channel modifiers (non-fatal if server doesn't support it)
    setup_channel_modifiers(client, hero_id, uv_id)

    # Virtual Console + Launchpad
    if not args.skip_vc:
        # Reconnect in case server restarted after channel modifiers
        try:
            client.call("query_universes", {})
        except Exception:
            print("\n  🔄 Reconnecting to MCP server...")
            client.connect()

        # Find Launchpad universe
        lp_universe = 0
        universes = client.call("query_universes", {})
        for uni in universes:
            inp = uni.get("inputPlugin", "")
            name = str(uni.get("inputName", uni.get("inputLine", "")))
            if "MIDI" in inp and "launchpad" in name.lower():
                lp_universe = uni["id"]
                print(f"  🎹 Found Launchpad on universe {lp_universe}")
                break

        build_show_page(client, lp_universe)

    # Summary
    total = sum(len(v) for v in ids.values())
    print("\n╔══════════════════════════════════════════════╗")
    print(f"║  ✅ PHASE SHOW COMPLETE                      ║")
    print(f"║  {total:3d} functions │ Launchpad mapped           ║")
    print("╚══════════════════════════════════════════════╝")
    print("\n  Layer architecture:")
    print("    Row 8: Phase   → texture/gobo/UV atmosphere")
    print("    Row 7: Energy  → movement speed, gobo rotation")
    print("    Row 6: Mood    → wash color (RGBW)")
    print("    Row 5: Auto    → chasers, buildups, impacts")
    print("    Row 4: Move    → EFX pan/tilt patterns")
    print("    Row 3: Master  → dimmer level + haze")
    print("    Row 2: Strobe  → spot + UV strobe speed")
    print("    Row 1: Shots   → flash accents")
    print("\n  Save the project in QLC+ (Ctrl+S) to persist!")

    with open("/tmp/phase_show_ids.json", "w") as f:
        json.dump(ids, f, indent=2)
    print("  Function IDs saved to /tmp/phase_show_ids.json")


if __name__ == "__main__":
    main()
