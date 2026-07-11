# Continuous low-poly island terrain

## Goal

Replace the concentric land ribbons with one continuous island surface. The
road, route physics and authored elevation profile remain the source of truth;
the terrain supports them visually without changing gameplay.

## Approach

- Sample the route into a closed XZ polygon with elevation at each sample.
- Cover its expanded bounds with a coarse deterministic grid.
- Keep grid cells inside the route polygon or within a coastal buffer outside
  it, producing a single connected surface instead of overlapping strips.
- Near the road, derive terrain height from the nearest route sample so the
  road never floats. Inside the loop, taper the ground gently below the road;
  outside it, ease elevation down to sea level at the coastline.
- Compute shared vertex normals from the emitted triangles for stable matte
  lighting.

The coarse grid is an intentional low-poly art choice and keeps the mesh cheap
enough for future iOS and tvOS targets. Fine coastline shaping, beaches and
road shoulders remain separate follow-up passes.

## Acceptance checks

- No empty holes are visible inside the circuit.
- The land is one connected mesh and meets the sea around a recognizable coast.
- The road remains above the terrain for the entire 8.2 km loop.
- Terrain generation is deterministic and completes during scene setup.
- Route, physics, trainer control and ride recording behavior are unchanged.
