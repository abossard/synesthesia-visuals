# Synesthesia OSC Monitor

Processing sketch that visualizes Synesthesia Live Pro’s OSC audio engine feed.

## Requirements

- Processing 4.x (use Intel build under Rosetta on Apple Silicon when Syphon is required)
- Libraries: [oscP5](http://www.sojamo.de/libraries/oscP5/) and [Syphon for Processing](https://github.com/Syphon/Processing)

## Usage

1. Open `SynesthesiaOSCMonitor.pde` in Processing.
2. Ensure libraries are installed (`Sketch → Import Library → Add Library…`).
3. Run the sketch. A Syphon server called `SynesthesiaOSC` will appear for downstream VJ apps.
4. In Synesthesia Live Pro:
   - Go to **Settings → OSC**.
   - Enable **Output** and **Output Audio Variables**.
   - Set **Address** to `127.0.0.1` and **Port** to `7000`.
5. Audio metrics (levels, presence, hits, beat timing, BPM/LFO) will update in real time.

## Data Reference

See `docs/reference/synesthesia-osc-audio-output.md` for a summary of the OSC namespaces consumed by this sketch.
