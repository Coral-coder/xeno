import Foundation

/// Data-driven decoder for Fieldpiece Job Link (JL3) and SMAN Bluetooth broadcasts.
///
/// Fieldpiece probes broadcast their readings in BLE manufacturer data — no connection is
/// needed. Layout (offsets as iOS delivers the bytes, company ID included):
///
///   0–1   "FP" (0x46 0x50, company ID 0x5046)
///   2–3   device type, two ASCII letters ("BF" = JL3PC …)
///   4–5   firmware major, minor
///   6–7   probe ID (shown on the probe label, hex)
///   8…    readings, little-endian int16, scaled per model; −30000 / 0x7FFF = no reading
///
/// Layouts per model live in `FieldpieceLayouts.builtIn`. Any of them can be replaced at run
/// time (Probe Lab in the app) by a user-verified `ModelLayout`, so a firmware change or a new
/// model can be supported in the field without an app update.
struct FieldpieceDecoder: ProbeAdvertDecoder {
    static let companyID: UInt16 = 0x5046
    let vendor = "Fieldpiece"
    var overrides: [String: ModelLayout] = [:]

    func layout(for typeCode: String) -> ModelLayout? {
        overrides[typeCode] ?? FieldpieceLayouts.builtIn[typeCode]
    }

    static func isFieldpiece(_ d: [UInt8]) -> Bool { d.count >= 8 && d[0] == 0x46 && d[1] == 0x50 }

    func decode(manufacturerData d: [UInt8], localName: String?) -> ProbeAdvert? {
        guard Self.isFieldpiece(d) else { return nil }
        let typeCode = String(bytes: d[2...3], encoding: .ascii) ?? String(format: "%02X%02X", d[2], d[3])
        let serial = String(format: "%02X%02X", d[6], d[7])
        let firmware = "\(d[4]).\(d[5])"
        guard let layout = layout(for: typeCode) else {
            return ProbeAdvert(vendor: vendor, model: Self.modelGuess(localName) ?? "FP-\(typeCode)", typeCode: typeCode, serial: serial,
                               firmware: firmware, category: .unknown, battery: nil, readings: [], raw: d)
        }
        var readings: [SensorReading] = []
        if layout.special == .clampMeter {
            readings = Self.decodeClampMeter(d)
        } else {
            for field in layout.fields {
                if let v = field.value(in: d) { readings.append(SensorReading(kind: field.kind, label: field.label, value: v)) }
            }
        }
        var battery: Int?
        if let b = layout.batteryOffset, b < d.count, d[b] <= 100 { battery = Int(d[b]) }
        return ProbeAdvert(vendor: vendor, model: layout.model, typeCode: typeCode, serial: serial, firmware: firmware,
                           category: layout.category, battery: battery, readings: readings, raw: d)
    }

    static func modelGuess(_ name: String?) -> String? {
        guard let n = name?.trimmingCharacters(in: .whitespaces), !n.isEmpty else { return nil }
        return n
    }

    /// SC680-style two-channel meter: value int16, range byte (÷10^range), mode byte.
    static func decodeClampMeter(_ d: [UInt8]) -> [SensorReading] {
        var out: [SensorReading] = []
        func channel(_ o: Int, modes: [UInt8: SensorKind], label: String) {
            guard o + 3 < d.count else { return }
            let raw = Int16(bitPattern: UInt16(d[o]) | UInt16(d[o + 1]) << 8)
            guard raw != 0x7FFF, let kind = modes[d[o + 3]] else { return }
            let v = Double(raw) / pow(10, Double(d[o + 2]))
            out.append(SensorReading(kind: kind, label: label, value: v))
        }
        channel(13, modes: [0x02: .voltageAC, 0x07: .voltageDC, 0x09: .frequency, 0x0E: .capacitance, 0x10: .resistance, 0x14: .temperature, 0x1A: .powerFactor], label: "Meter")
        channel(19, modes: [0x03: .currentAC, 0x05: .currentDC, 0x0C: .voltageAC, 0x13: .temperature, 0x19: .power], label: "Clamp")
        return out
    }
}

enum FieldEncoding: String, Codable, CaseIterable, Identifiable {
    case int16LE, uint16LE, int16BE, uint16BE, uint8
    var id: String { rawValue }
    var width: Int { self == .uint8 ? 1 : 2 }
}

enum FieldTransform: String, Codable, CaseIterable, Identifiable {
    case none
    case celsiusToF          // value is °C
    case kPaGaugeToPsig      // value is kPa gauge
    case kPaAbsToPsig        // value is kPa absolute (sea-level atmosphere subtracted)
    case pascalToInWC
    var id: String { rawValue }
}

struct FieldLayout: Codable, Hashable, Identifiable {
    var label: String
    var kind: SensorKind
    var offset: Int
    var encoding: FieldEncoding = .int16LE
    /// Raw value is divided by this.
    var divisor: Double = 10
    var transform: FieldTransform = .none
    var id: String { "\(label)@\(offset)" }

    func rawValue(in d: [UInt8]) -> Int? {
        guard offset >= 0, offset + encoding.width <= d.count else { return nil }
        let a = d[offset]
        switch encoding {
        case .uint8: return Int(a)
        case .int16LE: return Int(Int16(bitPattern: UInt16(a) | UInt16(d[offset + 1]) << 8))
        case .uint16LE: return Int(UInt16(a) | UInt16(d[offset + 1]) << 8)
        case .int16BE: return Int(Int16(bitPattern: UInt16(a) << 8 | UInt16(d[offset + 1])))
        case .uint16BE: return Int(UInt16(a) << 8 | UInt16(d[offset + 1]))
        }
    }

    func value(in d: [UInt8]) -> Double? {
        guard let raw = rawValue(in: d) else { return nil }
        if raw == -30000 || raw == 0x7FFF || (encoding == .uint16LE && raw == 0xFFFF) { return nil }
        let v = Double(raw) / (divisor == 0 ? 1 : divisor)
        switch transform {
        case .none: return v
        case .celsiusToF: return Units.cToF(v)
        case .kPaGaugeToPsig: return v / Units.kPaPerPsi
        case .kPaAbsToPsig: return v / Units.kPaPerPsi - Units.seaLevelPsia
        case .pascalToInWC: return v / 249.0889
        }
    }
}

struct ModelLayout: Codable, Hashable {
    enum Special: String, Codable { case clampMeter }
    var typeCode: String
    var model: String
    var category: ProbeCategory
    var fields: [FieldLayout]
    var batteryOffset: Int?
    var special: Special?
    /// How the layout is known: shown in Probe Lab so the tech knows what to verify.
    var provenance: String
}

enum FieldpieceLayouts {
    static let builtIn: [String: ModelLayout] = {
        let list: [ModelLayout] = [
            ModelLayout(typeCode: "BF", model: "JL3PC", category: .pipeClamp,
                        fields: [FieldLayout(label: "Pipe", kind: .temperature, offset: 13)],
                        batteryOffset: nil, provenance: "Verified against JL3PC hardware (two independent sources)."),
            ModelLayout(typeCode: "BT", model: "SM480V", category: .manifold,
                        fields: [FieldLayout(label: "Low side", kind: .pressure, offset: 8),
                                 FieldLayout(label: "High side", kind: .pressure, offset: 10),
                                 FieldLayout(label: "Suction line", kind: .temperature, offset: 12),
                                 FieldLayout(label: "Liquid line", kind: .temperature, offset: 14)],
                        batteryOffset: nil, provenance: "Verified against an SM480V display."),
            ModelLayout(typeCode: "BG", model: "JL3PR", category: .pressure,
                        fields: [FieldLayout(label: "Pressure", kind: .pressure, offset: 15, divisor: 1, transform: .kPaGaugeToPsig)],
                        batteryOffset: 22, provenance: "Community-decoded, unverified — confirm against the probe display in Probe Lab."),
            ModelLayout(typeCode: "BH", model: "JL3RH", category: .psychrometer,
                        fields: [FieldLayout(label: "Dry bulb", kind: .temperature, offset: 13),
                                 FieldLayout(label: "Wet bulb", kind: .wetBulb, offset: 15),
                                 FieldLayout(label: "Dew point", kind: .dewPoint, offset: 17),
                                 FieldLayout(label: "Humidity", kind: .humidity, offset: 19)],
                        batteryOffset: 24, provenance: "Community-decoded, unverified — confirm in Probe Lab."),
            ModelLayout(typeCode: "BX", model: "JL3KM", category: .manometer,
                        fields: [FieldLayout(label: "Supply", kind: .staticPressure, offset: 8, divisor: 100),
                                 FieldLayout(label: "Return", kind: .staticPressure, offset: 10, divisor: 100),
                                 FieldLayout(label: "Differential", kind: .staticPressure, offset: 13, divisor: 100)],
                        batteryOffset: nil, provenance: "Community-decoded static pressure layout, unverified."),
            ModelLayout(typeCode: "BO", model: "SRS3", category: .scale,
                        fields: [FieldLayout(label: "Weight", kind: .weight, offset: 10, encoding: .uint16LE, divisor: 100)],
                        batteryOffset: 16, provenance: "Community-decoded, unverified."),
            ModelLayout(typeCode: "CB", model: "SC680", category: .multimeter, fields: [],
                        batteryOffset: nil, special: .clampMeter, provenance: "Community-decoded mode/range layout."),
        ]
        return Dictionary(uniqueKeysWithValues: list.map { ($0.typeCode, $0) })
    }()
}
