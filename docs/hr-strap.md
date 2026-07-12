# Heart-rate strap support (BLE Heart Rate Service)

*Design note, 2026-07-11. Promoted from the backlog into v1 scope. See
Plan.md §9 (decision log) and docs/ble-reliability.md for the session
pattern this follows.*

## Goal

Read heart rate from a dedicated BLE chest strap (Garmin HRM, Polar H9/H10,
Wahoo TICKR — anything implementing the standard Heart Rate Service
`0x180D`), because most trainers don't report HR and straps are what riders
actually own. The bpm stream must reach everything that already understands
heart rate — HUD, ride recorder, TCX export — without changing any of it.

## Scope

In: scanning/pairing a strap (optional step in the pairing flow), live bpm,
strap remembered across launches and auto-connected, automatic reconnection,
strap overriding trainer-reported HR. Out: RR intervals / HRV, energy
expended, battery level, multiple simultaneous straps, HR zones display
(power zones exist; HR zones are a later feature), demo-mode fake HR.

## Architecture

Same three-layer split as the trainer stack (codec / pure session / thin
adapter), sized down to HRS's read-only simplicity:

- **`HRS`** (new, pure) — codec for the Heart Rate Measurement
  characteristic `0x2A37`: flags bit 0 selects uint8 vs uint16 LE bpm; sensor
  contact, energy expended and RR intervals are skipped. Returns nil on
  malformed payloads. Fully unit-tested like `FTMS`.
- **`HeartRateSession`** (new, pure) — small state machine mirroring
  `TrainerSession`'s event/command style (`idle / scanning / connecting /
  connected / reconnecting`). Reconnect policy differs from the trainer's
  backoff: on an unexpected disconnect it immediately re-emits
  `.connect(id)` and relies on CoreBluetooth's pending-connection semantics
  (a `connect` never times out and completes whenever the strap reappears) —
  straps drop and return constantly as people move, and there is no
  resistance-control handshake to redo. DECISION: no timer, no backoff.
- **`HeartRateMonitor`** (new, thin adapter) — `ObservableObject` owning a
  separate `CBCentralManager`, publishing `state`, `discovered`, `bpm`.
  Executes session commands; no decisions of its own.

The remembered strap (`UUID`) is stored via `@AppStorage` next to the rider
settings; on entering the pairing flow the monitor silently reconnects to it
when present.

### Data flow — merge at the data source

`RideEngine`, `RideRecorder` and `TCXExporter` stay untouched. The merge
happens where trainer and demo sources already meet, in `ContentView`'s
`dataSource` closure: take the trainer's (or demo's) `IndoorBikeData` and, if
the strap reports a bpm, overwrite `heartRateBpm` with it. The strap wins
over trainer-reported HR — dedicated straps are the accurate source; the
trainer value remains the fallback when no strap is paired.

## UI

`PairingView` gains an optional, collapsed-by-default "Heart rate (optional)"
section: scan, list of straps, connect, live bpm preview, and a "skip"
affordance — the Continue button never depends on it. The riding HUD already
renders heart rate when present; no `RideView` change.

## Testing

`HRSTests`: uint8/uint16 formats, flag combinations (contact bits, energy
expended, RR intervals present — all skipped correctly), truncated payloads.
`HeartRateSessionTests`: happy path (scan → connect → subscribe → bpm),
unexpected disconnect re-emits `.connect` immediately, user disconnect does
not, malformed measurement ignored, remembered-strap auto-connect intent.
Adapter stays hardware-verified only, like `TrainerManager`.

REVIEW (hardware session): pending-connection behavior when the strap
power-cycles; whether popular straps advertise `0x180D` while already
connected to a watch (Garmin dual-channel vs. Polar single-channel).
