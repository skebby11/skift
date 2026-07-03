# Game flow: menu → pairing → ride setup → ride → summary

*Design note, 2026-07-03. Goal: make Skift feel like a game, not a BLE demo.*

## Screens (one `GamePhase` state machine in ContentView)

1. **Menu** — title screen: SKIFT wordmark, Ride / Settings / Quit.
2. **Pairing** — the guided trainer connection (moved out of the old
   single-screen UI). Two exits: a connected trainer with SIM control, or
   **demo mode** (ride without a trainer, power set by a slider) so the game
   is fully testable on any Mac — including visual checks without the D500.
3. **Ride setup** — route card (name, length, elevation profile) plus the
   **target distance selector**: Free ride / 5 / 10 / 20 / 40 km. The target
   feeds `RideEngine.targetDistanceMeters`.
4. **Riding** — the 3D ride. HUD adds ride time and, when a target is set, a
   progress bar. Reaching the target auto-completes the ride (engine stops,
   flow jumps to summary). "End ride" remains for early exits.
5. **Summary** — the existing post-ride stats + TCX export, now a full screen
   with "Back to menu" instead of a sheet.

## Engine additions

- `targetDistanceMeters` (published): optional finish line in total meters.
- `elapsedSeconds` (published): the simulated ride clock, for the HUD.
- `isCompleted` (published): set once when the target is crossed; the engine
  stops itself so the trainer gets no further grade commands.

## Demo mode

`DemoPowerSource` (app target) fabricates `IndoorBikeData` from a watts
slider (cadence derived from power). The engine takes it through the same
`dataSource` closure as the real trainer — no special-casing inside SkiftKit.
The trainer-control side is simply `nil` in demo mode.

## Out of scope (next PRs)

Map/scenery upgrade, animated avatar, power zones/FTP, auto-pause.
