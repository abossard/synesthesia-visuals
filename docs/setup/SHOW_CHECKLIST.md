# Show Setup Checklist

Complete step-by-step guide from music preparation to live performance. Follow in order — each section builds on the previous one.

> **SwiftVJApp** sections are marked **(Optional)** — the core rig runs without it.

---

## 0. Prerequisites

### Software to Install

- [ ] **VirtualDJ** — DJ software ([virtualdj.com](https://virtualdj.com))
- [ ] **QLC+** — DMX lighting control ([qlcplus.org](https://qlcplus.org)) — v4 or v5
- [ ] **Magic Music Visuals** — visual engine ([magicmusicvisuals.com](https://magicmusicvisuals.com))
- [ ] **LedFX** — LED strip audio-reactive effects ([ledfx.app](https://ledfx.app))
- [ ] **BlackHole 2ch** — audio loopback ([existential.audio/blackhole](https://existential.audio/blackhole))
- [ ] **sACN_ledfx_bridge** — QLC+ → LedFX scene bridge (`go install github.com/abossard/sACN_ledfx_bridge@latest`)
- [ ] **musicky** — music tagging tool (`git clone https://github.com/abossard/musicky.git`)
- [ ] **(Optional) SwiftVJApp** — central hub, lyrics, Syphon (`cd swift-vj && swift build`)

### Hardware

- [ ] **Enttec USB Pro** (or compatible) — USB → DMX interface
- [ ] **Launchpad Mini Mk3** — pad controller (connect via USB)
- [ ] **Akai MIDImix** — fader/knob controller (connect via USB)
- [ ] **DMX fixtures** — Hero Spot Wash 140, Thunderwash 600 UV, Hz-200 Hazer
- [ ] **WLED controllers + LED strips** — 4× 5m RGB strips on Wi-Fi

---

## 1. Music Preparation (musicky)

Do this well before the show — tagging takes time.

### 1.1 Install & Start musicky

```bash
cd musicky
npm install
echo "DATABASE_URL=./database.sqlite" > .env
npm run sqlite:migrate
npm run dev
# Open http://localhost:3000
```

### 1.2 Tag Your Tracks

- [ ] Load your music folder in the musicky UI
- [ ] Tag each track with DJ phase hashtags:
  - `#starter` — opening, low-medium energy
  - `#buildup` — tension, lifting
  - `#peak` — maximum energy, drops
  - `#release` — cool-down, recovery
  - `#feature` — special/highlight tracks
- [ ] Add genre/mood tags as needed: `#techno`, `#house`, `#dark`, `#melodic`

### 1.3 Export Tags to MP3 Files

- [ ] Review pending changes in musicky export UI
- [ ] Apply — writes hashtags to MP3 comment field (preserves BPM, key, artwork)

### 1.4 Import to VirtualDJ

- [ ] Point VirtualDJ at your tagged music folder
- [ ] Create smart crates using comment filters:
  - Peak energy: `comment CONTAINS "#peak"`
  - Buildup: `comment CONTAINS "#buildup"`
  - Starter: `comment CONTAINS "#starter"`

---

## 2. Audio Routing (macOS)

### 2.1 Create Multi-Output Device

- [ ] Open **Audio MIDI Setup** (Applications → Utilities)
- [ ] Click **+** → **Create Multi-Output Device**
- [ ] Check: **Built-in Output** (speakers/headphones) + **BlackHole 2ch**
- [ ] Set as system default output (right-click → "Use This Device for Sound Output")

### 2.2 Verify

- [ ] Play music → hear it through speakers
- [ ] BlackHole silently mirrors the audio (apps like Magic can read from it)

> **Ref:** [docs/setup/README.md](README.md)

---

## 3. Hardware Setup

### 3.1 Connect USB Devices

- [ ] **Enttec USB Pro** → USB (DMX interface)
- [ ] **Launchpad Mini Mk3** → USB
- [ ] **Akai MIDImix** → USB

### 3.2 Set Launchpad to Programmer Mode

- [ ] Hold **Session** button briefly
- [ ] Press the **orange Scene Launch** button (bottom-right area)
- [ ] Release **Session**
- [ ] Pads should go dark — you're in Programmer mode

### 3.3 Connect DMX Fixtures

- [ ] Daisy-chain: Enttec → Hero Spot Wash → Thunderwash UV → Hazer
- [ ] Set fixture DMX addresses (match QLC+ patch — see step 5)
- [ ] Power on all fixtures

### 3.4 WLED Strips

- [ ] Ensure all 4 WLED controllers are on Wi-Fi
- [ ] Note their IP addresses (e.g., `192.168.1.x`)
- [ ] Verify they respond: open `http://<wled-ip>` in browser

---

## 4. QLC+ Setup from Scratch

### 4.1 Create Workspace

- [ ] Open QLC+
- [ ] Save immediately: `File → Save As → show_name.qxw`

### 4.2 Configure Universes (Input/Output Manager)

| Universe | Name | Type | Target |
|----------|------|------|--------|
| U1 | `DMX` | Output | Enttec USB Pro |
| U2 | `OS2L` | Input | OS2L plugin, port `9996` |
| U3 | `Launchpad` | Input + Feedback | Launchpad MIDI ports (NOT DAW port) |
| U4 | `Magic OSC` | Output | OSC, `127.0.0.1`, port `7700` |
| U5 | `sACN LedFX` | Output | E1.31, unicast `127.0.0.1`, port `5568`, universe 1, multicast OFF |

- [ ] U1: Enable Enttec output
- [ ] U2: Enable OS2L input, set port to `9996`
- [ ] U3: Enable Launchpad MIDI input + feedback
- [ ] U4: Enable OSC output, host `127.0.0.1`, port `7700`
- [ ] U5: Enable E1.31 output, unicast `127.0.0.1`, port `5568`
- [ ] Save and reopen — verify all mappings persist

### 4.3 Patch Fixtures (on Universe 1)

| Fixture | DMX Address | Channels |
|---------|------------|----------|
| Varytec Hero Spot Wash 140 | 1 | 23ch |
| Stairville Hz-200 Hazer | 24 | 2ch |
| Cameo Thunderwash 600 UV | 26 | 4ch |

- [ ] Fixture Manager → Add → search for each fixture definition
- [ ] Set DMX addresses to match physical fixture DIP switches

### 4.4 Patch LedFX Bridge Fixture (on Universe 5)

- [ ] Add **Generic Dimmer** on Universe 5, address 1
- [ ] This single channel controls LedFX scene selection (value 1-N = scene N)

### 4.5 Create Test Scenes

- [ ] `TEST Hero Open White` — Hero Spot dimmer 100%, white, open gobo
- [ ] `TEST Hazer Mid` — Hazer at 50%
- [ ] `TEST UV Full` — Thunderwash dimmer 100%
- [ ] `TEST LedFX Scene 1` — Generic Dimmer on U5 set to value 1

### 4.6 Verify with DMX Monitor

- [ ] Tools → DMX Monitor → select Universe 1
- [ ] Activate each test scene → only expected channels change
- [ ] Save workspace

> **Ref:** [docs/setup/qlcplus-detailed-setup.md](qlcplus-detailed-setup.md)

---

## 5. Magic Music Visuals Setup

### 5.1 Audio Input

- [ ] Open Magic Music Visuals
- [ ] **Input Sources Window** → set Source 0 to **BlackHole 2ch**
- [ ] Play music → verify the waveform responds

### 5.2 Audio Analysis (Dual-Envelope Globals)

Create 6 output Globals for audio-reactive control:

| Global Name | Audio Source | Frequency | Modifier |
|-------------|------------|-----------|----------|
| `LowPeak` | Source 0 | Custom 20-200Hz | Peak |
| `LowSmooth` | Source 0 | Custom 20-200Hz | Smooth |
| `LowRaw` | Source 0 | Custom 20-200Hz | Raw |
| `HighPeak` | Source 0 | Custom 6000-20000Hz | Peak |
| `HighSmooth` | Source 0 | Custom 6000-20000Hz | Smooth |
| `HighRaw` | Source 0 | Custom 6000-20000Hz | Raw |

- [ ] Create each Global: right-click Globals panel → Add
- [ ] Link to Audio Source 0 with Custom Frequency Range
- [ ] Apply Peak/Smooth/Raw modifiers
- [ ] Verify: play music → Globals respond to beats

### 5.3 OSC Output to QLC+

Add OSCSender modules to send audio data to QLC+:

- [ ] Add OSCSender module → IP: `127.0.0.1`, Port: `7700`
- [ ] Map messages:

| OSC Path | Linked Global |
|----------|--------------|
| `/audio/low/peak` | LowPeak |
| `/audio/low/avg` | LowSmooth |
| `/audio/low/raw` | LowRaw |
| `/audio/high/peak` | HighPeak |
| `/audio/high/avg` | HighSmooth |
| `/audio/high/raw` | HighRaw |

### 5.4 Verify Magic → QLC+ Connection

- [ ] In QLC+: Input/Output → U4 input → enable OSC on port `7700`
- [ ] Create Input Profile: Wizard → play music → auto-detect OSC paths
- [ ] Add a Virtual Console slider → map to `/audio/low/peak` → verify it moves with bass

### 5.5 MIDImix Control (in Magic)

- [ ] Use **MIDI Learn** to map MIDImix faders/knobs to Magic parameters
- [ ] Suggested: Faders → layer opacity, Knobs → effect parameters

> **Ref:** [docs/setup/magic-detailed-setup.md](magic-detailed-setup.md), [docs/setup/quickstart-magic-to-qlcplus.md](quickstart-magic-to-qlcplus.md)

---

## 6. LedFX + sACN Bridge

### 6.1 Start LedFX

```bash
ledfx
# Opens at http://127.0.0.1:8888
```

- [ ] Add WLED devices by IP address
- [ ] Create virtuals for each strip
- [ ] Create scenes for each DJ phase (use naming like `p1-gentle-energy`, `p3-hard-reactor`)
- [ ] Verify scenes activate correctly in LedFX UI

### 6.2 Start sACN Bridge

```bash
# Install (first time)
go install github.com/abossard/sACN_ledfx_bridge@latest

# Run
sACN_ledfx_bridge
```

- [ ] In TUI: set Universe to `1`, Channel to `1`, LedFX Host to `http://127.0.0.1:8888`
- [ ] Go to Scenes → select **"get scenes from LedFx Api"** → scenes load automatically
- [ ] Reorder scenes by phase (P1 scenes first, then P2, P3, P4)
- [ ] Save config (Ctrl+S in scene menu, then navigate to [Save])

### 6.3 Verify QLC+ → Bridge → LedFX

- [ ] In QLC+ Simple Desk: set U5/Ch1 to value `1` → bridge TUI shows scene name → LedFX activates
- [ ] Set to `0` → scene deactivates
- [ ] Try values 1-N → each scene activates in order

> **Ref:** [docs/setup/sacn-ledfx-bridge-setup.md](sacn-ledfx-bridge-setup.md)

---

## 7. VirtualDJ Configuration

### 7.1 OS2L Setup

- [ ] VirtualDJ → Settings → OS2L → **Enable**
- [ ] Set target IP: `127.0.0.1`
- [ ] Port for QLC+: `9996`

### 7.2 (Optional) OSC Output for SwiftVJApp

- [ ] Configure OSC output to port `9010` (SwiftVJApp receives track info)
- [ ] Configure second OS2L target on port `9997` (SwiftVJApp receives beat/cues)

### 7.3 Cue Point Actions

Set up POI (Points of Interest) in your tracks:

| Action | VirtualDJ Script |
|--------|-----------------|
| Drop hit | `os2l_button "drop"` |
| Chorus | `os2l_button "chorus"` |
| Strobe trigger | `os2l_button "strobe"` |
| Blackout | `os2l_button "blackout"` |

### 7.4 Verify OS2L Connection

- [ ] Play a track in VirtualDJ
- [ ] QLC+ should show OS2L activity indicator (joystick icon) on Universe 2
- [ ] Beat counter should be visible

---

## 8. (Optional) SwiftVJApp

> Skip this section if running without SwiftVJApp. The core rig works fine with just VirtualDJ + QLC+ + Magic + LedFX.

### 8.1 Build & Launch

```bash
cd swift-vj
swift build
swift run SwiftVJApp
```

### 8.2 Configure

- [ ] Set shader directory path
- [ ] Verify Syphon outputs appear (Shader, Mask, Lyrics, etc.)
- [ ] Connect to Magic via Syphon for visual overlays

### 8.3 Verify Connections

- [ ] OS2L from VirtualDJ (port 9997) — track changes visible
- [ ] Syphon to Magic — visual layers appear
- [ ] REST to LedFX (port 8888) — optional, bridge handles this now

---

## 9. Integration Verification

Run through each connection to confirm the full signal chain works.

### 9.1 Audio Chain

- [ ] Play music → hear through speakers
- [ ] Magic shows audio waveform (BlackHole input)
- [ ] QLC+ sliders respond to audio OSC from Magic
- [ ] LedFX strips react to audio

### 9.2 Beat/Cue Chain

- [ ] VirtualDJ playing → QLC+ receives OS2L beat data
- [ ] OS2L cue buttons trigger QLC+ actions

### 9.3 Lighting Chain

- [ ] QLC+ scene → DMX fixtures respond (Hero Spot, Thunderwash, Hazer)
- [ ] QLC+ U5/Ch1 value → sACN bridge → LedFX scene change → strips update

### 9.4 MIDI Controllers

- [ ] Launchpad pads trigger QLC+ buttons (in Programmer mode)
- [ ] MIDImix faders control Magic parameters

### 9.5 (Optional) SwiftVJApp Chain

- [ ] VirtualDJ track change → SwiftVJApp shows track info
- [ ] SwiftVJApp Syphon → Magic receives visual overlays

---

## 10. Pre-Show Final Checks

### Atmosphere

- [ ] Hazer ON at 25% — verify haze is building
- [ ] Hero Spot beam visible through haze

### Levels

- [ ] Master audio level comfortable
- [ ] LED strip brightness appropriate for room
- [ ] DMX fixture brightness not blinding at close range

### Ready State

- [ ] First track loaded in VirtualDJ
- [ ] QLC+ in Operate mode (not Design)
- [ ] LedFX scene ready (P1 starter)
- [ ] sACN bridge running (TUI or daemon mode)
- [ ] Magic visuals ready (first scene loaded)
- [ ] Launchpad showing expected pad colors
- [ ] All apps full-screen or positioned on correct displays

### Go Live

1. Start hazer (takes 2-3 min to fill room)
2. Start P1 lighting scene in QLC+ (sets both DMX + LedFX via bridge)
3. Start first track in VirtualDJ
4. Magic follows audio automatically
5. 🎉 **You're live**

---

## Quick Port Reference

| Port | Protocol | From → To | Purpose |
|------|----------|-----------|---------|
| 5568 | sACN/E1.31 | QLC+ → sACN_ledfx_bridge | LedFX scene select |
| 7700 | OSC/UDP | Magic → QLC+ | Audio-reactive lighting |
| 8888 | HTTP/REST | Bridge / SwiftVJApp → LedFX | Scene activation |
| 9010 | OSC/UDP | VirtualDJ → SwiftVJApp | Track info (optional) |
| 9996 | OS2L/TCP | VirtualDJ → QLC+ | Beat/cue sync |
| 9997 | OS2L/TCP | VirtualDJ → SwiftVJApp | Beat/cue sync (optional) |
| 11111 | OSC/UDP | SwiftVJApp → Magic | Shader control (optional) |

## Detailed Setup Docs

| Topic | Document |
|-------|----------|
| QLC+ full setup | [qlcplus-detailed-setup.md](qlcplus-detailed-setup.md) |
| Magic audio + OSC | [magic-detailed-setup.md](magic-detailed-setup.md) |
| Magic → QLC+ quickstart | [quickstart-magic-to-qlcplus.md](quickstart-magic-to-qlcplus.md) |
| sACN bridge | [sacn-ledfx-bridge-setup.md](sacn-ledfx-bridge-setup.md) |
| MIDI controllers | [midi-controller-setup.md](midi-controller-setup.md) |
| DJ phase design | [../../brief/DJ_PHASE_GUIDE.md](../../brief/DJ_PHASE_GUIDE.md) |
