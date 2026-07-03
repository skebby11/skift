# Animated avatar & game feel

*Design note, 2026-07-03. Third PR of the "real game" push.*

## Per-frame animation (the big change)

Until now avatar and camera moved inside SwiftUI's `updateNSView`, i.e. at
the engine's 10 Hz tick — visibly steppy. Now `RideSceneView` subscribes to
RealityKit's `SceneEvents.Update` (every rendered frame, 60+ Hz):

- The coordinator keeps a **display distance** that advances by the current
  speed each frame and is gently corrected toward the engine's authoritative
  distance (shortest wrap-aware difference, ~3 s time constant). The engine
  stays the single source of truth; the renderer just interpolates it.
- **Wheels spin** with speed (ω = v/r); each rim has a marker so the spin is
  visible on flat-shaded geometry.
- **Feet pedal** with real cadence: two pedal boxes orbit the crank in
  opposite phase (θ advances by cadence/60·2π per second).
- The chase camera eases per frame (`1 − e^(−4·dt)`), replacing the previous
  per-tick lerp.

`updateNSView` now only refreshes the coordinator's targets (distance, speed,
cadence) — cheap and allocation-free.

## Power zones (FTP)

`PowerZone` in SkiftKit: the standard 6-zone Coggan model off a configurable
FTP (Settings, default 200 W). The HUD shows a colored zone chip
(Z1 gray … Z6 red) under the watts and a live **W/kg** readout — the numbers
cyclists actually train by.

## Auto-pause

Zwift-style: when power is 0 **and** speed < 0.1 m/s the ride clock and the
recorder stop (no dead seconds polluting averages); a "Paused" badge shows on
the HUD. Coasting downhill at 0 W does NOT pause (speed condition). Distance
can't advance while paused, so summaries stay consistent.

## Out of scope

Sound, other riders/ghosts, camera angles selector, avatar customization.
