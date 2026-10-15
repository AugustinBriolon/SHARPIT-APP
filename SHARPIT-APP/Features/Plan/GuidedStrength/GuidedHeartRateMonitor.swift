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

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var measurementCharacteristic: CBCharacteristic?
    private var wantsRunning = false

    func startIfEnabled() {
        guard GuidedHeartRatePreference.isEnabled else {
            stop()
            return
        }
        wantsRunning = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else {
            handleCentralState(central?.state ?? .unknown)
        }
    }

    func stop() {
        wantsRunning = false
        if let peripheral, let measurementCharacteristic {
            peripheral.setNotifyValue(false, for: measurementCharacteristic)
        }
        if let peripheral {
            central?.cancelPeripheralConnection(peripheral)
        }
        central?.stopScan()
        peripheral = nil
        measurementCharacteristic = nil
        bpm = nil
        peripheralName = nil
        status = .idle
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
        if let id = GuidedHeartRatePreference.lastPeripheralUUID,
           let known = central?.retrievePeripherals(withIdentifiers: [id]).first {
            connect(known)
            return
        }
        status = .scanning
        central?.scanForPeripherals(
            withServices: [CBUUID(string: "180D")],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func connect(_ peripheral: CBPeripheral) {
        central?.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        peripheralName = peripheral.name
        status = .connecting
        central?.connect(peripheral, options: nil)
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
        guard wantsRunning, self.peripheral == nil else { return }
        connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        GuidedHeartRatePreference.lastPeripheralUUID = peripheral.identifier
        status = .connected
        peripheralName = peripheral.name
        peripheral.discoverServices([CBUUID(string: "180D")])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        self.peripheral = nil
        reconnectOrScan()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        bpm = nil
        measurementCharacteristic = nil
        self.peripheral = nil
        guard wantsRunning else {
            status = .idle
            return
        }
        reconnectOrScan()
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
        // Some straps only push after an initial read.
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
