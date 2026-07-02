# Skift

Open-source alternative to Zwift: ride a virtual world powered by your real
pedaling. Skift connects to your smart trainer over Bluetooth (FTMS), reads
live power/cadence/speed, and syncs the route gradient back to the trainer so
climbs feel like climbs.

**Status: early development — full v1 skeleton in place.** M1 (BLE), M2 (ride
engine), M3 (3D world, placeholder art) and M4 (ride recording, summary, TCX
export for Strava, settings) are code-complete. Hardware and visual validation
on a real trainer/screen is pending; `REVIEW:` markers in the code flag
everything to verify. See [`Plan.md`](Plan.md) for the roadmap and decision log.

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
