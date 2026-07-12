# BLE reliability: testable session state machine & auto-reconnect

*Design note, 2026-07-11. See Plan.md §8 (to-do: hardening) and docs/m1-ble-spike.md.*

## Goal

Close the two BLE gaps left by M1: `TrainerManager` is the only untested file
in `SkiftKit`, and a dropped connection mid-ride is unrecoverable (the ride
just stops publishing data). Both must be solved without hardware — the dev
trainer (Van Rysel D500) is not available yet, so everything below is
unit-tested against synthetic events and re-verified at the hardware
validation session.

## Scope

In: extracting the connection/handshake/reconnect logic into a pure,
CoreBluetooth-free state machine; automatic reconnect with exponential
backoff after an unexpected disconnect; surfacing a "reconnecting" state to
the UI. Out: multi-trainer support, non-FTMS fallbacks (CPS, FE-C),
CoreBluetooth state restoration across app relaunches, changes to the ride
engine (the existing auto-pause already freezes the ride when power drops to
zero during an outage).

## Architecture

Split `TrainerManager` in two, mirroring the FTMS-codec pattern from M1
("protocol logic testable without hardware"):

- **`TrainerSession`** (new, pure Foundation) — owns the entire session state
  machine: scanning, connecting, service/characteristic discovery, the
  control handshake (Request Control → Start/Resume), live-data parsing via
  `FTMS`, error handling, and the reconnect policy. It consumes typed inputs
  (user intents like `connect`/`setGrade` and BLE events like
  `didDisconnect`) and emits typed `SessionCommand`s (`startScan`,
  `connect(id)`, `write(data)`, `scheduleReconnect(after:)`, …) plus
  published-state snapshots. No CoreBluetooth import, no timers, no
  dispatch — delays are *data* in the emitted commands, so tests are fully
  synchronous: feed events, assert the command sequence and state.
- **`TrainerManager`** (rewritten as a thin adapter) — keeps its public API
  unchanged (`state`, `discovered`, `liveData`, `hasControl`, `lastError`,
  `startScan`/`connect`/`disconnect`/`setGrade`), so no view changes are
  required beyond the new state below. Internally it translates
  `CBCentralManagerDelegate`/`CBPeripheralDelegate` callbacks into session
  events and executes session commands against CoreBluetooth (including
  running `scheduleReconnect` via `DispatchQueue.main.asyncAfter`).

### Reconnect policy

On an unexpected disconnect from a connected/ready state:

- Enter `reconnecting(name:attempt:)` (new `ConnectionState` case) and retry
  `connect` to the same peripheral with exponential backoff 1, 2, 4, 8, 16,
  then 30 s capped — **indefinitely**, until the trainer comes back or the
  user disconnects/quits. Rationale: mid-ride, power drops to zero and the
  ride engine's auto-pause freezes the clock and recorder, so endless
  retrying costs nothing and never falsifies data.
- On reconnection the full handshake is redone (discovery → subscribe →
  Request Control → Start/Resume), and the last grade sent before the drop
  is re-sent once control is re-granted, so resistance is restored without
  waiting for the next engine tick.
- A user-initiated `disconnect()` never triggers reconnection.

The riding HUD shows a "Reconnecting…" badge driven by `trainer.state`
(hidden in demo mode); `PairingView` renders the new state like `connecting`.

## Testing

`TrainerSessionTests` drives the machine event-by-event: the happy-path
handshake command sequence; control refused (Zwift holds it); FTMS service or
characteristics missing; disconnect in every state (scanning, connecting,
discovering, ready); the exact backoff schedule including the 30 s cap and
counter reset after a successful reconnect; grade re-sent after control is
re-granted; user disconnect suppressing reconnection; out-of-order and
malformed events. `TrainerManager` shrinks to a translation layer with no
decisions of its own and stays hardware-verified only.

REVIEW (hardware session, D500): whether cached `CBPeripheral` references
survive a trainer power-cycle or a fresh scan is needed; whether
subscriptions must be re-established explicitly after reconnect; real-world
disconnect error codes.
