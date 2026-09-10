import Foundation
import CoreBluetooth

struct BLEDevice: Identifiable, Hashable {
    let id: UUID
    var name: String
    var rssi: Int
    var connected: Bool
    var selected: Bool
}

final class BluetoothSensorManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var devices: [BLEDevice] = []
    @Published var scanning = false
    @Published var bluetoothStatus = "Bluetooth starting…"
    @Published var heartRate = 0
    @Published var cadence = 0
    @Published var power = 0
    @Published var wheelSpeedMps = 0.0
    @Published var heartSource = "--"
    @Published var cadenceSource = "--"
    @Published var powerSource = "--"

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var lastWheel: (revs: UInt32, time: UInt16)?
    private var lastCrank: (revs: UInt16, time: UInt16)?
    var wheelCircumferenceMeters = 2.096

    private let hrService = CBUUID(string: "180D")
    private let cscService = CBUUID(string: "1816")
    private let powerService = CBUUID(string: "1818")
    private let hrMeasurement = CBUUID(string: "2A37")
    private let cscMeasurement = CBUUID(string: "2A5B")
    private let powerMeasurement = CBUUID(string: "2A63")

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: bluetoothStatus = "Ready to scan"
        case .poweredOff: bluetoothStatus = "Bluetooth is off"
        case .unauthorized: bluetoothStatus = "Bluetooth permission denied"
        case .unsupported: bluetoothStatus = "Bluetooth LE unavailable"
        default: bluetoothStatus = "Bluetooth unavailable"
        }
    }

    func startScan() {
        guard central.state == .poweredOn else { bluetoothStatus = "Turn Bluetooth on"; return }
        scanning = true
        bluetoothStatus = "Scanning nearby devices…"
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func stopScan() {
        central.stopScan(); scanning = false
        bluetoothStatus = devices.contains(where: \.connected) ? "Selected sensors connected" : "Scan stopped"
    }

    func toggle(_ id: UUID) {
        guard let i = devices.firstIndex(where: { $0.id == id }) else { return }
        devices[i].selected.toggle()
    }

    func connectSelected() {
        let targets = devices.filter(\.selected)
        for item in targets where !item.connected {
            if let peripheral = peripherals[item.id] { central.connect(peripheral, options: nil) }
        }
        bluetoothStatus = targets.isEmpty ? "Select one or more sensors" : "Connecting \(targets.count) selected device(s)…"
    }

    func disconnect(_ id: UUID) {
        if let p = peripherals[id] { central.cancelPeripheralConnection(p) }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let advertised = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertised ?? peripheral.name ?? "Bluetooth device"
        peripherals[peripheral.identifier] = peripheral
        if let i = devices.firstIndex(where: { $0.id == peripheral.identifier }) {
            devices[i].rssi = RSSI.intValue
            if devices[i].name == "Bluetooth device" { devices[i].name = name }
        } else {
            devices.append(BLEDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue, connected: false, selected: false))
            devices.sort { $0.rssi > $1.rssi }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([hrService, cscService, powerService])
        setConnected(peripheral.identifier, true)
        bluetoothStatus = "Connected to \(peripheral.name ?? "sensor")"
        if devices.filter(\.selected).allSatisfy(\.connected) { stopScan() }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        setConnected(peripheral.identifier, false)
        bluetoothStatus = "Connection failed: \(error?.localizedDescription ?? "retry")"
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        setConnected(peripheral.identifier, false)
        bluetoothStatus = "Sensor disconnected"
    }

    private func setConnected(_ id: UUID, _ value: Bool) {
        if let i = devices.firstIndex(where: { $0.id == id }) { devices[i].connected = value }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        peripheral.services?.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] where characteristic.uuid == hrMeasurement || characteristic.uuid == cscMeasurement || characteristic.uuid == powerMeasurement {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, error == nil else { return }
        let bytes = [UInt8](data)
        if characteristic.uuid == hrMeasurement { parseHeart(bytes, peripheral: peripheral) }
        else if characteristic.uuid == cscMeasurement { parseCSC(bytes, peripheral: peripheral) }
        else if characteristic.uuid == powerMeasurement { parsePower(bytes, peripheral: peripheral) }
    }

    private func parseHeart(_ b: [UInt8], peripheral: CBPeripheral) {
        guard b.count >= 2 else { return }
        heartRate = b[0] & 1 == 0 ? Int(b[1]) : (b.count >= 3 ? Int(UInt16(b[1]) | UInt16(b[2]) << 8) : 0)
        heartSource = peripheral.name ?? "BLE HR"
    }

    private func parsePower(_ b: [UInt8], peripheral: CBPeripheral) {
        guard b.count >= 4 else { return }
        power = Int(Int16(bitPattern: UInt16(b[2]) | UInt16(b[3]) << 8))
        powerSource = peripheral.name ?? "BLE Power"
    }

    private func parseCSC(_ b: [UInt8], peripheral: CBPeripheral) {
        guard !b.isEmpty else { return }
        var offset = 1
        if b[0] & 1 != 0, b.count >= offset + 6 {
            let revs = u32(b, offset), event = u16(b, offset + 4); offset += 6
            if let last = lastWheel {
                let dr = revs &- last.revs, dt = event &- last.time
                if dt > 0 && dt < 30_720 { wheelSpeedMps = Double(dr) * wheelCircumferenceMeters / (Double(dt) / 1024.0) }
            }
            lastWheel = (revs, event)
        }
        if b[0] & 2 != 0, b.count >= offset + 4 {
            let revs = u16(b, offset), event = u16(b, offset + 2)
            if let last = lastCrank {
                let dr = revs &- last.revs, dt = event &- last.time
                if dt > 0 && dt < 30_720 { cadence = Int((Double(dr) * 60 * 1024 / Double(dt)).rounded()) }
            }
            lastCrank = (revs, event); cadenceSource = peripheral.name ?? "BLE Cadence"
        }
    }

    private func u16(_ b: [UInt8], _ o: Int) -> UInt16 { UInt16(b[o]) | UInt16(b[o+1]) << 8 }
    private func u32(_ b: [UInt8], _ o: Int) -> UInt32 { UInt32(b[o]) | UInt32(b[o+1]) << 8 | UInt32(b[o+2]) << 16 | UInt32(b[o+3]) << 24 }
}

