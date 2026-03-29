#!/usr/bin/env python3
"""
JUNGLE DJ Show Builder for QLC+ MCP Server
===========================================
Creates a complete DJ lighting show with 60+ functions and full Virtual Console
layout optimized for Launchpad Mini MK3 control.

Usage:
    # With default fixtures (Hero Spot + Haze + UV):
    python3 build_jungle_show.py

    # Custom MCP server port:
    python3 build_jungle_show.py --port 9696

    # Skip fixture patching (fixtures already exist):
    python3 build_jungle_show.py --skip-patch --hero-id 0 --haze-id 1 --uv-id 2

    # Custom fixture addresses:
    python3 build_jungle_show.py --hero-addr 0 --haze-addr 30 --uv-addr 40

    # Skip VC layout (functions only):
    python3 build_jungle_show.py --skip-vc
"""

import json
import urllib.request
import argparse
import sys
import time

# ── MCP Client ──────────────────────────────────────────────────────────────

class MCPClient:
    def __init__(self, host="127.0.0.1", port=9696):
        self.url = f"http://{host}:{port}/mcp"
        self.session = None
        self._id = 0

    def connect(self, max_retries=10, retry_delay=2):
        """Initialize MCP session with startup retry."""
        body = json.dumps({
            "jsonrpc": "2.0", "method": "initialize", "id": 1,
            "params": {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "jungle-builder", "version": "1.0"}
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
        """Call an MCP tool with retry logic."""
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

# ── Fixture Definitions ─────────────────────────────────────────────────────

FIXTURES = {
    "hero": {
        "manufacturer": "Varytec",
        "model": "Hero Spot Wash 140 2in1 RGBW+W",
        "mode": "23 Channel",
        "name": "Hero Spot",
        # Channel map:
        #  0=Pan 1=PanFine 2=Tilt 3=TiltFine 4=PanTiltSpeed
        #  5=SpotDim 6=SpotStrobe 7=ColorWheel 8=StaticGobo 9=GoboWheel
        # 10=GoboRot 11=Focus 12=Prism 13=WashDim 14=WashStrobe
        # 15=R 16=G 17=B 18=W 19=ColorTemp 20=ColorMacro 21=ColourSeq 22=AutoShows
        "ch": {
            "pan": 0, "pan_fine": 1, "tilt": 2, "tilt_fine": 3, "pt_speed": 4,
            "spot_dim": 5, "spot_strobe": 6, "color_wheel": 7,
            "gobo": 8, "gobo_wheel": 9, "gobo_rot": 10,
            "focus": 11, "prism": 12,
            "wash_dim": 13, "wash_strobe": 14,
            "r": 15, "g": 16, "b": 17, "w": 18,
            "color_temp": 19, "color_macro": 20, "color_seq": 21, "auto_shows": 22,
        },
    },
    "haze": {
        "manufacturer": "Stairville",
        "model": "Hz-200 DMX",
        "mode": "2 Channel",
        "name": "Haze Machine",
        "ch": {"output": 0, "fan": 1},
    },
    "uv": {
        "manufacturer": "Cameo",
        "model": "Thunderwash 600 UV",
        "mode": "4 Channel",
        "name": "UV Wash",
        "ch": {"dim": 0, "strobe": 1, "strobe_dur": 2, "sound": 3},
    },
}

# Gobo values: Open=0, G1=10, G2=20, G3=28, G4=36, G5=44, G6=52, G7=60, G8=70
# Color wheel: White=0, Red=18, Orange=36, Green=54, Blue=72, Yellow=90, Purple=126
# Prism: Open=0, Prism=70, PrismRot=200

# ── Scene Definitions ───────────────────────────────────────────────────────

def cv(fixture_id, channel, value):
    """Shorthand for channelValues entry."""
    return {"fixtureID": fixture_id, "channel": channel, "value": value}

def make_scenes(hero_id, haze_id, uv_id):
    """Define all scenes. Returns dict of category -> scene definitions."""
    h = FIXTURES["hero"]["ch"]

    moods = [
        {"name": "🌿 Deep Jungle", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_dim"], 200), cv(hero_id, h["wash_dim"], 255),
            cv(hero_id, h["r"], 0), cv(hero_id, h["g"], 180),
            cv(hero_id, h["b"], 30), cv(hero_id, h["w"], 20)]},
        {"name": "🔥 Amber Canopy", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_dim"], 200), cv(hero_id, h["wash_dim"], 255),
            cv(hero_id, h["r"], 255), cv(hero_id, h["g"], 100),
            cv(hero_id, h["b"], 0), cv(hero_id, h["w"], 30)]},
        {"name": "🌙 Midnight Blue", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_dim"], 180), cv(hero_id, h["wash_dim"], 255),
            cv(hero_id, h["r"], 0), cv(hero_id, h["g"], 0),
            cv(hero_id, h["b"], 255), cv(hero_id, h["w"], 30)]},
        {"name": "🩸 Blood Moon", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_dim"], 220), cv(hero_id, h["wash_dim"], 255),
            cv(hero_id, h["r"], 255), cv(hero_id, h["g"], 0),
            cv(hero_id, h["b"], 0), cv(hero_id, h["w"], 0)]},
        {"name": "💜 Mystic Violet", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_dim"], 200), cv(hero_id, h["wash_dim"], 255),
            cv(hero_id, h["r"], 180), cv(hero_id, h["g"], 0),
            cv(hero_id, h["b"], 255), cv(hero_id, h["w"], 0)]},
        {"name": "❄️ Arctic White", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_dim"], 255), cv(hero_id, h["wash_dim"], 255),
            cv(hero_id, h["r"], 40), cv(hero_id, h["g"], 40),
            cv(hero_id, h["b"], 60), cv(hero_id, h["w"], 255)]},
        {"name": "🐬 Tropical Cyan", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_dim"], 200), cv(hero_id, h["wash_dim"], 255),
            cv(hero_id, h["r"], 0), cv(hero_id, h["g"], 200),
            cv(hero_id, h["b"], 255), cv(hero_id, h["w"], 30)]},
        {"name": "☀️ Solar Flare", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_dim"], 255), cv(hero_id, h["wash_dim"], 255),
            cv(hero_id, h["r"], 255), cv(hero_id, h["g"], 200),
            cv(hero_id, h["b"], 0), cv(hero_id, h["w"], 80)]},
    ]

    gobos = [
        {"name": "⭕ Open Beam", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_dim"], 255), cv(hero_id, h["gobo"], 0)]},
        {"name": "🌀 Spiral", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_dim"], 255), cv(hero_id, h["gobo"], 10)]},
        {"name": "💫 Starburst", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_dim"], 255), cv(hero_id, h["gobo"], 20)]},
        {"name": "🔵 Dots", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_dim"], 255), cv(hero_id, h["gobo"], 28)]},
        {"name": "🍀 Leaves", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_dim"], 255), cv(hero_id, h["gobo"], 36)]},
        {"name": "⚡ Lightning", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_dim"], 255), cv(hero_id, h["gobo"], 44)]},
        {"name": "🕸️ Web", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_dim"], 255), cv(hero_id, h["gobo"], 52)]},
        {"name": "🌊 Waves", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_dim"], 255), cv(hero_id, h["gobo"], 60)]},
    ]

    positions = [
        {"name": "📍 Center", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["pan"], 128), cv(hero_id, h["tilt"], 128), cv(hero_id, h["pt_speed"], 0)]},
        {"name": "⬅️ Stage Left", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["pan"], 40), cv(hero_id, h["tilt"], 128), cv(hero_id, h["pt_speed"], 0)]},
        {"name": "➡️ Stage Right", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["pan"], 216), cv(hero_id, h["tilt"], 128), cv(hero_id, h["pt_speed"], 0)]},
        {"name": "⬆️ Up High", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["pan"], 128), cv(hero_id, h["tilt"], 40), cv(hero_id, h["pt_speed"], 0)]},
        {"name": "⬇️ Floor", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["pan"], 128), cv(hero_id, h["tilt"], 220), cv(hero_id, h["pt_speed"], 0)]},
        {"name": "↗️ Upper Right", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["pan"], 200), cv(hero_id, h["tilt"], 60), cv(hero_id, h["pt_speed"], 0)]},
        {"name": "↙️ Lower Left", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["pan"], 56), cv(hero_id, h["tilt"], 200), cv(hero_id, h["pt_speed"], 0)]},
        {"name": "🎯 Audience", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["pan"], 128), cv(hero_id, h["tilt"], 180), cv(hero_id, h["pt_speed"], 0)]},
    ]

    rotations = [
        {"name": "⏹ Rotation Stop", "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["gobo_rot"], 0)]},
        {"name": "🔄 CW Slow", "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["gobo_rot"], 20)]},
        {"name": "🔄 CW Medium", "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["gobo_rot"], 70)]},
        {"name": "🔄 CW Fast", "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["gobo_rot"], 120)]},
        {"name": "🔃 CCW Slow", "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["gobo_rot"], 140)]},
        {"name": "🔃 CCW Medium", "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["gobo_rot"], 190)]},
        {"name": "🔃 CCW Fast", "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["gobo_rot"], 245)]},
    ]

    beams = [
        {"name": "🔦 Sharp Focus", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["focus"], 0), cv(hero_id, h["prism"], 0)]},
        {"name": "🔮 Soft Focus", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["focus"], 200), cv(hero_id, h["prism"], 0)]},
        {"name": "💎 Prism On", "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["prism"], 70)]},
        {"name": "🌈 Prism Spin", "fixtureIDs": [hero_id], "channelValues": [cv(hero_id, h["prism"], 200)]},
        {"name": "🔴 CW Red", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_dim"], 255), cv(hero_id, h["color_wheel"], 18)]},
        {"name": "🟢 CW Green", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_dim"], 255), cv(hero_id, h["color_wheel"], 54)]},
        {"name": "🔵 CW Blue", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_dim"], 255), cv(hero_id, h["color_wheel"], 72)]},
        {"name": "🟣 CW Purple", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_dim"], 255), cv(hero_id, h["color_wheel"], 126)]},
    ]

    hz = FIXTURES["haze"]["ch"]
    uvc = FIXTURES["uv"]["ch"]
    utils = [
        {"name": "🌫️ Haze Low", "fixtureIDs": [haze_id], "channelValues": [
            cv(haze_id, hz["output"], 80), cv(haze_id, hz["fan"], 120)]},
        {"name": "🌫️ Haze Full", "fixtureIDs": [haze_id], "channelValues": [
            cv(haze_id, hz["output"], 255), cv(haze_id, hz["fan"], 200)]},
        {"name": "🌫️ Haze Off", "fixtureIDs": [haze_id], "channelValues": [
            cv(haze_id, hz["output"], 0), cv(haze_id, hz["fan"], 0)]},
        {"name": "💜 UV Full", "fixtureIDs": [uv_id], "channelValues": [
            cv(uv_id, uvc["dim"], 255), cv(uv_id, uvc["strobe"], 0)]},
        {"name": "💜 UV Strobe", "fixtureIDs": [uv_id], "channelValues": [
            cv(uv_id, uvc["dim"], 255), cv(uv_id, uvc["strobe"], 180)]},
        {"name": "💜 UV Off", "fixtureIDs": [uv_id], "channelValues": [
            cv(uv_id, uvc["dim"], 0)]},
        {"name": "⚡ Spot Strobe Slow", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_dim"], 255), cv(hero_id, h["spot_strobe"], 40)]},
        {"name": "⚡ Spot Strobe Fast", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_dim"], 255), cv(hero_id, h["spot_strobe"], 220)]},
        {"name": "⚡ Strobe Off", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_strobe"], 0), cv(hero_id, h["wash_strobe"], 0)]},
        {"name": "⬛ BLACKOUT", "fixtureIDs": [hero_id, haze_id, uv_id], "channelValues": [
            cv(hero_id, h["spot_dim"], 0), cv(hero_id, h["wash_dim"], 0),
            cv(haze_id, hz["output"], 0), cv(uv_id, uvc["dim"], 0)]},
        {"name": "💡 FULL ON", "fixtureIDs": [hero_id], "channelValues": [
            cv(hero_id, h["spot_dim"], 255), cv(hero_id, h["wash_dim"], 255),
            cv(hero_id, h["r"], 255), cv(hero_id, h["g"], 255),
            cv(hero_id, h["b"], 255), cv(hero_id, h["w"], 255)]},
    ]

    return {
        "moods": moods, "gobos": gobos, "positions": positions,
        "rotations": rotations, "beams": beams, "utils": utils,
    }

# ── Launchpad Layout ────────────────────────────────────────────────────────
# Launchpad Mini MK3: 8x8 pad grid + top row (CC) + right column (CC)
# Pad notes: Row N (bottom=1, top=8), Col M (left=1, right=8) -> note = N*10 + M
# QLC+ input channel = 128 + MIDI note number
# Launchpad Mini MK3 color palette (velocity values)
# Source: QLC+ built-in color table (Novation-LaunchPadMiniMK3.qxi)
# Even values only. "100%" = saturated, "60%"/"30%" = progressively dimmer
LP_COLORS = {
    # Bright (100%) colors
    "red":         10,   # Red 100%         #ff6161
    "orange":      18,   # Orange 100%      #ffb361
    "yellow":      26,   # Yellow 100%      #ffff61
    "green":       42,   # Green 100%       #61ff61
    "cyan":        74,   # Cyan 100%        #61eeff
    "blue":        82,   # Blue 100%        #61c7ff
    "dark_blue":   90,   # Dark Blue 100%   #6161ff
    "purple":      98,   # Purple 100%      #a161ff
    "magenta":    106,   # Magenta 100%     #ff61ff
    "pink":       114,   # Pink 100%        #ff61c2
    "white":        6,   # White            #ffffff
    "fire_red":   120,   # Fire Red         #ff7661

    # Bright (pastel) versions
    "bright_red":     8,   # Bright Red     #ffb3b3
    "bright_orange": 16,   # Bright Orange  #fff3d5
    "bright_purple": 96,   # Bright Purple  #ccb3ff
    "bright_cyan":   72,   # Bright Cyan    #c2f3ff
    "bright_green":  40,   # Bright Green   #c2ffb3
    "bright_pink":  112,   # Bright Pink    #ffb3d5

    # Dim (30%) versions — for idle state
    "dim_red":      14,   # Red 30%         #b36161
    "dim_orange":   22,   # Orange 30%      #b37661
    "dim_yellow":   30,   # Yellow 30%      #b3b361
    "dim_green":    46,   # Green 30%       #61b361
    "dim_cyan":     78,   # Cyan 30%        #61a1b3
    "dim_blue":     86,   # Blue 30%        #6181b3
    "dim_dark_blue":94,   # Dark Blue 30%   #6161b3
    "dim_purple":  102,   # Purple 30%      #7661b3
    "dim_magenta": 110,   # Magenta 30%     #b361b3
    "dim_pink":    118,   # Pink 30%        #b3618c
    "dim_white":     2,   # White 30%       #b3b3b3
    "off":           0,   # Off             #000000
}

# Unified color theme per category:
# (vc_bg_hex, vc_fg_hex, lp_active, lp_idle, active_mode)
# active_mode: "static", "pulsing", "flashing"
CATEGORY_COLORS = {
    "collections": ("#660099", "#e0b0ff", LP_COLORS["purple"],    LP_COLORS["dim_purple"],  "pulsing"),
    "moods":       ("#226600", "#b3ff66", LP_COLORS["green"],     LP_COLORS["dim_green"],   "static"),
    "gobos":       ("#884400", "#ffcc66", LP_COLORS["orange"],    LP_COLORS["dim_orange"],  "static"),
    "positions":   ("#003388", "#66b3ff", LP_COLORS["blue"],      LP_COLORS["dim_blue"],    "static"),
    "rotations":   ("#666600", "#ffff66", LP_COLORS["yellow"],    LP_COLORS["dim_yellow"],  "static"),
    "beams":       ("#880066", "#ff99ee", LP_COLORS["pink"],      LP_COLORS["dim_pink"],    "static"),
    "movement":    ("#006666", "#66ffff", LP_COLORS["cyan"],      LP_COLORS["dim_cyan"],    "pulsing"),
    "utils":       ("#880000", "#ff6666", LP_COLORS["fire_red"],  LP_COLORS["dim_red"],     "flashing"),
}

# Row layout (top to bottom = rows 8→1):
#  Row 8: 🌴 PHASE Collections (high-level shows)
#  Row 7: 🎨 MOOD Wash colors (solo)
#  Row 6: 🎭 GOBO patterns (solo)
#  Row 5: 📐 POSITION presets (solo)
#  Row 4: 🔄 ROTATION speed (solo)
#  Row 3: 💎 BEAM effects (prism, color wheel, focus)
#  Row 2: 🌀 MOVEMENT EFX + Chasers
#  Row 1: ⚡ QUICK ACTIONS (blackout, strobe, haze, UV)

def launchpad_channel(row, col):
    """Launchpad pad -> QLC+ input channel. Row 1-8 bottom to top, col 1-8 left to right."""
    return 128 + row * 10 + col

def find_launchpad_universe(client):
    """Query universes to find which one has the Launchpad MIDI input."""
    universes = client.call("query_universes", {})
    for uni in universes:
        input_plugin = uni.get("inputPlugin", "")
        input_name = uni.get("inputName", uni.get("inputLine", ""))
        # Check if this universe has a MIDI input with "Launchpad" in the name
        if "MIDI" in input_plugin and "launchpad" in str(input_name).lower():
            print(f"  🎹 Found Launchpad on universe {uni['id']}")
            return uni["id"]
        # Also check the universe name
        if "launchpad" in uni.get("name", "").lower():
            print(f"  🎹 Found Launchpad universe {uni['id']} by name")
            return uni["id"]
    print("  ⚠ Launchpad not found in any universe, defaulting to universe 0")
    return 0

# ── Virtual Console Layout ──────────────────────────────────────────────────

def build_vc(client, ids):
    """Build the full Virtual Console with Launchpad-mapped buttons."""
    print("\n══════════════════════════════════════════")
    print("  VIRTUAL CONSOLE LAYOUT")
    print("══════════════════════════════════════════")

    # Page 0 exists by default (pageIndex=0 → parentID for frames)
    PAGE_ID = 0

    # Layout constants
    FRAME_W = 1100
    BTN_W = 130
    BTN_H = 55
    PAD = 5
    FRAME_H = 90       # taller frames so header is visible
    FRAME_GAP = 5      # gap between frames
    BTN_Y_OFFSET = 25  # push buttons down so frame header is readable

    # Button labels per category (readable names, no function IDs)
    btn_labels = {
        "collections": ["JUNGLE\nVIBE", "FIRE\nRITUAL", "MIDNIGHT\nHUNT", "BLOOD\nRAVE",
                        "MYSTICAL\nFOREST", "ARCTIC\nSTORM", "OCEAN\nDEEP", "SOLAR\nERUPTION"],
        "moods":       ["Deep\nJungle", "Amber\nCanopy", "Midnight\nBlue", "Blood\nMoon",
                        "Mystic\nViolet", "Arctic\nWhite", "Tropical\nCyan", "Solar\nFlare"],
        "gobos":       ["Open\nBeam", "Spiral", "Starburst", "Dots",
                        "Leaves", "Lightning", "Web", "Waves"],
        "positions":   ["Center", "Stage\nLeft", "Stage\nRight", "Up High",
                        "Floor", "Upper\nRight", "Lower\nLeft", "Audience"],
        "rotations":   ["Stop", "CW\nSlow", "CW\nMedium", "CW\nFast",
                        "CCW\nSlow", "CCW\nMedium", "CCW\nFast"],
        "beams":       ["Sharp\nFocus", "Soft\nFocus", "Prism\nOn", "Prism\nSpin",
                        "Red\nWheel", "Green\nWheel", "Blue\nWheel", "Purple\nWheel"],
        "movement":    ["Circle", "Infinity", "Square", "Random",
                        "Color\nCycle", "Gobo\nCarousel", "Position\nSweep", "Strobe\nBuildup"],
        "utils":       ["Haze\nLow", "Haze\nFull", "Haze\nOff", "UV\nFull",
                        "UV\nStrobe", "UV\nOff", "Strobe\nSlow", "Strobe\nFast"],
    }

    # Frame positions (stacked vertically with gaps)
    y = 0
    frames_def = []
    for (caption, solo, bg, cat_key, lp_row) in [
        ("PHASES — Full Show Presets",    False, "#1a0033", "collections", 8),
        ("MOODS — Wash Colors",           True,  "#1a3300", "moods",       7),
        ("GOBOS — Spot Patterns",         True,  "#33200a", "gobos",       6),
        ("POSITIONS — Pan/Tilt",          True,  "#0a1a33", "positions",   5),
        ("ROTATION — Gobo Spin",          True,  "#1a1a00", "rotations",   4),
        ("BEAMS — Focus/Prism/Color",     True,  "#1a0033", "beams",       3),
        ("MOVEMENT — EFX + Chasers",      False, "#001a1a", "movement",    2),
        ("QUICK — Strobe/Haze/UV",        False, "#1a0000", "utils",       1),
    ]:
        frames_def.append((y, FRAME_H, caption, solo, bg, cat_key, lp_row))
        y += FRAME_H + FRAME_GAP

    # Colors come from the unified CATEGORY_COLORS table

    # Create all frames
    frame_items = []
    for (y, h, caption, solo, bg, _, _) in frames_def:
        frame_items.append({
            "pageIndex": 0, "x": 0, "y": y,
            "width": FRAME_W, "height": h,
            "caption": caption, "solo": solo,
            "bgColor": bg, "fgColor": "#ffffff",
        })

    print("  Creating frames...", end=" ", flush=True)
    frame_results = client.call("add_vc_frames", {"items": frame_items})
    frame_ids = {frames_def[i][5]: r["widgetID"] for i, r in enumerate(frame_results)}
    print(f"✓ ({len(frame_ids)} frames)")

    # Build buttons for each category
    all_buttons = []  # (widget_id, lp_row, lp_col, led_color)

    for (_, _, _, _, _, cat_key, lp_row) in frames_def:
        parent_id = frame_ids[cat_key]
        if parent_id < 0:
            print(f"  ⚠ Frame '{cat_key}' creation failed, skipping buttons")
            continue

        bg, fg, _, _, _ = CATEGORY_COLORS.get(cat_key, ("#333333", "#ffffff", 0, 0, "static"))

        if cat_key == "movement":
            func_ids = ids["efx"] + ids["chasers"]
        elif cat_key in ids:
            func_ids = ids[cat_key]
        else:
            continue

        labels = btn_labels.get(cat_key, [])

        btn_items = []
        for col_idx, fid in enumerate(func_ids[:8]):  # max 8 per row
            label = labels[col_idx] if col_idx < len(labels) else f"Fn {fid}"
            btn_items.append({
                "parentID": parent_id,
                "x": PAD + col_idx * (BTN_W + PAD),
                "y": BTN_Y_OFFSET,
                "width": BTN_W, "height": BTN_H,
                "functionID": fid,
                "caption": label,
                "action": "flash" if cat_key == "utils" and col_idx >= 6 else "toggle",
                "bgColor": bg, "fgColor": fg,
            })

        print(f"  Creating {cat_key} buttons ({len(btn_items)})...", end=" ", flush=True)
        btn_results = client.call("add_vc_buttons", {"items": btn_items})
        ok_count = sum(1 for r in btn_results if r.get("widgetID", -1) >= 0)
        print(f"✓ ({ok_count}/{len(btn_items)})")

        for col_idx, r in enumerate(btn_results):
            if r.get("widgetID", -1) >= 0:
                _, _, lp_active, lp_idle, lp_mode = CATEGORY_COLORS.get(cat_key, ("#333", "#fff", 0, 0, "static"))
                all_buttons.append((r["widgetID"], lp_row, col_idx + 1, lp_active, lp_idle, lp_mode))

    # Auto-detect Launchpad universe and set input profile
    lp_universe = find_launchpad_universe(client)

    # Set the Launchpad input profile + enable feedback
    print(f"  Setting Launchpad input profile on universe {lp_universe}...", end=" ", flush=True)
    profile_result = client.call("set_input_profile", {"items": [
        {"universeID": lp_universe, "profileName": "Novation Launchpad Mini MK3"}
    ]})
    profile_ok = all(r.get("status") == "ok" for r in profile_result)
    # Also enable feedback on the Launchpad universe
    fb_uni_result = client.call("configure_universes", {"items": [
        {"universeID": lp_universe, "feedbackEnabled": True}
    ]})
    print(f"✓ (profile: {'ok' if profile_ok else 'failed'}, feedback: {fb_uni_result[0].get('status', '?')})")

    # Map Launchpad inputs
    if all_buttons:
        print(f"\n  Mapping {len(all_buttons)} Launchpad inputs (universe {lp_universe})...", end=" ", flush=True)
        input_items = []
        for (wid, lp_row, lp_col, _, _, _) in all_buttons:
            input_items.append({
                "widgetID": wid,
                "inputUniverse": lp_universe,
                "inputChannel": launchpad_channel(lp_row, lp_col),
            })
        input_results = client.call("map_vc_inputs", {"items": input_items})
        ok = sum(1 for r in input_results if r.get("status") == "ok")
        print(f"✓ ({ok}/{len(input_items)})")

    # Configure LED feedback
    if all_buttons:
        print(f"  Configuring {len(all_buttons)} LED feedbacks...", end=" ", flush=True)
        fb_items = []
        for (wid, _, _, lp_active, lp_idle, lp_mode) in all_buttons:
            fb_items.append({
                "widgetID": wid,
                "idleValue": lp_idle,
                "activeValue": lp_active,
                "monitorValue": lp_active,
                "idleMode": "static",
                "activeMode": lp_mode,
                "monitorMode": lp_mode,
            })
        fb_results = client.call("configure_vc_feedback", {"items": fb_items})
        ok = sum(1 for r in fb_results if r.get("status") == "ok")
        print(f"✓ ({ok}/{len(fb_items)})")

    return all_buttons

# ── Main Builder ────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="JUNGLE DJ Show Builder for QLC+ MCP")
    parser.add_argument("--host", default="127.0.0.1", help="MCP server host")
    parser.add_argument("--port", type=int, default=9696, help="MCP server port")
    parser.add_argument("--skip-patch", action="store_true", help="Skip fixture patching")
    parser.add_argument("--skip-vc", action="store_true", help="Skip Virtual Console layout")
    parser.add_argument("--hero-id", type=int, default=None, help="Existing Hero Spot fixture ID")
    parser.add_argument("--haze-id", type=int, default=None, help="Existing Haze fixture ID")
    parser.add_argument("--uv-id", type=int, default=None, help="Existing UV Wash fixture ID")
    parser.add_argument("--hero-addr", type=int, default=0, help="Hero Spot DMX address")
    parser.add_argument("--haze-addr", type=int, default=30, help="Haze Machine DMX address")
    parser.add_argument("--uv-addr", type=int, default=40, help="UV Wash DMX address")
    args = parser.parse_args()

    print("╔══════════════════════════════════════════╗")
    print("║     🌴 JUNGLE DJ Show Builder v1.0       ║")
    print("║     QLC+ MCP Automated Setup             ║")
    print("╚══════════════════════════════════════════╝")

    # Connect
    print("\n📡 Connecting to MCP server...")
    client = MCPClient(args.host, args.port)
    client.connect()

    # Clean up existing functions to avoid duplicates
    print("\n🧹 Cleaning up existing functions...")
    existing = client.call("query_functions", {})
    if existing:
        del_ids = [f["id"] for f in existing]
        client.call("delete_functions", {"functionIDs": del_ids})
        print(f"  ✓ Deleted {len(del_ids)} existing functions")
    else:
        print("  ✓ No existing functions")

    # Patch fixtures
    if not args.skip_patch:
        print("\n🔌 Patching fixtures...")
        patch_items = [
            {**{k: FIXTURES["hero"][k] for k in ("manufacturer", "model", "mode", "name")},
             "universe": 0, "address": args.hero_addr, "quantity": 1},
            {**{k: FIXTURES["haze"][k] for k in ("manufacturer", "model", "mode", "name")},
             "universe": 0, "address": args.haze_addr, "quantity": 1},
            {**{k: FIXTURES["uv"][k] for k in ("manufacturer", "model", "mode", "name")},
             "universe": 0, "address": args.uv_addr, "quantity": 1},
        ]
        results = client.call("patch_fixtures", {"items": patch_items})
        hero_id = results[0]["id"]
        haze_id = results[1]["id"]
        uv_id = results[2]["id"]
        for r in results:
            if "error" in r:
                print(f"  ✗ {r['error']}")
                sys.exit(1)
            print(f"  ✓ {r['name']} → ID {r['id']} (addr {r['address']})")
    else:
        hero_id = args.hero_id if args.hero_id is not None else 0
        haze_id = args.haze_id if args.haze_id is not None else 1
        uv_id = args.uv_id if args.uv_id is not None else 2
        print(f"\n🔌 Using existing fixtures: hero={hero_id}, haze={haze_id}, uv={uv_id}")

    # Create scenes
    print("\n══════════════════════════════════════════")
    print("  CREATING FUNCTIONS")
    print("══════════════════════════════════════════")

    scene_defs = make_scenes(hero_id, haze_id, uv_id)
    ids = {}
    total = 0

    for category, scenes in scene_defs.items():
        print(f"  🎬 {category:12s} ({len(scenes):2d} scenes)...", end=" ", flush=True)
        results = client.call("create_scenes", {"items": scenes})
        ids[category] = [s["id"] for s in results]
        total += len(results)
        print(f"✓ IDs: {ids[category]}")

    # Chasers
    print(f"  🔁 {'chasers':12s} ( 4 chasers)...", end=" ", flush=True)
    chasers = client.call("create_chasers", {"items": [
        {"name": "🌈 Color Cycle", "functionIDs": ids["moods"][:6],
         "fadeIn": 2000, "fadeOut": 2000, "holdTime": 3000,
         "runOrder": "loop", "direction": "forward", "durationMode": "common"},
        {"name": "🎰 Gobo Carousel", "functionIDs": ids["gobos"],
         "fadeIn": 500, "fadeOut": 500, "holdTime": 2000,
         "runOrder": "loop", "direction": "forward", "durationMode": "common"},
        {"name": "📐 Position Sweep", "functionIDs": ids["positions"][:5],
         "fadeIn": 1500, "fadeOut": 1500, "holdTime": 1000,
         "runOrder": "pingpong", "direction": "forward", "durationMode": "common"},
        {"name": "🚨 Strobe Buildup", "functionIDs": [ids["utils"][6], ids["utils"][7]],
         "fadeIn": 0, "fadeOut": 0, "holdTime": 4000,
         "runOrder": "single", "direction": "forward", "durationMode": "common"},
    ]})
    ids["chasers"] = [c["id"] for c in chasers]
    total += len(chasers)
    print(f"✓ IDs: {ids['chasers']}")

    # EFX
    print(f"  ✨ {'efx':12s} ( 4 EFX)...", end=" ", flush=True)
    efxs = client.call("create_efxs", {"items": [
        {"name": "🌀 Circle Pan/Tilt", "fixtureIDs": [hero_id], "algorithm": "Circle",
         "width": 80, "height": 80, "speed": 3000},
        {"name": "♾️ Infinity Move", "fixtureIDs": [hero_id], "algorithm": "Eight",
         "width": 100, "height": 60, "speed": 4000},
        {"name": "🔲 Square Scan", "fixtureIDs": [hero_id], "algorithm": "Square",
         "width": 120, "height": 80, "speed": 5000},
        {"name": "🫨 Random Jungle", "fixtureIDs": [hero_id], "algorithm": "Lissajous",
         "width": 130, "height": 100, "speed": 3500},
    ]})
    ids["efx"] = [e["id"] for e in efxs]
    total += len(efxs)
    print(f"✓ IDs: {ids['efx']}")

    # Collections
    print(f"  📦 {'collections':12s} ( 8 collections)...", end=" ", flush=True)
    colls = client.call("create_collections", {"items": [
        {"name": "🌴 JUNGLE VIBE",      "functionIDs": [ids["moods"][0], ids["gobos"][4], ids["positions"][0], ids["utils"][0]]},
        {"name": "🔥 FIRE RITUAL",      "functionIDs": [ids["moods"][1], ids["gobos"][5], ids["efx"][0], ids["utils"][0]]},
        {"name": "🌙 MIDNIGHT HUNT",    "functionIDs": [ids["moods"][2], ids["gobos"][6], ids["efx"][1], ids["utils"][3]]},
        {"name": "💀 BLOOD RAVE",       "functionIDs": [ids["moods"][3], ids["gobos"][1], ids["efx"][3], ids["utils"][4]]},
        {"name": "✨ MYSTICAL FOREST",  "functionIDs": [ids["moods"][4], ids["gobos"][2], ids["beams"][2], ids["utils"][0]]},
        {"name": "❄️ ARCTIC STORM",     "functionIDs": [ids["moods"][5], ids["gobos"][3], ids["beams"][3], ids["efx"][2]]},
        {"name": "🌊 OCEAN DEEP",       "functionIDs": [ids["moods"][6], ids["gobos"][7], ids["efx"][1], ids["utils"][3]]},
        {"name": "☀️ SOLAR ERUPTION",   "functionIDs": [ids["moods"][7], ids["gobos"][5], ids["beams"][3], ids["utils"][1]]},
    ]})
    ids["collections"] = [c["id"] for c in colls]
    total += len(colls)
    print(f"✓ IDs: {ids['collections']}")

    print(f"\n  ═══ {total} functions created ═══")

    # Virtual Console
    if not args.skip_vc:
        build_vc(client, ids)

    # Summary
    print("\n╔══════════════════════════════════════════╗")
    print(f"║  ✅ JUNGLE SHOW COMPLETE                 ║")
    print(f"║  {total:3d} functions │ 8 VC frames │ LP mapped  ║")
    print("╚══════════════════════════════════════════╝")
    print("\n  Save the project in QLC+ (Ctrl+S) to persist!")

    # Write IDs for reference
    with open("/tmp/jungle_ids.json", "w") as f:
        json.dump(ids, f, indent=2)
    print("  Function IDs saved to /tmp/jungle_ids.json")

if __name__ == "__main__":
    main()
