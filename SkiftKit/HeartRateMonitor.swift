import Foundation
import CoreBluetooth

/// Connects to a BLE heart-rate strap (Heart Rate Service, `0x180D`) and
/// streams live bpm.
///
/// This is a thin CoreBluetooth adapter: all session logic (state machine,
/// error handling, the pending-connect reconnect policy) lives in the pure
/// `HeartRateSession` state machine. This type only translates
/// `CBCentralManagerDelegate`/`CBPeripheralDelegate` callbacks into session
/// `Event`s and executes session `Command`s against CoreBluetooth — it makes
/// no decisions of its own. See `docs/hr-strap.md` for the design.
///
/// Owns its own `CBCentralManager`, separate from `TrainerManager`'s, so the
/// trainer and the strap can be scanned/connected independently.
public final class HeartRateMonitor: NSObject, ObservableObject {

    /// `HeartRateSession.State` is the single source of truth for connection
    /// state; kept as a typealias so call sites compile unchanged if the
    /// session type is renamed.
    public typealias ConnectionState = HeartRateSession.State

    @Published public private(set) var state: ConnectionState = .idle
    @Published public private(set) var discovered: [DiscoveredSensor] = []
    @Published public private(set) var bpm: Int?
    @Published public private(set) var lastError: String?

    private let session = HeartRateSession()

    private var central: CBCentralManager!
    private var strap: CBPeripheral?
    private var hrsService: CBService?
    private var measurementCharacteristic: CBCharacteristic?

    private let serviceUUID = CBUUID(string: HRS.serviceUUID)
    private let measurementUUID = CBUUID(string: HRS.measurementUUID)

    public override init() {
        super.init()
        session.onCommand = { [weak self] command in
            self?.execute(command)
        }
        // Main queue keeps all delegate callbacks and @Published updates on
        // the main thread; fine at HRS data rates (about 1 notification/s).
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

    public func connect(_ device: DiscoveredSensor) {
        // Must go through the session's intent (not a direct CB `connect`)
        // so it remembers the target for the reconnect policy.
        session.connect(id: device.id, name: device.name)
        syncFromSession()
    }

    public func disconnect() {
        session.disconnect()
        syncFromSession()
    }

    /// Reconnects to a strap remembered from a previous launch (see
    /// `RiderSettings.hrStrapIDKey`). The real name isn't known until
    /// CoreBluetooth resolves the peripheral on `didConnect`; the session
    /// doesn't depend on the placeholder being meaningful until then.
    public func connectRemembered(id: UUID) {
        session.connect(id: id, name: "Remembered heart rate strap")
        syncFromSession()
    }

    // MARK: - Command execution (session → CoreBluetooth)

    private func execute(_ command: HeartRateSession.Command) {
        switch command {
        case .startScan:
            central.scanForPeripherals(withServices: [serviceUUID])

        case .stopScan:
            central.stopScan()

        case let .connect(id):
            guard let target = central.retrievePeripherals(withIdentifiers: [id]).first else {
                session.handle(.didFailToConnect(message: "Strap is no longer reachable — scan again."))
                syncFromSession()
                return
            }
            strap = target
            target.delegate = self
            central.connect(target)

        case .cancelConnection:
            if let strap {
                central.cancelPeripheralConnection(strap)
            }

        case .discoverServices:
            strap?.discoverServices([serviceUUID])

        case .discoverCharacteristics:
            if let hrsService {
                strap?.discoverCharacteristics([measurementUUID], for: hrsService)
            }

        case .subscribeMeasurement:
            if let measurementCharacteristic {
                strap?.setNotifyValue(true, for: measurementCharacteristic)
            }
        }
    }

    // MARK: - Snapshot sync

    /// Copies the session's snapshot into the `@Published` properties,
    /// assigning only when the value changed to avoid redundant SwiftUI
    /// invalidation.
    private func syncFromSession() {
        if state != session.state { state = session.state }
        if discovered != session.discovered { discovered = session.discovered }
        if bpm != session.bpm { bpm = session.bpm }
        if lastError != session.lastError { lastError = session.lastError }
    }
}

// MARK: - CBCentralManagerDelegate

extension HeartRateMonitor: CBCentralManagerDelegate {

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
            ?? "Unknown heart rate strap"
        session.handle(.didDiscover(id: peripheral.identifier, name: name, rssi: RSSI.intValue))
        syncFromSession()
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        session.handle(.didConnect(name: peripheral.name ?? "Heart rate strap"))
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
        hrsService = nil
        measurementCharacteristic = nil
        session.handle(.didDisconnect(message: error?.localizedDescription))
        syncFromSession()
    }
}

// MARK: - CBPeripheralDelegate

extension HeartRateMonitor: CBPeripheralDelegate {

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let service = peripheral.services?.first(where: { $0.uuid == serviceUUID })
        hrsService = service
        if service != nil {
            // Mechanical continuation, not a decision: HRS's Heart Rate
            // Measurement characteristic is mandatory on this service, so
            // finding the service just means "keep looking" — the session
            // only needs to know the final found/not-found answer (see
            // `HeartRateSession.Event.didDiscoverMeasurementCharacteristic`).
            execute(.discoverCharacteristics)
        } else {
            session.handle(.didDiscoverMeasurementCharacteristic(found: false))
            syncFromSession()
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        let characteristic = service.characteristics?.first(where: { $0.uuid == measurementUUID })
        measurementCharacteristic = characteristic
        session.handle(.didDiscoverMeasurementCharacteristic(found: characteristic != nil))
        syncFromSession()
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, let data = characteristic.value, characteristic.uuid == measurementUUID else { return }
        session.handle(.didReceiveMeasurement(data))
        syncFromSession()
    }
}
