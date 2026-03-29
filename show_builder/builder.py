"""Show builder — orchestration layer.

Action module: coordinates pure compile functions with MCP side effects.
Deep module interface: build_show(client, rig, skip_vc) does everything.
"""

import json
import sys

from .fixtures import FIXTURE_PATCHES, CHANNEL_MODIFIERS, make_rig
from .scenes import (
    compile_all_scenes, compile_efx,
    compile_auto_chasers, compile_energy_chaser,
    compile_buildup_chasers, compile_vc_chasers,
    compile_phase_collections,
)
from .layout import (
    FRAME_W, BTN_W, BTN_H, PAD, FRAME_H, FRAME_GAP, BTN_Y,
    GRANULAR_CATEGORIES, launchpad_channel, get_launchpad_layout,
)


# ═══════════════════════════════════════════════════════════════════════════
# Fixture Patching
# ═══════════════════════════════════════════════════════════════════════════

def patch_fixtures(client, addresses):
    """Patch fixtures via MCP. Returns (hero_id, haze_id, uv_id)."""
    print("\n🔌 Patching fixtures...")
    patch_items = [
        {**patch, "universe": 0, "address": addr}
        for patch, addr in zip(FIXTURE_PATCHES, addresses)
    ]
    results = client.call("patch_fixtures", {"items": patch_items})
    for r in results:
        if "error" in r:
            print(f"  ✗ {r['error']}")
            sys.exit(1)
        print(f"  ✓ {r['name']} → ID {r['id']} (addr {r['address']})")
    return results[0]["id"], results[1]["id"], results[2]["id"]


# ═══════════════════════════════════════════════════════════════════════════
# Scene/Function Creation
# ═══════════════════════════════════════════════════════════════════════════

def _create_batch(client, tool, label, items):
    """Create a batch via MCP and return IDs."""
    print(f"  {'🎬' if tool == 'create_scenes' else '✨' if tool == 'create_efxs' else '🔁' if tool == 'create_chasers' else '📦'} "
          f"{label:20s} ({len(items):2d})...", end=" ", flush=True)
    results = client.call(tool, {"items": items})
    ids = [r["id"] for r in results]
    print(f"✓ IDs: {ids}")
    return ids


def create_all_functions(client, rig):
    """Create all scenes, EFX, chasers, collections. Returns ids dict.

    Flow: compile (pure) → create via MCP (action) → use IDs to compile
    next level → create next level.
    """
    ids = {}

    # ── Scenes ──
    print("\n══════════════════════════════════════════")
    print("  CREATING SCENES")
    print("══════════════════════════════════════════")

    compiled = compile_all_scenes(rig)
    scene_labels = {
        "phase_textures": "Phase textures",
        "energy": "Energy levels",
        "moods": "Mood colors",
        "master": "Master intensity",
        "haze": "Haze control",
        "strobes": "Strobe presets",
        "shots": "Quick shots",
        "vc_gobos": "VC gobos",
        "vc_positions": "VC positions",
        "vc_rotations": "VC rotations",
        "vc_beams": "VC beams",
    }
    for key, scenes in compiled.items():
        label = scene_labels.get(key, key)
        ids[key] = _create_batch(client, "create_scenes", label, scenes)

    # ── EFX ──
    print("\n══════════════════════════════════════════")
    print("  CREATING EFX")
    print("══════════════════════════════════════════")

    efx_items = compile_efx(rig)
    ids["efx"] = _create_batch(client, "create_efxs", "EFX", efx_items)

    # ── Chasers ──
    print("\n══════════════════════════════════════════")
    print("  CREATING CHASERS")
    print("══════════════════════════════════════════")

    ids["auto_chasers"] = _create_batch(
        client, "create_chasers", "Phase auto-chasers",
        compile_auto_chasers(ids["moods"]),
    )
    ids["auto_energy"] = _create_batch(
        client, "create_chasers", "Auto-energy chaser",
        compile_energy_chaser(ids["energy"]),
    )
    ids["buildups"] = _create_batch(
        client, "create_chasers", "Buildups",
        compile_buildup_chasers(ids["strobes"], ids["haze"], ids["master"]),
    )
    ids["vc_chasers"] = _create_batch(
        client, "create_chasers", "VC chasers",
        compile_vc_chasers(ids["vc_gobos"], ids["vc_positions"]),
    )

    # ── Collections ──
    print("\n══════════════════════════════════════════")
    print("  CREATING COLLECTIONS")
    print("══════════════════════════════════════════")

    ids["phase_collections"] = _create_batch(
        client, "create_collections", "Phase collections",
        compile_phase_collections(ids["phase_textures"], ids["moods"]),
    )

    total = sum(len(v) for v in ids.values())
    print(f"\n  ═══ {total} functions created ═══")
    return ids


# ═══════════════════════════════════════════════════════════════════════════
# Channel Modifiers
# ═══════════════════════════════════════════════════════════════════════════

def setup_channel_modifiers(client, rig):
    """Apply dimmer response curves."""
    print("\n  Applying channel modifiers...")
    try:
        # Group modifiers by fixture type
        by_fixture = {}
        for mod in CHANNEL_MODIFIERS:
            ft = mod["fixture"]
            fid = rig[ft]["id"]
            ch_offset = rig[ft]["channels"][mod["channel"]]
            by_fixture.setdefault(fid, []).append(
                {"channel": ch_offset, "modifier": mod["modifier"]}
            )
        items = [
            {"fixtureID": fid, "modifications": mods}
            for fid, mods in by_fixture.items()
        ]
        client.call("set_channel_modifiers", {"items": items})
        for mod in CHANNEL_MODIFIERS:
            print(f"  ✓ {mod['fixture']}.{mod['channel']} → {mod['modifier']}")
    except Exception as e:
        print(f"  ⚠ Channel modifiers failed: {e}")


# ═══════════════════════════════════════════════════════════════════════════
# Virtual Console + Launchpad
# ═══════════════════════════════════════════════════════════════════════════

def _find_launchpad_universe(client):
    """Detect Launchpad MIDI universe."""
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


def _build_launchpad_rows(client, ids, layout):
    """Create VC frames/buttons for each Launchpad row. Returns button metadata."""
    all_buttons = []

    # Y position per lp_row (top-down: row 8 at top)
    row_y = {}
    y = 0
    for row_num in range(8, 0, -1):
        row_y[row_num] = y
        y += FRAME_H + FRAME_GAP

    for frame_def in layout:
        lp_row = frame_def["lp_row"]
        frame_y = row_y[lp_row]

        # Create frame
        print(f"  Frame: {frame_def['caption']:20s}...", end=" ", flush=True)
        frame_results = client.call("add_vc_frames", {"items": [{
            "pageIndex": 0, "x": frame_def["x"], "y": frame_y,
            "width": frame_def["w"], "height": FRAME_H,
            "caption": frame_def["caption"], "solo": frame_def["solo"],
            "bgColor": "#111111", "fgColor": "#ffffff",
        }]})
        frame_id = frame_results[0]["widgetID"]
        if frame_id < 0:
            print("✗ FAILED")
            continue
        print(f"✓ (ID {frame_id})")

        # Resolve column offset for split rows
        col_offset = 0
        if frame_def["x"] > 0:
            if frame_def["w"] < FRAME_W:
                col_offset = len(
                    [b for b in layout
                     if b["lp_row"] == lp_row and b["x"] == 0][0]["buttons"]
                )

        # Create buttons
        btn_items, btn_meta = [], []
        for col_idx, btn in enumerate(frame_def["buttons"]):
            if btn is None:
                continue
            btn_item = {
                "parentID": frame_id,
                "x": PAD + col_idx * (BTN_W + PAD), "y": BTN_Y,
                "width": BTN_W, "height": BTN_H,
                "caption": btn["label"],
                "bgColor": "#222222", "fgColor": "#ffffff",
            }
            if "special" in btn:
                btn_item["action"] = btn["special"]
            else:
                btn_item["action"] = btn["action"]
                btn_item["functionID"] = ids[btn["key"]][btn["idx"]]

            btn_items.append(btn_item)
            btn_meta.append({
                "lp_row": lp_row,
                "lp_col": col_idx + 1 + col_offset,
                "idle": btn["idle"], "active": btn["active"],
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
                m = btn_meta[i]
                all_buttons.append((
                    r["widgetID"], m["lp_row"], m["lp_col"],
                    m["idle"], m["active"], m["mode"],
                ))

    return all_buttons, y  # y = next available vertical position


def _map_launchpad_inputs(client, all_buttons, lp_universe):
    """Map Launchpad pads to VC buttons and configure LED feedback."""
    if not all_buttons:
        return

    # Input mapping
    print(f"\n  Mapping {len(all_buttons)} Launchpad inputs (universe {lp_universe})...",
          end=" ", flush=True)
    input_items = [{
        "widgetID": wid,
        "inputUniverse": lp_universe,
        "inputChannel": launchpad_channel(row, col),
    } for wid, row, col, _, _, _ in all_buttons]
    results = client.call("map_vc_inputs", {"items": input_items})
    ok = sum(1 for r in results if r.get("status") == "ok")
    print(f"✓ ({ok}/{len(input_items)})")

    # LED feedback
    print(f"  Configuring {len(all_buttons)} LED feedbacks...", end=" ", flush=True)
    fb_items = [{
        "widgetID": wid,
        "idleValue": idle, "activeValue": active, "monitorValue": active,
        "idleMode": "static", "activeMode": mode, "monitorMode": mode,
    } for wid, _, _, idle, active, mode in all_buttons]
    results = client.call("configure_vc_feedback", {"items": fb_items})
    ok = sum(1 for r in results if r.get("status") == "ok")
    print(f"✓ ({ok}/{len(fb_items)})")


def _build_granular_vc(client, ids, start_y):
    """Build VC-only granular controls (not mapped to Launchpad)."""
    print("\n══════════════════════════════════════════")
    print("  VIRTUAL CONSOLE — GRANULAR (VC ONLY)")
    print("══════════════════════════════════════════")

    gy = start_y + 20
    for cat_key, caption, solo in GRANULAR_CATEGORIES:
        if cat_key not in ids:
            continue
        func_ids = ids[cat_key]

        frame_res = client.call("add_vc_frames", {"items": [{
            "pageIndex": 0, "x": 0, "y": gy,
            "width": FRAME_W, "height": FRAME_H,
            "caption": caption, "solo": solo,
            "bgColor": "#0a0a0a", "fgColor": "#888888",
        }]})
        fid = frame_res[0]["widgetID"]
        if fid < 0:
            continue

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

    # VC chasers (Gobo Carousel + Position Sweep)
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


def build_vc(client, ids, lp_universe):
    """Build entire Virtual Console: Launchpad rows + granular VC controls."""
    print("\n══════════════════════════════════════════")
    print("  VIRTUAL CONSOLE — LAUNCHPAD LAYOUT")
    print("══════════════════════════════════════════")

    layout = get_launchpad_layout()
    all_buttons, next_y = _build_launchpad_rows(client, ids, layout)
    _map_launchpad_inputs(client, all_buttons, lp_universe)
    _build_granular_vc(client, ids, next_y)


# ═══════════════════════════════════════════════════════════════════════════
# Top-Level Orchestration
# ═══════════════════════════════════════════════════════════════════════════

def clean_existing_functions(client):
    """Remove all existing functions. Reconnects if needed."""
    print("\n🧹 Cleaning up existing functions...")
    try:
        existing = client.call("query_functions", {})
        if existing:
            del_ids = [f["id"] for f in existing]
            try:
                client.call("delete_functions", {"functionIDs": del_ids})
                print(f"  ✓ Deleted {len(del_ids)} existing functions")
            except Exception:
                print("  ⚠ Delete failed, reconnecting...")
                client.connect()
        else:
            print("  ✓ No existing functions")
    except Exception:
        print("  ⚠ Query failed, reconnecting...")
        client.connect()


def build_show(client, hero_id, haze_id, uv_id, skip_vc=False):
    """Build the complete phase-based DJ show.

    Deep module: takes fixture IDs, produces a fully configured QLC+ show
    with scenes, EFX, chasers, collections, and Virtual Console layout.
    """
    rig = make_rig(hero_id, haze_id, uv_id)

    # Create all functions (scenes → EFX → chasers → collections)
    ids = create_all_functions(client, rig)

    # Channel modifiers
    setup_channel_modifiers(client, rig)

    # Virtual Console + Launchpad
    if not skip_vc:
        try:
            client.call("query_universes", {})
        except Exception:
            print("\n  🔄 Reconnecting to MCP server...")
            client.connect()

        lp_universe = _find_launchpad_universe(client)

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

    # Save ID manifest
    with open("/tmp/phase_show_ids.json", "w") as f:
        json.dump(ids, f, indent=2)
    print("  Function IDs saved to /tmp/phase_show_ids.json")

    return ids
