import Foundation
import CoreBluetooth

/// A trainer found while scanning, as shown in the pairing list.
public struct DiscoveredTrainer: Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let rssi: Int
}

/// Connects to a smart trainer over BLE FTMS: streams live ride data and
/// controls resistance through simulation parameters.
///
/// This is a thin CoreBluetooth adapter: all session logic (handshake,
/// error handling, auto-reconnect with backoff) lives in the pure
/// `TrainerSession` state machine. This type only translates
/// `CBCentralManagerDelegate`/`CBPeripheralDelegate` callbacks into session
/// `Event`s and executes session `Command`s against CoreBluetooth — it makes
/// no decisions of its own. See `docs/ble-reliability.md` for the design.
///
/// REVIEW (to verify on the Van Rysel D500 during hardware testing):
/// - whether the D500 requires Start/Resume after Request Control, or accepts
///   simulation parameters straight away;
/// - behaviour when another app (Zwift) already holds control;
/// - REVIEW: whether a stale `CBPeripheral` reference retrieved via
///   `retrievePeripherals(withIdentifiers:)` during a reconnect attempt is
///   still connectable (trainer power-cycle, radio re-pairing, etc.) is
///   unverified — see docs/ble-reliability.md §REVIEW.
public final class TrainerManager: NSObject, ObservableObject {

    /// `TrainerSession.State` is the single source of truth for connection
    /// state; kept as a typealias so existing call sites (and most of the
    /// UI) compile unchanged.
    public typealias ConnectionState = TrainerSession.State

    @Published public private(set) var state: ConnectionState = .idle
    @Published public private(set) var discovered: [DiscoveredTrainer] = []
    @Published public private(set) var liveData = FTMS.IndoorBikeData()
    @Published public private(set) var hasControl = false
    @Published public private(set) var lastError: String?

    private let session = TrainerSession()

    private var central: CBCentralManager!
    private var trainer: CBPeripheral?
    private var ftmsService: CBService?
    private var indoorBikeDataCharacteristic: CBCharacteristic?
    private var controlPointCharacteristic: CBCharacteristic?

    /// Cancellable stand-in for the session's `scheduleReconnect`/`cancelReconnect`
    /// commands: the session has no timers of its own (see `TrainerSession`),
    /// so the adapter is the one thing that actually waits.
    private var reconnectWorkItem: DispatchWorkItem?

    private let serviceUUID = CBUUID(string: FTMS.serviceUUID)
    private let indoorBikeDataUUID = CBUUID(string: FTMS.indoorBikeDataUUID)
    private let controlPointUUID = CBUUID(string: FTMS.controlPointUUID)

    public override init() {
        super.init()
        session.onCommand = { [weak self] command in
            self?.execute(command)
        }
        // Main queue keeps all delegate callbacks and @Published updates on
        // the main thread; fine at FTMS data rates (a few notifications/s).
        central = CBCentralManager(delegate: self, queue: .main)
        syncFromSession()
    }

    // MARK: - Public API

    public func startScan() {
        session.startScan()
        syncFromSession()
    }

    public func stopScan() {
        session.stopScan()
        syncFromSession()
    }

    public func connect(_ device: DiscoveredTrainer) {
        // Must go through the session's intent (not a direct CB `connect`)
        // so it remembers the target for reconnect attempts.
        session.connect(id: device.id, name: device.name)
        syncFromSession()
    }

    public func disconnect() {
        session.disconnect()
        syncFromSession()
    }

    /// Sends a slope to the trainer via FTMS SIM mode.
    public func setGrade(percent: Double) {
        session.setGrade(percent: percent)
        syncFromSession()
    }

    /// Sends a power target to the trainer via FTMS ERG mode.
    public func setTargetPower(watts: Int) {
        session.setTargetPower(watts: watts)
        syncFromSession()
    }

    // MARK: - Command execution (session → CoreBluetooth)

    private func execute(_ command: TrainerSession.Command) {
        switch command {
        case .startScan:
            central.scanForPeripherals(withServices: [serviceUUID])

        case .stopScan:
            central.stopScan()

        case let .connect(id):
            guard let target = central.retrievePeripherals(withIdentifiers: [id]).first else {
                // REVIEW: real-hardware behavior of a stale CBPeripheral
                // reference (e.g. after a power-cycle) during a reconnect
                // attempt is unverified — see docs/ble-reliability.md §REVIEW.
                // Feeding back a failure keeps the backoff loop going instead
                // of leaving the session stuck mid-connect.
                session.handle(.didFailToConnect(message: "Trainer is no longer reachable — scan again."))
                syncFromSession()
                return
            }
            trainer = target
            target.delegate = self
            central.connect(target)

        case .cancelConnection:
            if let trainer {
                central.cancelPeripheralConnection(trainer)
            }

        case .discoverServices:
            trainer?.discoverServices([serviceUUID])

        case .discoverCharacteristics:
            if let ftmsService {
                trainer?.discoverCharacteristics([indoorBikeDataUUID, controlPointUUID], for: ftmsService)
            }

        case .subscribeIndoorBikeData:
            if let indoorBikeDataCharacteristic {
                trainer?.setNotifyValue(true, for: indoorBikeDataCharacteristic)
            }

        case .subscribeControlPoint:
            if let controlPointCharacteristic {
                trainer?.setNotifyValue(true, for: controlPointCharacteristic)
            }

        case let .write(data):
            if let trainer, let controlPointCharacteristic {
                trainer.writeValue(data, for: controlPointCharacteristic, type: .withResponse)
            }

        case let .scheduleReconnect(after):
            reconnectWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.session.handle(.reconnectTimerFired)
                self?.syncFromSession()
            }
            reconnectWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + after, execute: workItem)

        case .cancelReconnect:
            reconnectWorkItem?.cancel()
            reconnectWorkItem = nil
        }
    }

    // MARK: - Snapshot sync

    /// Copies the session's snapshot into the `@Published` properties,
    /// assigning only when the value changed to avoid redundant SwiftUI
    /// invalidation.
    private func syncFromSession() {
        if state != session.state { state = session.state }
        if discovered != session.discovered { discovered = session.discovered }
        if liveData != session.liveData { liveData = session.liveData }
        if hasControl != session.hasControl { hasControl = session.hasControl }
        if lastError != session.lastError { lastError = session.lastError }
    }
}

// MARK: - CBCentralManagerDelegate

extension TrainerManager: CBCentralManagerDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            session.handle(.bluetoothDidBecomeAvailable)
        case .poweredOff:
            session.handle(.bluetoothDidBecomeUnavailable(reason: "Bluetooth is turned off."))
        case .unauthorized:
            session.handle(.bluetoothDidBecomeUnavailable(
                reason: "Bluetooth access denied — allow Skift in System Settings → Privacy & Security → Bluetooth."
            ))
        case .unsupported:
            session.handle(.bluetoothDidBecomeUnavailable(reason: "This Mac does not support Bluetooth LE."))
        default:
            break
        }
        syncFromSession()
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? "Unknown trainer"
        session.handle(.didDiscover(id: peripheral.identifier, name: name, rssi: RSSI.intValue))
        syncFromSession()
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        session.handle(.didConnect(name: peripheral.name ?? "Trainer"))
        syncFromSession()
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        session.handle(.didFailToConnect(message: error?.localizedDescription))
        syncFromSession()
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        ftmsService = nil
        indoorBikeDataCharacteristic = nil
        controlPointCharacteristic = nil
        session.handle(.didDisconnect(message: error?.localizedDescription))
        syncFromSession()
    }
}

// MARK: - CBPeripheralDelegate

extension TrainerManager: CBPeripheralDelegate {

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let service = peripheral.services?.first(where: { $0.uuid == serviceUUID })
        ftmsService = service
        session.handle(.didDiscoverFTMSService(found: service != nil))
        syncFromSession()
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        var foundIndoorBikeData = false
        var foundControlPoint = false
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case indoorBikeDataUUID:
                indoorBikeDataCharacteristic = characteristic
                foundIndoorBikeData = true
            case controlPointUUID:
                controlPointCharacteristic = characteristic
                foundControlPoint = true
            default:
                break
            }
        }
        session.handle(.didDiscoverCharacteristics(indoorBikeData: foundIndoorBikeData, controlPoint: foundControlPoint))
        syncFromSession()
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, let data = characteristic.value else { return }
        switch characteristic.uuid {
        case indoorBikeDataUUID:
            session.handle(.didReceiveIndoorBikeData(data))
        case controlPointUUID:
            session.handle(.didReceiveControlPointResponse(data))
        default:
            return
        }
        syncFromSession()
    }
}
