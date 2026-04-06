# sACN → LedFX Bridge Setup

## Overview

The [sACN\_ledfx\_bridge](https://github.com/abossard/sACN_ledfx_bridge) is a Go CLI tool that lets QLC+ control LedFX scenes over sACN (E1.31). It listens on a configurable sACN universe/channel for DMX values and maps each value to a LedFX scene via the REST API. DMX value 0 deactivates the current scene; values 1–N activate the corresponding scene from the configured list. This means QLC+ chasers, collections, and sliders can automate LedFX scene changes alongside your DMX fixtures — no manual switching required.

---

## Prerequisites

- **Go 1.21+** installed (`go version` to check)
- **LedFX** running at `http://127.0.0.1:8888` (default)
- **QLC+** with an E1.31 (sACN) output configured
- At least **one LedFX scene** created in the LedFX UI

---

## Install

```bash
# Option A: go install (gets the latest tagged release)
go install github.com/abossard/sACN_ledfx_bridge@latest

# Option B: clone and build locally
git clone https://github.com/abossard/sACN_ledfx_bridge.git
cd sACN_ledfx_bridge
go build
```

After building, the binary is `./sACN_ledfx_bridge` (or in your `$GOPATH/bin` for Option A).

---

## Configure

### Using the TUI

Run the bridge without flags to enter the interactive Charm TUI:

```bash
./sACN_ledfx_bridge
```

From the TUI you can set:

| Setting | Description | Default |
|---|---|---|
| Universe | sACN universe to listen on — must match the QLC+ E1.31 output | `1` |
| Channel | DMX channel within that universe that selects scenes | `1` |
| LedFX Host | LedFX REST API URL | `http://127.0.0.1:8888` |
| Scenes | Enter the scene submenu, then select **"get scenes from LedFx Api"** to auto-populate | `[]` |

### Manual config.json

The bridge reads from `config.json` in the working directory. You can edit it directly:

```json
{
  "sAcnUniverse": 1,
  "channel": 1,
  "scenes": [
    "warm-ambient",
    "cool-pulse",
    "rainbow-wave",
    "strobe-white"
  ],
  "ledfx_host": "http://127.0.0.1:8888"
}
```

Scene names must match the IDs returned by the LedFX API (`GET /api/scenes`). The easiest way to get them right is to auto-fetch from the TUI first, then reorder the resulting `config.json`.

---

## Scene Ordering Strategy

The order of scenes in `config.json` determines which DMX value activates which scene:

| DMX Value | Action |
|---|---|
| 0 | **OFF** — deactivate current scene |
| 1 | Activate scene[0] (first in list) |
| 2 | Activate scene[1] |
| … | … |
| N | Activate scene[N-1] |

**Recommended ordering by DJ phase:**

| DMX Values | Phase | Example Scenes |
|---|---|---|
| 1–4 | P1 Starter | warm-ambient, soft-fade, slow-rainbow, cool-drift |
| 5–8 | P2 Buildup | energy-pulse, bass-chase, mid-sweep, color-cycle |
| 9–12 | P3 Peak | strobe-white, full-spectrum, hard-flash, laser-sim |
| 13–16 | P4 Release | fade-out, chill-wave, dim-pulse, afterglow |

This way a QLC+ slider on the bridge channel gives a logical progression through the set phases.

---

## QLC+ Configuration

### E1.31 Output Setup

In QLC+ **Input/Output Manager**:

1. Select **Universe 5** (or another available universe — keep DMX fixtures on U1).
2. Enable **E1.31** as the output plugin.
3. Set to **unicast**: `127.0.0.1` (same machine).
4. Port: **5568** (E1.31 default).
5. Multicast: **OFF** (unicast is more reliable on macOS).
6. Universe number: **1** (must match the bridge's `sAcnUniverse` config).

> **Why Universe 5?** Universes 1–4 are already allocated in the recommended layout (see [qlcplus-detailed-setup.md](qlcplus-detailed-setup.md#recommended-universe-layout)). Universe 5 keeps LedFX bridge traffic isolated.

### Scene Selector Fixture

1. In Fixture Manager, add a **Generic Dimmer** on Universe 5, address 1, 1 channel.
2. This single-channel fixture represents the LedFX scene selector.

You can now control it from:

- **Scene function**: set the dimmer value (1–N) to select a specific LedFX scene.
- **Virtual Console slider**: map a slider to U5/Ch1 for manual scene browsing.
- **Chaser steps**: include the fixture in chaser steps for timed scene changes.

### Phase Collections

Create QLC+ **Collection** functions that fire both DMX lighting changes and LedFX scene changes simultaneously:

| Collection | DMX Content | LedFX (U5/Ch1) |
|---|---|---|
| P1-Entry | Hero Spot warm wash scene | Value 1 (warm-ambient) |
| P2-Build | Moving head sweep + color cycle | Value 5 (energy-pulse) |
| P3-Peak-Drop | Strobe burst + full RGB | Value 10 (hard-flash) |
| P4-Cooldown | Slow fade to ambient | Value 14 (chill-wave) |

This keeps DMX and LedFX in sync from a single button press on the Virtual Console or Launchpad.

---

## Running

```bash
# TUI mode (interactive — use during setup and rehearsal)
./sACN_ledfx_bridge

# Daemon mode (headless — use for production/performance)
./sACN_ledfx_bridge -d

# Custom config path
./sACN_ledfx_bridge -c /path/to/config.json
```

In daemon mode the bridge runs silently and processes DMX values without the TUI. Use this when the bridge is stable and you don't need to see status output.

---

## Verify

Walk through these steps to confirm the full pipeline works:

1. **LedFX scenes exist** — open `http://127.0.0.1:8888/api/scenes` in a browser and confirm your scenes are listed.
2. **Start the bridge** — `./sACN_ledfx_bridge` (TUI mode for visual feedback).
3. **Load scenes** — in the bridge TUI, enter the scene submenu and select "get scenes from LedFx Api". Confirm the scene list populates.
4. **Open QLC+ Simple Desk** — or create a slider on U5/Ch1 in the Virtual Console.
5. **Set channel 1 to value 1** — the bridge TUI should print the first scene name; LedFX should activate that scene visually.
6. **Set value to 0** — the scene should deactivate in LedFX.
7. **Sweep values 1–N** — each value should activate the corresponding scene in order.

If all steps pass, the bridge is ready for show use.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Bridge not receiving any data | QLC+ not sending E1.31 | Check that Universe 5 output is enabled and set to unicast `127.0.0.1` |
| Bridge receives but LedFX doesn't change | Wrong LedFX host or port | Verify `ledfx_host` in `config.json` matches the running LedFX instance |
| Only some scenes work | Scene list out of sync | Re-fetch scenes from LedFX API in the bridge TUI after adding/removing scenes |
| Port conflict on 5568 | Another sACN receiver on the same port | Use a different E1.31 universe number in both QLC+ and bridge config |
| Multicast not working | macOS firewall blocking multicast | Switch to unicast (`127.0.0.1`) — this is the recommended setup on macOS |
| Bridge exits immediately in daemon mode | Config file missing or invalid | Run in TUI mode first to generate a valid `config.json`, then switch to `-d` |
