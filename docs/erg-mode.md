# ERG mode & basic interval workouts

*Design note, 2026-07-12. Scope decided: simple ERG + a minimal interval
builder — no .zwo import, no full workout editor (backlog).*

## Goal

Structured training on the trainer: the app holds a power target (FTMS
"Set Target Power", the trainer adjusts resistance regardless of cadence)
and steps through a simple interval sequence — enough for FTP tests and
classic repeats (warmup → N × work/recovery → cooldown).

## Scope

In: FTMS target-power command; an ERG ride mode that replaces grade-sync
with target-power-sync; a `Workout` model (flat list of steps, each
`targetWatts` + `durationSeconds`) with a builder UI limited to warmup /
repeats × (work + recovery) / cooldown; saved workouts (JSON store, same
pattern as rides); in-ride ERG HUD (current target, step countdown, next
step, ±5 W bump, skip step); workout completion → ride summary. Out: .zwo
/ .erg file import, %FTP-relative steps (steps are absolute watts in v1;
the builder pre-fills from FTP setting), ramps, cadence targets, workout
sharing.

## Architecture

- **`FTMS.setTargetPower(watts:)`** (codec) — opcode `0x05`, sint16 LE
  watts, clamped to 0…2000. Response handling already generic.
- **`Workout`** (SkiftKit, pure) — `WorkoutStep { label, targetWatts,
  durationSeconds }`, `Workout { name, steps }`, plus
  `Workout.intervals(warmup:repeats:work:recovery:cooldown:)` factory that
  flattens the builder's parameters into steps (skipping zero-duration
  parts). Total duration computed.
- **`WorkoutTracker`** (SkiftKit, pure) — given ride-clock elapsed seconds
  returns current step index, seconds left in step, next step; supports
  `skipCurrentStep()` (rebases an internal offset) and `adjustWatts(by:)`
  (global offset applied to every remaining step's target, so ±5 W sticks
  across steps like on real head units); reports `isFinished`. Driven by
  the engine's ride clock, so auto-pause freezes the workout for free.
- **`RideEngine`** — gains `enum RideMode { case sim; case workout(Workout) }`
  (default `.sim`, zero behavior change for existing rides). In workout
  mode: grade-sync is disabled entirely; each tick asks the tracker for the
  current target and sends `setTargetPower` when it changed (reusing the
  existing ≥1 s throttle); physics still integrates the *actual* power, so
  speed/distance/3D stay honest; `isCompleted` also flips when the tracker
  finishes. Route/gradient continue to drive the 3D world, they just don't
  reach the trainer. DECISION: the trainer exits ERG naturally when the
  next SIM ride starts (Request Control → grade sync); no explicit mode
  teardown command in v1 beyond target 0 W on `stop()`.
- **`TrainerControlling`** — gains `setTargetPower(watts: Int)`;
  `TrainerSession`/`TrainerManager` forward it like `setGrade` (recorded as
  `lastTargetPower` and re-sent after reconnect, mutually exclusive with
  grade re-send: whichever was sent last wins).
- **`WorkoutStore`** (SkiftKit) — same pattern as `RideStore`: one JSON per
  workout in Application Support, corrupt files skipped.

## UI

`RideSetupView` gains a mode picker: Free ride / Target distance (existing)
/ Workout. Workout mode shows the saved-workout list + "New workout…" sheet
(builder: warmup min+W, repeat count, work min+W, recovery min+W, cooldown
min+W — watts pre-filled from FTP: 50% / 105% / 55% / 40%), Start begins the
ride in `.workout` mode. Riding HUD adds an ERG panel when in workout mode:
big target watts, step label, countdown, next-step preview, − / + 5 W and
"Skip" buttons. Demo mode works (target is sent nowhere, `control` is nil —
useful to preview workouts).

## Testing

`FTMSTests`: target-power encoding + clamping. `WorkoutTests`: factory
flattening (zero-duration parts skipped, repeat expansion), total duration.
`WorkoutTrackerTests`: step lookup at boundaries, countdown, skip rebasing,
watt adjustment on remaining steps, finish detection. `RideEngineTests`:
workout mode sends target power (throttled, on change), never sends grade,
completion on workout end, auto-pause freezing the workout clock, demo
(nil control) safe. `WorkoutStoreTests`: round-trip, corrupt-skip.

REVIEW (hardware session): whether the D500 needs Stop/Pause or target 0 W
between ERG and SIM rides; ERG response latency to target changes.
