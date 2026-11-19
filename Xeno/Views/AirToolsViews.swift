import SwiftUI

struct PressureTestView: View {
    @Environment(AppModel.self) private var model
    @State private var pressureRole: ProbeRole = .liquidPressure
    @State private var tempRole: ProbeRole = .outdoorAir
    @State private var start: (date: Date, psig: Double, tempF: Double?)?
    @State private var samples: [TimedSample] = []
    @State private var saving: JobRecord?
    @State private var allowedDrop: Double = 1

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let fmt = model.fmt
            let p = model.input(pressureRole)
            let t = model.input(tempRole)
            ScrollView {
                VStack(spacing: 14) {
                    XenoCard(glow: Theme.beam) {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Pressure from", selection: $pressureRole) {
                                Text("Suction probe").tag(ProbeRole.suctionPressure)
                                Text("Liquid probe").tag(ProbeRole.liquidPressure)
                            }.pickerStyle(.segmented)
                            Picker("Temperature from", selection: $tempRole) {
                                Text("Outdoor air").tag(ProbeRole.outdoorAir)
                                Text("Suction line").tag(ProbeRole.suctionLine)
                                Text("Liquid line").tag(ProbeRole.liquidLine)
                            }.pickerStyle(.segmented)
                            HStack {
                                RoleInput(role: pressureRole, caption: "Pressure", size: 40, color: Theme.beam)
                                Spacer()
                                RoleInput(role: tempRole, caption: "Temperature", size: 28)
                            }
                        }
                    }
                    if let start {
                        let expected = start.tempF.flatMap { st in t.map { PressureTest.expectedPsig(startPsig: start.psig, startTempF: st, nowTempF: $0, atmPsia: model.settings.atmPsia) } } ?? start.psig
                        let loss = p.map { expected - $0 }
                        let pass = (loss ?? 0) <= allowedDrop
                        XenoCard(glow: pass ? Theme.alien : Theme.danger) {
                            VStack(alignment: .leading, spacing: 8) {
                                KeyValueRow(key: "Elapsed", value: Duration.seconds(ctx.date.timeIntervalSince(start.date)).formatted(.time(pattern: .hourMinuteSecond)))
                                KeyValueRow(key: "Start", value: fmt.pressure(start.psig), unit: fmt.pUnit)
                                KeyValueRow(key: "Temp-compensated expected", value: fmt.pressure(expected), unit: fmt.pUnit)
                                KeyValueRow(key: "Now", value: fmt.pressure(p), unit: fmt.pUnit)
                                KeyValueRow(key: "Corrected loss", value: fmt.pressure(loss), unit: fmt.pUnit)
                                Text(pass ? "HOLDING" : "LOSING PRESSURE — look for a leak").font(.system(.headline, design: .rounded)).foregroundStyle(pass ? Theme.alien : Theme.danger)
                                SeriesChart(samples: samples, kind: .pressure, color: Theme.beam).frame(height: 160)
                                HStack {
                                    Button("Stop") { self.start = nil }.buttonStyle(GlowButtonStyle(color: Theme.danger))
                                    Button("Save") { saving = record(expected: expected, loss: loss, pass: pass) }.buttonStyle(GlowButtonStyle())
                                }
                            }
                        }
                    } else {
                        XenoCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Pressurise with dry nitrogen, let it stabilise, then start. Temperature changes are compensated (Gay-Lussac's law).").font(.caption).foregroundStyle(Theme.textDim)
                                Stepper("Allowed drop: \(allowedDrop.formatted(decimals: 1)) psi", value: $allowedDrop, in: 0...10, step: 0.5).font(.subheadline)
                                Button { if let p { start = (.now, p, t); samples = [] } } label: { Label("Start test", systemImage: "play.fill") }
                                    .buttonStyle(GlowButtonStyle(color: Theme.beam)).disabled(p == nil)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .onChange(of: ctx.date) { _, now in
                if start != nil, let p = model.input(pressureRole) { samples.append(TimedSample(t: now, value: p)) }
            }
        }
        .xenoScreen()
        .navigationTitle("Pressure test")
        .sheet(item: $saving) { SaveToJobSheet(record: $0) }
    }

    func record(expected: Double, loss: Double?, pass: Bool) -> JobRecord {
        let f = model.fmt
        return JobRecord(title: "Nitrogen pressure test", values: [
            .init(label: "Start", value: "\(f.pressure(start?.psig)) \(f.pUnit)"),
            .init(label: "End", value: "\(f.pressure(samples.last?.value)) \(f.pUnit)"),
            .init(label: "Expected (temp-compensated)", value: "\(f.pressure(expected)) \(f.pUnit)"),
            .init(label: "Corrected loss", value: "\(f.pressure(loss)) \(f.pUnit)"),
            .init(label: "Duration", value: Duration.seconds((samples.last?.t ?? .now).timeIntervalSince(start?.date ?? .now)).formatted(.time(pattern: .hourMinuteSecond))),
        ], verdict: pass ? "Holding" : "Losing pressure", verdictGood: pass, series: samples, seriesLabel: "psig")
    }
}

struct AirflowView: View {
    @Environment(AppModel.self) private var model
    @State private var cfmText = "1200"
    @State private var tonsText = "3"
    @State private var saving: JobRecord?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let fmt = model.fmt, s = model.settings
            let ret = model.air(.returnAir), sup = model.air(.supplyAir)
            let cfm = Double(cfmText) ?? 0
            let tons = Double(tonsText) ?? 0
            ScrollView {
                VStack(spacing: 14) {
                    XenoCard(glow: Theme.nebula) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 8) {
                                RoleInput(role: .returnAir, caption: "Return DB", size: 26)
                                RoleInput(role: .returnAir, caption: "Return RH", humidity: true, size: 20)
                                Text("WB \(fmt.temp(ret?.wetBulbF))  DP \(fmt.temp(ret?.dewPointF))").font(.caption).foregroundStyle(Theme.textDim)
                            }
                            Spacer()
                            VStack(alignment: .leading, spacing: 8) {
                                RoleInput(role: .supplyAir, caption: "Supply DB", size: 26)
                                RoleInput(role: .supplyAir, caption: "Supply RH", humidity: true, size: 20)
                                Text("WB \(fmt.temp(sup?.wetBulbF))  DP \(fmt.temp(sup?.dewPointF))").font(.caption).foregroundStyle(Theme.textDim)
                            }
                        }
                    }
                    XenoCard(glow: Theme.beam) {
                        VStack(spacing: 10) {
                            HStack {
                                Text("Airflow").foregroundStyle(Theme.textDim)
                                TextField("CFM", text: $cfmText).keyboardType(.numberPad).multilineTextAlignment(.trailing).font(Theme.reading(20))
                                Text("CFM").font(.caption).foregroundStyle(Theme.textDim)
                            }
                            HStack {
                                Text("Nominal size").foregroundStyle(Theme.textDim)
                                TextField("tons", text: $tonsText).keyboardType(.decimalPad).multilineTextAlignment(.trailing).font(Theme.reading(20))
                                Text("tons").font(.caption).foregroundStyle(Theme.textDim)
                            }
                            if tons > 0 { KeyValueRow(key: "CFM per ton", value: (cfm / tons).formatted(decimals: 0)) }
                        }
                    }
                    if let ret, let sup {
                        let dT = ret.dryBulbF - sup.dryBulbF
                        let sens = HVACCalc.sensibleBTUh(cfm: cfm, deltaTF: dT, psia: s.atmPsia)
                        let total = HVACCalc.totalBTUh(cfm: cfm, deltaEnthalpy: ret.enthalpy - sup.enthalpy, psia: s.atmPsia)
                        XenoCard {
                            VStack(spacing: 12) {
                                HStack {
                                    ReadingView(caption: "ΔT", value: fmt.delta(dT), unit: fmt.dUnit, color: Theme.alien)
                                    Spacer()
                                    ReadingView(caption: "Target ΔT", value: fmt.delta(HVACCalc.targetCoolingDeltaT(returnDryBulbF: ret.dryBulbF, returnRH: ret.relativeHumidity)), unit: fmt.dUnit)
                                }
                                HStack {
                                    ReadingView(caption: "Total capacity", value: (total / 1000).formatted(decimals: 1), unit: "kBTU/h", color: Theme.beam)
                                    Spacer()
                                    ReadingView(caption: "Tons delivered", value: (total / 12000).formatted(decimals: 2), unit: "tons", color: Theme.beam)
                                }
                                KeyValueRow(key: "Sensible", value: (sens / 1000).formatted(decimals: 1), unit: "kBTU/h")
                                KeyValueRow(key: "Latent", value: ((total - sens) / 1000).formatted(decimals: 1), unit: "kBTU/h")
                                KeyValueRow(key: "Sensible heat ratio", value: total > 0 ? (sens / total).formatted(decimals: 2) : "––")
                                KeyValueRow(key: "Moisture removed", value: (ret.grainsPerLb - sup.grainsPerLb).formatted(decimals: 1), unit: "gr/lb")
                                if tons > 0 { KeyValueRow(key: "% of nominal", value: (total / (tons * 12000) * 100).formatted(decimals: 0), unit: "%") }
                                Button { saving = record(ret: ret, sup: sup, cfm: cfm, total: total, sens: sens) } label: { Label("Save to job", systemImage: "square.and.arrow.down") }
                                    .buttonStyle(GlowButtonStyle())
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .xenoScreen()
        .navigationTitle("Airflow & capacity")
        .sheet(item: $saving) { SaveToJobSheet(record: $0) }
    }

    func record(ret: AirState, sup: AirState, cfm: Double, total: Double, sens: Double) -> JobRecord {
        let f = model.fmt
        return JobRecord(title: "Airflow & capacity", values: [
            .init(label: "Return", value: "\(f.temp(ret.dryBulbF)) \(f.tUnit) / \(ret.relativeHumidity.formatted(decimals: 0))% RH"),
            .init(label: "Supply", value: "\(f.temp(sup.dryBulbF)) \(f.tUnit) / \(sup.relativeHumidity.formatted(decimals: 0))% RH"),
            .init(label: "ΔT", value: "\(f.delta(ret.dryBulbF - sup.dryBulbF)) \(f.dUnit)"),
            .init(label: "Airflow", value: "\(cfm.formatted(decimals: 0)) CFM"),
            .init(label: "Total capacity", value: "\((total / 1000).formatted(decimals: 1)) kBTU/h"),
            .init(label: "Sensible capacity", value: "\((sens / 1000).formatted(decimals: 1)) kBTU/h"),
        ])
    }
}

struct StaticPressureView: View {
    @Environment(AppModel.self) private var model
    @State private var ratedText = "0.50"
    @State private var rpm1 = "1000"
    @State private var rpm2 = "1100"
    @State private var cfm1 = "1200"
    @State private var saving: JobRecord?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let fmt = model.fmt, s = model.settings
            let sup = model.input(.staticSupply), ret = model.input(.staticReturn)
            let tesp = (sup != nil && ret != nil) ? HVACCalc.tesp(supplyInWC: sup!, returnInWC: ret!) : nil
            let rated = s.staticUnit.toInWC(Double(ratedText) ?? 0.5)
            ScrollView {
                VStack(spacing: 14) {
                    XenoCard {
                        VStack(spacing: 12) {
                            HStack {
                                RoleInput(role: .staticSupply, caption: "Supply (+)", size: 26, color: Theme.beam)
                                Spacer()
                                RoleInput(role: .staticReturn, caption: "Return (−)", size: 26, color: Theme.nebula)
                            }
                            Divider().opacity(0.3)
                            TargetGauge(title: "Total external static", value: tesp.map { s.staticUnit.fromInWC($0) }, target: s.staticUnit.fromInWC(rated),
                                        tolerance: s.staticUnit.fromInWC(0.1), unit: " \(s.staticUnit.rawValue)") { $0.formatted(decimals: s.staticUnit == .inWC ? 2 : 0) }
                            HStack {
                                Text("Rated max ESP").foregroundStyle(Theme.textDim)
                                TextField("0.50", text: $ratedText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                                Text(s.staticUnit.rawValue).font(.caption).foregroundStyle(Theme.textDim)
                            }
                            if let tesp {
                                Text(tesp <= rated ? "Within the blower's rated static" : "Above rated — restricted ductwork, filter or coil")
                                    .font(.subheadline).foregroundStyle(tesp <= rated ? Theme.alien : Theme.danger)
                                Button { saving = JobRecord(title: "Static pressure", values: [
                                    .init(label: "Supply", value: "\(fmt.stat(sup)) \(s.staticUnit.rawValue)"),
                                    .init(label: "Return", value: "\(fmt.stat(ret)) \(s.staticUnit.rawValue)"),
                                    .init(label: "TESP", value: "\(fmt.stat(tesp)) \(s.staticUnit.rawValue)"),
                                    .init(label: "Rated", value: "\(fmt.stat(rated)) \(s.staticUnit.rawValue)"),
                                ], verdict: tesp <= rated ? "Within rating" : "Over rating", verdictGood: tesp <= rated) } label: { Label("Save to job", systemImage: "square.and.arrow.down") }
                                    .buttonStyle(GlowButtonStyle())
                            }
                        }
                    }
                    SectionHeader(title: "Fan laws", symbol: "fanblades")
                    XenoCard(glow: Theme.beam) {
                        VStack(spacing: 8) {
                            LabeledField(label: "Current CFM", text: $cfm1)
                            LabeledField(label: "Current RPM", text: $rpm1)
                            LabeledField(label: "New RPM", text: $rpm2)
                            if let c = Double(cfm1), let a = Double(rpm1), let b = Double(rpm2), a > 0 {
                                let r = HVACCalc.fanLaw(cfm1: c, rpm1: a, rpm2: b)
                                Divider().opacity(0.3)
                                KeyValueRow(key: "New CFM", value: r.cfm.formatted(decimals: 0))
                                KeyValueRow(key: "Static pressure ×", value: r.spRatio.formatted(decimals: 2))
                                if let tesp { KeyValueRow(key: "New TESP", value: fmt.stat(tesp * r.spRatio), unit: s.staticUnit.rawValue) }
                                KeyValueRow(key: "Fan power ×", value: r.bhpRatio.formatted(decimals: 2))
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .xenoScreen()
        .navigationTitle("Static pressure")
        .sheet(item: $saving) { SaveToJobSheet(record: $0) }
    }
}

struct LabeledField: View {
    var label: String
    @Binding var text: String
    var unit: String = ""
    var body: some View {
        HStack {
            Text(label).foregroundStyle(Theme.textDim)
            TextField("", text: $text).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .font(.system(.body, design: .rounded).monospacedDigit().weight(.semibold))
            if !unit.isEmpty { Text(unit).font(.caption).foregroundStyle(Theme.textDim) }
        }
        .font(.system(.subheadline, design: .rounded))
    }
}

struct TargetSuperheatView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let fmt = model.fmt
            let ret = model.air(.returnAir)
            let od = model.input(.outdoorAir)
            let target = (ret != nil && od != nil) ? HVACCalc.targetSuperheat(indoorWetBulbF: ret!.wetBulbF, outdoorDryBulbF: od!) : nil
            let actual = model.chargeResult.superheatF
            ScrollView {
                VStack(spacing: 14) {
                    XenoCard(glow: Theme.nebula) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 8) {
                                RoleInput(role: .returnAir, caption: "Indoor DB", size: 24)
                                RoleInput(role: .returnAir, caption: "Indoor RH", humidity: true, size: 20)
                                Text("Indoor WB \(fmt.temp(ret?.wetBulbF))").font(.caption).foregroundStyle(Theme.textDim)
                            }
                            Spacer()
                            RoleInput(role: .outdoorAir, caption: "Outdoor DB", size: 24)
                        }
                    }
                    XenoCard {
                        VStack(alignment: .leading, spacing: 12) {
                            TargetGauge(title: "Actual vs target superheat", value: actual.map { model.settings.temperatureUnit.deltaFromF($0) },
                                        target: target.map { model.settings.temperatureUnit.deltaFromF($0) }, tolerance: 5, unit: fmt.dUnit) { $0.formatted(decimals: 1) }
                            if ret != nil && od != nil && target == nil {
                                Text("Outside the chart (target < 5°F): don't charge by superheat in these conditions; use weigh-in.").font(.caption).foregroundStyle(Theme.warn)
                            }
                            if let target, let actual {
                                Text(actual > target + 5 ? "Superheat high: add refrigerant" : actual < target - 5 ? "Superheat low: recover refrigerant" : "On target")
                                    .font(.system(.headline, design: .rounded))
                                    .foregroundStyle(abs(actual - target) <= 5 ? Theme.alien : Theme.warn)
                            }
                            Text("For fixed-orifice (piston/cap tube) systems only. TXV/EEV systems charge by subcooling. Formula: (3 × indoor WB − 80 − outdoor DB) ÷ 2.").font(.caption).foregroundStyle(Theme.textDim)
                        }
                    }
                }
                .padding(16)
            }
        }
        .xenoScreen()
        .navigationTitle("Target superheat")
    }
}

struct PsychroView: View {
    @Environment(AppModel.self) private var model
    @State private var role: ProbeRole = .returnAir
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let fmt = model.fmt
            let a = model.air(role)
            ScrollView {
                VStack(spacing: 14) {
                    Picker("Air", selection: $role) {
                        Text("Return").tag(ProbeRole.returnAir); Text("Supply").tag(ProbeRole.supplyAir); Text("Outdoor").tag(ProbeRole.outdoorAir)
                    }.pickerStyle(.segmented)
                    XenoCard(glow: Theme.nebula) {
                        HStack {
                            RoleInput(role: role, caption: "Dry bulb", size: 32)
                            Spacer()
                            RoleInput(role: role, caption: "Humidity", humidity: true, size: 32)
                        }
                    }
                    XenoCard {
                        VStack(spacing: 10) {
                            KeyValueRow(key: "Wet bulb", value: fmt.temp(a?.wetBulbF), unit: fmt.tUnit)
                            KeyValueRow(key: "Dew point", value: fmt.temp(a?.dewPointF), unit: fmt.tUnit)
                            KeyValueRow(key: "Humidity ratio", value: a.map { $0.grainsPerLb.formatted(decimals: 1) } ?? "––", unit: "gr/lb")
                            KeyValueRow(key: "Enthalpy", value: a.map { $0.enthalpy.formatted(decimals: 2) } ?? "––", unit: "BTU/lb")
                            KeyValueRow(key: "Barometric pressure", value: (model.settings.atmPsia * 2.03602).formatted(decimals: 2), unit: "inHg")
                        }
                    }
                }
                .padding(16)
            }
        }
        .xenoScreen()
        .navigationTitle("Psychrometrics")
    }
}

struct FurnaceView: View {
    @Environment(AppModel.self) private var model
    @State private var inputText = "80000"
    @State private var effText = "80"
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let fmt = model.fmt
            let ret = model.input(.returnAir), sup = model.input(.supplyAir)
            let rise = (ret != nil && sup != nil) ? sup! - ret! : nil
            let output = (Double(inputText) ?? 0) * (Double(effText) ?? 0) / 100
            ScrollView {
                VStack(spacing: 14) {
                    XenoCard(glow: Theme.danger) {
                        HStack {
                            RoleInput(role: .returnAir, caption: "Return", size: 26)
                            Spacer()
                            RoleInput(role: .supplyAir, caption: "Supply", size: 26, color: Theme.danger)
                        }
                    }
                    XenoCard {
                        VStack(spacing: 10) {
                            LabeledField(label: "Input (nameplate)", text: $inputText, unit: "BTU/h")
                            LabeledField(label: "Efficiency (AFUE)", text: $effText, unit: "%")
                            KeyValueRow(key: "Output", value: (output / 1000).formatted(decimals: 1), unit: "kBTU/h")
                            Divider().opacity(0.3)
                            HStack {
                                ReadingView(caption: "Temperature rise", value: fmt.delta(rise), unit: fmt.dUnit, color: Theme.danger)
                                Spacer()
                                ReadingView(caption: "Airflow", value: rise.flatMap { HVACCalc.cfmFromTempRise(outputBTUh: output, riseF: $0, psia: model.settings.atmPsia) }.map { $0.formatted(decimals: 0) } ?? "––", unit: "CFM", color: Theme.beam)
                            }
                            Text("Compare the rise with the range on the furnace rating plate (typically 35–65°F).").font(.caption).foregroundStyle(Theme.textDim)
                        }
                    }
                }
                .padding(16)
            }
        }
        .xenoScreen()
        .navigationTitle("Furnace airflow")
    }
}
