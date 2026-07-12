# Terrain relief and coastline variation

## Goal

Turn the continuous island mesh into intentional low-poly terrain rather than a
uniform green surface. Preserve a stable road bed while adding visible facets,
rolling relief and a less mechanical coastline.

## Approach

- Vary the coastal buffer with deterministic multi-frequency noise so the
  shoreline no longer follows one constant-width offset from the route.
- Add low-amplitude terrain noise only away from the road. A smooth influence
  mask keeps the asphalt supported and prevents sudden roadside banks.
- Fade relief toward sea level so the shoreline remains readable.
- Expand indexed grid triangles into flat-shaded faces. The resulting mesh is
  still small, but each coarse triangle catches light independently and makes
  the low-poly art direction visible.

All variation is derived from world coordinates and contains no runtime
randomness, keeping screenshots and future regression tests reproducible.

The verified in-app result is captured in
[`art/terrain-relief-runtime.png`](art/terrain-relief-runtime.png). Relief is
deliberately suppressed beside the road and becomes visible toward the horizon;
this keeps riding readable while preparing the wider island for detailed
coastal and vegetation passes.

## Acceptance checks

- No terrain deformation reaches the road bed.
- The coastline has visible broad variation without isolated islands.
- Terrain reads as faceted from the chase camera.
- No cracks appear between triangles.
- Existing build and unit tests remain green.
