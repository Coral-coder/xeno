import Foundation

/// Saturation table for one refrigerant (see RefrigerantData.swift, generated from CoolProp).
struct RefrigerantTable: Identifiable, Hashable {
    let name: String
    let safetyClass: String
    let oil: String
    let use: String
    let startC: Int
    let bubbleKPa: [Double]
    let dewKPa: [Double]

    var id: String { name }
    var minF: Double { Units.cToF(Double(startC)) }
    var maxF: Double { Units.cToF(Double(startC + bubbleKPa.count - 1)) }

    /// True for zeotropic blends (bubble and dew differ by > 1 °F at 40 °F).
    var hasGlide: Bool { abs(glideF(atPsig: satPsig(tempF: 40, side: .dew, atmPsia: Units.seaLevelPsia), atmPsia: Units.seaLevelPsia) ?? 0) > 1 }

    enum Side: String, Codable { case bubble, dew }

    /// Saturation pressure (psig) at a temperature. Dew for superheat, bubble for subcool.
    func satPsig(tempF: Double, side: Side, atmPsia: Double) -> Double {
        let table = side == .bubble ? bubbleKPa : dewKPa
        let x = Units.fToC(tempF) - Double(startC)
        let i = max(0, min(table.count - 2, Int(floor(x))))
        let f = x - Double(i)
        // Interpolate ln(P) — saturation curves are close to exponential in T.
        let lp = log(table[i]) + (log(table[i + 1]) - log(table[i])) * f
        return exp(lp) / Units.kPaPerPsi - atmPsia
    }

    /// Saturation temperature (°F) at a gauge pressure. Nil when outside the table.
    func satTempF(psig: Double, side: Side, atmPsia: Double) -> Double? {
        let table = side == .bubble ? bubbleKPa : dewKPa
        let kPa = (psig + atmPsia) * Units.kPaPerPsi
        guard kPa > 0, let first = table.first, let last = table.last else { return nil }
        // Allow a small extrapolation below the table (deep vacuum readings would be nonsense anyway).
        if kPa < first * 0.5 || kPa > last * 1.02 { return nil }
        let target = log(kPa)
        var lo = 0, hi = table.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if log(table[mid]) < target { lo = mid } else { hi = mid }
        }
        let a = log(table[lo]), b = log(table[hi])
        let f = (target - a) / (b - a)
        return Units.cToF(Double(startC + lo) + f)
    }

    /// Temperature glide at a pressure (dew − bubble), °F.
    func glideF(atPsig p: Double, atmPsia: Double) -> Double? {
        guard let d = satTempF(psig: p, side: .dew, atmPsia: atmPsia),
              let b = satTempF(psig: p, side: .bubble, atmPsia: atmPsia) else { return nil }
        return d - b
    }
}

enum Refrigerants {
    static var all: [RefrigerantTable] { RefrigerantData.all }
    static func named(_ name: String) -> RefrigerantTable? {
        let key = normalize(name)
        return RefrigerantData.all.first { normalize($0.name) == key }
    }
    static var defaultRefrigerant: RefrigerantTable { named("R-410A") ?? RefrigerantData.all[0] }
    private static func normalize(_ s: String) -> String {
        s.uppercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
    }
}
