# Processing VJ Levels

Individual level design documents for the Launchpad-controlled VJ system.

## Quick Links

| # | Level | Description |
|---|-------|-------------|
| 00 | [Common Reference](./00-common.md) | Shared Launchpad mappings, coding guidance, module layout |
| 01 | [Gravity Wells](./01-gravity-wells.md) | Particle attractor simulation |
| 02 | [Jelly Blobs](./02-jelly-blobs.md) | Soft-body physics creatures |
| 03 | [Agent Trails](./03-agent-trails.md) | Steering-behavior trails |
| 04 | [Reaction Diffusion](./04-reaction-diffusion.md) | Gray-Scott chemical patterns |
| 05 | [Recursive City](./05-recursive-city.md) | Escher-style camera ride |
| 06 | [Liquid Floor](./06-liquid-floor.md) | Non-Newtonian fluid blobs |
| 07 | [Cellular Automata](./07-cellular-automata.md) | CA Zoo (GoL, Wolfram, Brian's Brain) |
| 08 | [Portal Raymarcher](./08-portal-raymarcher.md) | Wormhole / tunnel shader |
| 09 | [Rope Simulation](./09-rope-simulation.md) | Verlet string physics |
| 10 | [Logo Wind Tunnel](./10-logo-wind-tunnel.md) | SVG mesh deformation |
| 11 | [Swarm Cameras](./11-swarm-cameras.md) | Boid-based multi-cam cuts |
| 12 | [Time Smear](./12-time-smear.md) | History-trail compositing |
| 13 | [Mirror Rooms](./13-mirror-rooms.md) | Kaleidoscope symmetry |
| 14 | [Text Engine](./14-text-engine.md) | Recursive typographic zoom |

## Document Structure

Each level document follows this template:

1. **Overview** — concept summary
2. **Launchpad Controls** — pad → function table
3. **Audio Reactivity** — which audio triggers affect visuals
4. **Implementation Notes** — tech hints
5. **State Machine** — Mermaid FSM diagram
6. **References** — external resources

## Related Documents

- [Implementation Plan](../../development/processing-implementation-plan.md) — step-by-step build order
- [Idea Board (legacy)](../processing-syphon-idea-board.md) — original brainstorm doc
- [Live VJ Setup Guide](../../setup/live-vj-setup-guide.md) — Syphon/audio/MIDI rig
- [MIDI Controller Setup](../../setup/midi-controller-setup.md) — Launchpad configuration
