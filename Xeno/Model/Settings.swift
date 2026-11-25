import Foundation

enum ThemeKind: String, Codable, CaseIterable, Identifiable {
    case biolume, vfd
    var id: String { rawValue }
    var title: String { self == .biolume ? "Bioluminescent" : "Amber VFD" }
    var subtitle: String { self == .biolume ? "Organic alien-ship interface" : "Retro vacuum-fluorescent dot matrix" }
}


/// Phosphor colour of the VFD theme.
enum VFDTint: String, Codable, CaseIterable, Identifiable {
    case amber, green, teal, red, blue, white, orange
    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
    var subtitle: String {
        switch self {
        case .amber: return "CLASSIC AMBER VFD"
        case .green: return "P1 GREEN PHOSPHOR"
        case .teal: return "BLUE-GREEN VFD TUBE"
        case .red: return "RED LED DOT MATRIX"
        case .blue: return "ICE BLUE VFD"
        case .white: return "WARM WHITE FILAMENT"
        case .orange: return "NEON PLASMA ORANGE"
        }
    }
    /// Base phosphor colour, 0...1.
    var rgb: (Double, Double, Double) {
        switch self {
        case .amber: return (1.00, 0.69, 0.08)
        case .green: return (0.30, 1.00, 0.30)
        case .teal: return (0.33, 1.00, 0.85)
        case .red: return (1.00, 0.16, 0.10)
        case .blue: return (0.35, 0.75, 1.00)
        case .white: return (1.00, 0.93, 0.82)
        case .orange: return (1.00, 0.45, 0.10)
        }
    }

    /// Display palette derived from the base colour: readouts, text, labels/borders, alarm.
    var palette: [UInt8: (Double, Double, Double)] {
        let b = rgb
        func mix(_ a: (Double, Double, Double), _ c: (Double, Double, Double), _ t: Double) -> (Double, Double, Double) {
            (a.0 + (c.0 - a.0) * t, a.1 + (c.1 - a.1) * t, a.2 + (c.2 - a.2) * t)
        }
        let text = self == .white ? (1.0, 1.0, 1.0) : mix(b, (1.0, 0.96, 0.90), 0.62)
        let dim = (b.0 * 0.55, b.1 * 0.55, b.2 * 0.55)
        let alarm: (Double, Double, Double) = (self == .red || self == .orange) ? (1.0, 0.92, 0.35) : (1.0, 0.25, 0.12)
        var p: [UInt8: (Double, Double, Double)] = [1: b, 2: text, 3: dim, 4: alarm, 5: text]
        for (i, t) in VFDTint.allCases.enumerated() { p[UInt8(10 + i)] = t.rgb }
        return p
    }
}

struct XenoSettings: Codable, Equatable {
    var temperatureUnit: TemperatureUnit = .fahrenheit
    var pressureUnit: PressureUnit = .psig
    var vacuumUnit: VacuumUnit = .microns
    var staticUnit: StaticPressureUnit = .inWC
    var altitudeFt: Double = 0
    var refrigerant: String = "R-410A"
    var metering: MeteringDevice = .txv
    var targetSubcool: Double = 10
    var chargeTolerance: Double = 3
    var vacuumTarget: Double = 500
    var vacuumDecayLimit: Double = 1000
    var vacuumHoldMinutes: Double = 10
    var companyName: String = ""
    var technician: String = ""
    var license: String = ""
    var companyPhone: String = ""
    var autoAssign: Bool = true
    var demoMode: Bool = false
    var staleSeconds: Double = 20
    var keepAwake: Bool = true
    var theme: ThemeKind = .biolume
    var vfdTint: VFDTint = .amber

    var atmPsia: Double { Units.atmosphericPsia(altitudeFt: altitudeFt) }
}

/// Formatting helpers bound to the user's unit choices.
struct Fmt {
    let s: XenoSettings
    func temp(_ f: Double?) -> String { f.map { s.temperatureUnit.fromF($0).formatted(decimals: 1) } ?? "––" }
    func delta(_ f: Double?) -> String { f.map { s.temperatureUnit.deltaFromF($0).formatted(decimals: 1) } ?? "––" }
    func pressure(_ p: Double?) -> String { p.map { s.pressureUnit.fromPsig($0).formatted(decimals: s.pressureUnit.decimals) } ?? "––" }
    func vacuum(_ m: Double?) -> String {
        guard let m else { return "––" }
        let v = s.vacuumUnit.fromMicrons(m)
        return v.formatted(decimals: s.vacuumUnit == .microns ? 0 : (v < 1 ? 3 : 2))
    }
    func stat(_ v: Double?) -> String { v.map { s.staticUnit.fromInWC($0).formatted(decimals: s.staticUnit == .inWC ? 2 : 0) } ?? "––" }
    var tUnit: String { s.temperatureUnit.rawValue }
    var dUnit: String { s.temperatureUnit == .fahrenheit ? "°F" : "K" }
    var pUnit: String { s.pressureUnit.rawValue }

    /// Converts a reading to display units and returns (value, unit).
    func reading(_ r: SensorReading) -> (String, String) {
        switch r.kind {
        case .temperature, .wetBulb, .dewPoint: return (temp(r.value), tUnit)
        case .pressure: return (pressure(r.value), pUnit)
        case .vacuum: return (vacuum(r.value), s.vacuumUnit.rawValue)
        case .staticPressure: return (stat(r.value), s.staticUnit.rawValue)
        case .humidity: return (r.value.formatted(decimals: 1), "%RH")
        case .weight: return (r.value.formatted(decimals: 2), "lb")
        case .capacitance, .voltageDC: return (r.value.formatted(decimals: 2), r.kind.canonicalUnit)
        case .currentAC, .currentDC: return (r.value.formatted(decimals: 2), "A")
        default: return (r.value.formatted(decimals: 1), r.kind.canonicalUnit)
        }
    }
}
