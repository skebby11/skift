import Foundation

/// A heart-rate strap found while scanning, as shown in the pairing list.
public struct DiscoveredSensor: Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let rssi: Int

    public init(id: UUID, name: String, rssi: Int) {
        self.id = id
        self.name = name
        self.rssi = rssi
    }
}

/// Pure, CoreBluetooth-free BLE session state machine for a heart-rate
/// strap (BLE Heart Rate Service, `0x180D`). Mirrors `TrainerSession`'s
/// event/command style, sized down to HRS's read-only simplicity: no
/// control-point handshake, and a different reconnect policy.
///
/// See docs/hr-strap.md for the design and reconnect policy.
public final class HeartRateSession {

    public enum State: Equatable {
        case bluetoothUnavailable(reason: String)
        case idle
        case scanning
        case connecting
        case connected(name: String)
        case reconnecting(name: String)
    }

    public enum Event: Equatable {
        case bluetoothDidBecomeAvailable
        case bluetoothDidBecomeUnavailable(reason: String)
        case didDiscover(id: UUID, name: String, rssi: Int)
        case didConnect(name: String)
        case didFailToConnect(message: String?)
        case didDisconnect(message: String?)
        /// Whether the Heart Rate Measurement characteristic was found.
        /// Unlike FTMS's Indoor Bike Data / Control Point (both optional),
        /// HRS's Heart Rate Measurement characteristic is mandatory on the
        /// service that advertises it, so a single found/not-found event
        /// covers both "no HRS service" and "no measurement characteristic"
        /// — the adapter reports whichever it discovers first.
        case didDiscoverMeasurementCharacteristic(found: Bool)
        case didReceiveMeasurement(Data)
    }

    public enum Command: Equatable {
        case startScan
        case stopScan
        case connect(id: UUID)
        case cancelConnection
        case discoverServices
        case discoverCharacteristics
        case subscribeMeasurement
    }

    // MARK: - Published snapshot

    public private(set) var state: State = .idle
    public private(set) var discovered: [DiscoveredSensor] = []
    public private(set) var bpm: Int?
    public private(set) var lastError: String?

    public var onCommand: ((Command) -> Void)?

    /// Identifier of the peripheral currently connected/connecting, remembered
    /// so a reconnect can target the same device.
    private var connectingID: UUID?

    /// Set by `disconnect()`, consumed by the next `didDisconnect`, so that a
    /// user-initiated drop never triggers a reconnect (rule below).
    private var userInitiatedDisconnect = false

    public init() {}

    // MARK: - User intents

    public func startScan() {
        if case .bluetoothUnavailable = state { return }
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
        emit(.cancelConnection)
    }

    // MARK: - BLE events

    public func handle(_ event: Event) {
        switch event {
        case .bluetoothDidBecomeAvailable:
            if case .bluetoothUnavailable = state { state = .idle }
        case let .bluetoothDidBecomeUnavailable(reason):
            bpm = nil
            state = .bluetoothUnavailable(reason: reason)
        case let .didDiscover(id, name, rssi):
            if let index = discovered.firstIndex(where: { $0.id == id }) {
                discovered[index] = DiscoveredSensor(id: id, name: name, rssi: rssi)
            } else {
                discovered.append(DiscoveredSensor(id: id, name: name, rssi: rssi))
            }
        case let .didConnect(name):
            state = .connected(name: name)
            emit(.discoverServices)
        case let .didFailToConnect(message):
            lastError = message ?? "Connection failed."
            if userInitiatedDisconnect {
                userInitiatedDisconnect = false
                state = .idle
            } else if case let .reconnecting(name) = state {
                // DECISION: no backoff here — a pending CoreBluetooth
                // `connect(_:)` call never times out and completes whenever
                // the strap reappears, so there is nothing to schedule.
                // Re-emitting `.connect(id)` just keeps the pending
                // connection registered after a rare hard failure.
                state = .reconnecting(name: name)
                if let connectingID { emit(.connect(id: connectingID)) }
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
            } else if case let .reconnecting(name) = state {
                beginReconnecting(name: name)
            } else {
                resetToIdle()
            }
        case let .didDiscoverMeasurementCharacteristic(found):
            if found {
                emit(.subscribeMeasurement)
            } else {
                lastError = "Connected device does not expose the Heart Rate Measurement characteristic."
                emit(.cancelConnection)
            }
        case let .didReceiveMeasurement(data):
            if let parsed = HRS.parseHeartRateMeasurement(data) {
                bpm = parsed
            }
        }
    }

    private func resetToIdle() {
        bpm = nil
        state = .idle
    }

    /// DECISION: no attempt counter, no backoff — straps drop and return
    /// constantly as people move, and there is no resistance-control
    /// handshake to redo, so the adapter's single pending `connect(_:)` call
    /// is left to complete whenever CoreBluetooth reconnects it. See
    /// docs/hr-strap.md.
    private func beginReconnecting(name: String) {
        bpm = nil
        state = .reconnecting(name: name)
        if let connectingID { emit(.connect(id: connectingID)) }
    }

    private func emit(_ command: Command) {
        onCommand?(command)
    }
}
