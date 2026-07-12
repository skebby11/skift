# Skift

Open-source alternative to Zwift: an e-cycling app where your avatar rides a virtual
world and your smart trainer's resistance is synced to the terrain over Bluetooth,
so climbs feel like climbs.

**Current status: v1 feature-complete, pre-release.** Milestones M0–M4 are done and
merged to `main` (PRs #1–#13), CI is green with 47 unit tests. What remains:

- **Real-hardware validation** — blocked: the dev trainer (Van Rysel D500) is not
  available yet. Code carries explicit `REVIEW:` comments on every FTMS assumption
  that must be verified against real hardware.
- **M5 (ship v0.1)** — app icon, code signing / notarization, release workflow.

Read `Plan.md` for research, architecture, roadmap and the decision log
(all v1 decisions resolved). Each shipped feature has a design note in `docs/`.

## Stack & decisions

- **Stack**: Swift 5.9 + SwiftUI + RealityKit + Core Bluetooth. Native macOS app,
  deployment target macOS 14 (this is why the 3D layer uses `ARView` and
  primitive-only meshes — `RealityView` and cylinder/cone generators need macOS 15).
- **Map**: one fictional low-poly island loop (~8.2 km), fully procedural,
  deterministic (no random seeds at runtime).
- **License**: Apache-2.0. **Dev trainer**: Van Rysel D500 (BLE FTMS native).
- **Build**: XcodeGen (`project.yml`) → `xcodegen generate`, then `xcodebuild`.
  CI (`.github/workflows/ci.yml`) runs build + tests on macos-15, unsigned.

## Project layout

- `SkiftKit/` — framework, pure Swift, unit-testable. FTMS codec, physics,
  ride engine (10 Hz loop), route/track layout, recorder, TCX export, power zones.
  Only `TrainerManager.swift` imports CoreBluetooth (and is the only untested file).
- `Skift/` — app target. `UI/` (game flow: menu → pairing → ride setup → riding →
  summary, driven by `GamePhase` in `ContentView.swift`), `Scene3D/` (procedural
  RealityKit world, two-rate animation: 10 Hz engine → 60+ Hz render).
- `SkiftKitTests/` — 8 test files mirroring SkiftKit.
- Demo mode is first-class: `DemoPowerSource` replaces the trainer data source,
  everything downstream is identical. Use it for all development without hardware.

## Data flow (one line)

BLE FTMS notify → `TrainerManager.liveData` → `RideEngine.step` (10 Hz) →
`PhysicsEngine` → distance → `Route.smoothedGradient` → throttled
`setGrade(percent:)` back to the trainer (SIM mode) + `TrackLayout.position`
for the 3D avatar.

## Working conventions

- Language of code, comments, commits and docs: **English**.
- Keep `Plan.md` up to date: decisions move to the "Decision log" with a
  one-line rationale.
- Plan-first: any significant feature gets a short design note in `docs/`
  before implementation.
- Small commits with descriptive messages; feature branches off `main`.

## Backlog (post-v1, from Plan.md)

BLE auto-reconnect, FIT export, ride history, ERG mode / workouts, HR strap
support, ghost rider, Italian localization, iOS/tvOS targets, multiplayer.

## Domain glossary

- **FTMS** — Fitness Machine Service, the Bluetooth SIG standard (service `0x1826`)
  for fitness equipment. Lets an app read ride data and *control* the trainer.
- **SIM mode** — trainer simulates physics: the app sends grade/wind/Crr/CdA,
  the trainer sets resistance accordingly. This is what makes slopes "feel real".
- **ERG mode** — trainer holds a target power regardless of cadence (not in v1).
- **Smart trainer** — indoor trainer with a controllable brake (Wahoo KICKR,
  Tacx/Garmin Neo & Flux, Elite Direto/Suito, Zwift Hub, ...).
- **CPS / HRS / CSC** — companion BLE services: Cycling Power `0x1818`,
  Heart Rate `0x180D`, Cycling Speed & Cadence `0x1816`.
