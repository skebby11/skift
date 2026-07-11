import Foundation

/// Pure, CoreBluetooth-free BLE session state machine for a smart trainer.
///
/// Consumes user intents (`startScan`, `connect`, `disconnect`, `setGrade`)
/// and typed BLE `Event`s, and emits typed `Command`s for an adapter (see
/// `TrainerManager`) to execute against CoreBluetooth. Delays are data inside
/// commands (`scheduleReconnect(after:)`), so this type owns no timers and is
/// fully synchronous/testable: feed events, assert the command sequence and
/// the resulting state snapshot.
///
/// See `docs/ble-reliability.md` for the design and reconnect policy.
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

    // MARK: - Published snapshot

    public private(set) var state: State = .idle
    public private(set) var discovered: [DiscoveredTrainer] = []
    public private(set) var liveData = FTMS.IndoorBikeData()
    public private(set) var hasControl = false
    public private(set) var lastError: String?

    public var onCommand: ((Command) -> Void)?

    /// Identifier of the peripheral currently connected/connecting, remembered
    /// so a reconnect can target the same device.
    private var connectingID: UUID?

    /// Set by `disconnect()`, consumed by the next `didDisconnect`, so that a
    /// user-initiated drop never schedules a reconnect (rule 5).
    private var userInitiatedDisconnect = false

    /// Last grade passed to `setGrade`, resent once control is (re-)granted.
    private var lastGrade: Double?

    public init() {}

    // MARK: - User intents

    public func startScan() {
        discovered = []
        lastError = nil
        state = .scanning
        emit(.startScan)
    }

    public func stopScan() {
        emit(.stopScan)
        if state == .scanning { state = .idle }
    }

    public func connect(id: UUID, name: String) {
        connectingID = id
        state = .connecting
        emit(.stopScan)
        emit(.connect(id: id))
    }

    public func disconnect() {
        userInitiatedDisconnect = true
        emit(.cancelReconnect)
        emit(.cancelConnection)
    }

    public func setGrade(percent: Double) {
        lastGrade = percent
        if hasControl {
            emit(.write(FTMS.setIndoorBikeSimulation(gradePercent: percent)))
        }
    }

    // MARK: - BLE events

    public func handle(_ event: Event) {
        switch event {
        case .bluetoothDidBecomeAvailable:
            if case .bluetoothUnavailable = state { state = .idle }
        case let .bluetoothDidBecomeUnavailable(reason):
            state = .bluetoothUnavailable(reason: reason)
            emit(.cancelReconnect)
        case let .didDiscover(id, name, rssi):
            if let index = discovered.firstIndex(where: { $0.id == id }) {
                discovered[index] = DiscoveredTrainer(id: id, name: name, rssi: rssi)
            } else {
                discovered.append(DiscoveredTrainer(id: id, name: name, rssi: rssi))
            }
        case let .didConnect(name):
            state = .connected(name: name)
            emit(.discoverServices)
        case let .didFailToConnect(message):
            lastError = message ?? "Connection failed."
            if userInitiatedDisconnect {
                // A user disconnect can race an in-flight (re)connect attempt;
                // never continue the backoff loop once the user has bailed.
                userInitiatedDisconnect = false
                state = .idle
            } else if case let .reconnecting(name, attempt) = state {
                scheduleNextReconnectAttempt(name: name, previousAttempt: attempt)
            } else {
                state = .idle
            }
        case let .didDisconnect(message):
            if let message { lastError = message }
            if userInitiatedDisconnect {
                userInitiatedDisconnect = false
                resetToIdle()
            } else if case let .connected(name) = state {
                beginReconnecting(name: name)
            } else if case let .reconnecting(name, attempt) = state {
                scheduleNextReconnectAttempt(name: name, previousAttempt: attempt)
            } else {
                resetToIdle()
            }
        case let .didDiscoverFTMSService(found):
            if found {
                emit(.discoverCharacteristics)
            } else {
                lastError = "Connected device does not expose the FTMS service."
                emit(.cancelConnection)
            }
        case let .didDiscoverCharacteristics(indoorBikeData, controlPoint):
            if indoorBikeData && controlPoint {
                emit(.subscribeIndoorBikeData)
                emit(.subscribeControlPoint)
                emit(.write(FTMS.requestControl()))
            } else {
                lastError = "Connected device does not expose the required FTMS characteristics."
                emit(.cancelConnection)
            }
        case let .didReceiveIndoorBikeData(data):
            if let parsed = FTMS.parseIndoorBikeData(data) {
                liveData = parsed
            }
        case let .didReceiveControlPointResponse(data):
            handleControlPointResponse(data)
        case .reconnectTimerFired:
            if let id = connectingID {
                emit(.connect(id: id))
            }
        }
    }

    private func resetToIdle() {
        hasControl = false
        liveData = FTMS.IndoorBikeData()
        state = .idle
    }

    private func beginReconnecting(name: String) {
        hasControl = false
        liveData = FTMS.IndoorBikeData()
        state = .reconnecting(name: name, attempt: 1)
        emit(.scheduleReconnect(after: backoffDelay(forAttempt: 1)))
    }

    private func scheduleNextReconnectAttempt(name: String, previousAttempt: Int) {
        let attempt = previousAttempt + 1
        state = .reconnecting(name: name, attempt: attempt)
        emit(.scheduleReconnect(after: backoffDelay(forAttempt: attempt)))
    }

    /// Exponential backoff: 1, 2, 4, 8, 16, then capped at 30 s — indefinitely.
    private func backoffDelay(forAttempt attempt: Int) -> TimeInterval {
        min(pow(2.0, Double(attempt - 1)), 30)
    }

    private func handleControlPointResponse(_ data: Data) {
        guard let response = FTMS.parseControlPointResponse(data) else { return }
        if response.requestOpCode == FTMS.OpCode.requestControl.rawValue {
            hasControl = response.result == .success
            if hasControl {
                emit(.write(FTMS.startOrResume()))
                if let lastGrade {
                    emit(.write(FTMS.setIndoorBikeSimulation(gradePercent: lastGrade)))
                }
            } else {
                lastError = "Trainer refused control — is another app (e.g. Zwift) connected?"
            }
        } else if response.result != .success {
            let opcode = String(format: "0x%02X", response.requestOpCode)
            lastError = "Trainer rejected command \(opcode)."
        }
    }

    private func emit(_ command: Command) {
        onCommand?(command)
    }
}
