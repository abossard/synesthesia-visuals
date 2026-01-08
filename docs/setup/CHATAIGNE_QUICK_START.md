# Chataigne Quick Start: 400 Shader VJ Rig

**Goal**: Get a 400-shader Launchpad-controlled VJ rig running in 30 minutes.

---

## Prerequisites

- [ ] macOS with Synesthesia installed
- [ ] Magic Music Visuals (Performer edition or Demo)
- [ ] Launchpad Mini MK3
- [ ] Akai MIDImix (optional, for advanced controls)
- [ ] BlackHole audio loopback installed
- [ ] 400+ Synesthesia scenes organized in library

---

## 5-Minute Setup

### 1. Install Chataigne

```bash
# Download from https://benjamin.kuperberg.fr/chataigne/
# Install the .dmg
# Launch Chataigne
```

### 2. Load Sample Configuration

```bash
# Clone this repo if not already done
git clone https://github.com/abossard/synesthesia-visuals.git
cd synesthesia-visuals

# Open Chataigne
# File → Open → Select lpsyn.noisette
```

### 3. Connect Hardware

1. Connect Launchpad Mini MK3 via USB
2. Put Launchpad in **Programmer Mode**:
   - Hold **Session** button
   - Press top-right button (orange light)
   - Release both
3. Verify in Chataigne: Modules → Launchpad Mini MK3 → Devices shows "Launchpad Mini MK3 LPMiniMK3 MIDI Out"

### 4. Configure Audio Routing

1. Open **Audio MIDI Setup** (in /Applications/Utilities)
2. Create **Multi-Output Device**:
   - Click `+` → Create Multi-Output Device
   - Check: ☑ MacBook Pro Speakers, ☑ BlackHole 2ch
3. Set as system output: System Settings → Sound → Output → Multi-Output Device
4. In **Synesthesia**:
   - Settings → Audio → Input Device: BlackHole 2ch

### 5. Enable Synesthesia OSC

1. In Synesthesia: Settings → OSC
2. Configure:
   - ☑ Enable OSC Output
   - Output Address: `127.0.0.1`
   - Output Port: `9999`
   - ☑ Output Audio Variables
   - ☑ Enable OSC Input
   - Input Port: `7777`

### 6. Enable Synesthesia Syphon

1. In Synesthesia: Settings → Video
2. Configure:
   - ☑ Enable Syphon Output
   - Server Name: "Synesthesia Main Output" (or custom)

### 7. Test the Connection

1. **Play music** (Spotify, DJ app, or audio file)
2. **Check Synesthesia** VU meter shows audio activity
3. **Check Chataigne** OSC module shows values updating:
   - `/audio/level/bass`
   - `/audio/beat/onbeat`
4. **Press Launchpad pad** (e.g., top-left pad)
5. **Verify Synesthesia** scene changes

✅ **If scene changed**: You're ready to go!  
❌ **If not working**: See [Troubleshooting](#troubleshooting) below.

---

## 10-Minute Customization

### Map Your Scenes to Launchpad Pads

**For each bank (0-7)**:

1. Click **States** panel in Chataigne
2. Select state (e.g., `BANK0`)
3. Add **Action** in Processors panel:
   - Right-click Processors → Add → Action
4. Set **Condition**:
   - Add Condition → From Input Value
   - Input Value: `/modules/launchpadMiniMk3/values/mainButtons/button11` (for pad 1,1)
   - Comparator: `==` `true`
5. Set **Consequence**:
   - Add Consequence
   - Module: `OSC`
   - Command Type: `Custom Message`
   - Address: `/scenes/[your_scene_name]` (e.g., `/scenes/canvas`)
6. **Repeat** for all 64 pads in the bank

**Launchpad Grid Coordinates**:

```
button11  button12  button13  button14  button15  button16  button17  button18
button21  button22  button23  button24  button25  button26  button27  button28
button31  button32  button33  button34  button35  button36  button37  button38
button41  button42  button43  button44  button45  button46  button47  button48
button51  button52  button53  button54  button55  button56  button57  button58
button61  button62  button63  button64  button65  button66  button67  button68
button71  button72  button73  button74  button75  button76  button77  button78
button81  button82  button83  button84  button85  button86  button87  button88
```

### Organize Scenes by Bank

Recommended bank structure (400 shaders):

| Bank | Category | Example Scenes |
|------|----------|----------------|
| 0 | Low Energy / Ambient | Nebula, SlowDrift, AmbientWaves, StarField |
| 1 | Med Energy / Geometric | TunnelZoom, GridPulse, MandalaMorph, HexagonShift |
| 2 | High Energy / Chaotic | StrobeRings, FractalExplosion, RGBGlitch, LaserBeams |
| 3 | Specialty / Effects | Kaleidoscope, MirrorSymmetry, ChromaticAberration, Pixelate |
| 4 | Masks / Displacement | RadialVignette, Stripes, NoiseMask, CirclePulse |
| 5 | Favorites | (Your top 64 scenes for quick access) |
| 6 | User Presets | (Custom scene combinations) |
| 7 | Emergency | Blackout, SolidBlack, SolidWhite, SafeAmbient |

---

## 15-Minute Magic Music Visuals Integration

### Setup Magic to Receive Synesthesia

1. **Launch Magic Music Visuals**
2. **Add Syphon Input**:
   - Add Module: Media → SyphonClient
   - Select Server: "Synesthesia Main Output"
   - Verify video appears
3. **Add OSC Input**:
   - Settings → OSC Input
   - Port: `9999` (to receive Synesthesia audio OSC, forwarded by Chataigne)
4. **Map Audio to Parameters**:
   - Right-click any parameter (e.g., Opacity)
   - Learn MIDI/OSC
   - Play music, watch `/audio/level/bass` arrive
   - Click to assign

### Add Multiple Synesthesia Scenes

**Technique 1: Multiple SyphonClients** (one per scene)

```
Scene: GEN_BUS_A
  ├─ SyphonClient_1 (Synesthesia scene 1)
  ├─ SyphonClient_2 (Synesthesia scene 2)
  ├─ SyphonClient_3 (Synesthesia scene 3)
  ├─ Mix_A0 (input: SyphonClient_1, opacity: Slot0Weight)
  ├─ Mix_A1 (input: SyphonClient_2, opacity: Slot1Weight)
  ├─ Mix_A2 (input: SyphonClient_3, opacity: Slot2Weight)
  └─ Combiner → GEN_A_OUT
```

**Issue**: Synesthesia has ONE Syphon output (current active scene).

**Solution**: Use **Chataigne to control scene switching**, Magic receives via Syphon.

**Technique 2: Single SyphonClient** (recommended)

```
Scene: MAIN
  ├─ SyphonClient (Synesthesia - always active scene)
  ├─ Effects/Masks applied
  └─ Output
```

Change scenes via **Launchpad** → Synesthesia scene changes → Magic receives new scene automatically.

### Add Shader Masks

1. Create **Mask Bank** in Synesthesia (Bank 4):
   - Organize grayscale mask shaders (vignette, stripes, noise)
2. In Magic:
   - Add Multiply module
   - Input A: Main generator (color shader)
   - Input B: Mask shader (via Syphon when you switch to Bank 4)
3. Use Launchpad to switch between color shaders (Banks 0-3) and masks (Bank 4)

---

## Troubleshooting

### Launchpad Not Detected

**Symptoms**: Chataigne Launchpad module shows "No device"

**Solutions**:
1. Check USB connection
2. Verify Launchpad in Programmer Mode (orange light on top-right)
3. Restart Chataigne
4. Check macOS Privacy settings: System Settings → Privacy & Security → Input Monitoring → Allow Chataigne

### OSC Values Not Updating

**Symptoms**: Chataigne OSC module shows no incoming messages

**Solutions**:
1. Verify Synesthesia OSC output enabled (Settings → OSC)
2. Verify port `9999` (must match Chataigne OSC input port)
3. Play music (Synesthesia only sends OSC when audio is active)
4. Check Chataigne: Modules → OSC → Enable "Log Incoming"
5. Test with another OSC app (e.g., TouchOSC, osculator)

### Scene Not Changing in Synesthesia

**Symptoms**: Launchpad press, but Synesthesia stays on current scene

**Solutions**:
1. Check Chataigne State Machine:
   - Verify active state (highlighted)
   - Check Action condition (should be green when pad pressed)
   - Enable OSC module "Log Outgoing"
2. Check OSC address format:
   - Must be `/scenes/[scene_name]` (lowercase, no spaces)
   - Example: `/scenes/canvas` ✅ `/scenes/Canvas` ❌
3. Verify scene exists in Synesthesia library
4. Check Synesthesia OSC input enabled (Settings → OSC → Input Port `7777`)

### Syphon Not Working in Magic

**Symptoms**: Magic SyphonClient shows "No server found"

**Solutions**:
1. Verify Synesthesia Syphon output enabled (Settings → Video)
2. Refresh server list in Magic SyphonClient (click refresh icon)
3. Test with Syphon Recorder (free tool) to verify server exists
4. Restart both apps (Synesthesia first, then Magic)

---

## Next Steps

### Expand to 400 Shaders

1. **Organize Synesthesia library** into 8 categories (50 scenes each)
2. **Map all 8 banks** in Chataigne (64 pads × 8 banks = 512 slots)
3. **Create naming convention** for scenes (e.g., `01_AMBIENT_Nebula`)
4. **Test each pad** in live environment

### Add Advanced Controls

1. **Connect Akai MIDImix**
   - Follow [MMV Master Pipeline Guide](../operation/mmv-master-pipeline-guide.md)
   - Map faders to Magic globals (intensity, buildup, FX)
2. **Add custom actions** to Launchpad side buttons
   - Bank 7 side buttons: Blackout, strobe, safe scene
3. **Create macro actions** in Chataigne
   - One pad press → multiple OSC messages (e.g., scene + FX + color)

### Integrate SwiftVJApp (Optional)

For **lyrics + AI analysis**, keep SwiftVJApp running in background:

1. Launch SwiftVJApp
2. Configure headless mode (disable UI + Launchpad modules)
3. Enable OSC forwarding to Magic (port 11111)
4. Add SyphonClient in Magic for lyrics overlay

See [Chataigne SwiftVJApp Replacement Guide](chataigne-swiftvjapp-replacement-guide.md) for details.

---

## Sample Chataigne File Included

**File**: `lpsyn.noisette`

**What's configured**:
- OSC module (port 9999 input, 7777 output)
- Launchpad Mini MK3 module
- State machine with BANK0 and BANK1 examples
- OSC Router forwarding Synesthesia audio values
- Sample scene triggers

**To use**:
1. File → Open → `lpsyn.noisette`
2. Verify hardware detected
3. Customize scene mappings for your library

---

## Reference Links

- [Chataigne Official Site](https://benjamin.kuperberg.fr/chataigne/)
- [Chataigne Documentation](https://benjamin.kuperberg.fr/chataigne/docs/)
- [Synesthesia Official Site](https://synesthesia.live/)
- [Magic Music Visuals](https://magicmusicvisuals.com/)
- [Full Setup Guide](chataigne-swiftvjapp-replacement-guide.md)
- [MMV Master Pipeline](../operation/mmv-master-pipeline-guide.md)

---

**Estimated Time**: 5 min setup + 10 min customization + 15 min Magic integration = **30 minutes total**

Ready to VJ with 400 shaders at your fingertips! 🎨✨
