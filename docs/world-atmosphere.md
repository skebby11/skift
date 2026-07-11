# World atmosphere art pass

## Goal

Give the existing procedural island an intentional Mediterranean low-poly mood
before replacing its geometry. This pass changes atmosphere and materials only:
route, physics, camera, landmarks and gameplay remain unchanged.

The visual target is captured in
[`art/world-atmosphere-concept.png`](art/world-atmosphere-concept.png). It is an
original ImageGen concept used as direction, not a runtime texture or a promise
of geometry included in this first pass.

The implemented first-pass result is captured in
[`art/world-atmosphere-runtime.png`](art/world-atmosphere-runtime.png). It shows
the palette, matte surface response and distant silhouettes in the real app;
the ribbon terrain and placeholder avatar remain intentionally visible as the
baseline for the next geometry passes.

## Direction

- Warm late-afternoon key light with cool ambient sky contrast.
- Pale blue horizon and layered blue-grey distant landforms for depth.
- Deep teal water, muted sage vegetation, sun-baked ochre ground and charcoal
  asphalt; reserve vivid orange for the rider and Skift UI.
- Matte, restrained materials. Avoid pure white, saturated toy colors and
  photorealistic texture noise.
- Keep the scene lightweight and deterministic so the same world remains
  suitable for future iOS and tvOS targets.

## Scope

1. Establish the palette in one named `WorldPalette` source of truth.
2. Replace the flat blue background with a warmer atmospheric sky color.
3. Add distant low-poly horizon silhouettes that hide the empty world edge and
   reinforce aerial perspective.
4. Tune the directional sun and enable soft real-time shadows where supported.
5. Recolor existing water, terrain, road, vegetation, village and avatar.

Terrain topology, road shoulders, detailed vegetation and the avatar model are
separate follow-up passes.

## Acceptance checks

- Road and rider remain readable in both lit and shadowed areas.
- The horizon no longer ends in a flat empty line.
- Palette remains coherent from chase-camera height around the full loop.
- No generated raster is loaded at runtime; the concept is documentation only.
- The app builds on macOS 14+, and the existing unit suite remains green.
