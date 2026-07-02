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
/// Handshake on connect: discover the FTMS service, subscribe to Indoor Bike
/// Data notifications and Control Point indications, then Request Control and
/// Start/Resume. Simulation commands only take effect once control is granted.
public final class TrainerManager: NSObject, ObservableObject {

    public enum ConnectionState: Equatable {
        case bluetoothUnavailable(reason: String)
        case idle
        case scanning
        case connecting
        case connected(name: String)
    }

    @Published public private(set) var state: ConnectionState = .idle
    @Published public private(set) var discovered: [DiscoveredTrainer] = []
    @Published public private(set) var liveData = FTMS.IndoorBikeData()
    @Published public private(set) var hasControl = false
    @Published public private(set) var lastError: String?

    private var central: CBCentralManager!
    private var trainer: CBPeripheral?
    private var controlPoint: CBCharacteristic?

    private let serviceUUID = CBUUID(string: FTMS.serviceUUID)
    private let indoorBikeDataUUID = CBUUID(string: FTMS.indoorBikeDataUUID)
    private let controlPointUUID = CBUUID(string: FTMS.controlPointUUID)

    public override init() {
        super.init()
        // Main queue keeps all delegate callbacks and @Published updates on
        // the main thread; fine at FTMS data rates (a few notifications/s).
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Public API

    public func startScan() {
        guard central.state == .poweredOn else { return }
        discovered = []
        lastError = nil
        state = .scanning
        central.scanForPeripherals(withServices: [serviceUUID])
    }

    public func stopScan() {
        central.stopScan()
        if state == .scanning { state = .idle }
    }

    public func connect(_ device: DiscoveredTrainer) {
        guard let target = central.retrievePeripherals(withIdentifiers: [device.id]).first else {
            lastError = "Trainer is no longer reachable — scan again."
            return
        }
        central.stopScan()
        state = .connecting
        trainer = target
        target.delegate = self
        central.connect(target)
    }

    public func disconnect() {
        guard let trainer else { return }
        central.cancelPeripheralConnection(trainer)
    }

    /// Sends a slope to the trainer via FTMS SIM mode.
    public func setGrade(percent: Double) {
        send(FTMS.setIndoorBikeSimulation(gradePercent: percent))
    }

    private func send(_ command: Data) {
        guard let trainer, let controlPoint else { return }
        trainer.writeValue(command, for: controlPoint, type: .withResponse)
    }

    private func resetConnection() {
        trainer = nil
        controlPoint = nil
        hasControl = false
        liveData = FTMS.IndoorBikeData()
        state = .idle
    }
}

// MARK: - CBCentralManagerDelegate

extension TrainerManager: CBCentralManagerDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if case .bluetoothUnavailable = state { state = .idle }
        case .poweredOff:
            state = .bluetoothUnavailable(reason: "Bluetooth is turned off.")
        case .unauthorized:
            state = .bluetoothUnavailable(
                reason: "Bluetooth access denied — allow Skift in System Settings → Privacy & Security → Bluetooth."
            )
        case .unsupported:
            state = .bluetoothUnavailable(reason: "This Mac does not support Bluetooth LE.")
        default:
            break
        }
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
        let found = DiscoveredTrainer(id: peripheral.identifier, name: name, rssi: RSSI.intValue)
        if let index = discovered.firstIndex(where: { $0.id == found.id }) {
            discovered[index] = found
        } else {
            discovered.append(found)
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        state = .connected(name: peripheral.name ?? "Trainer")
        peripheral.discoverServices([serviceUUID])
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        lastError = error?.localizedDescription ?? "Connection failed."
        resetConnection()
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        if let error {
            lastError = error.localizedDescription
        }
        resetConnection()
    }
}

// MARK: - CBPeripheralDelegate

extension TrainerManager: CBPeripheralDelegate {

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            lastError = "Connected device does not expose the FTMS service."
            disconnect()
            return
        }
        peripheral.discoverCharacteristics([indoorBikeDataUUID, controlPointUUID], for: service)
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case indoorBikeDataUUID:
                peripheral.setNotifyValue(true, for: characteristic)
            case controlPointUUID:
                controlPoint = characteristic
                // Command responses arrive as indications on this characteristic.
                peripheral.setNotifyValue(true, for: characteristic)
                peripheral.writeValue(FTMS.requestControl(), for: characteristic, type: .withResponse)
            default:
                break
            }
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, let data = characteristic.value else { return }
        switch characteristic.uuid {
        case indoorBikeDataUUID:
            if let parsed = FTMS.parseIndoorBikeData(data) {
                liveData = parsed
            }
        case controlPointUUID:
            handleControlPointResponse(data)
        default:
            break
        }
    }

    private func handleControlPointResponse(_ data: Data) {
        guard let response = FTMS.parseControlPointResponse(data) else { return }
        if response.requestOpCode == FTMS.OpCode.requestControl.rawValue {
            hasControl = response.result == .success
            if hasControl {
                send(FTMS.startOrResume())
            } else {
                lastError = "Trainer refused control — is another app (e.g. Zwift) connected?"
            }
        } else if response.result != .success {
            let opcode = String(format: "0x%02X", response.requestOpCode)
            lastError = "Trainer rejected command \(opcode)."
        }
    }
}
