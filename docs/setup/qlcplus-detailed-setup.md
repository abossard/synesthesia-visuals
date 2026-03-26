# QLC+ Detailed Setup And Verification Guide

This guide goes deeper than the main live-rig guide and focuses only on **QLC+ 5.2.1** in the MacBook Neo stack.

The target role for QLC+ is:

- receive beat and transport-style signals from VirtualDJ over OS2L
- control DMX fixtures through the Enttec USB Pro
- drive Magic over OSC
- call LedFx and WLED over Script functions
- expose the whole show on the Launchpad with reliable RGB feedback

If you keep this mental model clear, the QLC+ project stays manageable.

---

## The QLC+ Mental Model

Think in layers:

1. **Universes**
   - transport layers for input/output domains
2. **Fixtures**
   - physical devices patched to a DMX universe
3. **Functions**
   - scenes, chasers, collections, scripts, EFX
4. **Virtual Console**
   - the operator surface
5. **External controllers**
   - Launchpad and OS2L feeding the Virtual Console

Official references:

- [QLC+ Input/Output](https://docs.qlcplus.org/v5/input-output)
- [QLC+ Input Profiles](https://docs.qlcplus.org/v5/input-output/input-profiles)
- [QLC+ Scene Editor](https://docs.qlcplus.org/v5/function-manager/scene-editor)
- [QLC+ Chaser Editor](https://docs.qlcplus.org/v5/function-manager/chaser-editor)
- [QLC+ Collection Editor](https://docs.qlcplus.org/v5/function-manager/collection-editor)
- [QLC+ Button widget](https://docs.qlcplus.org/v5/virtual-console/button)
- [QLC+ Slider widget](https://docs.qlcplus.org/v5/virtual-console/slider)
- [QLC+ Script Editor](https://docs.qlcplus.org/v5/function-manager/script-editor)
- [QLC+ OSC plugin](https://docs.qlcplus.org/v5/plugins/osc)
- [QLC+ OS2L plugin](https://docs.qlcplus.org/v5/plugins/os2l)

Verification basis for this guide:

- QLC+ 5.2.1 desktop behavior
- current QLC+ v5 documentation paths
- direct verification of the behaviors those docs currently describe

---

## Recommended Universe Layout

QLC+ stores its I/O mapping in the project. The official docs note that each universe can map a single input, a single output, and a single feedback line, which is exactly why a clean layout matters.

Use this layout:

| Universe | Job | Why |
| --- | --- | --- |
| 1 | DMX output to Enttec USB Pro | all physical fixtures live here |
| 2 | OS2L input from VirtualDJ | keeps beat data isolated from lighting values |
| 3 | Launchpad input + feedback | controller traffic and RGB feedback stay together |
| 4 | OSC output to Magic | dedicated control bus, no fixture confusion |

QLC+ ships with 4 universes by default, which is enough for this rig.

---

## Phase 1: Build The Project Skeleton

Start from either:

- [q2.qxw](../../q2.qxw)
- [GARAGE.qxw](../../GARAGE.qxw)

Or build from a new workspace.

### 1.1 Save Early

1. Open QLC+.
2. Save the workspace immediately with a real name such as `neo_show.qxw`.
3. Save again after each completed phase.

Reason:

- the I/O map is stored in the project
- the fixture patch is stored in the project
- the Virtual Console is stored in the project

### 1.2 Name The Universes

In the Input/Output Manager, rename the universes so the left rail is readable:

- `U1 DMX`
- `U2 OS2L`
- `U3 Launchpad`
- `U4 Magic OSC`

This sounds trivial, but it prevents mistakes later when debugging Auto Detect and OSC.

### Verification

Pass if:

- the workspace saves successfully
- the four universes are present and clearly named
- reopening the file restores the universe names

Fail if:

- universe names disappear after reopen
- another workspace opens instead of the one you edited

---

## Phase 2: Patch Inputs And Outputs

The official Input/Output docs say the Inputs/Outputs tab shows:

- universes on the left
- devices and their input/output/feedback lines on the right
- checkboxes for mapping lines

That is the exact place where most show-killing mistakes happen.

### 2.1 Universe 1 -> Enttec USB Pro

1. Select `U1 DMX`.
2. Find the Enttec USB Pro under DMX USB devices.
3. Enable its **output** checkbox.
4. If multiple USB DMX devices are connected, confirm you picked the correct one.

### 2.2 Universe 2 -> OS2L

1. Select `U2 OS2L`.
2. Enable the **OS2L** input line.
3. Open its configuration and set the port to match VirtualDJ.
4. Use `127.0.0.1:9996` as the starting point on the same Mac.

The official OS2L docs explicitly say:

- set `os2lDirectIp` in VirtualDJ to the QLC+ IP:port
- restart VirtualDJ
- QLC+ will show activity with the joystick icon next to the universe

### 2.3 Universe 3 -> Launchpad Input And Feedback

1. Select `U3 Launchpad`.
2. Enable the Launchpad **input** line.
3. Enable the Launchpad **feedback** line.
4. Use the Launchpad's **MIDI** ports, not the DAW ports.

Important detail from the input-profile side:

- feedback values can have separate lower and upper values
- widgets can override the profile's default feedback values when needed

That is what lets you make pad colors and pad states match your QLC+ widget logic instead of sending one generic LED value everywhere.

### 2.4 Universe 4 -> OSC Output For Magic

1. Select `U4 Magic OSC`.
2. Enable the OSC **output** line.
3. Set host to `127.0.0.1`.
4. Either:
   - keep the plugin default for Universe 4, which is port `9003`, or
   - set a custom port like `11111` and match it in Magic

The official OSC docs note that OSC output defaults to `9000 + universe index`, so Universe 4 defaults to `9003`.

### Verification

Pass if:

- Enttec output is enabled on U1
- OS2L input is enabled on U2
- Launchpad input and feedback are enabled on U3
- OSC output is enabled on U4

Deep verification:

1. Close and reopen the workspace.
2. Confirm all mappings persist.

Fail if:

- mappings vanish after reopen
- Launchpad shows up on the wrong universe
- OS2L and Launchpad share a universe accidentally

---

## Phase 3: Patch Fixtures Cleanly

Do not build functions until the fixture patch is correct.

### 3.1 Patch Real Devices

Patch at least these fixtures on Universe 1:

1. `Varytec Hero Spot Wash 140 2in1 RGBW+W`
2. `Stairville Hz-200 DMX`
3. `Cameo Thunder Wash 600 UV`

Your repo already shows these starting points:

- [GARAGE.qxw](../../GARAGE.qxw)
- [q1_test.qxw](../../q1_test.qxw)

`q1_test.qxw` suggests:

- Hero Spot at address 1
- Hz-200 immediately after it

Patch the Cameo at the next free address based on the mode you actually use.

### 3.2 Keep Addressing Explicit

Write down:

- fixture name
- universe
- DMX start address
- selected mode
- physical location

This belongs both in the workspace and in a one-page physical patch sheet.

### 3.3 Make A Test Scene Immediately

Create a single scene per fixture:

- `TEST Hero Open White`
- `TEST Hazer Mid`
- `TEST UV Full`

The QLC+ scene editor lets you add only the fixtures and channels you need. That is the right way to avoid accidentally stomping unrelated channels.

### Verification

Pass if:

- each fixture can be isolated in a dedicated scene
- the Hero moves and lights correctly
- the hazer responds only when its scene is run
- the UV fixture responds only when its scene is run

Deep verification:

1. Start the scene.
2. Open the DMX Monitor.
3. Confirm only the expected channels move.

Fail if:

- running a haze scene changes the moving head
- a color scene also changes pan/tilt
- the wrong fixture responds

---

## Phase 4: Build Functions The Right Way

QLC+ is easiest to maintain if you separate functions by intent.

### 4.1 Scene Categories

Create scene folders or naming prefixes like:

- `POS_` for position scenes
- `CLR_` for color scenes
- `DIM_` for intensity scenes
- `FX_` for special single-state effects
- `LED_` for LedFx and WLED script wrappers
- `MAG_` for Magic OSC-bus scenes
- `TEST_` for diagnostics

### 4.2 Scenes For Static States

Use scenes when the output is a fixed state:

- spot home
- UV full
- hazer off
- white wash
- Magic blackout on
- Magic intensity 50

The scene editor is ideal here because you choose the exact fixtures and channels that take part.

### 4.3 Chasers For Time-Based Looks

Use chasers for:

- strobe bursts
- sweeps
- rise macros
- multi-step movement

The official chaser editor docs call out the per-step fields clearly:

- fade in
- hold
- fade out
- total duration
- notes

Use those notes. They matter when a show file gets big.

### 4.4 Collections For Compound Looks

Collections are where the show becomes usable.

The official collection docs make two important points:

1. collections are shortcuts that combine functions
2. function order matters when the same channels are involved

That second rule is the one that usually explains "why did this look come back wrong?" when a collection mixes dimmer, color, and position layers.

Use Collections for:

- `LOOK Main Wash`
- `LOOK UV Build`
- `PANIC Full Blackout`
- `DROP Strobe Hit`

Example:

`LOOK Main Wash` might contain:

1. `DIM_All 80`
2. `CLR_White`
3. `POS_Front`
4. `MAG_Intensity_60`
5. `LED_Wash`

### Verification

Pass if:

- a Scene does one thing only
- a Chaser runs correctly from inside the editor
- a Collection starts all intended layers together

Deep verification:

1. Run a Collection.
2. Stop and restart it several times.
3. Confirm the same state comes back every time.

Fail if:

- collections produce different states on repeated runs
- relative EFX override base position unexpectedly
- scenes touch channels they should not own

---

## Phase 5: Use Scripts For LedFx And WLED

The official Script Editor docs matter here:

- scripts execute line by line in sequence
- `systemcommand:` runs an executable program or script at an absolute path
- the target must be executable
- arguments are passed as `arg:...`

### 5.1 Keep QLC+ Scripts Thin

Do not bury business logic in QLC+ script text if you can avoid it.

Better:

- QLC+ script launches shell wrapper
- wrapper handles `curl`
- wrapper can be tested outside QLC+

### 5.2 Example Pattern

QLC+ script:

```text
systemcommand:/absolute/path/to/ledfx-scene.sh arg:drop-strobe
```

Or if you need to chain multiple local QLC functions first:

```text
startfunction:42 // MAG_Strobe_Fast
systemcommand:/absolute/path/to/ledfx-scene.sh arg:drop-strobe
```

### 5.3 When To Use `blackout:on`

QLC+ scripts support:

```text
blackout:on
blackout:off
```

Use that only if you want **QLC+ blackout mode** specifically.

Do not confuse it with whole-rig blackout.

Whole-rig blackout should usually be a Collection:

- DMX zero scene
- Magic blackout scene
- LedFx blackout script
- optional WLED off script

### Verification

Pass if:

- the wrapper works from Terminal
- the same wrapper works from QLC+ Script Editor test run
- the Launchpad can trigger the script through a button

Fail if:

- the script works from Terminal but not from QLC+
- the path is relative instead of absolute
- the script is not executable

---

## Phase 6: Build The Virtual Console Around The Launchpad

The Virtual Console is your live desk. Do not dump raw functions on it.

### 6.1 Build By Operator Meaning, Not By Function Type

Good page layout:

- top row: panic and kills
- center: looks
- lower center: intensity and build tools
- bottom: utility

Bad page layout:

- all scenes first
- all chasers second
- all scripts third

The operator thinks in results, not editor types.

### 6.2 Buttons

The official Button widget docs are the core of Launchpad mapping:

- Auto Detect can bind the next external control
- buttons can Toggle Function, Flash Function, Toggle Blackout, or Stop All Functions
- a button in monitoring state does **not** send controller feedback

That last point is critical.

Design consequence:

- one live action should ideally have one owning button

### 6.3 Sliders

The official Slider widget docs say sliders are for:

- fixture channel levels
- function playback/intensity
- submaster use

Use sliders inside QLC+ for:

- global dimmer submaster
- hazer amount
- Magic macro intensity bus

For this rig, treat "submaster" literally:

- one slider for all-light dimming
- one slider for haze ceiling
- one slider for a global Magic intensity bus if you want manual override above scene logic

If an external controller does not have motorized feedback, enable the slider option:

- `Catch up with the external controller input value`

That avoids nasty jumps when switching pages or re-grabbing a value.

### 6.4 Launchpad Mapping Workflow

For each important widget:

1. create the widget
2. assign the function
3. configure external input
4. Auto Detect with the Launchpad
5. test feedback immediately

Do not map a whole page first and test later. That is how you lose an hour.

### Verification

Pass if:

- Auto Detect immediately sees the pad you press
- the button changes state in QLC+
- the Launchpad LED reflects Off vs On correctly

Fail if:

- Auto Detect never sees input
- the button works with mouse but not pad
- the pad works but feedback color never changes

---

## Phase 7: OS2L Deep Verification

OS2L is easy to misdiagnose because users often blame QLC+ when VirtualDJ is the real problem.

### 7.1 What Good Looks Like

The official OS2L plugin docs say QLC+ will start receiving signals and the joystick icon beside the universe will blink.

That is your first check.

The same docs also describe the core incoming event types:

- `beat`
- `cmd`
- `btn`

For beat verification specifically, the documented test is that beat events appear on channel `8342` with value `255`.

### 7.2 Verification Procedure

1. Start QLC+.
2. Start VirtualDJ.
3. Play a track with a clear beat.
4. Confirm the joystick icon on `U2 OS2L` blinks.
5. Open the DMX Monitor and watch Universe 2 values.
6. Confirm some channels change when beat or button events occur.
7. If you want the hard proof check, confirm beat hits drive channel `8342` to `255`.

### 7.3 Practical Use

Use OS2L as:

- beat input for timing logic
- optional button or deck-state trigger source

Do not let OS2L own the whole show state.

Treat it as one trigger input among several.

### Fail Cases

- no joystick activity: VirtualDJ is not sending or port mismatch exists
- joystick activity but no useful mapping: input profile or widget binding is missing
- intermittent activity: another app is fighting for the port or VirtualDJ was not restarted

---

## Phase 8: OSC To Magic Deep Verification

This is the most important non-DMX verification path.

### 8.1 Build A Tiny OSC Bus First

On Universe 4, create only three test scenes:

- `MAG_Test_Intensity_25`
- `MAG_Test_Intensity_75`
- `MAG_Test_Blackout_On`

These should set only the OSC-bus channels, not DMX fixtures.

### 8.2 Verify In Magic

In Magic:

1. create an OSC source on the matching port
2. use MIDI/OSC Learn on one parameter
3. trigger the QLC+ test scene
4. confirm Magic learns the address and reacts

If QLC+ is using Universe 4 with default OSC porting, the learned addresses should look like `/3/dmx/...`.

That leading `3` is consistent with the plugin's universe indexing, while the port default for Universe 4 is `9003`.

### 8.3 Keep OSC Meanings Stable

Once Magic learns:

- channel 1 = macro intensity
- channel 2 = blackout
- channel 3 = strobe

do not casually reassign those channels later.

Treat Universe 4 as an API.

### Verification

Pass if:

- Magic learns the OSC path from QLC+
- triggering the scene always drives the same Magic parameter

Fail if:

- Magic never sees the OSC traffic
- the OSC path changes because you moved the scene to another universe design

---

## Receiving OSC from Magic Music Visuals

Magic can send audio-envelope values back to QLC+ using **OSCSender** modules, letting lighting react to the same audio analysis that drives visuals.

### How It Works

- Each OSCSender module in Magic sends a float value (`0.0`–`1.0`) to a target OSC address.
- QLC+ scales the incoming float to DMX range `0`–`255` automatically.
- Magic sends **descriptive OSC paths** like `/audio/low/peak`, `/audio/high/avg`, etc.
- QLC+ accepts **any arbitrary OSC path** as input — it internally hashes each path to a 16-bit channel number.
- The `/universe/dmx/channel` format is **only** used for QLC+ OSC *output* (sending DMX values out), not for input.

### Enable OSC Input in QLC+

1. Open the **Inputs/Outputs** tab.
2. Select the universe you want to receive OSC on (e.g., Universe 1).
3. Find the OSC plugin row and check the **Input** checkbox.
4. Configure the input port to **7700** (or whichever port Magic's OSCSender targets).

### Map Incoming OSC Paths to Channels

QLC+ needs to know which OSC paths to listen for. Use one of these methods:

1. **Input Profile Wizard (recommended):** Create an Input Profile (type: OSC) → click the Wizard button → play music in Magic → QLC+ auto-detects the 6 incoming OSC paths and assigns each to an internal channel.
2. **Channel Calculator:** In the OSC plugin configuration, use the Channel Calculator to manually compute the internal channel number for a given OSC path (e.g., `/audio/low/peak`).

Once mapped, you can use the detected input channels in QLC+ functions, Virtual Console widgets (sliders, buttons), or input profiles to control lighting from audio.

### Further Reading

- End-to-end quickstart: [Magic → QLC+ Quickstart](quickstart-magic-to-qlcplus.md)
- QLC+ OSC plugin reference: <https://docs.qlcplus.org/v4/plugins/osc>

---

## Golden Verification Routine

Run this before every real session.

1. `TEST Hero Open White` lights only the Hero.
2. `TEST Hazer Mid` affects only haze.
3. `TEST UV Full` affects only the UV fixture.
4. Launchpad pad mapping works on one button with feedback.
5. `U2 OS2L` joystick blinks when VirtualDJ plays.
6. `MAG_Test_Intensity_75` changes one learned Magic parameter.
7. `LED_Wash` script triggers LedFx.
8. `PANIC Full Blackout` kills DMX, Magic, and LED outputs together.

If any one of those fails, do not keep building upward. Fix the broken layer first.

---

## Failure Isolation

### DMX broken, OS2L working

Look at:

- Enttec output mapping
- fixture addresses
- scene channel ownership

### Launchpad input broken, mouse still works

Look at:

- universe assignment
- MIDI vs DAW port selection
- input profile selection

### Launchpad feedback broken, input still works

Look at:

- feedback line not enabled
- wrong profile
- button in monitoring state instead of owning state

### Magic not reacting, DMX is fine

Look at:

- Universe 4 OSC output host/port
- Magic OSC source port
- whether you are actually sending OSC-bus scenes

### LedFx not reacting, Magic is fine

Look at:

- script path
- execute permissions
- wrapper correctness
- LedFx REST endpoint availability

---

## Practical Advice

Keep the QLC+ project boring.

The best live QLC+ file is:

- boring to read
- obvious to debug
- predictable to operate

That means:

- separate universes by job
- separate scenes by ownership
- use collections for operator-facing looks
- use scripts only for discrete external actions
- verify every layer in isolation
