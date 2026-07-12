# Skift

[![CI](https://github.com/skebby11/skift/actions/workflows/ci.yml/badge.svg)](https://github.com/skebby11/skift/actions/workflows/ci.yml)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
![Platform: macOS 14+](https://img.shields.io/badge/Platform-macOS_14%2B-lightgrey)

**Open-source e-cycling for macOS.** Put your bike on a smart trainer, ride a
3D world, and feel the climbs: Skift reads your real pedaling power over
Bluetooth (FTMS) and syncs the route gradient back to the trainer, so an 8%
wall on screen is an 8% wall in your legs.

> **Status: v1 feature-complete, pre-release.**
> Everything below works in code and CI (47 unit tests), but the app hasn't
> been validated on real hardware yet and the 3D art is still first-pass
> procedural. Not ready for daily training — ready for curious contributors.
> No trainer? **Demo mode** makes the whole game playable with a power slider.

## Why

Zwift is great and costs $19.99/month. The protocol it relies on (Bluetooth
FTMS) is an open standard. Skift is the free, open, native-macOS take:
single player, one map, your watts — no subscription, no account, no cloud.

## Features (v1 scope)

- 🎮 **A real game flow** — main menu → guided pairing → ride setup with a
  **target distance selector** (free / 5 / 10 / 20 / 40 km, auto-finish) →
  ride → summary. **Demo mode** plays without any hardware.
- 🔌 **Trainer connection over BLE FTMS** — guided pairing, live power /
  cadence / speed / heart rate from any FTMS trainer, automatic reconnect
  with backoff if the link drops mid-ride
- ❤️ **Heart-rate strap pairing** — optional BLE HRS strap (Garmin, Polar,
  Wahoo TICKR…), remembered across launches, overrides trainer-reported HR
- ⚡ **Power-based riding** — your real watts drive the avatar through a
  physics model (gravity, rolling resistance, aero drag); the HUD leads with
  watts, **power zones off your FTP**, W/kg, and a Zwift-style **auto-pause**
- ⛰️ **Slope simulation** — the smoothed route gradient is sent to the
  trainer (FTMS SIM mode) with a configurable "trainer difficulty" scale
- 🏝️ **One 3D island loop** — 8.2 km with a ~5% climb around a mountain:
  spline road with markings, start/finish arch, km signs, village, forest;
  animated avatar (spinning wheels, pedaling cadence) interpolated at 60+ fps,
  chase camera, mini map, elevation profile
- 📊 **Ride recording** — per-second samples, post-ride summary (avg/max
  power, elevation gain, energy), **TCX export → upload to Strava**
- 🗂️ **Ride history** — every completed ride is saved locally; browse past
  rides, re-export any of them to TCX, or delete them
- ⚙️ **Settings** — rider/bike weight, FTP, trainer difficulty (⌘,)

Out of scope for v1: multiplayer, racing, ERG workouts, ANT+. See
[`Plan.md`](Plan.md) for the roadmap and every design decision.

## Requirements

- macOS 14+ (Apple Silicon or Intel)
- Xcode 15+ (16 recommended)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- A smart trainer speaking Bluetooth FTMS — developed against a
  **Van Rysel D500**; Wahoo, Tacx/Garmin, Elite, JetBlack, Zwift Hub and
  anything else FTMS should work (reports welcome!)

## Build & run

```sh
git clone https://github.com/skebby11/skift.git
cd skift
xcodegen generate      # creates Skift.xcodeproj (generated, not committed)
open Skift.xcodeproj   # then ⌘R
```

Tests: `⌘U` in Xcode, or:

```sh
xcodebuild -project Skift.xcodeproj -scheme Skift -destination 'platform=macOS' test
```

## How it works

```
             notify: power, cadence, speed          10 Hz tick
  Trainer ──────────────────────────────▶ TrainerManager ──▶ RideEngine
     ▲                                                      │  ├─ PhysicsEngine  watts → m/s
     │                                                      │  ├─ Route           distance → gradient
     └──────────────────────────────────────────────────────┘  └─ RideRecorder    1 sample/s
        write: grade % (FTMS SIM mode, rate-limited)
                                                     SwiftUI + RealityKit render
```

The physics integrates the road-cycling force balance
(`P/v − m·g·sinθ − m·g·Crr·cosθ − ½ρ·CdA·v²`), so coasting, descents and
standing starts behave naturally. The world is generated procedurally from the
route: a Catmull-Rom spline lays the track, elevation becomes Y, and the
trainer always feels the segment you're on.

## Project layout

| Path | What it is |
|---|---|
| `Skift/` | The macOS app: SwiftUI views, RealityKit 3D scene |
| `SkiftKit/` | Framework with the testable core: FTMS codec, BLE manager, physics, route, ride engine, recorder, TCX export |
| `SkiftKitTests/` | Unit tests (run in CI on every PR) |
| `docs/` | One short design note per milestone/feature — written *before* the code |
| `Plan.md` | Research, architecture, roadmap, decision log, living to-do |
| `CLAUDE.md` | Project context and working conventions |

## Contributing

Early enough that everything is up for discussion — issues and PRs welcome.

- **Conventions**: English everywhere; small commits; feature branches off
  `main`; plan-first (significant features get a design note in `docs/`).
- **CI is the gate**: every PR builds and tests on a macOS runner.
- **`REVIEW:` markers** in the code flag things awaiting hardware/visual
  validation — great first issues if you own an FTMS trainer.
- **Trainer reports**: if you run Skift with a trainer we haven't tested,
  open an issue with the brand/model and what worked — the compatibility
  matrix needs you.

## License

[Apache-2.0](LICENSE)
