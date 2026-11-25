import Foundation
import Observation

/// Where a probe reading is used in the system calculations.
enum ProbeRole: String, CaseIterable, Codable, Identifiable {
    case suctionPressure, liquidPressure, suctionLine, liquidLine
    case returnAir, supplyAir, outdoorAir
    case vacuum, staticSupply, staticReturn

    var id: String { rawValue }
    var title: String {
        switch self {
        case .suctionPressure: return "Suction pressure"
        case .liquidPressure: return "Liquid pressure"
        case .suctionLine: return "Suction line temp"
        case .liquidLine: return "Liquid line temp"
        case .returnAir: return "Return air"
        case .supplyAir: return "Supply air"
        case .outdoorAir: return "Outdoor air"
        case .vacuum: return "Vacuum"
        case .staticSupply: return "Supply static"
        case .staticReturn: return "Return static"
        }
    }
    var short: String {
        switch self {
        case .suctionPressure: return "SUCT P"
        case .liquidPressure: return "LIQ P"
        case .suctionLine: return "SLT"
        case .liquidLine: return "LLT"
        case .returnAir: return "RETURN"
        case .supplyAir: return "SUPPLY"
        case .outdoorAir: return "OUTDOOR"
        case .vacuum: return "VAC"
        case .staticSupply: return "SUP SP"
        case .staticReturn: return "RET SP"
        }
    }
    /// The reading kind this role consumes (air roles also use humidity).
    var kind: SensorKind {
        switch self {
        case .suctionPressure, .liquidPressure: return .pressure
        case .suctionLine, .liquidLine, .returnAir, .supplyAir, .outdoorAir: return .temperature
        case .vacuum: return .vacuum
        case .staticSupply, .staticReturn: return .staticPressure
        }
    }
}

/// A reference to one channel of one probe.
struct ChannelRef: Codable, Hashable {
    var probeKey: String
    var label: String
}

@Observable
final class Probe: Identifiable {
    let key: String
    var vendor: String
    var model: String
    var typeCode: String
    var serial: String
    var firmware: String?
    var category: ProbeCategory
    var nickname: String = ""
    var battery: Int?
    var rssi: Int = 0
    var lastSeen: Date = .now
    var readings: [SensorReading] = []
    var raw: [UInt8] = []
    var packets: Int = 0
    /// Per-channel history for graphs/logging, sampled at most once a second.
    var history: [String: [TimedSample]] = [:]
    var id: String { key }

    init(advert: ProbeAdvert) {
        key = advert.key; vendor = advert.vendor; model = advert.model; typeCode = advert.typeCode
        serial = advert.serial; firmware = advert.firmware; category = advert.category
    }

    var displayName: String { nickname.isEmpty ? "\(model) · \(serial)" : nickname }
    func reading(_ label: String) -> SensorReading? { readings.first { $0.label == label } }
    func first(_ kind: SensorKind) -> SensorReading? { readings.first { $0.kind == kind } }
    func isStale(now: Date, after seconds: Double) -> Bool { now.timeIntervalSince(lastSeen) > seconds }
}

@Observable
final class ProbeStore {
    private(set) var probes: [Probe] = []
    var assignments: [ProbeRole: ChannelRef] = [:] { didSet { saveAssignments() } }
    var nicknames: [String: String] = [:] { didSet { UserDefaults.standard.set(nicknames, forKey: "xeno.nicknames") } }
    /// Per-channel zero offsets ("probeKey|label" -> value subtracted), set with Zero pressure.
    var zeroOffsets: [String: Double] = [:] { didSet { UserDefaults.standard.set(zeroOffsets, forKey: "xeno.zeroOffsets") } }
    var autoAssign = true
    /// Seconds without a broadcast before a probe counts as offline (from settings).
    var staleAfter: Double = 20
    private let historyLimit = 7200

    init() {
        if let data = UserDefaults.standard.data(forKey: "xeno.assignments"),
           let a = try? JSONDecoder().decode([ProbeRole: ChannelRef].self, from: data) {
            // JL3KM is single-port: drop assignments made to its old "Supply/Return/Differential" channels.
            assignments = a.filter { !["Supply", "Return", "Differential"].contains($0.value.label) || !$0.value.probeKey.contains(".BX.") }
        }
        nicknames = (UserDefaults.standard.dictionary(forKey: "xeno.nicknames") as? [String: String]) ?? [:]
        zeroOffsets = (UserDefaults.standard.dictionary(forKey: "xeno.zeroOffsets") as? [String: Double]) ?? [:]
        // Build 8 decoded JL3PR from the wrong field; zeros taken then are invalid.
        if !UserDefaults.standard.bool(forKey: "xeno.zeroReset.jl3pr") {
            zeroOffsets = zeroOffsets.filter { !$0.key.contains(".BG.") }
            UserDefaults.standard.set(true, forKey: "xeno.zeroReset.jl3pr")
        }
    }

    private func saveAssignments() {
        if let data = try? JSONEncoder().encode(assignments) { UserDefaults.standard.set(data, forKey: "xeno.assignments") }
    }

    func probe(_ key: String) -> Probe? { probes.first { $0.key == key } }

    func ingest(_ ad: ProbeAdvert, rssi: Int, at now: Date = .now) {
        let p: Probe
        if let existing = probe(ad.key) {
            p = existing
        } else {
            p = Probe(advert: ad)
            p.nickname = nicknames[ad.key] ?? ""
            probes.append(p)
            probes.sort { ($0.category.rawValue, $0.serial) < ($1.category.rawValue, $1.serial) }
        }
        p.model = ad.model; p.category = ad.category; p.firmware = ad.firmware
        if let b = ad.battery { p.battery = b }
        p.rssi = rssi; p.raw = ad.raw; p.packets += 1
        p.readings = ad.readings.map { r in
            guard r.kind == .pressure || r.kind == .staticPressure, let z = zeroOffsets["\(ad.key)|\(r.label)"] else { return r }
            var r = r; r.value -= z; return r
        }
        let last = p.lastSeen
        p.lastSeen = now
        for r in p.readings {
            var h = p.history[r.id] ?? []
            if let tail = h.last, now.timeIntervalSince(tail.t) < 1, now.timeIntervalSince(last) < 5 { continue }
            h.append(TimedSample(t: now, value: r.value))
            if h.count > historyLimit { h.removeFirst(h.count - historyLimit) }
            p.history[r.id] = h
        }
        if autoAssign { autoAssignRoles(for: p) }
    }

    /// Treat the current pressure readings as zero (probe open to atmosphere).
    func zeroPressure(_ p: Probe) {
        for r in p.readings where r.kind == .pressure || r.kind == .staticPressure {
            let k = "\(p.key)|\(r.label)"
            zeroOffsets[k] = (zeroOffsets[k] ?? 0) + r.value
        }
    }

    func clearZero(_ p: Probe) {
        for k in zeroOffsets.keys where k.hasPrefix(p.key + "|") { zeroOffsets[k] = nil }
    }

    func hasZero(_ p: Probe) -> Bool { zeroOffsets.keys.contains { $0.hasPrefix(p.key + "|") } }

    func rename(_ p: Probe, to name: String) {
        p.nickname = name
        nicknames[p.key] = name.isEmpty ? nil : name
    }

    func forget(_ p: Probe) {
        probes.removeAll { $0.key == p.key }
        for (role, ref) in assignments where ref.probeKey == p.key { assignments[role] = nil }
    }

    func clearAll() { probes.removeAll() }

    func roles(of p: Probe) -> [ProbeRole] {
        ProbeRole.allCases.filter { assignments[$0]?.probeKey == p.key }
    }

    func assign(_ role: ProbeRole, to probe: Probe?, label: String? = nil) {
        guard let probe else { assignments[role] = nil; return }
        let l = label ?? probe.first(role.kind)?.label ?? probe.readings.first?.label ?? ""
        assignments[role] = ChannelRef(probeKey: probe.key, label: l)
    }

    /// Fills empty roles in Job Link order: 1st pressure probe → suction, 2nd → liquid, etc.
    private func autoAssignRoles(for p: Probe) {
        guard roles(of: p).isEmpty else { return }
        // A position is free if nobody holds it, or its probe is gone / offline.
        func free(_ role: ProbeRole) -> Bool {
            guard let ref = assignments[role] else { return true }
            guard let holder = probe(ref.probeKey) else { return true }
            return holder.key != p.key && holder.isStale(now: .now, after: staleAfter)
        }
        func take(_ candidates: [ProbeRole], label: String? = nil) -> Bool {
            for role in candidates where free(role) {
                assign(role, to: p, label: label); return true
            }
            return false
        }
        switch p.category {
        case .pressure: _ = take([.suctionPressure, .liquidPressure])
        case .pipeClamp: _ = take([.suctionLine, .liquidLine])
        case .psychrometer: _ = take([.returnAir, .supplyAir, .outdoorAir])
        case .vacuum: _ = take([.vacuum])
        case .manometer:
            _ = take([.staticSupply, .staticReturn])
        case .manifold:
            let map: [(ProbeRole, String)] = [(.suctionPressure, "Low side"), (.liquidPressure, "High side"), (.suctionLine, "Suction line"), (.liquidLine, "Liquid line")]
            for (role, label) in map where free(role) && p.reading(label) != nil { assign(role, to: p, label: label) }
        default: break
        }
    }

    // MARK: Values for calculations

    func liveProbe(for role: ProbeRole, staleAfter: Double, now: Date = .now) -> Probe? {
        guard let ref = assignments[role], let p = probe(ref.probeKey), !p.isStale(now: now, after: staleAfter) else { return nil }
        return p
    }

    func value(_ role: ProbeRole, staleAfter: Double, now: Date = .now) -> Double? {
        guard let ref = assignments[role], let p = liveProbe(for: role, staleAfter: staleAfter, now: now) else { return nil }
        return (p.reading(ref.label) ?? p.first(role.kind))?.value
    }

    func humidity(_ role: ProbeRole, staleAfter: Double, now: Date = .now) -> Double? {
        liveProbe(for: role, staleAfter: staleAfter, now: now)?.first(.humidity)?.value
    }

    func history(_ role: ProbeRole) -> [TimedSample] {
        guard let ref = assignments[role], let p = probe(ref.probeKey) else { return [] }
        let r = p.reading(ref.label) ?? p.first(role.kind)
        return r.flatMap { p.history[$0.id] } ?? []
    }
}
