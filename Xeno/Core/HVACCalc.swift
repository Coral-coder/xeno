import Foundation

enum MeteringDevice: String, CaseIterable, Codable, Identifiable {
    case txv = "TXV / EEV", fixed = "Fixed orifice / piston"
    var id: String { rawValue }
}

/// Results of a refrigerant-side reading (all temperatures °F, pressures psig).
struct ChargeResult: Equatable {
    var suctionSatF: Double?
    var superheatF: Double?
    var liquidSatF: Double?
    var subcoolF: Double?
    var targetSuperheatF: Double?
    var targetSubcoolF: Double?
    var compressionRatio: Double?
    var diagnosis: ChargeDiagnosis
}

enum ChargeDiagnosis: String, Equatable {
    case needsData = "Waiting for readings"
    case inRange = "Charge looks correct"
    case undercharged = "Low charge — add refrigerant"
    case overcharged = "Overcharged — recover refrigerant"
    case restriction = "Possible restriction / metering device starving"
    case meteringOverfeeding = "Metering device overfeeding / low airflow"
    case lowAirflow = "Low indoor airflow or low load"
    case nonCondensables = "High head — dirty condenser / non-condensables"
    case inefficientCompressor = "Weak compressor (low head, high suction)"

    var detail: String {
        switch self {
        case .needsData: return "Assign suction/liquid pressure and line temperature probes."
        case .inRange: return "Superheat and subcooling are within ±tolerance of target."
        case .undercharged: return "High superheat with low subcooling."
        case .overcharged: return "Low superheat with high subcooling."
        case .restriction: return "High superheat with high subcooling."
        case .meteringOverfeeding: return "Low superheat with low subcooling."
        case .lowAirflow: return "Low superheat; check filter, blower, coil and duct static."
        case .nonCondensables: return "High subcooling and high condensing temperature."
        case .inefficientCompressor: return "Low compression ratio."
        }
    }
    var isGood: Bool { self == .inRange }
}

enum HVACCalc {
    /// Superheat = suction line temp − dew-point saturation temp at suction pressure.
    static func superheat(suctionPsig: Double, suctionLineF: Double, refrigerant r: RefrigerantTable, atmPsia: Double) -> (sat: Double, sh: Double)? {
        guard let sat = r.satTempF(psig: suctionPsig, side: .dew, atmPsia: atmPsia) else { return nil }
        return (sat, suctionLineF - sat)
    }

    /// Subcooling = bubble-point saturation temp at liquid pressure − liquid line temp.
    static func subcool(liquidPsig: Double, liquidLineF: Double, refrigerant r: RefrigerantTable, atmPsia: Double) -> (sat: Double, sc: Double)? {
        guard let sat = r.satTempF(psig: liquidPsig, side: .bubble, atmPsia: atmPsia) else { return nil }
        return (sat, sat - liquidLineF)
    }

    /// Target superheat for fixed-orifice systems (industry standard chart formula):
    /// TSH = (3 × indoor WB − 80 − outdoor DB) / 2. Nil when outside the chart (< 5 °F).
    static func targetSuperheat(indoorWetBulbF: Double, outdoorDryBulbF: Double) -> Double? {
        let t = (3 * indoorWetBulbF - 80 - outdoorDryBulbF) / 2
        return t < 5 ? nil : min(t, 40)
    }

    /// Target evaporator saturation for TXV systems, a common rule of thumb: return DB − 35 °F.
    static func targetEvapSatF(returnDryBulbF: Double) -> Double { returnDryBulbF - 35 }

    /// Target condensing temperature: outdoor DB + 15…30 °F depending on SEER.
    static func targetCondensingOverAmbientF(seer: Double) -> Double {
        switch seer {
        case ..<10: return 30
        case ..<13: return 25
        case ..<16: return 20
        default: return 15
        }
    }

    static func charge(suctionPsig: Double?, suctionLineF: Double?, liquidPsig: Double?, liquidLineF: Double?,
                       refrigerant r: RefrigerantTable, metering: MeteringDevice, targetSuperheat: Double?,
                       targetSubcool: Double?, atmPsia: Double, tolerance: Double = 3) -> ChargeResult {
        var result = ChargeResult(diagnosis: .needsData)
        if let p = suctionPsig, let t = suctionLineF, let s = superheat(suctionPsig: p, suctionLineF: t, refrigerant: r, atmPsia: atmPsia) {
            result.suctionSatF = s.sat; result.superheatF = s.sh
        } else if let p = suctionPsig {
            result.suctionSatF = r.satTempF(psig: p, side: .dew, atmPsia: atmPsia)
        }
        if let p = liquidPsig, let t = liquidLineF, let s = subcool(liquidPsig: p, liquidLineF: t, refrigerant: r, atmPsia: atmPsia) {
            result.liquidSatF = s.sat; result.subcoolF = s.sc
        } else if let p = liquidPsig {
            result.liquidSatF = r.satTempF(psig: p, side: .bubble, atmPsia: atmPsia)
        }
        if let s = suctionPsig, let l = liquidPsig, s + atmPsia > 0 {
            result.compressionRatio = (l + atmPsia) / (s + atmPsia)
        }
        result.targetSuperheatF = targetSuperheat
        result.targetSubcoolF = targetSubcool
        result.diagnosis = diagnose(result: result, metering: metering, tolerance: tolerance)
        return result
    }

    static func diagnose(result: ChargeResult, metering: MeteringDevice, tolerance: Double) -> ChargeDiagnosis {
        if let cr = result.compressionRatio, cr < 2.0, result.superheatF != nil { return .inefficientCompressor }
        switch metering {
        case .fixed:
            guard let sh = result.superheatF, let target = result.targetSuperheatF else { return .needsData }
            let d = sh - target
            if abs(d) <= max(tolerance, 5) {
                if let sc = result.subcoolF, sc > 20 { return .nonCondensables }
                return .inRange
            }
            if d > 0 {
                if let sc = result.subcoolF, sc > 15 { return .restriction }
                return .undercharged
            }
            if let sc = result.subcoolF, sc > 15 { return .overcharged }
            return .lowAirflow
        case .txv:
            guard let sc = result.subcoolF, let target = result.targetSubcoolF else { return .needsData }
            let d = sc - target
            let sh = result.superheatF
            if abs(d) <= tolerance {
                if let sh = sh, sh > 20 { return .restriction }
                if let sh = sh, sh < 2 { return .meteringOverfeeding }
                return .inRange
            }
            if d < 0 {
                if let sh = sh, sh < 4 { return .meteringOverfeeding }
                return .undercharged
            }
            if let sh = sh, sh > 20 { return .restriction }
            return .overcharged
        }
    }

    // MARK: Air side

    /// Sensible capacity (BTU/h) = 1.08 × CFM × ΔT, density-corrected.
    static func sensibleBTUh(cfm: Double, deltaTF: Double, psia: Double) -> Double {
        1.08 * Psychrometrics.airDensityRatio(psia: psia) * cfm * deltaTF
    }

    /// Total capacity (BTU/h) = 4.5 × CFM × Δh, density-corrected.
    static func totalBTUh(cfm: Double, deltaEnthalpy: Double, psia: Double) -> Double {
        4.5 * Psychrometrics.airDensityRatio(psia: psia) * cfm * deltaEnthalpy
    }

    /// Furnace airflow from temperature rise: CFM = output BTU/h / (1.08 × rise).
    static func cfmFromTempRise(outputBTUh: Double, riseF: Double, psia: Double) -> Double? {
        guard riseF > 0 else { return nil }
        return outputBTUh / (1.08 * Psychrometrics.airDensityRatio(psia: psia) * riseF)
    }

    /// Target cooling ΔT from return RH (standard split-system ΔT chart, 400 CFM/ton).
    static func targetCoolingDeltaT(returnDryBulbF db: Double, returnRH rh: Double) -> Double {
        // Linear fit of the common chart: ~21 °F at 20 %RH falling to ~10 °F at 80 %RH, shifted by return DB vs 80 °F.
        let base = 21 - (max(20, min(80, rh)) - 20) * (11.0 / 60.0)
        return base + (db - 80) * 0.25
    }

    /// Fan law: new CFM from RPM change; static pressure scales with the square, power with the cube.
    static func fanLaw(cfm1: Double, rpm1: Double, rpm2: Double) -> (cfm: Double, spRatio: Double, bhpRatio: Double) {
        let r = rpm2 / rpm1
        return (cfm1 * r, r * r, r * r * r)
    }

    /// Total external static pressure (inWC) from supply (+) and return (−) readings.
    static func tesp(supplyInWC: Double, returnInWC: Double) -> Double { abs(supplyInWC) + abs(returnInWC) }
}

// MARK: - Vacuum / pressure tests

struct TimedSample: Codable, Hashable {
    var t: Date
    var value: Double
}

enum VacuumAnalysis {
    enum Verdict: String { case running = "Decay test running", pass = "PASS — system is tight and dry", leak = "FAIL — rising steadily: probable leak", moisture = "FAIL — levelling off high: moisture/outgassing" }

    /// Classifies a decay test (isolated pump). Industry guidance: stays under `limit`
    /// (typically 500 µ, max 1000 µ rise) for the hold time.
    static func verdict(samples: [TimedSample], limit: Double, holdSeconds: TimeInterval) -> Verdict {
        guard let first = samples.first, let last = samples.last else { return .running }
        let elapsed = last.t.timeIntervalSince(first.t)
        if last.value > limit {
            // Compare the rise rate in the first and second halves: leaks rise linearly, moisture flattens.
            let mid = first.t.addingTimeInterval(elapsed / 2)
            let firstHalf = samples.filter { $0.t <= mid }
            let secondHalf = samples.filter { $0.t >= mid }
            let r1 = rate(firstHalf), r2 = rate(secondHalf)
            if r1 > 0, r2 / r1 > 0.6 { return .leak }
            return .moisture
        }
        return elapsed >= holdSeconds ? .pass : .running
    }

    /// Rise rate in microns per minute.
    static func rate(_ s: [TimedSample]) -> Double {
        guard let a = s.first, let b = s.last, b.t > a.t else { return 0 }
        return (b.value - a.value) / (b.t.timeIntervalSince(a.t) / 60)
    }
}

enum PressureTest {
    /// Temperature-compensated pressure (Gay-Lussac): what the start pressure should read now
    /// purely from the temperature change. Pressures psig, temps °F.
    static func expectedPsig(startPsig: Double, startTempF: Double, nowTempF: Double, atmPsia: Double) -> Double {
        let p1 = startPsig + atmPsia
        let t1 = startTempF + 459.67, t2 = nowTempF + 459.67
        return p1 * t2 / t1 - atmPsia
    }
}
