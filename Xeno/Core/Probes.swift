import Foundation

/// What a probe channel measures. Values are stored in canonical units (see Units.swift).
enum SensorKind: String, Codable, CaseIterable, Identifiable {
    case pressure, temperature, humidity, wetBulb, dewPoint, vacuum, staticPressure, weight
    case voltageAC, voltageDC, currentAC, currentDC, resistance, capacitance, frequency, power, powerFactor
    case carbonMonoxide, raw

    var id: String { rawValue }
    var title: String {
        switch self {
        case .pressure: return "Pressure"
        case .temperature: return "Temperature"
        case .humidity: return "Humidity"
        case .wetBulb: return "Wet bulb"
        case .dewPoint: return "Dew point"
        case .vacuum: return "Vacuum"
        case .staticPressure: return "Static pressure"
        case .weight: return "Weight"
        case .voltageAC: return "Voltage AC"
        case .voltageDC: return "Voltage DC"
        case .currentAC: return "Current AC"
        case .currentDC: return "Current DC"
        case .resistance: return "Resistance"
        case .capacitance: return "Capacitance"
        case .frequency: return "Frequency"
        case .power: return "Power"
        case .powerFactor: return "Power factor"
        case .carbonMonoxide: return "CO"
        case .raw: return "Raw"
        }
    }
    /// Canonical unit symbol.
    var canonicalUnit: String {
        switch self {
        case .pressure: return "psig"
        case .temperature, .wetBulb, .dewPoint: return "°F"
        case .humidity: return "%RH"
        case .vacuum: return "microns"
        case .staticPressure: return "inWC"
        case .weight: return "lb"
        case .voltageAC: return "VAC"
        case .voltageDC: return "VDC"
        case .currentAC, .currentDC: return "A"
        case .resistance: return "Ω"
        case .capacitance: return "µF"
        case .frequency: return "Hz"
        case .power: return "W"
        case .powerFactor: return "%"
        case .carbonMonoxide: return "ppm"
        case .raw: return ""
        }
    }
}

struct SensorReading: Codable, Hashable, Identifiable {
    var kind: SensorKind
    var label: String
    var value: Double
    var id: String { "\(kind.rawValue).\(label)" }
}

enum ProbeCategory: String, Codable, CaseIterable {
    case pressure, pipeClamp, psychrometer, manifold, manometer, vacuum, scale, multimeter, combustion, unknown

    var title: String {
        switch self {
        case .pressure: return "Pressure probe"
        case .pipeClamp: return "Pipe clamp"
        case .psychrometer: return "Psychrometer"
        case .manifold: return "Manifold"
        case .manometer: return "Manometer"
        case .vacuum: return "Vacuum gauge"
        case .scale: return "Refrigerant scale"
        case .multimeter: return "Clamp meter"
        case .combustion: return "Combustion"
        case .unknown: return "Unknown"
        }
    }
    var symbol: String {
        switch self {
        case .pressure: return "gauge.with.dots.needle.67percent"
        case .pipeClamp: return "thermometer.medium"
        case .psychrometer: return "humidity"
        case .manifold: return "gauge.with.needle"
        case .manometer: return "wind"
        case .vacuum: return "arrow.down.to.line.compact"
        case .scale: return "scalemass"
        case .multimeter: return "bolt"
        case .combustion: return "flame"
        case .unknown: return "questionmark.circle"
        }
    }
}

/// One decoded broadcast from a probe.
struct ProbeAdvert: Equatable {
    var vendor: String
    var model: String
    var typeCode: String
    var serial: String
    var firmware: String?
    var category: ProbeCategory
    var battery: Int?
    var readings: [SensorReading]
    var raw: [UInt8]
    /// Stable identity independent of the iOS peripheral UUID.
    var key: String { "\(vendor).\(typeCode).\(serial)" }
}

/// A decoder for one family of probes. Add other HVAC brands by conforming to this.
protocol ProbeAdvertDecoder {
    var vendor: String { get }
    /// Manufacturer data as iOS delivers it (company ID in the first two bytes).
    func decode(manufacturerData: [UInt8], localName: String?) -> ProbeAdvert?
}
