import Foundation

/// Canonical internal units: °F, psig, microns, inWC, %RH, lb, volts, amps.
/// Everything shown on screen is converted at display time with these helpers.

enum TemperatureUnit: String, CaseIterable, Codable, Identifiable {
    case fahrenheit = "°F", celsius = "°C"
    var id: String { rawValue }
    func fromF(_ f: Double) -> Double { self == .fahrenheit ? f : (f - 32) * 5 / 9 }
    func toF(_ v: Double) -> Double { self == .fahrenheit ? v : v * 9 / 5 + 32 }
    /// Converts a temperature *difference* (superheat, ΔT) from °F.
    func deltaFromF(_ d: Double) -> Double { self == .fahrenheit ? d : d * 5 / 9 }
}

enum PressureUnit: String, CaseIterable, Codable, Identifiable {
    case psig = "psig", kPa = "kPa", bar = "bar", mpa = "MPa"
    var id: String { rawValue }
    func fromPsig(_ p: Double) -> Double {
        switch self {
        case .psig: return p
        case .kPa: return p * Units.kPaPerPsi
        case .bar: return p * Units.kPaPerPsi / 100
        case .mpa: return p * Units.kPaPerPsi / 1000
        }
    }
    func toPsig(_ v: Double) -> Double {
        switch self {
        case .psig: return v
        case .kPa: return v / Units.kPaPerPsi
        case .bar: return v * 100 / Units.kPaPerPsi
        case .mpa: return v * 1000 / Units.kPaPerPsi
        }
    }
    var decimals: Int { self == .mpa ? 3 : (self == .bar ? 2 : 1) }
}

enum VacuumUnit: String, CaseIterable, Codable, Identifiable {
    case microns = "microns", pascal = "Pa", mbar = "mbar", torr = "Torr", inHg = "inHg"
    var id: String { rawValue }
    func fromMicrons(_ m: Double) -> Double {
        switch self {
        case .microns: return m
        case .pascal: return m * 0.133322
        case .mbar: return m * 0.00133322
        case .torr: return m / 1000
        case .inHg: return m / 25400
        }
    }
}

enum StaticPressureUnit: String, CaseIterable, Codable, Identifiable {
    case inWC = "inWC", pascal = "Pa", mmWC = "mmWC"
    var id: String { rawValue }
    func fromInWC(_ v: Double) -> Double {
        switch self {
        case .inWC: return v
        case .pascal: return v * 249.0889
        case .mmWC: return v * 25.4
        }
    }
    func toInWC(_ v: Double) -> Double {
        switch self {
        case .inWC: return v
        case .pascal: return v / 249.0889
        case .mmWC: return v / 25.4
        }
    }
}

enum Units {
    static let kPaPerPsi = 6.894757
    static let seaLevelPsia = 14.6959

    /// Barometric pressure (psia) at an altitude in feet (standard atmosphere).
    static func atmosphericPsia(altitudeFt: Double) -> Double {
        seaLevelPsia * pow(1 - 6.8754e-6 * altitudeFt, 5.2559)
    }

    static func fToC(_ f: Double) -> Double { (f - 32) * 5 / 9 }
    static func cToF(_ c: Double) -> Double { c * 9 / 5 + 32 }

    /// Absolute pressure in microns of mercury → psia.
    static func micronsToPsia(_ m: Double) -> Double { m / 51714.9 }
    static func psiaToMicrons(_ p: Double) -> Double { p * 51714.9 }
}

extension Double {
    func formatted(decimals: Int) -> String { String(format: "%.\(decimals)f", self) }
}
