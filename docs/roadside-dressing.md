# Roadside dressing: a lived-in Mediterranean roadside

*Design note, 2026-07-12. Follow-up to docs/world-atmosphere.md and
docs/terrain-relief.md — the world reads as an island now, but the roadside
itself is bare: one alternating tree every 140 m, a handful of houses at the
start, nothing else at rider eye level.*

## Goal

Make the 10–25 m band beside the road feel continuously dressed at riding
speed: something of visual interest every few seconds (~15–25 m spacing on
at least one side), in the established flat-shaded Mediterranean language.
The rider looks AT the roadside, not at the horizon — this band is where the
sense of place lives.

## Scope

In: new scenery element types (below), deterministic placement along the
whole loop, palette additions, denser tree spacing. Out: geometry changes to
road/terrain, textures or image assets (palette-only, per world-atmosphere),
animated elements, gameplay markers (km markers/arch exist).

## Element vocabulary (all primitives + MeshDescriptor, macOS 14 — no
generateCylinder/Cone)

- **Cypress** — the Mediterranean vertical: 3 stacked, shrinking squashed
  spheres on a stub trunk (tall, dark green). Placed in groups of 2–4, and
  in one formal double row flanking a ~100 m road stretch ("viale").
- **Olive tree** — short gnarled box trunk, wide pale-green squashed-sphere
  crown (distinct silhouette vs. existing crown green). Small groves of
  3–6 on gentle stretches.
- **Dry-stone wall** — low long boxes (0.6 m high) in `rock`-family color,
  following the road edge for 30–80 m stretches, occasionally on both
  sides. The single strongest "someone lives here" cue per meter.
- **Bush/shrub** — squashed spheres 0.4–0.9 m in two greens; scattered
  freely, also clustered at wall ends and tree feet.
- **Agave** — 5–7 flattened, tilted thin boxes fanning from a point,
  desaturated blue-green; singles near the sand/coast side.
- **Wildflower patch** — a cluster of tiny spheres (poppy red / ochre) at
  grass level; sparse, sunny stretches only.
- **Vineyard block** — one or two flat parcels: 4–6 parallel rows of low
  posts (thin boxes) with a green box "hedge" per row; reads instantly as
  agriculture from the saddle.
- **Fence posts** — short weathered posts with a single rail near the
  village approach, tying the buildings to the road.

## Placement rules

- Deterministic index math only (existing `makeTrees` pattern) — same world
  every run, tests stay reproducible.
- Band: 6–25 m from the road centerline (existing trees sit 10–21 m; walls
  hug 6–8 m). Y: drop like existing scenery (road-relative, −0.5) — beyond
  ~25 m terrain relief diverges from road height, so stay inside the band.
- Respect existing landmarks: keep 80 m around the start village clear of
  vineyards/groves (fences take over there), keep the arch approach clean,
  never place anything on the road/sand ribbons or in water.
- Existing trees: reduce spacing to ~90 m and mix in olive/cypress types so
  the old poplar-ish tree is one of three, not the only tree.

## Performance budget

Merge aggressively, following `dashedCenterLine`'s single-mesh pattern: all
geometry sharing a material is accumulated into one mesh. Trees, shrubs,
walls, posts, vine rows and flower patches therefore produce **ten additional
ModelEntities total**, independent of placement density. This is intentionally
well below the original ≤80-entity ceiling. 60 fps on the render loop is
untouchable.

## Palette additions (WorldPalette)

`cypress` (dark blue-green), `olive` (pale grey-green), `bushLight`,
`agave`, `flowerRed`, `flowerOchre`, `post` (weathered grey-brown), `vine`
(saturated leaf green) — all matte, desaturated to sit inside the existing
scene; rider orange stays the only saturated accent.

## Verification

Build + full test suite green (world building runs inside tests via
TrackLayout — determinism assertions must still hold). Visual check: launch
the app, demo ride, screenshot the first kilometer and the village approach;
compare against the "bare" baseline screenshot. The look is signed off by a
human (this note's author reviews composition, the user has final say).
