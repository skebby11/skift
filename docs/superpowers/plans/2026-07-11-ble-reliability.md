# BLE Reliability (TrainerSession + auto-reconnect) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract all BLE session logic from `TrainerManager` into a pure, unit-tested `TrainerSession` state machine and add infinite exponential-backoff auto-reconnect, per `docs/ble-reliability.md`.

**Architecture:** `TrainerSession` (pure Foundation, no CoreBluetooth, no timers) consumes user intents + typed BLE events and emits typed `Command`s; delays are data inside commands, so tests are synchronous. `TrainerManager` becomes a thin adapter translating CoreBluetooth delegate callbacks ↔ session events/commands and republishing session snapshots via `@Published`. Public API of `TrainerManager` stays source-compatible; one new state case `reconnecting(name:attempt:)`.

**Tech Stack:** Swift 5.9, XCTest, XcodeGen. Build/test exactly like CI (`.github/workflows/ci.yml`): `xcodegen generate` then `xcodebuild test` with `CODE_SIGNING_ALLOWED=NO`, destination `platform=macOS`. Read `ci.yml` first and reuse its flags verbatim.

**Read first:** `docs/ble-reliability.md` (spec), `SkiftKit/TrainerManager.swift` (current logic being extracted), `SkiftKit/FTMS.swift` (codec API), `SkiftKitTests/FTMSTests.swift` (house test style), `AGENTS.md` (conventions — English everywhere, small commits).

---

## Locked interface contract

All tasks build toward this exact API (adjust only if the compiler forces it, and note why in the commit):

```swift
// SkiftKit/TrainerSession.swift
public final class TrainerSession {

    public enum State: Equatable {
        case bluetoothUnavailable(reason: String)
        case idle
        case scanning
        case connecting
        case connected(name: String)
        case reconnecting(name: String, attempt: Int)
    }

    public enum Event: Equatable {
        case bluetoothDidBecomeAvailable
        case bluetoothDidBecomeUnavailable(reason: String)
        case didDiscover(id: UUID, name: String, rssi: Int)
        case didConnect(name: String)
        case didFailToConnect(message: String?)
        case didDisconnect(message: String?)
        case didDiscoverFTMSService(found: Bool)
        /// Which of the two required characteristics were found on the FTMS service.
        case didDiscoverCharacteristics(indoorBikeData: Bool, controlPoint: Bool)
        case didReceiveIndoorBikeData(Data)
        case didReceiveControlPointResponse(Data)
        case reconnectTimerFired
    }

    public enum Command: Equatable {
        case startScan
        case stopScan
        case connect(id: UUID)
        case cancelConnection
        case discoverServices
        case discoverCharacteristics
        case subscribeIndoorBikeData
        case subscribeControlPoint
        case write(Data)
        case scheduleReconnect(after: TimeInterval)
        case cancelReconnect
    }

    // Snapshot the adapter republishes after every intent/event call.
    public private(set) var state: State = .idle
    public private(set) var discovered: [DiscoveredTrainer] = []
    public private(set) var liveData = FTMS.IndoorBikeData()
    public private(set) var hasControl = false
    public private(set) var lastError: String?

    public var onCommand: ((Command) -> Void)?

    // User intents (same semantics as today's TrainerManager methods).
    public func startScan()
    public func stopScan()
    public func connect(id: UUID, name: String)
    public func disconnect()
    public func setGrade(percent: Double)

    // BLE events from the adapter.
    public func handle(_ event: Event)
}
```

`DiscoveredTrainer` moves (or stays visible) unchanged. `TrainerManager.ConnectionState` becomes `public typealias ConnectionState = TrainerSession.State` so existing views compile untouched (except `PairingView`'s exhaustive switch — see Task 6).

**Behavioral rules** (from the spec — encode each as a test):

1. Handshake: `connect` intent → `.stopScan` + `.connect(id)`; `didConnect` → `.discoverServices`; service found → `.discoverCharacteristics`; both characteristics found → `.subscribeIndoorBikeData`, `.subscribeControlPoint`, `.write(FTMS.requestControl())`; Control Point success for `requestControl` → `hasControl = true`, `.write(FTMS.startOrResume())`.
2. Control refused → `hasControl = false`, `lastError` mentions another app holding control (keep today's wording).
3. FTMS service missing → `lastError` set, `.cancelConnection`. Characteristics incomplete → same.
4. Indoor Bike Data payloads parse via `FTMS.parseIndoorBikeData`; unparseable data is ignored (no state change).
5. User `disconnect()` → `userInitiated` flag set, `.cancelReconnect` + `.cancelConnection`; the following `didDisconnect` resets to `.idle` with **no** reconnect scheduled.
6. Unexpected `didDisconnect` while `connected` → state `.reconnecting(name:attempt:1)`, `hasControl = false`, `liveData` reset, emit `.scheduleReconnect(after: 1)`.
7. Backoff: attempts 1,2,3,4,5,6,7… wait 1,2,4,8,16,30,30… s (cap 30, infinite). `reconnectTimerFired` → `.connect(id)` to the remembered peripheral. `didFailToConnect` (or another `didDisconnect`) during reconnecting → increment attempt, emit next `.scheduleReconnect`.
8. Successful reconnect runs the full handshake again; when control is re-granted, if a grade was ever sent, immediately `.write(FTMS.setIndoorBikeSimulation(gradePercent: lastGrade))`; attempt counter resets.
9. `setGrade` only emits `.write` when `hasControl`; it always records `lastGrade`. Note: this deliberately **tightens** today's guard (`controlPoint != nil`, which is true slightly before control is granted) — no current UI path calls `setGrade` in that window, but don't assume behavior-preservation here.
10. `bluetoothDidBecomeUnavailable` → state `.bluetoothUnavailable(reason:)` and `.cancelReconnect`.

---

### Task 1: TrainerSession scaffolding + happy-path handshake

**Files:** Create `SkiftKit/TrainerSession.swift`, `SkiftKitTests/TrainerSessionTests.swift`.

- [x] **Step 1:** Write failing test `testHappyPathHandshakeEmitsExpectedCommandSequence` — helper records commands into `[Command]`; drive `startScan()` → `didDiscover` → `connect(id:name:)` → `didConnect` → `didDiscoverFTMSService(found: true)` → `didDiscoverCharacteristics(true, true)` → `didReceiveControlPointResponse(<success payload for requestControl>)`; assert the exact command array per rule 1 and final `state == .connected(name:)`, `hasControl == true`. Build the success payload with the same byte layout `FTMSTests` uses (`[0x80, 0x00, 0x01]`).
- [x] **Step 2:** Run it; expected: FAIL (type doesn't exist). Use the CI xcodebuild invocation filtered to this test.
- [x] **Step 3:** Implement the minimal state machine to pass (no reconnect logic yet).
- [x] **Step 4:** Run; expected: PASS. Run the whole `SkiftKitTests` bundle too — nothing else may break.
- [x] **Step 5:** Commit `feat(ble): TrainerSession pure state machine — happy-path handshake`.

### Task 2: Discovery list, live data, scan/stop semantics

**Files:** Modify both Task 1 files.

- [x] **Step 1:** Failing tests: `testDiscoveredTrainersDeduplicateById` (same id twice updates rssi in place, preserves order), `testIndoorBikeDataUpdatesLiveData` (use a known-good payload copied from `FTMSTests`), `testMalformedIndoorBikeDataIsIgnored`, `testStopScanWhileScanningReturnsToIdle`, `testStartScanClearsPreviousDiscoveredAndError`.
- [x] **Step 2:** Run; FAIL. **Step 3:** Implement. **Step 4:** Run; PASS. **Step 5:** Commit `feat(ble): TrainerSession discovery and live-data handling`.

### Task 3: Error paths

**Files:** Same.

- [x] **Step 1:** Failing tests: `testControlRefusedSetsErrorAndNoControl` (result byte ≠ success), `testMissingFTMSServiceCancelsConnection`, `testMissingControlPointCharacteristicCancelsConnection`, `testDidFailToConnectFromInitialConnectResetsToIdleWithError`, `testBluetoothUnavailableSetsStateAndCancelsReconnect`, `testRejectedNonControlCommandSetsError` (rule from today's `handleControlPointResponse`).
- [x] **Steps 2-5:** TDD cycle, commit `feat(ble): TrainerSession error paths`.

### Task 4: User disconnect vs auto-reconnect

**Files:** Same.

- [x] **Step 1:** Failing tests: `testUserDisconnectDoesNotScheduleReconnect` (rule 5), `testUnexpectedDisconnectSchedulesFirstRetryAfterOneSecond` (rule 6, also asserts `liveData` reset and state `.reconnecting(name:, attempt: 1)`), `testReconnectTimerFiredEmitsConnectToSamePeripheral`.
- [x] **Steps 2-5:** TDD cycle, commit `feat(ble): auto-reconnect on unexpected disconnect`.

### Task 5: Backoff schedule, cap, reset, grade restore

**Files:** Same.

- [x] **Step 1:** Failing tests: `testBackoffScheduleIsExponentialCappedAt30s` (drive 8 consecutive failures, assert delays `[1,2,4,8,16,30,30,30]`), `testSuccessfulReconnectRunsFullHandshake`, `testAttemptCounterResetsAfterSuccessfulReconnect` (reconnect, then drop again → next delay is 1 s), `testLastGradeIsResentOnceControlRegained` (setGrade(3.5) while connected → drop → reconnect handshake → assert `.write(FTMS.setIndoorBikeSimulation(gradePercent: 3.5))` right after startOrResume), `testNoGradeResentIfNeverSet`, `testSetGradeWithoutControlEmitsNothingButRecordsGrade`.
- [x] **Steps 2-5:** TDD cycle, commit `feat(ble): backoff schedule and grade restore after reconnect`.

### Task 6: Rewrite TrainerManager as a thin adapter

**Files:** Modify `SkiftKit/TrainerManager.swift` (full rewrite of internals; public surface preserved + typealias). Also modify `Skift/UI/PairingView.swift` **in this same task**: its `switch trainer.state` (lines ~51–111) has no `default:`, so adding the `reconnecting` case breaks exhaustiveness — add a minimal `case .reconnecting:` arm rendering exactly like `.connecting` (cosmetic attempt-count polish stays in Task 7).

- [x] **Step 1:** Rewrite: owns `CBCentralManager`, `CBPeripheral?`, characteristic refs, and a `TrainerSession`. Delegate callbacks map 1:1 to `session.handle(...)` (`didDiscoverServices` → `.didDiscoverFTMSService(found:)` by checking for the FTMS UUID, etc.). `onCommand` executes against CoreBluetooth; `.scheduleReconnect(after:)` uses a cancellable `DispatchWorkItem` on the main queue that feeds back `.reconnectTimerFired`; `.cancelReconnect` cancels it. After every intent/event, copy the session snapshot into the `@Published` properties (only assign when changed, to avoid redundant SwiftUI invalidation). Keep the file's existing `REVIEW:` comment style; carry over the D500 notes and add the ones from `docs/ble-reliability.md` §REVIEW. No decisions may live in the adapter.
- [x] **Step 2:** Build the whole project + run all tests (CI invocation). Expected: everything green with **no behavioral view changes** beyond the required exhaustive-switch arm in `PairingView`.
- [x] **Step 3:** Commit `refactor(ble): TrainerManager is now a thin CoreBluetooth adapter over TrainerSession`.

### Task 7: UI surface for reconnecting

**Files:** Modify `Skift/UI/PairingView.swift` (render `.reconnecting` like `.connecting`, with attempt count), `Skift/UI/ContentView.swift` (in the `.riding` phase, overlay a small "Reconnecting…" badge when `!isDemoMode`, matching the HUD style in `RideView.swift` — dark panel, orange accent, top-center).

- [ ] **Step 1:** Implement (SwiftUI views have no test target; keep the diff minimal and switch-exhaustive).
- [ ] **Step 2:** Build app target; expected: compiles, no warnings introduced.
- [ ] **Step 3:** Commit `feat(ui): show reconnecting state during pairing and mid-ride`.

### Task 8: Docs + full verification

**Files:** Modify `Plan.md` (move "BLE auto-reconnect" out of the backlog; add a decision-log **table row** matching Plan.md §9's pipe-delimited format: `| 2026-07-11 | Auto-reconnect: infinite exponential backoff (1→30 s cap) | Ride integrity protected by existing auto-pause |`), `README.md` feature list one-liner if it mentions reconnect gaps.

- [ ] **Step 1:** Update docs.
- [ ] **Step 2:** Full CI-equivalent run: `xcodegen generate` + build + test, all green. Report the test count delta (was 47).
- [ ] **Step 3:** Commit `docs: record BLE auto-reconnect decision and status`.
