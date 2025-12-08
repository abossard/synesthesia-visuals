# Synesthesia OSC Audio Output Snapshot

## ⚙️ Runtime Context

- Source: Synesthesia Live Pro OSC output (`Settings → OSC → Output Audio Variables`).
- Target: Local logger listening on `127.0.0.1:7000` (`python-vj/scripts/synesthesia_osc_logger.py`).
- Reference docs: [Synesthesia OSC Manual](https://app.synesthesia.live/docs/manual/osc.html).

## 🔍 Captured Sample (2025-12-08)

```text
2025-12-08 14:17:48,546 INFO /audio/energy/intensity 1.000000
2025-12-08 14:17:48,546 INFO /audio/beat/beattime 5.000000
2025-12-08 14:17:48,546 INFO /audio/bpm/bpm 129.648346
2025-12-08 14:17:48,579 INFO /audio/level/high 0.922661
2025-12-08 14:17:48,579 INFO /audio/hits/high 0.657219
2025-12-08 14:17:48,579 INFO /audio/time/midhigh 39.498566
...
```

## 📡 Address Groups & Interpretation

- **`/audio/level/{band}`** (`bass`, `mid`, `midhigh`, `high`, `all`, `raw`)  
  - Instantaneous amplitude, normalized 0–1.  
  - `raw` reports unclamped amplitude before Synesthesia’s dynamic scaling.
- **`/audio/presence/{band}`** (`bass`, `mid`, `midhigh`, `high`, `all`)  
  - Slow envelope indicating sustained energy (0–1).  
  - Useful for gating long-form effects.
- **`/audio/hits/{band}`** (`bass`, `mid`, `midhigh`, `high`, `all`)  
  - Transient spike detector; large values align with percussion accents.  
  - In sample: `hits/high` peaked at `0.657219` during treble events.
- **`/audio/time/{band}`** (`bass`, `mid`, `midhigh`, `high`, `all`, `curved`)  
  - Accumulated seconds that each band has been active above threshold.  
  - `curved` tracks Synesthesia’s smoothed timeline for tempo-driven animations.
- **`/audio/energy/intensity`**  
  - Global loudness mix; frequently at `1.0` when limiter is engaged.
- **`/audio/bpm/` family**  
  - `bpm`: detected tempo (≈129.65 BPM in capture).  
  - `bpmconfidence`: quality score (1.0 = locked).  
  - `bpmtwitcher`: rapidly oscillating saw used for bar-synced sweeps.  
  - `bpmtri`, `bpmtri2/4/8`, `bpmsin`, `bpmsin2/4/8`: triangle/sine LFO harmonics for beat subdivisions.
- **`/audio/beat/` family**  
  - `onbeat`: rises near 1.0 on downbeats, then decays.  
  - `randomonbeat`: pseudo-random float per beat for stochastic triggers.  
  - `beattime`: bar counter (ticks 0–7 for 8-beat cycle).

## 🧭 Usage Tips

- Normalize downstream consumers expecting 0–1 to avoid spikes from `level/raw`.  
- Combine `presence` (slow) + `hits` (fast) for expressive envelopes.  
- Switch effects per bar using `beattime` or `bpmsin4` (quarter-beat sine).  
- Log files can be replayed for testing by piping timestamps into OSC generators (e.g., `oscsend`).

## 📁 File Location

- `docs/reference/synesthesia-osc-audio-output.md`
- Origin data stored in session log `2025-12-08 14:17:48` (see `synesthesia_osc_logger.py`).
