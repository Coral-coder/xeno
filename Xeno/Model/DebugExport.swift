import Foundation
import UIKit

/// Builds a zip of everything needed to debug probe decoding remotely: raw packets, nearby
/// devices, decoded probe state, display notes, GATT logs, layouts and app/device info.
enum DebugExport {
    static func makeBundle(model: AppModel, technicianNote: String) throws -> URL {
        let fm = FileManager.default
        let stamp = DateFormatter.fileStamp.string(from: Date())
        let root = fm.temporaryDirectory.appendingPathComponent("XenoDebug-\(stamp)")
        try? fm.removeItem(at: root)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        func write(_ name: String, _ text: String) throws {
            try text.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        func json<T: Encodable>(_ name: String, _ value: T) throws {
            let e = JSONEncoder()
            e.outputFormatting = [.prettyPrinted, .sortedKeys]
            e.dateEncodingStrategy = .iso8601
            try e.encode(value).write(to: root.appendingPathComponent(name))
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02X", $0) }.joined(separator: " ") }

        let info = Bundle.main.infoDictionary ?? [:]
        let device = UIDevice.current
        try write("README.txt", """
        Xeno debug capture — \(Date().formatted(date: .long, time: .standard))
        App: \(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?"))
        Device: \(device.model) · \(device.systemName) \(device.systemVersion) · \(machine())
        Bluetooth state: \(model.bluetooth.state) · adverts/s: \(model.bluetooth.advertsPerSecond.formatted(decimals: 1))
        Demo mode: \(model.settings.demoMode)

        Technician note:
        \(technicianNote.isEmpty ? "(none)" : technicianNote)

        Files:
          display_notes.csv  what each probe's own screen showed + the raw bytes at that moment
          packets.csv        every recorded advertisement (time, peripheral, name, rssi, hex)
          devices.csv        every nearby BLE device: name, rssi, manufacturer data, service UUIDs
          probes.json        decoded probe state (model, ID, readings, raw bytes)
          layouts.json       decoder layouts in use (built-in + field overrides)
          gatt_log.txt       log of the last GATT inspection session, if any
          settings.json      units / altitude / refrigerant settings
        Manufacturer data hex includes the 2-byte company ID first (Fieldpiece = 46 50 "FP").
        """)

        var notes = "time,probe,model,display_shows,decoded,hex\n"
        for n in model.lab.notes {
            notes += "\(iso.string(from: n.date)),\(csv(n.probe)),\(csv(n.model)),\(csv(n.displayShows)),\(csv(n.decoded)),\(n.hex)\n"
        }
        try write("display_notes.csv", notes)
        try write("packets.csv", model.lab.csv())

        var devices = "last_seen,peripheral,name,rssi,connectable,manufacturer_hex,services\n"
        for d in model.bluetooth.devices.values.sorted(by: { $0.rssi > $1.rssi }) {
            devices += "\(iso.string(from: d.lastSeen)),\(d.id.uuidString),\(csv(d.name ?? "")),\(d.rssi),\(d.connectable),\(hex(d.manufacturer)),\(csv(d.services.joined(separator: " ")))\n"
        }
        try write("devices.csv", devices)

        struct ProbeDump: Encodable {
            var key, vendor, model, typeCode, serial, nickname, rawHex: String
            var firmware: String?
            var battery: Int?
            var rssi, packets: Int
            var lastSeen: Date
            var readings: [SensorReading]
            var roles: [String]
            var historyPoints: Int
        }
        try json("probes.json", model.probes.probes.map { p in
            ProbeDump(key: p.key, vendor: p.vendor, model: p.model, typeCode: p.typeCode, serial: p.serial, nickname: p.nickname,
                      rawHex: hex(p.raw), firmware: p.firmware, battery: p.battery, rssi: p.rssi, packets: p.packets,
                      lastSeen: p.lastSeen, readings: p.readings, roles: model.probes.roles(of: p).map(\.rawValue),
                      historyPoints: p.history.values.reduce(0) { $0 + $1.count })
        })
        var layouts = FieldpieceLayouts.builtIn
        layouts.merge(model.lab.overrides) { _, o in o }
        try json("layouts.json", layouts)
        try json("settings.json", model.settings)
        try write("gatt_log.txt", model.bluetooth.gatt.map { g in
            "Device: \(g.name)\n" + g.characteristics.values.map { "\($0.id) [\($0.properties)] svc \($0.service) last=\(hex($0.lastValue))" }.joined(separator: "\n")
                + "\n\n" + g.lines.map { "\(iso.string(from: $0.date)) \($0.text)" }.joined(separator: "\n")
        } ?? "No GATT session.\n")

        return try zipDirectory(root)
    }

    /// Zips a directory using the system's built-in archiver (NSFileCoordinator .forUploading).
    static func zipDirectory(_ dir: URL) throws -> URL {
        var result: URL?
        var copyError: Error?
        var coordError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: dir, options: .forUploading, error: &coordError) { tmp in
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(dir.lastPathComponent + ".zip")
            try? FileManager.default.removeItem(at: dest)
            do { try FileManager.default.copyItem(at: tmp, to: dest); result = dest } catch { copyError = error }
        }
        if let coordError { throw coordError }
        if let copyError { throw copyError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        return result
    }

    private static func csv(_ s: String) -> String {
        s.contains(",") || s.contains("\"") || s.contains("\n") ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }

    private static func machine() -> String {
        var u = utsname(); uname(&u)
        return withUnsafeBytes(of: &u.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}

extension DateFormatter {
    static let fileStamp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
}
