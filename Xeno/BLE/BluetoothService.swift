import CoreBluetooth
import Foundation
import Observation

/// Listens for probe broadcasts. Fieldpiece Job Link probes put their readings in the
/// advertisement itself, so we scan continuously with duplicates allowed and never connect.
/// `GATTSession` handles connectable probes (other brands / older models) for exploration.
@Observable
final class BluetoothService: NSObject {
    enum State: Equatable { case unknown, poweredOff, unauthorized, unsupported, scanning, idle }
    private(set) var state: State = .unknown
    private(set) var advertsPerSecond: Double = 0
    /// Every nearby BLE device (for the explorer).
    private(set) var devices: [UUID: SeenDevice] = [:]

    struct SeenDevice: Identifiable, Hashable {
        let id: UUID
        var name: String?
        var rssi: Int
        var lastSeen: Date
        var manufacturer: [UInt8]
        var services: [String]
        var connectable: Bool
    }

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var counter = 0
    @ObservationIgnored private var counterStart = Date()
    @ObservationIgnored private(set) var peripherals: [UUID: CBPeripheral] = [:]
    var gatt: GATTSession?

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func start() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: true])
        } else {
            scan()
        }
    }

    func scan() {
        guard let central, central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        state = .scanning
    }

    func stop() {
        central?.stopScan()
        state = .idle
    }

    func connect(_ id: UUID) {
        guard let central, let p = peripherals[id] else { return }
        gatt?.disconnect()
        let session = GATTSession(peripheral: p, central: central)
        gatt = session
        central.connect(p)
    }

    func disconnectGATT() {
        gatt?.disconnect()
        gatt = nil
    }
}

extension BluetoothService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: scan()
        case .poweredOff: state = .poweredOff
        case .unauthorized: state = .unauthorized
        case .unsupported: state = .unsupported
        default: state = .unknown
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let rssi = RSSI.intValue
        guard rssi != 127 else { return }
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
        let mfg = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data).map { [UInt8]($0) } ?? []
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map(\.uuidString) ?? []
        let connectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? false
        peripherals[peripheral.identifier] = peripheral

        counter += 1
        let elapsed = Date().timeIntervalSince(counterStart)
        if elapsed > 2 { advertsPerSecond = Double(counter) / elapsed; counter = 0; counterStart = Date() }

        var dev = devices[peripheral.identifier] ?? SeenDevice(id: peripheral.identifier, name: name, rssi: rssi, lastSeen: .now, manufacturer: mfg, services: services, connectable: connectable)
        if let name { dev.name = name }
        dev.rssi = rssi; dev.lastSeen = .now
        if !mfg.isEmpty { dev.manufacturer = mfg }
        if !services.isEmpty { dev.services = services }
        dev.connectable = connectable
        devices[peripheral.identifier] = dev

        guard let model, !mfg.isEmpty else { return }
        model.lab.capture(bytes: mfg, name: name, rssi: rssi, peripheral: peripheral.identifier)
        let decoders: [ProbeAdvertDecoder] = [model.decoder]
        for decoder in decoders {
            if let ad = decoder.decode(manufacturerData: mfg, localName: name) {
                model.probes.ingest(ad, rssi: rssi)
                break
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        gatt?.didConnect()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        gatt?.log("Connect failed: \(error?.localizedDescription ?? "unknown")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        gatt?.log("Disconnected\(error.map { ": \($0.localizedDescription)" } ?? "")")
        gatt?.connected = false
    }
}

/// Connects to one peripheral, discovers everything, subscribes to every notify/indicate
/// characteristic and logs the bytes — for decoding new probe types.
@Observable
final class GATTSession: NSObject, CBPeripheralDelegate {
    struct Line: Identifiable, Hashable { let id = UUID(); let date: Date; let text: String }
    struct Characteristic: Identifiable, Hashable {
        let id: String
        let service: String
        var properties: String
        var lastValue: [UInt8]
    }

    let name: String
    var connected = false
    private(set) var lines: [Line] = []
    private(set) var characteristics: [String: Characteristic] = [:]
    private let peripheral: CBPeripheral
    @ObservationIgnored private weak var central: CBCentralManager?

    init(peripheral: CBPeripheral, central: CBCentralManager) {
        self.peripheral = peripheral
        self.central = central
        self.name = peripheral.name ?? peripheral.identifier.uuidString
        super.init()
        peripheral.delegate = self
        log("Connecting to \(name)…")
    }

    func log(_ s: String) {
        lines.append(Line(date: .now, text: s))
        if lines.count > 2000 { lines.removeFirst(200) }
    }

    func didConnect() {
        connected = true
        log("Connected. Discovering services…")
        peripheral.discoverServices(nil)
    }

    func disconnect() {
        central?.cancelPeripheralConnection(peripheral)
    }

    func read(_ id: String) {
        guard let c = find(id) else { return }
        peripheral.readValue(for: c)
    }

    func write(_ id: String, hex: String) {
        guard let c = find(id) else { return }
        let clean = hex.replacingOccurrences(of: " ", with: "")
        var bytes: [UInt8] = []
        var i = clean.startIndex
        while i < clean.endIndex, let j = clean.index(i, offsetBy: 2, limitedBy: clean.endIndex) {
            if let b = UInt8(clean[i..<j], radix: 16) { bytes.append(b) }
            i = j
        }
        let type: CBCharacteristicWriteType = c.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(Data(bytes), for: c, type: type)
        log("→ \(c.uuid.uuidString): \(bytes.map { String(format: "%02X", $0) }.joined(separator: " "))")
    }

    private func find(_ id: String) -> CBCharacteristic? {
        peripheral.services?.flatMap { $0.characteristics ?? [] }.first { $0.uuid.uuidString == id }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for s in peripheral.services ?? [] {
            log("Service \(s.uuid.uuidString)")
            peripheral.discoverCharacteristics(nil, for: s)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            var props: [String] = []
            if c.properties.contains(.read) { props.append("read") }
            if c.properties.contains(.write) { props.append("write") }
            if c.properties.contains(.writeWithoutResponse) { props.append("writeNR") }
            if c.properties.contains(.notify) { props.append("notify") }
            if c.properties.contains(.indicate) { props.append("indicate") }
            characteristics[c.uuid.uuidString] = Characteristic(id: c.uuid.uuidString, service: service.uuid.uuidString, properties: props.joined(separator: " "), lastValue: [])
            log("  Char \(c.uuid.uuidString) [\(props.joined(separator: ","))]")
            if c.properties.contains(.notify) || c.properties.contains(.indicate) { peripheral.setNotifyValue(true, for: c) }
            if c.properties.contains(.read) { peripheral.readValue(for: c) }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let bytes = characteristic.value.map { [UInt8]($0) } ?? []
        characteristics[characteristic.uuid.uuidString]?.lastValue = bytes
        let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        let ascii = String(bytes: bytes.map { (32...126).contains($0) ? $0 : 46 }, encoding: .ascii) ?? ""
        log("← \(characteristic.uuid.uuidString): \(hex)  \(ascii)")
    }
}
