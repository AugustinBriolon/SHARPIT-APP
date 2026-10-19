import Combine
import CoreBluetooth
import Foundation

/// Bluetooth SIG Heart Rate Measurement characteristic (0x2A37) payload → bpm.
enum HeartRateMeasurement {
    static func parseBpm(_ data: Data) -> Int? {
        guard let flags = data.first else { return nil }
        let isUint16 = (flags & 0x01) != 0
        if isUint16 {
            guard data.count >= 3 else { return nil }
            let value = UInt16(data[1]) | (UInt16(data[2]) << 8)
            return Int(value)
        }
        guard data.count >= 2 else { return nil }
        return Int(data[1])
    }
}

/// Scans / connects a standard BLE heart-rate strap and publishes live bpm.
///
/// `CBCentralManager` runs on the main queue; published fields are updated on main.
final class GuidedHeartRateMonitor: NSObject, ObservableObject {
    struct Device: Identifiable, Equatable {
        let id: UUID
        let name: String
    }

    enum Status: Equatable {
        case idle
        case unavailable
        case unauthorized
        case scanning
        case connecting
        case connected
    }

    @Published private(set) var bpm: Int?
    @Published private(set) var status: Status = .idle
    @Published private(set) var peripheralName: String?
    @Published private(set) var devices: [Device] = []

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var measurementCharacteristic: CBCharacteristic?
    private var knownPeripherals: [UUID: CBPeripheral] = [:]
    private var wantsRunning = false
    /// Resume path: reconnect last peripheral without waiting for picker selection.
    private var preferLastPeripheral = false

    /// Session appear — reconnect only when the athlete already opted in.
    func startIfEnabled() {
        guard GuidedHeartRatePreference.isEnabled else {
            stop()
            return
        }
        wantsRunning = true
        preferLastPeripheral = true
        ensureCentral()
    }

    /// Picker sheet — scan and list devices; never auto-connects the first hit.
    func startScanningForPicker() {
        wantsRunning = true
        preferLastPeripheral = false
        devices = []
        knownPeripherals = [:]
        if let peripheral {
            knownPeripherals[peripheral.identifier] = peripheral
            upsertDevice(peripheral, name: Self.displayName(for: peripheral))
        }
        ensureCentral()
        if central?.state == .poweredOn {
            beginScanKeepingConnection()
        }
    }

    /// Sheet dismissed — stop advertising scan; keep an active link if any.
    func endPickerScan() {
        central?.stopScan()
        if peripheral != nil, status == .connected || status == .connecting {
            return
        }
        if GuidedHeartRatePreference.isEnabled {
            preferLastPeripheral = true
            reconnectOrScan()
            return
        }
        stop()
    }

    func connect(to id: UUID) {
        let target = knownPeripherals[id]
            ?? central?.retrievePeripherals(withIdentifiers: [id]).first
        guard let target else { return }
        GuidedHeartRatePreference.setEnabled(true)
        wantsRunning = true
        preferLastPeripheral = false
        if let peripheral, peripheral.identifier != id {
            if let measurementCharacteristic {
                peripheral.setNotifyValue(false, for: measurementCharacteristic)
            }
            central?.cancelPeripheralConnection(peripheral)
            self.peripheral = nil
            self.measurementCharacteristic = nil
            bpm = nil
        }
        connect(target)
    }

    func disconnectAndDisable() {
        GuidedHeartRatePreference.setEnabled(false)
        GuidedHeartRatePreference.lastPeripheralUUID = nil
        stop()
    }

    func stop() {
        wantsRunning = false
        preferLastPeripheral = false
        if let peripheral, let measurementCharacteristic {
            peripheral.setNotifyValue(false, for: measurementCharacteristic)
        }
        if let peripheral {
            central?.cancelPeripheralConnection(peripheral)
        }
        central?.stopScan()
        peripheral = nil
        measurementCharacteristic = nil
        knownPeripherals = [:]
        devices = []
        bpm = nil
        peripheralName = nil
        status = .idle
    }

    private func ensureCentral() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else {
            handleCentralState(central?.state ?? .unknown)
        }
    }

    private func handleCentralState(_ state: CBManagerState) {
        guard wantsRunning else { return }
        switch state {
        case .poweredOn:
            reconnectOrScan()
        case .unauthorized:
            status = .unauthorized
        case .unsupported, .poweredOff, .resetting, .unknown:
            status = .unavailable
        @unknown default:
            status = .unavailable
        }
    }

    private func reconnectOrScan() {
        if preferLastPeripheral,
           let id = GuidedHeartRatePreference.lastPeripheralUUID,
           let known = central?.retrievePeripherals(withIdentifiers: [id]).first {
            connect(known)
            return
        }
        beginScanKeepingConnection()
    }

    private func beginScanKeepingConnection() {
        if status != .connected, status != .connecting {
            status = .scanning
        }
        central?.scanForPeripherals(
            withServices: [CBUUID(string: "180D")],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func connect(_ peripheral: CBPeripheral) {
        central?.stopScan()
        self.peripheral = peripheral
        knownPeripherals[peripheral.identifier] = peripheral
        peripheral.delegate = self
        peripheralName = Self.displayName(for: peripheral)
        status = .connecting
        upsertDevice(peripheral, name: Self.displayName(for: peripheral))
        central?.connect(peripheral, options: nil)
    }

    private func upsertDevice(_ peripheral: CBPeripheral, name: String) {
        knownPeripherals[peripheral.identifier] = peripheral
        let device = Device(id: peripheral.identifier, name: name)
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            if devices[index].name != device.name {
                devices[index] = device
            }
        } else {
            devices.append(device)
            devices.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    static func displayName(for peripheral: CBPeripheral) -> String {
        let raw = peripheral.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? String(localized: "Capteur sans nom") : raw
    }
}

extension GuidedHeartRateMonitor: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        handleCentralState(central.state)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard wantsRunning else { return }
        let label: String = {
            if let name = peripheral.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                return name
            }
            if let local = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
                let trimmed = local.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            return String(localized: "Capteur sans nom")
        }()
        upsertDevice(peripheral, name: label)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        GuidedHeartRatePreference.lastPeripheralUUID = peripheral.identifier
        status = .connected
        peripheralName = Self.displayName(for: peripheral)
        peripheral.discoverServices([CBUUID(string: "180D")])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        self.peripheral = nil
        if preferLastPeripheral {
            reconnectOrScan()
        } else if wantsRunning {
            beginScanKeepingConnection()
        } else {
            status = .idle
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        bpm = nil
        measurementCharacteristic = nil
        self.peripheral = nil
        peripheralName = nil
        guard wantsRunning else {
            status = .idle
            return
        }
        if preferLastPeripheral {
            reconnectOrScan()
        } else {
            beginScanKeepingConnection()
        }
    }
}

extension GuidedHeartRateMonitor: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let serviceUUID = CBUUID(string: "180D")
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else { return }
        peripheral.discoverCharacteristics([CBUUID(string: "2A37")], for: service)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        let measurementUUID = CBUUID(string: "2A37")
        guard let characteristic = service.characteristics?
            .first(where: { $0.uuid == measurementUUID })
        else { return }
        measurementCharacteristic = characteristic
        peripheral.setNotifyValue(true, for: characteristic)
        peripheral.readValue(for: characteristic)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard Self.isHeartRateMeasurement(characteristic.uuid),
              let data = characteristic.value,
              let bpm = HeartRateMeasurement.parseBpm(data)
        else { return }
        self.bpm = bpm
        status = .connected
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil,
              Self.isHeartRateMeasurement(characteristic.uuid),
              characteristic.isNotifying
        else { return }
        peripheral.readValue(for: characteristic)
    }

    private static func isHeartRateMeasurement(_ uuid: CBUUID) -> Bool {
        uuid == CBUUID(string: "2A37") || uuid.uuidString.uppercased().hasSuffix("2A37")
    }
}
