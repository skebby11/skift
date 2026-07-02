# Skift

Open-source alternative to Zwift: an e-cycling app where your avatar rides a virtual
world and your smart trainer's resistance is synced to the terrain over Bluetooth,
so climbs feel like climbs.

**Current status: PLANNING COMPLETE, ready for M0.** No code yet. Read `Plan.md`
before doing anything — it contains the full research, architecture, roadmap,
and the decision log. All v1 decisions are resolved:

- **Stack**: Swift + SwiftUI + RealityKit + Core Bluetooth (native macOS app;
  future iOS/iPadOS/tvOS targets share the codebase).
- **Map**: one fictional low-poly island loop, ~8–10 km.
- **License**: Apache-2.0.
- **Dev trainer**: Van Rysel D500 (BLE FTMS native).

## Project goals (v1 / MVP)

1. Connect to a smart trainer via Bluetooth LE (FTMS standard).
2. Read live power/cadence/speed from the trainer.
3. One 3D map: the avatar moves along a route, speed computed from real power
   via a physics model (gravity, rolling resistance, aero drag).
4. Sync slope to the trainer: send the route gradient back so resistance changes
   on climbs and descents ("simulation mode").
5. macOS first (see Plan.md → Decisions).

## Non-goals for v1

- Multiplayer / other riders on the road
- Structured workouts / ERG mode
- Racing, drafting, power-ups
- Multiple maps, running mode
- ANT+ (Bluetooth only)

## Working conventions

- Language of code, comments, commits and docs: **English**.
- Keep `Plan.md` up to date: when a decision is made, move it from
  "Open decisions" to the "Decision log" with a one-line rationale.
- Plan-first: any significant feature gets a short design note in `docs/`
  before implementation.
- Small commits with descriptive messages; feature branches off `main`.

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
