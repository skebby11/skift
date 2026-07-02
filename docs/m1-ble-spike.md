# M1 — BLE spike: trainer connection & resistance control

*Design note, 2026-07-02. See Plan.md §3 and §6 (M1).*

## Goal

Prove the project's riskiest assumption end-to-end: that we can connect to a
smart trainer over BLE FTMS, stream live ride data, and change its resistance
from the app. Exit criterion: moving a slope slider in the app makes the
pedals physically harder on the Van Rysel D500.

## Scope

In: scanning for FTMS devices, connect/disconnect, live power/cadence/speed
(and heart rate when the trainer reports it), a −10…+15% grade slider sent as
FTMS "Set Indoor Bike Simulation Parameters". Out: physics, 3D, ride
recording, reconnection strategies, non-FTMS fallbacks (CPS, FE-C).

## Architecture

Two layers inside `SkiftKit` so the protocol logic is testable without
hardware:

- **`FTMS`** — pure Foundation codec, no CoreBluetooth. Parses Indoor Bike
  Data (`0x2AD2`) notifications (flag-gated field layout per the FTMS spec;
  note the inverted "More Data" bit: instantaneous speed is present when
  bit 0 is **0**), builds Control Point (`0x2AD9`) commands (Request Control
  `0x00`, Start/Resume `0x07`, Set Indoor Bike Simulation Parameters `0x11`),
  and parses Control Point response indications (`0x80`). Fully unit-tested.
- **`TrainerManager`** — `CBCentralManager` wrapper, `ObservableObject`
  publishing connection state, discovered trainers, live data, and control
  status. Delegate callbacks run on the main queue (UI-bound app; revisit if
  it ever shows up in profiling).

Control handshake on connect: discover FTMS service → subscribe to Indoor
Bike Data and Control Point indications → write Request Control → on success
write Start/Resume. Simulation commands are only meaningful after control is
granted.

The app (`Skift` target) contains SwiftUI views only.

## Testing

Unit tests cover the codec with synthetic payloads (field combinations,
truncated data, negative grades, clamping). The BLE layer is verified
manually against the D500 — automating that needs a peripheral simulator,
deferred until the protocol surface grows.
