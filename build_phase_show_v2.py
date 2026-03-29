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
    {"manufacturer": "Stairville", "model": "Hz-200 DMX",
     "mode": "2 Channel", "name": "Haze Machine"},
    {"manufacturer": "Cameo", "model": "Thunderwash 600 UV",
     "mode": "4 Channel", "name": "UV Wash"},
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
        {"name": "Gobo Snap",    "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["gobo"], 52)]},  # Web gobo — surprise texture
    ]


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

# Phase chaser timing (holdTime_ms, fadeIn_ms, fadeOut_ms)
PHASE_CHASE_TIMING = {
    "P1": (4000, 2000, 2000),  # 8 beats hold, 4 beats fade — slow
    "P2": (3000, 1000, 1000),  # 6 beats hold, 2 beats fade
    "P3": (2000, 500,  500),   # 4 beats hold, 1 beat fade — fast snaps
    "P4": (4000, 2000, 2000),  # same as P1 — back to slow
}

# Default mood per phase (index into mood_ids)
PHASE_DEFAULT_MOOD = {"P1": 0, "P2": 2, "P3": 3, "P4": 6}


# ═══════════════════════════════════════════════════════════════════════════
# Launchpad Layout Definition
# ═══════════════════════════════════════════════════════════════════════════

# Layout constants
FRAME_W = 1100
BTN_W = 130
BTN_H = 55
PAD = 5
FRAME_H = 90
FRAME_GAP = 5
BTN_Y = 25  # button y offset inside frame (below header)

# Each row definition: (lp_row, caption, solo, buttons_spec)
# Buttons spec: list of dicts with keys for building + mapping
# "key"/"idx" → lookup in ids dict;  "special" → blackout/stopall
# Split rows use two frame entries at same lp_row

def get_launchpad_layout():
    """Returns the layout definition — button references resolved at build time."""
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
             "idle": LP["dim_white"], "active": LP["dim_white"],   "mode": "static"},
            {"key": "master", "idx": 1, "label": "50%",  "action": "toggle",
             "idle": LP["dim_white"], "active": LP["white"],       "mode": "static"},
            {"key": "master", "idx": 2, "label": "75%",  "action": "toggle",
             "idle": LP["dim_white"], "active": LP["white"],       "mode": "static"},
            {"key": "master", "idx": 3, "label": "100%", "action": "toggle",
             "idle": LP["dim_white"], "active": LP["bright_white"],"mode": "static"},
            {"key": "master", "idx": 4, "label": "KILL", "action": "toggle",
             "idle": LP["dim_red"],   "active": LP["red"],         "mode": "flashing"},
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
            {"key": "shots", "idx": 0, "label": "UV\nBurst",   "action": "flash",
             "idle": LP["dim_purple"], "active": LP["purple"],   "mode": "static"},
            {"key": "shots", "idx": 1, "label": "Strobe\n1",   "action": "flash",
             "idle": LP["dim_red"],    "active": LP["red"],      "mode": "static"},
            {"key": "shots", "idx": 2, "label": "Strobe\n2",   "action": "flash",
             "idle": LP["dim_red"],    "active": LP["fire_red"], "mode": "static"},
            {"key": "shots", "idx": 3, "label": "Double\nFlash","action": "flash",
             "idle": LP["dim_white"],  "active": LP["white"],    "mode": "static"},
            {"key": "shots", "idx": 4, "label": "Snap\n←",     "action": "flash",
             "idle": LP["dim_blue"],   "active": LP["blue"],     "mode": "static"},
            {"key": "shots", "idx": 5, "label": "Snap\n→",     "action": "flash",
             "idle": LP["dim_blue"],   "active": LP["blue"],     "mode": "static"},
            {"key": "shots", "idx": 6, "label": "Snap\n↑",     "action": "flash",
             "idle": LP["dim_blue"],   "active": LP["blue"],     "mode": "static"},
            {"key": "shots", "idx": 7, "label": "Gobo\nSnap",  "action": "flash",
             "idle": LP["dim_orange"], "active": LP["orange"],   "mode": "static"},
        ]},
    ]


# ═══════════════════════════════════════════════════════════════════════════
# Function Builders (chasers, EFX, collections)
# ═══════════════════════════════════════════════════════════════════════════

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

    print("\n══════════════════════════════════════════")
    print("  CREATING CHASERS")
    print("══════════════════════════════════════════")

    # Phase auto-chasers (random mood cycling per phase)
    auto_chaser_items = []
    for phase_key, mood_indices in PHASE_CHASE_MOODS.items():
        hold, fi, fo = PHASE_CHASE_TIMING[phase_key]
        auto_chaser_items.append({
            "name": f"{phase_key} Color Cycle",
            "functionIDs": [ids["moods"][i] for i in mood_indices],
            "fadeIn": fi, "fadeOut": fo, "holdTime": hold,
            "runOrder": "random", "direction": "forward", "durationMode": "common",
        })
    print(f"  🔁 {'Phase auto-chasers':20s} ({len(auto_chaser_items):2d})...", end=" ", flush=True)
    auto_results = client.call("create_chasers", {"items": auto_chaser_items})
    ids["auto_chasers"] = [c["id"] for c in auto_results]
    print(f"✓ IDs: {ids['auto_chasers']}")

    # Auto-energy chaser (Entry→Flow→Build→Bullet→Peak→Accent→Exit)
    print(f"  🔁 {'Auto-energy chaser':20s} ( 1)...", end=" ", flush=True)
    ae_result = client.call("create_chasers", {"items": [{
        "name": "Auto Energy Arc",
        "functionIDs": ids["energy"],
        "fadeIn": 2000, "fadeOut": 2000, "holdTime": 8000,
        "runOrder": "single", "direction": "forward", "durationMode": "common",
    }]})
    ids["auto_energy"] = [ae_result[0]["id"]]
    print(f"✓ IDs: {ids['auto_energy']}")

    # Buildup chasers (single-shot ramps)
    buildup_items = [
        {"name": "Strobe Ramp",
         "functionIDs": [ids["strobes"][0], ids["strobes"][1], ids["strobes"][2], ids["strobes"][3]],
         "fadeIn": 0, "fadeOut": 0, "holdTime": 2000,
         "runOrder": "single", "direction": "forward", "durationMode": "common"},
        {"name": "UV Surge",
         "functionIDs": [ids["strobes"][4], ids["strobes"][5], ids["strobes"][6], ids["strobes"][7]],
         "fadeIn": 0, "fadeOut": 0, "holdTime": 3000,
         "runOrder": "single", "direction": "forward", "durationMode": "common"},
        {"name": "Haze Pump",
         "functionIDs": [ids["haze"][0], ids["haze"][1], ids["haze"][2]],
         "fadeIn": 500, "fadeOut": 500, "holdTime": 5000,
         "runOrder": "single", "direction": "forward", "durationMode": "common"},
        {"name": "Blackout Hit",
         "functionIDs": [ids["master"][3], ids["master"][4], ids["master"][3]],
         "fadeIn": 0, "fadeOut": 0, "holdTime": 200,
         "runOrder": "single", "direction": "forward", "durationMode": "common"},
    ]
    print(f"  🔁 {'Buildups':20s} ({len(buildup_items):2d})...", end=" ", flush=True)
    bu_results = client.call("create_chasers", {"items": buildup_items})
    ids["buildups"] = [c["id"] for c in bu_results]
    print(f"✓ IDs: {ids['buildups']}")

    # Gobo carousel + position sweep (VC automatisms using granular scenes)
    vc_chasers = [
        {"name": "Gobo Carousel",
         "functionIDs": ids["vc_gobos"],
         "fadeIn": 500, "fadeOut": 500, "holdTime": 2000,
         "runOrder": "loop", "direction": "forward", "durationMode": "common"},
        {"name": "Position Sweep",
         "functionIDs": ids["vc_positions"][:5],
         "fadeIn": 1500, "fadeOut": 1500, "holdTime": 1000,
         "runOrder": "pingpong", "direction": "forward", "durationMode": "common"},
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

    # Count total
    total = sum(len(v) for v in ids.values())
    print(f"\n  ═══ {total} functions created ═══")

    return ids


# ═══════════════════════════════════════════════════════════════════════════
# VC + Launchpad Builder
# ═══════════════════════════════════════════════════════════════════════════

def find_launchpad_universe(client):
    universes = client.call("query_universes", {})
    for uni in universes:
        input_plugin = uni.get("inputPlugin", "")
        input_name = str(uni.get("inputName", uni.get("inputLine", "")))
        if "MIDI" in input_plugin and "launchpad" in input_name.lower():
            print(f"  🎹 Found Launchpad on universe {uni['id']}")
            return uni["id"]
        if "launchpad" in uni.get("name", "").lower():
            print(f"  🎹 Found Launchpad universe {uni['id']} by name")
            return uni["id"]
    print("  ⚠ Launchpad not found, defaulting to universe 0")
    return 0


def build_vc(client, ids, lp_universe):
    """Build Virtual Console: Launchpad-mapped rows + VC-only granular controls."""
    print("\n══════════════════════════════════════════")
    print("  VIRTUAL CONSOLE — LAUNCHPAD LAYOUT")
    print("══════════════════════════════════════════")

    layout = get_launchpad_layout()
    all_buttons = []  # (widget_id, lp_row, lp_col, idle, active, mode)

    # Track Y position per lp_row (rows can be split into multiple frames)
    row_y = {}
    y = 0
    for row_num in range(8, 0, -1):
        row_y[row_num] = y
        y += FRAME_H + FRAME_GAP

    vc_granular_y = y  # where granular VC starts

    # Build Launchpad frames and buttons
    for frame_def in layout:
        lp_row = frame_def["lp_row"]
        frame_y = row_y[lp_row]

        # Create frame
        frame_item = {
            "pageIndex": 0, "x": frame_def["x"], "y": frame_y,
            "width": frame_def["w"], "height": FRAME_H,
            "caption": frame_def["caption"], "solo": frame_def["solo"],
            "bgColor": "#111111", "fgColor": "#ffffff",
        }
        print(f"  Frame: {frame_def['caption']:20s}...", end=" ", flush=True)
        frame_results = client.call("add_vc_frames", {"items": [frame_item]})
        frame_id = frame_results[0]["widgetID"]
        if frame_id < 0:
            print("✗ FAILED")
            continue
        print(f"✓ (ID {frame_id})")

        # Create buttons inside frame
        buttons = frame_def["buttons"]
        btn_items = []
        btn_meta = []  # parallel list for post-creation mapping

        # Track column position for split rows
        col_offset = 0
        if frame_def["x"] > 0:
            # This is a right-side split frame, shift Launchpad column
            if frame_def["w"] < FRAME_W:
                col_offset = len([b for b in layout if b["lp_row"] == lp_row and b["x"] == 0][0]["buttons"])

        for col_idx, btn in enumerate(buttons):
            if btn is None:
                continue

            btn_item = {
                "parentID": frame_id,
                "x": PAD + col_idx * (BTN_W + PAD),
                "y": BTN_Y,
                "width": BTN_W, "height": BTN_H,
                "caption": btn["label"],
                "bgColor": "#222222", "fgColor": "#ffffff",
            }

            if "special" in btn:
                btn_item["action"] = btn["special"]
            else:
                btn_item["action"] = btn["action"]
                fn_id = ids[btn["key"]][btn["idx"]]
                btn_item["functionID"] = fn_id

            btn_items.append(btn_item)
            btn_meta.append({
                "lp_row": lp_row,
                "lp_col": col_idx + 1 + col_offset,
                "idle": btn["idle"],
                "active": btn["active"],
                "mode": btn["mode"],
            })

        if not btn_items:
            continue

        print(f"    Buttons ({len(btn_items)})...", end=" ", flush=True)
        btn_results = client.call("add_vc_buttons", {"items": btn_items})
        ok = sum(1 for r in btn_results if r.get("widgetID", -1) >= 0)
        print(f"✓ ({ok}/{len(btn_items)})")

        for i, r in enumerate(btn_results):
            if r.get("widgetID", -1) >= 0:
                meta = btn_meta[i]
                all_buttons.append((
                    r["widgetID"], meta["lp_row"], meta["lp_col"],
                    meta["idle"], meta["active"], meta["mode"],
                ))

    # Map Launchpad inputs
    if all_buttons:
        print(f"\n  Mapping {len(all_buttons)} Launchpad inputs (universe {lp_universe})...", end=" ", flush=True)
        input_items = [{
            "widgetID": wid,
            "inputUniverse": lp_universe,
            "inputChannel": launchpad_channel(row, col),
        } for wid, row, col, _, _, _ in all_buttons]
        results = client.call("map_vc_inputs", {"items": input_items})
        ok = sum(1 for r in results if r.get("status") == "ok")
        print(f"✓ ({ok}/{len(input_items)})")

    # Configure LED feedback
    if all_buttons:
        print(f"  Configuring {len(all_buttons)} LED feedbacks...", end=" ", flush=True)
        fb_items = [{
            "widgetID": wid,
            "idleValue": idle, "activeValue": active,
            "monitorValue": active,
            "idleMode": "static", "activeMode": mode, "monitorMode": mode,
        } for wid, _, _, idle, active, mode in all_buttons]
        results = client.call("configure_vc_feedback", {"items": fb_items})
        ok = sum(1 for r in results if r.get("status") == "ok")
        print(f"✓ ({ok}/{len(fb_items)})")

    # ── VC-Only Granular Controls ──
    print("\n══════════════════════════════════════════")
    print("  VIRTUAL CONSOLE — GRANULAR (VC ONLY)")
    print("══════════════════════════════════════════")

    granular_cats = [
        ("vc_gobos",     "GOBOS — Spot Patterns",      True),
        ("vc_positions", "POSITIONS — Pan/Tilt",        True),
        ("vc_rotations", "ROTATION — Gobo Spin",        True),
        ("vc_beams",     "BEAMS — Focus/Prism/Color",   True),
    ]

    gy = vc_granular_y + 20  # add gap
    for cat_key, caption, solo in granular_cats:
        if cat_key not in ids:
            continue
        func_ids = ids[cat_key]

        # Create frame
        frame_res = client.call("add_vc_frames", {"items": [{
            "pageIndex": 0, "x": 0, "y": gy,
            "width": FRAME_W, "height": FRAME_H,
            "caption": caption, "solo": solo,
            "bgColor": "#0a0a0a", "fgColor": "#888888",
        }]})
        fid = frame_res[0]["widgetID"]
        if fid < 0:
            continue

        # Create buttons
        btn_items = [{
            "parentID": fid,
            "x": PAD + i * (BTN_W + PAD), "y": BTN_Y,
            "width": BTN_W, "height": BTN_H,
            "functionID": func_ids[i],
            "caption": f"F{func_ids[i]}",
            "action": "toggle",
            "bgColor": "#1a1a1a", "fgColor": "#888888",
        } for i in range(len(func_ids))]
        client.call("add_vc_buttons", {"items": btn_items})
        print(f"  ✓ {caption}: {len(btn_items)} buttons")
        gy += FRAME_H + FRAME_GAP

    # VC chasers (Gobo Carousel + Position Sweep) as toggle buttons
    if "vc_chasers" in ids:
        chase_frame = client.call("add_vc_frames", {"items": [{
            "pageIndex": 0, "x": 0, "y": gy,
            "width": 400, "height": FRAME_H,
            "caption": "VC AUTOMATISMS", "solo": False,
            "bgColor": "#0a0a0a", "fgColor": "#888888",
        }]})
        cfid = chase_frame[0]["widgetID"]
        if cfid >= 0:
            chase_labels = ["Gobo\nCarousel", "Position\nSweep"]
            chase_btns = [{
                "parentID": cfid,
                "x": PAD + i * (BTN_W + PAD), "y": BTN_Y,
                "width": BTN_W, "height": BTN_H,
                "functionID": ids["vc_chasers"][i],
                "caption": chase_labels[i],
                "action": "toggle",
                "bgColor": "#1a1a1a", "fgColor": "#888888",
            } for i in range(len(ids["vc_chasers"]))]
            client.call("add_vc_buttons", {"items": chase_btns})
            print(f"  ✓ VC Automatisms: {len(chase_btns)} buttons")

    return all_buttons


# ═══════════════════════════════════════════════════════════════════════════
# Channel Modifiers
# ═══════════════════════════════════════════════════════════════════════════

def setup_channel_modifiers(client, hero_id, uv_id):
    """Apply dimmer response curves for better live feel."""
    print("\n  Applying channel modifiers...")
    try:
        client.call("set_channel_modifiers", {"items": [
            {"fixtureID": hero_id, "modifications": [
                {"channel": HERO_CH["spot_dim"],  "modifier": "Exponential Medium"},
                {"channel": HERO_CH["wash_dim"],  "modifier": "S-curve"},
            ]},
            {"fixtureID": uv_id, "modifications": [
                {"channel": UV_CH["dim"], "modifier": "Threshold"},
            ]},
        ]})
        print("  ✓ Spot Dim → Exponential Medium")
        print("  ✓ Wash Dim → S-curve")
        print("  ✓ UV Dim   → Threshold")
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
            "universe": 0, "address": [args.hero_addr, args.haze_addr, args.uv_addr][i],
        } for i in range(3)]
        results = client.call("patch_fixtures", {"items": patch_items})
        hero_id, haze_id, uv_id = results[0]["id"], results[1]["id"], results[2]["id"]
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
        lp_universe = find_launchpad_universe(client)

        # Set input profile + feedback
        print(f"\n  Setting Launchpad input profile on universe {lp_universe}...")
        try:
            client.call("set_input_profile", {"items": [
                {"universeID": lp_universe, "profileName": "Novation Launchpad Mini MK3"}
            ]})
            client.call("configure_universes", {"items": [
                {"universeID": lp_universe, "feedbackEnabled": True}
            ]})
            print("  ✓ Input profile + feedback enabled")
        except Exception as e:
            print(f"  ⚠ Profile setup: {e}")

        build_vc(client, ids, lp_universe)

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
