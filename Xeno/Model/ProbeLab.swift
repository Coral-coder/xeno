import Foundation
import Observation

/// Raw advertisement capture and user-verified decoder layouts ("Probe Lab").
@Observable
final class ProbeLab {
    struct Packet: Identifiable, Hashable {
        let id = UUID()
        let date: Date
        let peripheral: UUID?
        let name: String?
        let rssi: Int
        let bytes: [UInt8]
        var hex: String { bytes.map { String(format: "%02X", $0) }.joined(separator: " ") }
    }

    /// Latest raw packet per Fieldpiece type+serial (or peripheral for other vendors).
    private(set) var latest: [String: Packet] = [:]
    private(set) var log: [Packet] = []
    var recording = false
    var showAllVendors = false
    var overrides: [String: ModelLayout] = [:] { didSet { save() } }
    /// "The probe display shows X" notes captured next to the raw bytes — the key data for
    /// decoding a probe remotely.
    private(set) var notes: [DisplayNote] = []

    struct DisplayNote: Codable, Identifiable, Hashable {
        var id = UUID()
        var date = Date()
        var probe: String
        var model: String
        var displayShows: String
        var hex: String
        var decoded: String
    }

    func addNote(probe: String, model: String, displayShows: String, bytes: [UInt8], decoded: String) {
        notes.append(DisplayNote(probe: probe, model: model, displayShows: displayShows,
                                 hex: bytes.map { String(format: "%02X", $0) }.joined(separator: " "), decoded: decoded))
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: "xeno.layoutOverrides"),
           let o = try? JSONDecoder().decode([String: ModelLayout].self, from: data) { overrides = o }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(overrides) { UserDefaults.standard.set(data, forKey: "xeno.layoutOverrides") }
    }

    func capture(bytes: [UInt8], name: String?, rssi: Int, peripheral: UUID?) {
        let isFP = FieldpieceDecoder.isFieldpiece(bytes)
        guard isFP || showAllVendors else { return }
        let key = isFP ? String(format: "FP.%02X%02X.%02X%02X", bytes[2], bytes[3], bytes[6], bytes[7]) : (peripheral?.uuidString ?? name ?? "?")
        let p = Packet(date: .now, peripheral: peripheral, name: name, rssi: rssi, bytes: bytes)
        if latest[key]?.bytes != bytes || recording { latest[key] = p }
        if recording {
            log.append(p)
            if log.count > 20000 { log.removeFirst(1000) }
        }
    }

    func clear() { latest.removeAll(); log.removeAll(); notes.removeAll() }

    func layout(for typeCode: String) -> ModelLayout? { overrides[typeCode] ?? FieldpieceLayouts.builtIn[typeCode] }

    func csv() -> String {
        var s = "time,peripheral,name,rssi,hex\n"
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for p in log.isEmpty ? Array(latest.values) : log {
            s += "\(f.string(from: p.date)),\(p.peripheral?.uuidString ?? ""),\(p.name ?? ""),\(p.rssi),\(p.hex)\n"
        }
        return s
    }

    func exportLayouts() -> String {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? String(data: e.encode(overrides), encoding: .utf8)) ?? "{}"
    }

    func importLayouts(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8), let o = try? JSONDecoder().decode([String: ModelLayout].self, from: data) else { return false }
        overrides.merge(o) { _, new in new }
        return true
    }
}
