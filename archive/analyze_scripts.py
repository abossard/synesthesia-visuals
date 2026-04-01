#!/usr/bin/env python3
"""Analyze what each script calls, using saved IDs."""
import json

ids = json.load(open("/tmp/phase_show_ids.json"))

name_map = {}
labels = {
    "moods": ["Deep Jungle","Amber Canopy","Midnight Blue","Blood Moon","Mystic Violet","Arctic White","Tropical Cyan","Solar Flare"],
    "phase_textures": ["P1 Jungle Texture","P2 Buildup Texture","P3 Peak Texture","P4 Release Texture"],
    "energy": ["E1 Entry","E2 Flow","E3 Build","E4 Bullet","E5 Peak","E6 Accent","E7 Exit"],
    "efx": ["Gentle Sway","Rhythmic Scan","Bar Sweep","Beat Snap","Half-Beat Twitch","Glitch Jitter","Seizure Mode","Chaos Engine"],
    "phase_collections": ["P1 Jungle","P2 Buildup","P3 Peak","P4 Release"],
    "auto_chasers": ["P1 Color Cycle","P2 Color Cycle","P3 Color Cycle","P4 Color Cycle"],
    "buildups": ["Strobe Ramp","UV Surge","Haze Pump","Blackout Hit"],
    "strobes": ["SpotStrobeOff","SpotStrobeSlow","SpotStrobeMed","SpotStrobeFast","UVStrobeOff","UVStrobeSlow","UVStrobeMed","UVStrobeFast"],
    "master": ["Master25","Master50","Master75","Master100","KILL"],
    "haze": ["HazeOff","HazeLow","HazeFull"],
}
for key, names in labels.items():
    if key in ids:
        for i, fid in enumerate(ids[key]):
            if i < len(names):
                name_map[fid] = names[i]

phase_efx = [ids["efx"][0], ids["efx"][1], ids["efx"][3], ids["efx"][0]]
phase_keys = ["P1", "P2", "P3", "P4"]
phase_names = ["P1 Jungle", "P2 Buildup", "P3 Peak", "P4 Release"]

print("=" * 50)
print("  TRANSITION SCRIPTS")
print("=" * 50)
for i, (pk, pn) in enumerate(zip(phase_keys, phase_names)):
    start_ids = {ids["phase_collections"][i], ids["auto_chasers"][i], phase_efx[i]}
    stop_ids = set()
    for j in range(4):
        if j != i:
            stop_ids.add(ids["phase_collections"][j])
            stop_ids.add(ids["auto_chasers"][j])
            stop_ids.add(phase_efx[j])
    stop_ids -= start_ids

    sid = ids["transition_scripts"][i]
    print(f"\nGO {pn} (script ID {sid}):")
    for fid in sorted(stop_ids):
        print(f"  STOP  {name_map.get(fid, f'??? ID={fid}'):30s} (fn {fid})")
    for fid in sorted(start_ids):
        print(f"  START {name_map.get(fid, f'??? ID={fid}'):30s} (fn {fid})")

print()
print("=" * 50)
print("  IMPACT SCRIPTS")
print("=" * 50)

impacts = {
    "DROP HIT": [
        ("START", ids["buildups"][3], "Blackout Hit chaser"),
        ("START", ids["buildups"][0], "Strobe Ramp chaser"),
        ("START", ids["energy"][4],   "E5 Peak"),
    ],
    "UV STROBE BLAST": [
        ("START", ids["buildups"][1], "UV Surge chaser"),
        ("START", ids["strobes"][3],  "Spot Strobe Fast"),
        ("START", ids["energy"][5],   "E6 Accent"),
    ],
    "TENSION BUILD": [
        ("START", ids["buildups"][2], "Haze Pump chaser"),
        ("START", ids["buildups"][0], "Strobe Ramp chaser"),
        ("START", ids["energy"][2],   "E3 Build"),
        ("START", ids["efx"][4],      "Half-Beat Twitch"),
    ],
    "CALM RESET": [
        ("STOP",  ids["buildups"][0], "Strobe Ramp"),
        ("STOP",  ids["buildups"][1], "UV Surge"),
        ("STOP",  ids["strobes"][3],  "Spot Strobe Fast"),
        ("STOP",  ids["strobes"][7],  "UV Strobe Fast"),
        ("START", ids["strobes"][0],  "Spot Strobe Off"),
        ("START", ids["strobes"][4],  "UV Strobe Off"),
        ("START", ids["energy"][0],   "E1 Entry"),
        ("START", ids["efx"][0],      "Gentle Sway"),
    ],
    "CHAOS MOMENT": [
        ("START", ids["efx"][7],      "Chaos Engine"),
        ("START", ids["buildups"][0], "Strobe Ramp"),
        ("START", ids["buildups"][1], "UV Surge"),
        ("START", ids["energy"][5],   "E6 Accent"),
    ],
    "CLEAN STOP": [
        ("STOP",  ids["buildups"][0], "Strobe Ramp"),
        ("STOP",  ids["buildups"][1], "UV Surge"),
        ("STOP",  ids["buildups"][2], "Haze Pump"),
        ("STOP",  ids["buildups"][3], "Blackout Hit"),
        ("STOP",  ids["strobes"][3],  "Spot Strobe Fast"),
        ("STOP",  ids["strobes"][7],  "UV Strobe Fast"),
        ("START", ids["strobes"][0],  "Spot Strobe Off"),
        ("START", ids["strobes"][4],  "UV Strobe Off"),
        ("START", ids["energy"][0],   "E1 Entry"),
    ],
}

impact_names = list(impacts.keys())
for name, cmds in impacts.items():
    idx = impact_names.index(name)
    sid = ids["impact_scripts"][idx]
    print(f"\n{name} (script ID {sid}):")
    for action, fid, desc in cmds:
        print(f"  {action:5s} {desc:30s} (fn {fid})")
