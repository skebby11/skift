# Skift

Open-source alternative to Zwift: ride a virtual world powered by your real
pedaling. Skift connects to your smart trainer over Bluetooth (FTMS), reads
live power/cadence/speed, and syncs the route gradient back to the trainer so
climbs feel like climbs.

**Status: early development.** Current milestone: M1 — the BLE spike
(connect to a trainer, show live data, control resistance with a slope
slider). See [`Plan.md`](Plan.md) for the full roadmap and decision log.

## Requirements

- macOS 14+
- Xcode 15+ (Xcode 16 recommended)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- A smart trainer with Bluetooth FTMS (developed against a Van Rysel D500;
  any FTMS trainer — Wahoo, Tacx/Garmin, Elite, JetBlack, Zwift Hub — should work)

## Build & run

```sh
xcodegen generate      # creates Skift.xcodeproj (not committed)
open Skift.xcodeproj   # then ⌘R
```

Run tests with `⌘U`, or from the terminal:

```sh
xcodebuild -project Skift.xcodeproj -scheme Skift -destination 'platform=macOS' test
```

## Project layout

| Path | What it is |
|---|---|
| `Skift/` | The macOS app (SwiftUI) |
| `SkiftKit/` | Framework: FTMS protocol codec, BLE trainer manager — the testable core |
| `SkiftKitTests/` | Unit tests for SkiftKit |
| `docs/` | Design notes, one per significant feature |
| `Plan.md` | Research, architecture, roadmap, decision log |

## License

[Apache-2.0](LICENSE)
