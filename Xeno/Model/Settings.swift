import Foundation

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
