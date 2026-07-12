# Skift — Project Plan

*Last updated: 2026-07-11 · Status: v1 feature-complete, validation in progress*

## 1. What we are building

An open-source e-cycling app. You put your bike on a smart trainer, open Skift,
and ride a 3D world. Your **real pedaling power** moves the avatar; the **virtual
slope** is sent back to the trainer so resistance changes on climbs and descents.
One map, single player, macOS first.

## 2. What Zwift is (research summary)

Zwift (Zwift Inc., California, 2014; beta Sep 2014, paid since Oct 2015, now
~$19.99/month) is a massively-multiplayer online cycling & running game. Key
elements, and whether they are in Skift v1:

| Zwift feature | What it is | Skift v1? |
|---|---|---|
| Virtual worlds | 12 worlds; Watopia (fictional island, incl. Alpe du Zwift) always available, others rotate | ✅ **1 map** |
| Smart trainer sync | Reads power, controls resistance via ANT+ FE-C or **BLE FTMS**; "trainer difficulty" slider scales felt gradient | ✅ core feature (BLE only) |
| Avatar & physics | Speed computed from watts, rider weight, gradient, drafting, virtual bike | ✅ (no drafting) |
| Multiplayer | Thousands of riders visible, group rides | ❌ later |
| Racing | Events, categories, ZwiftPower rankings | ❌ later |
| Structured workouts | ERG mode, training plans, FTP tests | ❌ later |
| Running mode, steering, Play controllers | Extra hardware/modes | ❌ |

Existing open-source prior art proving feasibility:
- **Auuki** (github.com/dvmarinoff/Auuki) — browser PWA, structured training over
  BLE FTMS. Proves FTMS control is tractable for a small team.
- **CyCARLA** (github.com/tensorturtle/cycarla) — ride in the CARLA driving
  simulator with Zwift accessories. Proves the "real trainer → game engine" loop.
- **GoldenCheetah** — OSS training analysis with trainer ERG control.
- **qdomyos-zwift** — OSS bridge translating proprietary bikes to FTMS.

**Verdict: not crazy at all.** The MVP is a well-trodden path technically. What is
genuinely hard about Zwift is content (art, many worlds) and multiplayer
infrastructure — both explicitly out of scope for v1.

## 3. How the core loop works (technical)

### 3.1 Bluetooth: FTMS (Fitness Machine Service, `0x1826`)

The Bluetooth SIG standard implemented by virtually all smart trainers sold
since ~2018–2020 (Wahoo, Tacx/Garmin, Elite, JetBlack, Zwift Hub...).

- **Indoor Bike Data** `0x2AD2` (notify): instantaneous power (W), cadence (rpm),
  wheel speed — our input stream, ~1–4 Hz.
- **Fitness Machine Control Point** `0x2AD9` (write + indicate):
  - `0x00` Request Control → must be sent first
  - `0x07` Start/Resume
  - `0x11` **Set Indoor Bike Simulation Parameters** — payload: wind speed (m/s),
    **grade (%)**, rolling resistance coefficient (Crr), wind resistance
    coefficient (Cw). This single opcode is what makes slopes feel real.
- **Fitness Machine Feature** `0x2ACC` (read): capability flags.

Fallbacks (later): Cycling Power Service `0x1818` for power-only setups (no
resistance control), Heart Rate `0x180D`, Tacx FE-C-over-BLE for older Tacx.

### 3.2 Physics: watts → avatar speed

Standard road-cycling power equation, solved for speed `v` each tick
(Newton–Raphson, it's a cubic):

```
P = v · m·g·(sin θ + Crr·cos θ)  +  ½·ρ·CdA·v³
    └── gravity + rolling ──┘       └─ aero drag ─┘
```

Inputs: rider weight (user setting) + bike weight (~8 kg), gradient from route
data, constants Crr ≈ 0.004, CdA ≈ 0.32, ρ = 1.226. Add inertia smoothing so
speed doesn't jump with each power sample. Descents: freewheel physics
(gravity accelerates you at 0 W). This matches how Zwift does it.

### 3.3 Route & slope sync

- Route = 3D spline with distance + elevation (either authored by hand or
  imported from a GPX file).
- Avatar position advances along the spline by `v·dt`.
- Every ~1 s (or on significant change) send current grade to the trainer via
  opcode `0x11`.
- **Trainer difficulty setting** (like Zwift's): send `grade × k` with k
  default 0.5, so an 8% wall doesn't require heroics; physics still uses the
  full grade for speed.

### 3.4 The loop

```
Trainer ──BLE notify (power, cadence)──▶ Ride Engine ──▶ Physics ──▶ Avatar position
   ▲                                                        │
   └───────BLE write (grade %, SIM params)◀─── Route gradient at position
```

## 4. Platform: Mac vs Windows (the user's question)

**Recommendation: macOS first.** Reasons:

1. **Core Bluetooth** (Apple's BLE framework) is mature, well-documented, and
   pleasant. Windows BLE (WinRT `GattDeviceService`) works but is fiddlier and
   worse-documented for peripheral control.
2. **App Store path**: a native Mac app is directly sandboxable/notarizable for
   the Mac App Store, and the BLE + UI code ports to **iOS/iPadOS and Apple TV**
   (Apple TV is a hugely popular way to run Zwift). A Windows-first codebase
   gives none of that.
3. Team/user context: primary early users are on Mac.

Trade-off to be honest about: a Swift-native app will **not** run on
Windows/Linux, which shrinks the potential OSS contributor pool. The engine
choice below is where that trade-off is actually decided.

## 5. Tech stack options — DECISION NEEDED

Context that changed the recommendation: the founding developer's background is
**100% web development** (no native/desktop experience), and the must-have is a
real Zwift-like 3D map — not a dashboard app like Auuki.

| | A. Native Swift | B. Godot 4 | C. Web (TS + Three.js) |
|---|---|---|---|
| UI/3D | SwiftUI + **RealityKit** (or SceneKit) | Godot renderer (GDScript/C#) | **Three.js** (WebGL/WebGPU) |
| BLE | Core Bluetooth (first-class) | No built-in BLE → native GDExtension plugin or Swift sidecar process (the main risk) | Web Bluetooth (Chrome/Edge; **no Safari**) — Auuki proves FTMS works |
| Platforms | macOS → iOS/tvOS | macOS/Win/Linux (+mobile) | Any Chromium desktop; **Electron wrapper → installable Mac/Win/Linux app** |
| App Store fit | ★★★ best | ★★ possible, more friction | ★★ via Electron (accepted in Mac App Store); no iOS path |
| OSS contributor appeal | Apple devs only | ★★★ (engine itself MIT/OSS) | ★★★ web devs (largest pool) |
| MVP speed *for this team* | ★ (learn Swift + Xcode + RealityKit first) | ★★ (learn engine + BLE plugin work) | ★★★ (existing skills, hot reload, npm ecosystem) |
| 3D world quality ceiling | High (Metal) | High | Medium-high — **fully sufficient for a low-poly world**; Three.js runs far heavier games than this |
| Learning curve for a web dev | Steep (new language, new toolchain, compiled builds) | Medium | ~None |

Notes on the common web-stack worries:
- *"Can the web really do the Zwift map?"* Yes for the chosen art direction:
  a low-poly island with one route is comfortably within Three.js territory.
  Auuki has no 3D because it never tried, not because the browser can't.
- *Compile cycle:* native Swift apps do compile on every change (incremental
  builds are seconds in Xcode, not minutes) — the real cost is learning a new
  language/toolchain, not build time. Web dev keeps instant hot-reload.
- *iPhone/iPad:* only stack A gives a real iOS/iPadOS/tvOS path (same
  SwiftUI/RealityKit codebase, multiple targets). Web Bluetooth does not work
  in any iOS browser, and Electron doesn't target iOS. **Choosing C means
  iOS/App Store-on-iPhone is off the table unless the app is later ported.**

**DECIDED: A — Swift + SwiftUI + RealityKit + Core Bluetooth.** The web
stack was recommended for MVP speed, but native iPhone/iPad/Apple TV reach
and a first-class App Store path were judged worth the Swift/Xcode learning
curve. Consequences accepted: no Windows/Linux, and the roadmap absorbs an
onboarding cost (see M0/M1 and Risks).

## 6. Roadmap

Each milestone is independently demo-able. Rough effort assumes part-time work.

- **M0 — Setup**: Xcode project scaffolding (SwiftUI macOS app target),
  Apache-2.0 LICENSE, README, CI (GitHub Actions macOS runner, build + tests).
  Includes Swift/Xcode onboarding for a web-background developer — M0/M1 are
  deliberately small so the language is learned on real, tiny features.
- **M1 — BLE spike** *(the de-risking milestone, ~1–2 weeks)*: minimal app
  that scans, connects to the trainer (Van Rysel D500), streams live
  power/cadence to screen, and has a slope slider that changes trainer
  resistance via FTMS SIM mode (Core Bluetooth). No 3D. If M1 works, the
  project works.
- **M2 — Ride engine** (~1–2 weeks): physics model, route model
  (spline + elevation), rider profile (weight), 2D debug view: elevation
  profile with a dot moving along it, auto slope-sync to trainer.
- **M3 — 3D world** (~3–6 weeks, the long pole): one map — recommend a
  **low-poly stylized island loop, ~8–10 km** with one climb (~5 min @ 5–7%),
  rolling section and flat. Avatar with basic pedaling animation, follow
  camera, skybox. Low-poly is a deliberate style choice: achievable solo,
  ages well.
- **M4 — Ride experience** (~2 weeks): HUD (power, speed, cadence, HR,
  gradient, distance, elevation profile), ride summary, **.FIT file export**
  (opens the door to Strava upload), settings (weight, trainer difficulty,
  units).
- **M5 — Ship v0.1** (~1 week): packaging, signing/notarization, README with
  supported-trainer list, demo video.

Total: **~2–3 months part-time to a real, ridable v0.1.** Sanity check: solo
devs have shipped comparable OSS (Auuki, CyCARLA).

Later (v2+ backlog): ERG workouts, GPX import of real routes, ghost rider
(race your past self — cheap "multiplayer"), heart-rate zones, more maps,
actual multiplayer (hardest), Windows/Linux (if stack B), iOS/tvOS (if stack A).

## 7. Risks

| Risk | Mitigation |
|---|---|
| Trainer quirks (FTMS implementations vary by brand) | Test with owned trainer first; M1 isolates this; community test matrix later |
| 3D content takes forever | Low-poly style; buy/CC0 asset packs; one map only |
| Swift/Xcode learning curve (team is web-background) | M0–M2 sized as learning milestones; SwiftUI is declarative (familiar to React-style devs); lean on Apple sample code for RealityKit |
| Scope creep toward Zwift parity | Non-goals list in CLAUDE.md; v1 = solo riding only |
| macOS BLE permissions/sandbox | Known path: `NSBluetoothAlwaysUsageDescription`, works in App Store sandbox |

## 8. Status & to-do

All v1 decisions are resolved (see Decision log). **v1 is feature-complete
on `main`** (PRs #1–#10, CI-green, 47 unit tests) and waiting for its first
run on real hardware. What the game does today:

- Main menu → guided pairing (or **demo mode**: playable on any Mac, power
  from a slider) → ride setup with **target distance** (Free/5/10/20/40 km)
  → 3D ride → auto-completion at the target → summary → TCX export.
- 3D island: spline track, smoothed gradients (no resistance steps), dashed
  center line, start/finish arch, km markers, village, central mountain,
  rocks, varied trees; mini map + elevation profile overlays.
- Avatar animated at render rate (60+ fps interpolation): spinning wheels,
  cadence-driven pedals, slope pitch; eased chase camera.
- Training HUD: watts first, power zones off FTP (Settings), W/kg, heart
  rate, ride clock with Zwift-style auto-pause.

*Keep this list current: check items off (or strike them) as they land, and
add new ones as they emerge.*

### To-do — next up

- [ ] **Validation session** (Sebastiano, at the Mac; the `REVIEW:` markers
  in the code are the detailed checklist):
  - [ ] `xcodegen generate`, build, run; grant Bluetooth permission
  - [ ] **Demo mode first** (no trainer needed): menu → demo ride → check 3D
        world, animated avatar, HUD, auto-pause, summary; screenshot for the
        art discussion
  - [ ] With the D500: scan → connect; verify live power/cadence/speed
  - [ ] Full ride: resistance follows terrain, smooth on profile corners;
        speeds believable vs. Zwift at the same watts
  - [ ] Log a few raw Indoor Bike Data payloads (which fields does the D500 send?)
  - [ ] Target ride (5 km) auto-completes into the summary
  - [ ] ERG: builder workout runs, resistance follows targets, ±5W and skip work
  - [ ] Export TCX; upload to Strava succeeds
  - [ ] With a HR strap (Garmin/Polar): pair, live bpm on HUD, bpm in exported TCX
  - [ ] Ride history: completed ride appears, re-exported TCX matches, delete works
  - [ ] Strava: connect, upload a ride, activity appears as VirtualRide
- [ ] **Fix whatever the validation session finds** (expect BLE quirks and
  rough 3D — that's the point of the session)
- [ ] **Art pass** (needs the screenshot + direction): reshape track control
  points, real coastline/terrain instead of ribbons, nicer avatar, skybox,
  camera polish
- [ ] **M5 — ship v0.1** (release pipeline ready — docs/release-pipeline.md;
  signing/notarization, screenshots still open)

### To-do — backlog (v1.x / v2, roughly ordered)

- [x] ~~BLE auto-reconnect after dropped link~~ (shipped: `TrainerSession`
      state machine with infinite 1→30 s backoff — see docs/ble-reliability.md)
- [ ] Italian localization (UI ships in English as the OSS lingua franca;
      add a String Catalog with `it` once strings stabilize)
- [x] ~~App icon~~ (shipped in PR #12 — original design, license-safe)
- [ ] Trainer test matrix beyond the D500 (Wahoo, Tacx, Elite via community)
- [ ] FIT export (Strava-native format; TCX ships first)
- [x] ~~Ride history persistence in-app~~ (promoted into v1.x on
      2026-07-12 — see docs/ride-history.md)
- [x] ~~Smoothed route gradients~~ (shipped in PR #9)
- [ ] Ghost rider (race your previous recording — cheap "multiplayer")
- [x] ~~ERG mode / structured workouts~~ (v1 slice in progress 2026-07-12:
      simple ERG + interval builder — see docs/erg-mode.md; .zwo import stays here)
- [x] ~~Heart-rate strap via BLE HRS (separate sensor pairing)~~ (promoted
      into v1 on 2026-07-11 — see docs/hr-strap.md)
- [ ] iOS/iPadOS/tvOS targets
- [ ] Real multiplayer (server, presence, drafting) — the big one

## 9. Decision log

| Date | Decision | Rationale |
|---|---|---|
| 2026-07-02 | macOS first | Core Bluetooth quality, user base, App Store path (§4) |
| 2026-07-02 | Bluetooth only, no ANT+ | ANT+ needs a USB dongle & proprietary stack; FTMS covers modern trainers |
| 2026-07-02 | v1 is single-player, 1 map | Multiplayer & content are Zwift's real moat; not needed to "feel real" |
| 2026-07-02 | Map: fictional low-poly island (~8–10 km loop) | Achievable solo, ages well aesthetically; real-GPX terrain deferred |
| 2026-07-02 | License: Apache-2.0 | Permissive like MIT plus explicit patent grant |
| 2026-07-02 | Test hardware: Van Rysel D500 (Decathlon) | Owned by the team; supports BLE FTMS natively (plus ANT+ and Zwift Cog/Click), 15% max grade simulation — ideal dev target |
| 2026-07-02 | Stack: Swift + SwiftUI + RealityKit + Core Bluetooth | iPhone/iPad/Apple TV reach and first-class App Store path judged worth the learning curve vs. the web stack (§5) |
| 2026-07-02 | Ride export: TCX first, FIT later | Plain XML, no binary SDK, Strava imports it; FIT stays on the backlog |
| 2026-07-11 | Auto-reconnect: infinite exponential backoff (1→30 s cap) | Ride integrity protected by existing auto-pause; BLE logic extracted into pure `TrainerSession` for unit testing |
| 2026-07-11 | HR strap (BLE HRS) promoted into v1 | Riders own straps and most trainers don't report HR; standard service, small surface (see docs/hr-strap.md) |
| 2026-07-12 | Ride history: local JSON store (one file per ride) | Full samples kept so TCX re-export matches the original; corrupt files skipped, never fatal (see docs/ride-history.md) |
| 2026-07-12 | Strava: direct upload via user-supplied API app | OSS can't ship a client secret; BYO credentials + OAuth loopback callback (see docs/strava-upload.md) |
| 2026-07-12 | ERG v1: absolute-watt steps, builder-only | Warmup/repeats/cooldown covers FTP tests and repeats; %FTP steps and .zwo import deferred (see docs/erg-mode.md) |
