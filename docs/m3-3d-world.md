# M3 — 3D world: first slice

*Design note, 2026-07-02. See Plan.md §6 (M3).*

## Goal of this slice

Put the ride on screen in 3D: terrain, a road that follows the route's
elevation, an avatar that moves with the ride engine, and a chase camera.
Placeholder visuals — the point is the pipeline (route → 3D world → moving
camera), not beauty. Art passes replace pieces incrementally later.

## Approach

- **`TrackLayout`** (`SkiftKit`, pure simd math, unit-tested) maps 1D route
  distance to 3D coordinates. Placeholder layout: the loop is a circle whose
  circumference equals the route length (r = L/2π ≈ 1.3 km for the island);
  elevation becomes Y. Later this becomes an authored 2D spline (curves,
  switchbacks) without touching anything downstream, because consumers only
  call `position(atMeters:)` / `tangent(atMeters:)`.
- **`WorldBuilder`** (app target) generates meshes with RealityKit
  `MeshDescriptor`: a road ribbon (two vertices per sample, triangles wound
  on both sides so winding mistakes can't blank the road), a wider green
  "island" ribbon slightly below it, a water plane at y = 0, a sun
  (directional light). Flat shading, `SimpleMaterial` — deliberately low-poly.
- **`RideSceneView`** (`NSViewRepresentable` wrapping RealityKit's `ARView`)
  hosts the scene. `ARView` works as a plain non-AR 3D view on macOS and is
  available on our macOS 14 deployment target, unlike SwiftUI's `RealityView`
  which needs macOS 15 — revisit when we bump the target. SwiftUI's 10 Hz
  invalidation from the ride engine drives `updateNSView`, which repositions
  the avatar and the chase camera (10 m behind, 4 m up, looking at the rider).

## Out of scope (rest of M3)

Authored island layout (curves instead of the circle), real terrain with
coastline, avatar model with pedaling animation, camera smoothing/variety,
scenery props, skybox. Each lands as its own PR on top of this pipeline.
