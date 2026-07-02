# M4 — Ride experience: recording, summary, TCX export, settings

*Design note, 2026-07-02. See Plan.md §6 (M4).*

## Goal

Make a ride worth something after it ends: record it, summarize it, export it
to Strava-compatible TCX, and let the rider configure weight and trainer
difficulty.

## Components

- **`RideRecorder`** (`SkiftKit`, pure, testable) — collects one
  `RideSample` per second (power, cadence, heart rate, speed, total distance,
  elevation) and computes a `Summary`: duration, distance, avg/max power,
  avg cadence, avg heart rate, elevation gain (sum of positive deltas),
  mechanical energy in kJ (∑ power·dt).
- **`TCXExporter`** (`SkiftKit`, pure) — renders samples to Garmin TCX XML
  (`Activity Sport="Biking"`, one `Lap`, `Trackpoint`s with altitude,
  distance, cadence, heart rate, and watts/speed in the ActivityExtension
  namespace). No GPS coordinates: Strava accepts indoor rides without them.
  Calories field uses the kJ number — the standard ≈1:1 kJ→kcal convention
  for cycling (≈24% muscular efficiency).
  DECISION: TCX first instead of FIT — plain XML, no binary SDK, Strava
  imports it. FIT stays on the backlog (Plan.md M4 note).
- **`RideEngine`** — `start` now takes a `() -> FTMS.IndoorBikeData` data
  source (was `() -> Double` power only) so the recorder sees cadence and
  heart rate too; accepts an optional `RiderProfile` so settings apply per
  ride; owns the recorder (fed once per simulated second).
- **Settings** (`SettingsView`, standard macOS Settings scene) —
  `@AppStorage`: rider weight, bike weight, trainer difficulty %. Read by
  `ContentView` when starting a ride.
- **Ride summary** (`RideSummaryView`) — sheet on "End ride": stats grid +
  "Export TCX…" (NSSavePanel) + Done.

## Out of scope

FIT export, automatic Strava upload (OAuth), ride history persistence,
pause/resume detection. REVIEW: verify Strava actually accepts our TCX on the
first real export (validators are lenient, Strava less so).
