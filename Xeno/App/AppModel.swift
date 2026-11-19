import Foundation
import Observation

@Observable
final class AppModel {
    var settings: XenoSettings { didSet { persistSettings() } }
    let probes = ProbeStore()
    let jobs = JobStore()
    let lab = ProbeLab()
    @ObservationIgnored private(set) var bluetooth: BluetoothService!
    @ObservationIgnored private(set) var demo: DemoSource!
    var selectedTab: AppTab = .probes

    init() {
        if let data = UserDefaults.standard.data(forKey: "xeno.settings"),
           let s = try? JSONDecoder().decode(XenoSettings.self, from: data) {
            settings = s
        } else {
            settings = XenoSettings()
        }
        // Launch arguments (used by the screenshot workflow): -XenoDemo YES -XenoTab charge
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "XenoDemo") { settings.demoMode = true }
        if let t = defaults.string(forKey: "XenoTab"), let tab = AppTab(rawValue: t) { selectedTab = tab }
        probes.autoAssign = settings.autoAssign
        bluetooth = BluetoothService(model: self)
        demo = DemoSource(model: self)
    }

    var fmt: Fmt { Fmt(s: settings) }
    var refrigerant: RefrigerantTable { Refrigerants.named(settings.refrigerant) ?? Refrigerants.defaultRefrigerant }
    var decoder: FieldpieceDecoder { FieldpieceDecoder(overrides: lab.overrides) }

    func start() {
        // The screenshot workflow runs in the simulator, where Bluetooth doesn't exist.
        if !UserDefaults.standard.bool(forKey: "XenoNoBluetooth") { bluetooth.start() }
        if UserDefaults.standard.bool(forKey: "XenoSampleJob"), jobs.jobs.isEmpty { addSampleJob() }
        if settings.demoMode { demo.start() }
    }

    func setDemo(_ on: Bool) {
        settings.demoMode = on
        if on { demo.start() } else { demo.stop(); probes.clearAll() }
    }

    func value(_ role: ProbeRole) -> Double? { probes.value(role, staleAfter: settings.staleSeconds) }
    func humidity(_ role: ProbeRole) -> Double? { probes.humidity(role, staleAfter: settings.staleSeconds) }

    /// Values typed in by hand when no probe is assigned (canonical units).
    var manual: [ProbeRole: Double] = [:]
    var manualRH: [ProbeRole: Double] = [:]

    /// Live probe value, else the manual entry.
    func input(_ role: ProbeRole) -> Double? { value(role) ?? manual[role] }
    func inputRH(_ role: ProbeRole) -> Double? { humidity(role) ?? manualRH[role] }
    func isLive(_ role: ProbeRole) -> Bool { value(role) != nil }

    func air(_ role: ProbeRole) -> AirState? {
        guard let db = input(role), let rh = inputRH(role) else { return nil }
        return AirState(dryBulbF: db, relativeHumidity: rh, pressurePsia: settings.atmPsia)
    }

    var chargeResult: ChargeResult {
        let r = refrigerant
        var targetSH: Double?
        if let ret = air(.returnAir), let od = input(.outdoorAir) {
            targetSH = HVACCalc.targetSuperheat(indoorWetBulbF: ret.wetBulbF, outdoorDryBulbF: od)
        }
        return HVACCalc.charge(suctionPsig: input(.suctionPressure), suctionLineF: input(.suctionLine),
                               liquidPsig: input(.liquidPressure), liquidLineF: input(.liquidLine),
                               refrigerant: r, metering: settings.metering, targetSuperheat: targetSH,
                               targetSubcool: settings.targetSubcool, atmPsia: settings.atmPsia,
                               tolerance: settings.chargeTolerance)
    }

    /// Example job for demos and screenshots (only created via the XenoSampleJob launch argument).
    private func addSampleJob() {
        var job = Job()
        job.customer = "Sample Customer"
        job.address = "123 Example St"
        job.workOrder = "WO-1042"
        job.equipment = Equipment(outdoorMake: "Example", outdoorModel: "AC-36", outdoorSerial: "X123", indoorMake: "Example", indoorModel: "AH-36",
                                  indoorSerial: "Y456", refrigerant: "R-410A", metering: .txv, tons: "3", seer: "15.2", factoryCharge: "9 lb 4 oz")
        job.records = [
            JobRecord(title: "Evacuation decay test", values: [.init(label: "Start", value: "312 microns"), .init(label: "End", value: "398 microns"), .init(label: "Duration", value: "10:00")],
                      verdict: VacuumAnalysis.Verdict.pass.rawValue, verdictGood: true),
            JobRecord(title: "Charge check", values: [.init(label: "Superheat", value: "9.8 °F"), .init(label: "Subcooling", value: "10.4 °F")],
                      verdict: ChargeDiagnosis.inRange.rawValue, verdictGood: true),
        ]
        jobs.create(job)
    }

    private func persistSettings() {
        probes.autoAssign = settings.autoAssign
        if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: "xeno.settings") }
    }
}

enum AppTab: String, CaseIterable {
    case probes, charge, tools, jobs, settings
}
