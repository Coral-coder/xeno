import Foundation

/// Moist-air properties (ASHRAE Fundamentals, Hyland–Wexler saturation pressure).
/// Inputs in °F / %RH, barometric pressure in psia. Results in °F, gr/lb, BTU/lb.
struct AirState: Equatable {
    let dryBulbF: Double
    let relativeHumidity: Double   // 0–100
    let pressurePsia: Double

    var wetBulbF: Double { Psychrometrics.wetBulbF(dryBulbF: dryBulbF, rh: relativeHumidity, psia: pressurePsia) }
    var dewPointF: Double { Psychrometrics.dewPointF(dryBulbF: dryBulbF, rh: relativeHumidity) }
    /// lb water / lb dry air
    var humidityRatio: Double { Psychrometrics.humidityRatio(dryBulbF: dryBulbF, rh: relativeHumidity, psia: pressurePsia) }
    var grainsPerLb: Double { humidityRatio * 7000 }
    /// BTU per lb dry air
    var enthalpy: Double { Psychrometrics.enthalpy(dryBulbF: dryBulbF, w: humidityRatio) }
}

enum Psychrometrics {
    /// Saturation vapour pressure over water/ice, psia.
    static func saturationPressurePsia(tempF: Double) -> Double {
        let t = (tempF + 459.67) // Rankine
        let lnP: Double
        if tempF < 32 {
            lnP = -1.0214165e4 / t - 4.8932428 - 5.3765794e-3 * t + 1.9202377e-7 * t * t
                + 3.5575832e-10 * pow(t, 3) - 9.0344688e-14 * pow(t, 4) + 4.1635019 * log(t)
        } else {
            lnP = -1.0440397e4 / t - 1.1294650e1 - 2.7022355e-2 * t + 1.2890360e-5 * t * t
                - 2.4780681e-9 * pow(t, 3) + 6.5459673 * log(t)
        }
        return exp(lnP)
    }

    static func humidityRatio(dryBulbF: Double, rh: Double, psia: Double) -> Double {
        let pw = max(0, min(100, rh)) / 100 * saturationPressurePsia(tempF: dryBulbF)
        return 0.621945 * pw / (psia - pw)
    }

    static func enthalpy(dryBulbF: Double, w: Double) -> Double {
        0.240 * dryBulbF + w * (1061 + 0.444 * dryBulbF)
    }

    static func dewPointF(dryBulbF: Double, rh: Double) -> Double {
        let pw = max(0.0001, min(100, rh)) / 100 * saturationPressurePsia(tempF: dryBulbF)
        // Bisection on the saturation curve.
        var lo = -80.0, hi = dryBulbF
        for _ in 0..<60 {
            let mid = (lo + hi) / 2
            if saturationPressurePsia(tempF: mid) < pw { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    /// Humidity ratio from dry bulb and wet bulb (thermodynamic wet bulb, ASHRAE eq. 35 in IP).
    static func humidityRatio(dryBulbF db: Double, wetBulbF wb: Double, psia: Double) -> Double {
        let pws = saturationPressurePsia(tempF: wb)
        let ws = 0.621945 * pws / (psia - pws)
        if wb >= 32 {
            return ((1093 - 0.556 * wb) * ws - 0.240 * (db - wb)) / (1093 + 0.444 * db - wb)
        }
        return ((1220 - 0.04 * wb) * ws - 0.240 * (db - wb)) / (1220 + 0.444 * db - 0.48 * wb)
    }

    static func wetBulbF(dryBulbF db: Double, rh: Double, psia: Double) -> Double {
        let w = humidityRatio(dryBulbF: db, rh: rh, psia: psia)
        var lo = -40.0, hi = db
        for _ in 0..<60 {
            let mid = (lo + hi) / 2
            if humidityRatio(dryBulbF: db, wetBulbF: mid, psia: psia) < w { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    static func relativeHumidity(dryBulbF db: Double, wetBulbF wb: Double, psia: Double) -> Double {
        let w = max(0, humidityRatio(dryBulbF: db, wetBulbF: wb, psia: psia))
        let pw = w * psia / (0.621945 + w)
        return min(100, max(0, pw / saturationPressurePsia(tempF: db) * 100))
    }

    /// Standard-air density correction factor for the 1.08 / 4.5 / 0.68 constants.
    static func airDensityRatio(psia: Double) -> Double { psia / Units.seaLevelPsia }
}
