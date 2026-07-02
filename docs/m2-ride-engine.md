# M2 — Ride engine: physics, route model, slope auto-sync

*Design note, 2026-07-02. See Plan.md §3.2–3.3 and §6 (M2).*

## Goal

Turn live trainer power into avatar motion along a route, and close the loop
by sending the route's gradient back to the trainer automatically. Rendered as
a 2D debug view (elevation profile with a moving rider dot) — the 3D world
comes in M3 on top of exactly this engine.

## Components (all in `SkiftKit`)

- **`PhysicsEngine`** — integrates the cycling power equation as force-based
  dynamics rather than solving for steady-state speed, so starts, coasting and
  descents feel natural:
  `a = (P/v − m·g·sin θ − m·g·Crr·cos θ − ½·ρ·CdA·v²) / m`, `v ← max(0, v + a·dt)`.
  The `P/v` drive term is capped with an effective speed floor (1 m/s) to avoid
  the standing-start singularity. Constants: ρ = 1.226 kg/m³, defaults
  Crr = 0.004, CdA = 0.32 m², rider 75 kg + bike 8 kg (`RiderProfile`).
- **`Route`** — piecewise-linear elevation profile: sorted `(distance,
  elevation)` points, linear interpolation for elevation, per-segment slope
  for gradient, loop-aware distance wrapping. Ships with `Route.island`, a
  placeholder 8.2 km loop matching the planned map: flat start, rolling
  section, ~1.8 km climb at ~5% to 110 m, descent, rolling return.
- **`RideEngine`** — the game loop (10 Hz `Timer`): reads power from an
  injected `() -> Double` source (decoupled from BLE for testability), steps
  the physics, advances distance along the route, publishes speed / distance /
  gradient / elevation, and syncs grade to a `TrainerControlling` (a protocol
  `TrainerManager` conforms to).

## Grade sync policy

Per Plan.md §3.3: the trainer receives `gradient × trainerDifficulty`
(default 0.5, like Zwift's default), while physics always uses the full
gradient for speed. Commands are rate-limited: sent only when the scaled
grade changed ≥ 0.1% since the last send and at most once per second — FTMS
control points don't need 10 Hz spam.

## Out of scope

3D rendering (M3), ride recording/FIT export (M4), rider weight settings UI
(M4), trainer-difficulty UI (M4 — the engine already exposes the knob),
free-wheeling detection beyond 0 W input.

## Testing

Physics: convergence to the analytic steady state on the flat, downhill
coasting from standstill, uphill deceleration to a stop, speed never negative.
Route: interpolation, segment gradients, loop wrapping, negative distances.
RideEngine: distance advances under constant power, grade-sync scaling,
rate limiting (single send while the gradient is stable).
