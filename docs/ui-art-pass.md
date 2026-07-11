# Ride UI art pass

## Goal

Make the 3D world the ride screen rather than one panel inside it. Ride data must
remain readable over both bright sky and dark terrain, at the minimum supported
window size and on a large display.

## Direction

- Use a full-bleed 3D canvas with a small set of floating, dark translucent HUD
  surfaces. Avoid recreating any competitor's layout or visual identity.
- Treat power as the primary live signal. Cadence and heart rate sit with it;
  speed, distance and time form a second compact group.
- Keep navigation context peripheral: gradient and mini-map at the top right,
  elevation and target progress in one shallow strip along the bottom.
- Use white, monospaced digits for stable high contrast and orange as Skift's
  single activity accent. Secondary labels must never rely on macOS's default
  dark foreground over a dark custom background.
- Collapse the HUD vertically on smaller windows. Demo power and end-ride
  controls occupy a narrow bottom bar and never reduce the 3D viewport to a
  card.

## Acceptance checks

- Power, speed, distance, time and gradient are legible over every scene region.
- The ride scene fills all space left by the small demo/action bar.
- The mini-map and elevation profile remain visible without obscuring the rider.
- Menu secondary actions have explicit foreground and background contrast.
- Existing ride, auto-pause, target progress, demo slider and completion behavior
  are unchanged.
