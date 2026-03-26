# Magic Music Visuals Detailed Setup And Verification Guide

This guide goes deep on **Magic Music Visuals Performer** in the MacBook Neo stack.

The target role for Magic is:

- take audio-reactive input from BlackHole
- take direct manual control from MIDImix
- take show-state control from QLC+ over OSC
- drive the projector through fullscreen or Syphon

If QLC+ is the lighting brain, Magic is the projector engine.

Official reference:

- [Magic User's Guide](https://magicmusicvisuals.com/downloads/Magic_UsersGuide.html)

Verification basis for this guide:

- current Magic User's Guide behavior for Input Sources, audio analysis, MIDI/OSC Learn, Playlist, Preview Mode, and performance settings
- practical Performer-oriented setup assumptions for a single-operator live rig

---

## The Magic Mental Model

Keep four domains separate:

1. **Audio input**
   - how reactive the visuals feel
2. **MIDImix**
   - live taste and manual shaping
3. **OSC from QLC+**
   - blackout, scene changes, macro states
4. **Playlist and output**
   - what the audience actually sees

If those roles blur together, Magic becomes hard to perform with.

---

## Phase 1: Build A Clean Project Shell

Start with a simple project that already proves the full path:

- one scene for base visuals
- one scene for a drop or strobe visual
- one blackout or low-energy scene
- one playlist containing those scenes

Do not start by building twenty scenes.

### 1.1 Window Layout

Magic's user guide lists the windows that matter here:

- Input Sources Window
- Editor Window
- Magic Window
- Preview Window
- Playlist Window

Open them all once and place them deliberately.

Suggested layout:

- Editor in the center
- Input Sources floating to one side
- Playlist visible
- Preview visible only while building
- Magic Window on the projector or second screen

### 1.2 Output Safety

The Magic module is the only path that displays a scene in the Magic Window.

Every scene you care about must flow left-to-right into the Magic module.

### Verification

Pass if:

- you can switch scenes and see them in the Magic Window
- every active scene reaches the Magic module
- the project opens with windows where you expect them

Fail if:

- a scene seems built but nothing renders
- Preview shows something but the Magic Window does not

---

## Phase 2: Input Sources Window

The Input Sources Window is where almost every setup issue starts or gets fixed.

The official guide says this window controls:

- audio device selection
- audio, MIDI, and OSC sources
- source routing
- source labels
- gain
- buffer size

### 2.1 Select The Audio Device

Magic's guide says:

- open `Window -> Input Sources Window`
- choose `Show Audio Config`
- select the desired device from the box at the top

For this rig:

- choose **BlackHole 2ch**

### 2.2 Label Sources Immediately

Magic creates default audio sources such as `Source 0` and `Source 1`.

The guide explicitly recommends relabeling, because modules refer to labels, not device names.

Rename them to something readable:

- `Music L`
- `Music R`
- `QLC OSC`
- `MIDImix Ch1`

If you later add more sources, keep the names operational, not generic.

### 2.3 Remove Unused Sources

The guide notes that every source consumes processor resources and unused ones should be removed.

After you know your actual setup, remove junk sources.

### Verification

Pass if:

- BlackHole is the selected input device
- audio source labels are readable
- modules show your custom labels

Fail if:

- sources still say `Source 0` and `Source 1` weeks later
- you are not sure which source is QLC+ OSC vs audio

---

## Phase 3: Audio Input, Gain, And Buffer Size

This is where responsiveness lives.

### 3.1 Audio Gain

The Magic guide allows up to 24 dB of gain per audio source.

Use that deliberately:

- if VirtualDJ master is too weak, raise gain
- if the scene explodes constantly, lower gain

Do not compensate for a bad input level by making every modifier extreme.

### 3.2 Buffer Size

The guide says:

- smaller buffer = better responsiveness
- smaller buffer = higher CPU cost
- beginners can leave the default

For live use:

- start on the default
- lower only if the response feels meaningfully late
- stop lowering if CPU or audio stability gets worse

### 3.3 First Audio-Reactive Test

Build one tiny scene:

1. add a simple geometry or shader source
2. insert a `Scale` or similar transform
3. link one parameter to audio
4. play a track

The Magic quick-start section uses exactly this style of link-and-react workflow.

### Verification

Pass if:

- silence produces near-zero motion
- music moves the linked parameter immediately
- the response changes when you alter input gain

Fail if:

- no movement at all
- movement even in silence
- movement feels a full beat late

---

## Phase 4: Use The Right Audio Features

The Magic guide says audio features are normalized to `0..1`, which is ideal for controlled mapping.

The most useful features for this rig are:

| Feature | Use |
| --- | --- |
| `Volume` | overall energy |
| `Freq. Range` | bass, mids, highs |
| `Tone` | brightness or sparkle logic |
| `Best Pitch` | special melodic effects, not general club control |

The guide also says `Freq. Range` includes five preset two-octave bands:

- `20-80 Hz`
- `80-320 Hz`
- `320-1.2k Hz`
- `1.2k-5k Hz`
- `5k-20k Hz`

### Practical Mapping

Use:

- low band for scale, zoom, pulse
- mid band for rotation, geometry complexity, secondary motion
- high band for glow, color accents, sparkle, strobe overlays

Do not drive every parameter from the same full-range volume signal.

### Verification

Pass if:

- kick-heavy tracks move bass-linked parameters most
- hi-hats mostly affect high-band parameters
- changing tracks produces different feature behavior

Fail if:

- every parameter reacts identically
- high hats shake the whole scene like kicks

---

## Phase 5: Use Modifiers To Make Audio Feel Musical

Raw input almost always feels too twitchy.

The Magic guide's modifier table is the key tool here. The most useful live modifiers are:

- `Smooth`
- `Threshold`
- `Trigger (Random)`
- `Expression`

The guide describes `Smooth` as reducing jerkiness at the cost of responsiveness. That is exactly the tradeoff to manage.

### 5.1 Good Defaults

Start with:

- low-band movement: moderate smoothing
- high-band sparkle: low smoothing
- strobe triggers: threshold or trigger-based, not raw volume

### 5.2 A Good Live Formula

For many parameters:

```text
final value = manual base * (0.35 + 0.65 * audio feature)
```

This keeps a scene alive between peaks.

### 5.3 When To Use `Trigger (Random)`

Use it for:

- random hit selection
- changing a seed or mode on kicks
- not for continuous opacity or scale

### Verification

Pass if:

- motion feels intentional, not jittery
- strobe-like changes happen on hits, not on every tiny fluctuation

Fail if:

- the scene is technically reactive but ugly
- lowering gain is the only thing that calms it down

---

## Dual Envelope Audio Analysis with Globals

Magic's Custom Freq. Range feature lets you isolate specific frequency bands and expose their energy as **output Globals**, which other modules (including OSCSender) can read.

Create 6 output Globals using two frequency bands — a low band and a high band — each with three modifiers:

| Global | Source | Modifier | Purpose |
| --- | --- | --- | --- |
| `LowPeak` | Custom Freq. Range (low band) | Peak | instant transient detection (kicks) |
| `LowSmooth` | Custom Freq. Range (low band) | Smooth | slow-moving bass energy |
| `LowRaw` | Custom Freq. Range (low band) | *(none)* | unprocessed low-band level |
| `HighPeak` | Custom Freq. Range (high band) | Peak | instant transient detection (hats, snares) |
| `HighSmooth` | Custom Freq. Range (high band) | Smooth | slow-moving high energy |
| `HighRaw` | Custom Freq. Range (high band) | *(none)* | unprocessed high-band level |

### EDM Defaults

- **LowFreq cutoff**: ~200 Hz (captures kick and sub-bass)
- **HighFreq cutoff**: ~6000 Hz (captures hats, cymbals, vocal sibilance)

Use the ISF spectrum analyzer shader [`magic/DualEnvelopeSpectrum.fs`](../../magic/DualEnvelopeSpectrum.fs) to visualize frequency content and find the right cutoff values for your material.

### Further Reading

- Full design rationale and wiring details: [Dual Envelope Audio Analysis](../reference/magic-dual-envelope-audio-analysis.md)
- End-to-end quickstart for sending these values to QLC+: [Magic → QLC+ Quickstart](quickstart-magic-to-qlcplus.md)

---

## Phase 6: MIDImix -> Magic

The Magic guide says MIDI sources can be selected in the Input Sources Window, rescanned, and assigned to channels, with Channel 1 as the default.

### 6.1 Add The MIDImix Source

1. Open Input Sources Window.
2. Add a MIDI source.
3. Select `MIDI Mix`.
4. Use Channel `1` unless you intentionally changed the controller preset.

If the MIDImix is not visible:

- use `Re-Scan MIDI Devices`

### 6.2 What MIDImix Should Control

Keep MIDImix on continuous values:

- master intensity
- per-layer opacity
- overdrive
- hue shift
- blur
- bypass toggles

Do not spend MIDImix on things QLC+ should own, like whole-show blackout logic.

### 6.3 MIDI Learn

The guide says MIDI/OSC Learn can auto-detect commands instead of manual entry.

Use that. It is faster and less error-prone than filling command data manually.

### Verification

Pass if:

- one fader cleanly controls one parameter
- letting go of a fader leaves the value stable
- re-scan restores the device if it was connected late

Fail if:

- multiple parameters move unexpectedly
- Magic is learning the wrong source because you left extra MIDI devices active

---

## Phase 7: QLC+ OSC -> Magic

This is the main integration point between lighting and visuals.

### 7.1 Add The OSC Source

The Magic guide says:

- select OSC from the source drop-down
- set the port to match the sending controller
- default port is `8000`

For this rig:

- set the OSC source port to match QLC+, for example `11111`

### 7.2 Use Learn, Not Manual Typing

The guide is explicit:

- OSC commands are open-ended
- they are not meant to be entered manually
- use MIDI/OSC Learn

That should be your default workflow.

### 7.3 Stable QLC+ Control Bus

If QLC+ uses Universe 4 as the OSC control bus, Magic will learn addresses like:

- `/3/dmx/0`
- `/3/dmx/1`
- `/3/dmx/2`

Treat those as stable slots:

- 1 = macro intensity
- 2 = blackout
- 3 = strobe
- 4 = hue shift
- 5 = build
- 6 = drop or scene select

### 7.4 Two Good Ways To Use OSC In Magic

#### A. Direct parameter control

Use QLC+ OSC directly on:

- final scene intensity
- strobe amount
- hue shift
- build amount

#### B. Playlist control

The Playlist Window can be controlled by MIDI or OSC. The guide documents:

- Prev/Next learnable controls
- global command mode for selecting entries by value
- per-entry learned commands

Important detail: playlist entry numbering in these controls starts at `0`, not `1`.

This is ideal if you want QLC+ to select Magic scenes explicitly.

### Verification

Pass if:

- Magic learns a QLC+ OSC path instantly
- the same QLC+ scene always changes the same Magic control
- Playlist prev/next or entry select works from QLC+

Fail if:

- OSC source exists but Learn never sees traffic
- the wrong port is configured
- you are changing QLC+ OSC channel meanings mid-build

---

## Phase 8: Build A Safe Playlist Workflow

Magic's guide is excellent here and this matters a lot in live use.

### 8.1 Use The Playlist Window For Live Output

The guide says the Playlist Window:

- lets you define ordered scene entries
- supports transitions
- supports MIDI/OSC control

That should be the live control surface inside Magic.

### 8.2 Keep Scene Editing Separate

The guide also says:

- changing playlist entry does not have to change the current scene tab
- this reduces processor load and prevents dropped frames

That is good live behavior.

### 8.3 Preview Mode

The guide strongly recommends Preview Mode for live editing:

- scene selection is redirected to the Preview Window
- the Magic Window stays undisturbed
- only the Playlist changes live output

The guide also documents an important editing shortcut: `Cmd`-click on macOS, or `Ctrl`-click on Windows, can switch the current scene tab without sending that scene to the Magic Window.

Use it.

### 8.4 Transitions

The guide documents three transition styles:

- `None`
- `Crossfade`
- `Additive Dissolve`

Keep transitions short and intentional.

The guide warns that transitions render two scenes at once and can drop frame rate on slower systems.

### Verification

Pass if:

- you can edit a scene in Preview without disturbing the projector
- playlist Next changes audience output
- scene tab clicking does not surprise the audience when Preview Mode is on

Fail if:

- editing a scene unexpectedly changes live output
- transitions tank frame rate

---

## Phase 9: Performance Tuning

This is where Magic goes from "working" to "show-safe."

### 9.1 Graphics Resolution

Set the Magic Window graphics resolution for the projector you actually use.

Do not edit at one aspect ratio and perform at another without checking the result.

### 9.2 Graphics Memory

The guide explains:

- scenes are stored in VRAM
- loading all scenes reduces scene-switch delay but uses more memory
- individual scenes can be kept in graphics memory
- free graphics memory can be displayed

Practical recommendation:

- keep the core live scenes in graphics memory
- do not enable `Load All Scenes Into Graphics Memory` unless your machine handles it comfortably

### 9.3 Preview Window Cost

The guide warns the Preview Window can cut frame rate significantly, even by around 50 percent on some systems.

So:

- keep Preview open while building
- close or minimize it during the actual set if performance is tight

### 9.4 Throttling And Sync

The guide says:

- default throttling is 1 ms
- 0 is generally not recommended
- vertical sync is enabled by default

On macOS, do not get clever unless you see an actual problem.

### 9.5 Syphon Output

If you use Syphon, the guide says:

- enable it in `Window -> Magic Window Options -> Syphon Output`
- the status display will show `s`

### Verification

Pass if:

- frame rate remains stable during scene changes
- VRAM stays healthy
- projector output matches expected resolution and aspect
- Syphon appears in the receiving app if enabled

Fail if:

- transitions hitch badly
- free graphics memory collapses after editing for a while
- the Preview Window halves performance during the show

---

## Phase 10: Build A Real Blackout Path

You need a single Magic behavior for blackout that QLC+ can hit every time.

Good choices:

- final master intensity parameter
- final opacity or color-multiply stage
- dedicated blackout scene in the playlist

Bad choice:

- trying to kill multiple unrelated module parameters at once during the show

### Recommended Pattern

Create one final control that represents:

- `0` = black
- `1` = full live output

Map QLC+ OSC blackout and intensity to that control.

### Verification

Pass if:

- a single QLC+ action reliably blacks out Magic
- releasing blackout restores exactly the expected scene state

Fail if:

- blackout depends on multiple unrelated controls
- recovering from blackout leaves the scene in a different state

---

## Golden Verification Routine

Run this before a real set.

1. BlackHole is selected in Input Sources.
2. `Music L` and `Music R` sources react to audio.
3. gain changes visibly affect reactivity.
4. one MIDImix fader controls one learned parameter.
5. one QLC+ OSC test scene moves one Magic parameter.
6. Playlist Next or entry select works from QLC+.
7. Preview Mode lets you edit without changing the Magic Window.
8. blackout from QLC+ reliably kills projector output.

If any of those fail, fix that layer before touching scene design.

---

## Failure Isolation

### Audio reacts badly

Look at:

- source selection
- source gain
- too little or too much smoothing
- wrong audio feature choice

### MIDImix does nothing

Look at:

- MIDI device not rescanned
- wrong MIDI channel
- wrong source selected during Learn

### QLC+ OSC does nothing

Look at:

- wrong OSC port
- no OSC source in Magic
- Learn not armed
- QLC+ not actually sending the test scene

### Scene changes cause hitches

Look at:

- transition style and duration
- VRAM policy
- Preview Window staying open
- too many heavy scenes loaded

### Editing disturbs the live output

Look at:

- Preview Mode not enabled
- using scene tabs instead of Playlist for live control

---

## Practical Advice

A good Magic project is not the one with the most tricks.

It is the one where:

- audio features are chosen intentionally
- MIDImix shapes visuals without owning show logic
- QLC+ changes stable macro controls
- Playlist owns the audience output
- Preview Mode protects the live screen
- blackout is a single known path
