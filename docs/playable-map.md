# Playable map: smoothed gradients + a world worth riding

*Design note, 2026-07-03. Second PR of the "real game" push.*

## Problem

Two things kept the island from feeling playable:
1. **Gradient steps.** The route profile is piecewise linear, so the gradient
   (and with it the trainer's resistance) jumped at every segment boundary —
   like riding over invisible cliff edges every few hundred meters.
2. **Empty world.** Road + trees + water communicates "tech demo", not "game".
   There was no start line, no sense of place, no landmarks to measure
   progress against.

## Gradient smoothing

`Route.smoothedGradient(atMeters:windowMeters:)` — central difference of the
elevation over a ±30 m window. Continuous by construction (elevation is
continuous and the loop closes), converges to the raw segment slope in the
middle of long segments, and rounds off the corners exactly where the steps
were. The ride engine now feeds this to both the physics and the trainer;
the raw per-segment `gradient(atMeters:)` stays for anything that wants the
profile's true slope (e.g. the max-gradient stat in ride setup).

## World additions (all procedural, macOS 14-safe primitives)

- **Dashed center line** — one merged mesh (3 m dashes, 12 m period), not
  hundreds of entities: a single draw call and the strongest speed cue of all.
- **Start/finish arch** at km 0 — red pillars + white crossbar spanning the
  road; also serves as the lap landmark.
- **Kilometer markers** — small roadside signs at every km (pole + plate).
- **Start village** — a handful of primitive houses (body + diamond roof)
  near the arch, so laps begin and end *somewhere*.
- **Central mountain** — a big squashed sphere rising inside the loop: the
  climb visually goes *around a mountain* instead of floating on nothing.
- **Rocks + varied trees** — deterministic scatter, tree scale varies with
  index so the forest doesn't look copy-pasted.

Everything remains deterministic (no randomness) so tests and runs see the
same world. REVIEW: all placements/colors are blind first drafts — tune on
screen at the validation session.
